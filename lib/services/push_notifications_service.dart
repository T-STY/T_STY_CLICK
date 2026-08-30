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

class PushNotificationsService {
  PushNotificationsService._();
  static final instance = PushNotificationsService._();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  String? _lastToken;
  bool _initialized = false;

  String? _appVersion;
  String? _appBuild;

  bool _shownThisSession = false;

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

    await m.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

  }

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

      }
    }
    _lastToken = null;
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (e) {
      debugPrint('deleteToken on signout failed: $e');
    }
  }

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

  void _handleTap(RemoteMessage msg) {
    NotificationActions.instance
        .dispatch(Map<String, dynamic>.from(msg.data));
  }

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
