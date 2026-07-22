import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'notification_actions.dart';

class LocalNotificationsService {
  LocalNotificationsService._();
  static final LocalNotificationsService instance =
      LocalNotificationsService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const int _reminder1Id = 9001;
  static const int _reminder2Id = 9002;
  static const String _channelId = 'cart_reminders';

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    tzdata.initializeTimeZones();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings =
        InitializationSettings(android: androidInit, iOS: darwinInit);

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        // Two flavors of local notification reach this handler:
        //   1. Cart reminders we scheduled ourselves — no payload, so
        //      we synthesize a `cart_reminder` action.
        //   2. The foreground-FCM bridge (`showRemoteForeground`) —
        //      payload is the FCM `msg.data` map encoded as JSON, so
        //      we decode and dispatch it verbatim. This routes order /
        //      coupon taps through the same dispatcher the background
        //      `onMessageOpenedApp` handler uses, keeping deep-link
        //      behavior identical regardless of fg/bg.
        final raw = response.payload;
        if (raw != null && raw.isNotEmpty) {
          try {
            final decoded = jsonDecode(raw);
            if (decoded is Map) {
              NotificationActions.instance
                  .dispatch(Map<String, dynamic>.from(decoded));
              return;
            }
          } catch (_) {
            // Fall through to cart_reminder fallback.
          }
        }
        NotificationActions.instance.dispatch({'type': 'cart_reminder'});
      },
    );

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      await android.createNotificationChannel(const AndroidNotificationChannel(
        'orders',
        'Pedidos y avisos',
        description: 'Actualizaciones de pedidos y cupones.',
        importance: Importance.high,
      ));
      await android.createNotificationChannel(const AndroidNotificationChannel(
        _channelId,
        'Recordatorios de carrito',
        description: 'Te recordamos los articulos que dejaste en tu carrito.',
        importance: Importance.high,
      ));
    }

    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      NotificationActions.instance.dispatch({'type': 'cart_reminder'});
    }
  }

  Future<void> scheduleCartReminders() async {
    try {
      await init();
      await cancelCartReminders();
      await _schedule(
        _reminder1Id,
        const Duration(minutes: 30),
        '¡Oye!',
        'Olvidaste tus articulos en el carrito, ¡que no te los ganen!',
      );
      await _schedule(
        _reminder2Id,
        const Duration(hours: 2),
        '¡Ups!',
        'Creo que ya te arrepentiste, pero ntp, cuando estes listo puedes finalizar tu compra.',
      );
    } catch (e) {
      debugPrint('scheduleCartReminders failed: $e');
    }
  }

  Future<void> cancelCartReminders() async {
    try {
      await _plugin.cancel(_reminder1Id);
      await _plugin.cancel(_reminder2Id);
    } catch (e) {
      debugPrint('cancelCartReminders failed: $e');
    }
  }

  // ID range for foreground FCM bridge notifications. We hash the FCM
  // message id (or fall back to a timestamp) into this range so
  // back-to-back arrivals don't collide / replace each other in the
  // tray. Keep this range disjoint from the static reminder IDs above.
  static const int _fgFcmIdBase = 10000;
  static const int _fgFcmIdMod = 50000;

  /// Bridge for FCM messages that arrive while the app is in the
  /// foreground on Android. The FCM SDK does NOT auto-display these
  /// (it just fires `onMessage`), so without this bridge the customer
  /// sees nothing until they background the app — which means missed
  /// order updates and coupon broadcasts they were physically present
  /// for. iOS handles foreground display via
  /// `setForegroundNotificationPresentationOptions` and doesn't need
  /// this path; the caller gates on `defaultTargetPlatform == android`.
  ///
  /// [payload] is forwarded into the tap callback so the existing
  /// `NotificationActions` dispatcher can route a tap to the right
  /// screen (order_status → orders tab, coupon → claim dialog, etc.).
  Future<void> showRemoteForeground({
    required String? title,
    required String? body,
    String? messageId,
    String? payload,
  }) async {
    if (title == null && body == null) return;
    try {
      await init();
      // Stable per-message id so duplicate deliveries don't double-post.
      final int id = ((messageId?.hashCode ?? DateTime.now().microsecondsSinceEpoch)
                  .abs() %
              _fgFcmIdMod) +
          _fgFcmIdBase;
      await _plugin.show(
        id,
        title ?? '',
        body ?? '',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'orders',
            'Pedidos y avisos',
            channelDescription: 'Actualizaciones de pedidos y cupones.',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        payload: payload,
      );
    } catch (e) {
      debugPrint('showRemoteForeground failed: $e');
    }
  }

  Future<void> _schedule(
    int id,
    Duration delay,
    String title,
    String body,
  ) async {
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.now(tz.local).add(delay),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Recordatorios de carrito',
          channelDescription:
              'Te recordamos los articulos que dejaste en tu carrito.',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }
}
