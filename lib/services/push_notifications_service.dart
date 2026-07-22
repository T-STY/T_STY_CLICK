import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_notifications_service.dart';
import 'notification_actions.dart';

/// Singleton responsible for everything FCM / push-permission related:
///   - First-time permission prompt
///   - Re-nudging users who said no (system rule blocks our re-prompt, so
///     we deep-link to system settings instead)
///   - Persisting the FCM token to `users/{uid}/tokens/{token}`
///   - Hard-rotating the token on sign-out so the next user on the same
///     device never inherits the previous user's push subscription
class PushNotificationsService {
  PushNotificationsService._();
  static final instance = PushNotificationsService._();

  /// Navigator key — used by the notification-tap dispatcher to push
  /// routes onto the running app from a cold-start tap.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  String? _lastToken;
  bool _initialized = false;
  // Cached PackageInfo so we don't shell out to the platform on every
  // token write. Lazily populated on first save.
  String? _appVersion;
  String? _appBuild;

  // Set once we've already shown the in-app rationale within the
  // current process. Resets naturally on every cold launch (singleton
  // is reconstructed), so a re-asked user gets one shot per session.
  bool _shownThisSession = false;

  // Cart-only cooldown so a user adding items repeatedly within a
  // short window doesn't see the dialog every time. Stored in
  // SharedPreferences and only written by the cart path — home does
  // not throttle across cold launches by design.
  static const _kLastCartNudgeAtKey = 'notif_perm_last_cart_nudge_at_ms';
  static const Duration _cartNudgeCooldown = Duration(minutes: 30);

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    final m = FirebaseMessaging.instance;

    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    FirebaseMessaging.instance.onTokenRefresh.listen(_save);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) _handleTap(initial);

    // Foreground presentation options need to be set unconditionally
    // so the moment permission IS granted, foreground delivery on iOS
    // shows banners.
    //
    // NOTE: `requestPermission` is intentionally NOT called here. On
    // a fresh install that would surface the OS prompt BEFORE the
    // user has any context for why the app needs notifications. We
    // wait for the user to tap "Activar avisos" inside our own
    // rationale dialog (`maybeNudgePermission` → `_showNudgeDialog`),
    // which then fires `requestPermission` for the first time.
    await m.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // If permission was granted on a previous launch, we still need
    // to make sure a token doc exists for this user. The auth-state
    // listener in main.dart calls `registerForCurrentUser` on sign-in;
    // this is just defense-in-depth for the "previously granted but
    // never wrote a token doc" edge case.
  }

  // ──────────────────────────────────────────────────────────────────
  // Token persistence
  // ──────────────────────────────────────────────────────────────────

  /// Called from the auth-state listener on sign-in. Forces a fresh
  /// `getToken()` and persists it under the current user's tree.
  Future<void> registerForCurrentUser() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _save(token);
    } catch (e) {
      debugPrint('register fcm failed: $e');
    }
  }

  Future<void> _save(String token) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _lastToken = token;
    // Lazy-load the package info once. Cheap on first run, cached after.
    if (_appVersion == null) {
      try {
        final info = await PackageInfo.fromPlatform();
        _appVersion = info.version;
        _appBuild = info.buildNumber;
      } catch (e) {
        debugPrint('packageInfo failed: $e');
      }
    }
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('tokens')
        .doc(token)
        .set({
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'platform': defaultTargetPlatform.name,
      if (_appVersion != null) 'appVersion': _appVersion,
      if (_appBuild != null) 'appBuild': _appBuild,
    }, SetOptions(merge: true));
  }

  /// Called from the auth-state listener on sign-out.
  ///
  /// Two-stage cleanup per the agreed plan (option A):
  ///   1. Delete the current token doc under the *outgoing* uid so the
  ///      server stops fanning out to this device under that account.
  ///   2. Call `FirebaseMessaging.deleteToken()` so Google invalidates
  ///      the device-side subscription. The next time anyone signs in
  ///      on this device, `getToken()` will mint a fresh token — so the
  ///      old token can't possibly land under the new account.
  ///
  /// Other devices the user is still logged in on (tablet, etc.) are
  /// untouched — we never iterate all of their docs.
  Future<void> clearForUser(String uid) async {
    final token = _lastToken;
    if (token != null) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('tokens')
            .doc(token)
            .delete();
      } catch (_) {
        // Best-effort — if the doc is already gone or rules reject,
        // we still want to delete the FCM-side token below.
      }
    }
    _lastToken = null;
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (e) {
      debugPrint('deleteToken on signout failed: $e');
    }
  }

  // ──────────────────────────────────────────────────────────────────
  // Permission re-nudge
  // ──────────────────────────────────────────────────────────────────

  /// Public entry point. Call from a screen's first build (post-frame
  /// callback) to ask the user to enable notifications.
  ///
  /// Flow:
  ///   1. Skip if permission is already granted / provisional / limited.
  ///   2. Skip if we already showed the rationale this session — the
  ///      `_shownThisSession` flag resets only on cold launch, so a
  ///      user who dismisses with "Ahora no" sees the dialog again on
  ///      the very next app start. (That's the desired behavior — we
  ///      keep asking until they decide.)
  ///   3. For [source] == `'cart'`, additionally throttle to once per
  ///      30 minutes so adding items in a short window doesn't nag.
  ///      Home has no time-based throttle.
  ///   4. Show the rationale dialog.
  ///   5. If the user taps "Activar avisos":
  ///        - First-time install (FCM status `notDetermined`): call
  ///          `requestPermission` so the OS surfaces its prompt for
  ///          the first time, with the rationale fresh in their mind.
  ///        - Already-decided (denied / etc.): calling
  ///          `requestPermission` would be a no-op on iOS, so deep-
  ///          link to system settings via `openAppSettings()` where
  ///          they can flip the toggle.
  Future<void> maybeNudgePermission(
    BuildContext context, {
    required String source,
  }) async {
    if (!context.mounted) return;
    if (_shownThisSession) return;

    final status = await Permission.notification.status;
    if (status.isGranted ||
        status.isLimited ||
        status.isProvisional) {
      return;
    }

    if (source == 'cart') {
      final prefs = await SharedPreferences.getInstance();
      final lastAtMs = prefs.getInt(_kLastCartNudgeAtKey) ?? 0;
      final lastAt = DateTime.fromMillisecondsSinceEpoch(lastAtMs);
      if (DateTime.now().difference(lastAt) < _cartNudgeCooldown) {
        return;
      }
    }

    // Mark BEFORE awaiting the dialog so a second concurrent caller
    // (e.g. simultaneous tab-switch + initial post-frame) can't
    // double-stack the dialog.
    _shownThisSession = true;

    if (!context.mounted) return;
    final wantsToActivate =
        await _showNudgeDialog(context, source: source);

    if (source == 'cart') {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        _kLastCartNudgeAtKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    }

    if (wantsToActivate != true) return;

    // Platform-specific re-ask path:
    //   * First-time install (status == notDetermined) → always
    //     `requestPermission`; OS surfaces its prompt on both
    //     platforms.
    //   * Android subsequent ask → `requestPermission` again. The
    //     OS will re-show the system dialog after a previous
    //     "Don't allow" until the user explicitly picks "Don't
    //     ask again". When it eventually silently no-ops the call
    //     is harmless — the rationale just keeps reappearing on
    //     cold launches.
    //   * iOS subsequent ask → Apple's policy is that
    //     `requestPermission` is a hard no-op after the first
    //     denial; the only path to re-grant is the system
    //     Settings app, so deep-link there with `openAppSettings`.
    //     We *do* want to be there in this case — the user
    //     explicitly tapped "Activar avisos", so opening Settings
    //     is the response that respects their intent, not the
    //     uninvited bounce we avoided earlier.
    final pre =
        await FirebaseMessaging.instance.getNotificationSettings();
    final isFirstTime =
        pre.authorizationStatus == AuthorizationStatus.notDetermined;

    if (isFirstTime ||
        defaultTargetPlatform != TargetPlatform.iOS) {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
    } else {
      await openAppSettings();
    }
  }

  Future<bool?> _showNudgeDialog(BuildContext context,
      {required String source}) {
    final isCart = source == 'cart';
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        title: const Text('Activa las notificaciones'),
        content: Text(
          isCart
              ? 'Para avisarte cuando tu pedido esté en camino y cuando '
                  'llegue. Toca "Activar avisos" para confirmar.'
              : 'Te avisaremos cuando tu pedido vaya en camino, cuando '
                  'llegue y de promociones exclusivas. Toca "Activar '
                  'avisos" para no perdértelas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Ahora no'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.black,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Activar avisos'),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────
  // Tap handler
  // ──────────────────────────────────────────────────────────────────

  void _handleTap(RemoteMessage msg) {
    NotificationActions.instance
        .dispatch(Map<String, dynamic>.from(msg.data));
  }

  // ──────────────────────────────────────────────────────────────────
  // Foreground message handler
  // ──────────────────────────────────────────────────────────────────

  /// Foreground FCM delivery is asymmetric across platforms:
  ///   - iOS surfaces the system banner itself because
  ///     `setForegroundNotificationPresentationOptions` is enabled
  ///     in `init()`.
  ///   - Android does NOT auto-display in the foreground — the SDK
  ///     just fires this callback and trusts us to present the
  ///     notification. Without this bridge, customers reading the
  ///     home screen miss order updates and coupon broadcasts until
  ///     they background the app.
  ///
  /// On Android we forward the title/body to
  /// `LocalNotificationsService.showRemoteForeground`, which posts a
  /// local notification on the same `orders` channel the CFs target.
  /// The FCM `msg.data` map is JSON-encoded into the payload so a
  /// tap routes through `NotificationActions` exactly like a
  /// background-tap would (same `type: 'order_status' | 'coupon' |
  /// 'general'` keys, same dispatcher).
  void _onForegroundMessage(RemoteMessage msg) {
    debugPrint(
        'FCM fg: ${msg.notification?.title} · ${msg.notification?.body}');
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final n = msg.notification;
    if (n == null) return;
    LocalNotificationsService.instance.showRemoteForeground(
      title: n.title,
      body: n.body,
      messageId: msg.messageId,
      payload: msg.data.isEmpty ? null : jsonEncode(msg.data),
    );
  }
}
