import 'package:flutter/foundation.dart';

class NotificationActions {
  NotificationActions._();
  static final NotificationActions instance = NotificationActions._();

  final ValueNotifier<Map<String, dynamic>?> pending =
      ValueNotifier<Map<String, dynamic>?>(null);

  void dispatch(Map<String, dynamic> data) {
    pending.value = data;
  }

  void consume() {
    pending.value = null;
  }
}
