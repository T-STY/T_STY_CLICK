import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'notification_actions.dart';

class PushNotificationsService {
  PushNotificationsService._();
  static final instance = PushNotificationsService._();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  String? _lastToken;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    final m = FirebaseMessaging.instance;

    FirebaseMessaging.onMessage.listen((msg) => debugPrint(
        'FCM fg: ${msg.notification?.title} · ${msg.notification?.body}'));
    FirebaseMessaging.instance.onTokenRefresh.listen(_save);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) _handleTap(initial);

    await m.requestPermission(alert: true, badge: true, sound: true);
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
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('tokens')
        .doc(token)
        .set({
      'createdAt': FieldValue.serverTimestamp(),
      'platform': defaultTargetPlatform.name,
    }, SetOptions(merge: true));
  }

  Future<void> clearForUser(String uid) async {
    final token = _lastToken;
    if (token == null) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('tokens')
        .doc(token)
        .delete()
        .catchError((_) {});
    _lastToken = null;
  }

  void _handleTap(RemoteMessage msg) {
    NotificationActions.instance.dispatch(Map<String, dynamic>.from(msg.data));
  }
}
