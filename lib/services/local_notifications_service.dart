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
      onDidReceiveNotificationResponse: (_) {
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
