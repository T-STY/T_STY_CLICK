import 'package:flutter/material.dart';

enum OrderingStatus { open, pickupOnly, closed }

class OrderWindow {

  static const TimeOfDay defaultQuietStart = TimeOfDay(hour: 22, minute: 0);
  static const TimeOfDay defaultQuietEnd = TimeOfDay(hour: 8, minute: 0);

  final OrderingStatus status;

  final TimeOfDay? todayOpen;
  final TimeOfDay? todayClose;

  final bool deliveryRestToday;

  final TimeOfDay quietStart;
  final TimeOfDay quietEnd;

  const OrderWindow._({
    required this.status,
    required this.todayOpen,
    required this.todayClose,
    required this.deliveryRestToday,
    required this.quietStart,
    required this.quietEnd,
  });

  static const OrderWindow openPlaceholder = OrderWindow._(
    status: OrderingStatus.open,
    todayOpen: TimeOfDay(hour: 9, minute: 0),
    todayClose: TimeOfDay(hour: 18, minute: 0),
    deliveryRestToday: false,
    quietStart: defaultQuietStart,
    quietEnd: defaultQuietEnd,
  );

  factory OrderWindow.evaluate({
    required Map<String, dynamic> doc,
    required DateTime now,
  }) {
    final local = now.toLocal();

    final quietRaw = doc['quietHours'];
    final qStart = (quietRaw is Map
            ? _parseHhMm(quietRaw['start'])
            : null) ??
        defaultQuietStart;
    final qEnd = (quietRaw is Map ? _parseHhMm(quietRaw['end']) : null) ??
        defaultQuietEnd;

    if (_isInWindow(local, qStart, qEnd, allowMidnightWrap: true)) {
      return OrderWindow._(
        status: OrderingStatus.closed,
        todayOpen: null,
        todayClose: null,
        deliveryRestToday: false,
        quietStart: qStart,
        quietEnd: qEnd,
      );
    }

    final weekday = local.weekday;
    TimeOfDay open = const TimeOfDay(hour: 9, minute: 0);
    TimeOfDay close = const TimeOfDay(hour: 18, minute: 0);
    bool restToday = false;

    final schedule = doc['weeklySchedule'];
    if (schedule is Map && schedule[weekday.toString()] is Map) {
      final entry = schedule[weekday.toString()] as Map;
      restToday = entry['closed'] == true;
      final parsedOpen = _parseHhMm(entry['open']);
      final parsedClose = _parseHhMm(entry['close']);
      if (parsedOpen != null) open = parsedOpen;
      if (parsedClose != null) close = parsedClose;
    } else {

      final legacyOpen = (doc['open_hour'] as num?)?.toInt();
      final legacyClose = (doc['close_hour'] as num?)?.toInt();
      if (legacyOpen != null) open = TimeOfDay(hour: legacyOpen, minute: 0);
      if (legacyClose != null) {
        close = TimeOfDay(hour: legacyClose, minute: 0);
      }
    }

    final canDeliver = !restToday &&
        _isInWindow(local, open, close, allowMidnightWrap: true);

    return OrderWindow._(
      status: canDeliver ? OrderingStatus.open : OrderingStatus.pickupOnly,
      todayOpen: open,
      todayClose: close,
      deliveryRestToday: restToday,
      quietStart: qStart,
      quietEnd: qEnd,
    );
  }

  static TimeOfDay? _parseHhMm(Object? value) {
    if (value is! String) return null;
    final parts = value.trim().split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    if (h < 0 || h > 24 || m < 0 || m > 59) return null;
    return TimeOfDay(hour: h % 24, minute: m);
  }

  static bool _isInWindow(
    DateTime now,
    TimeOfDay start,
    TimeOfDay end, {
    required bool allowMidnightWrap,
  }) {
    final nMin = now.hour * 60 + now.minute;
    final sMin = start.hour * 60 + start.minute;
    var eMin = end.hour * 60 + end.minute;
    if (eMin == sMin) return false;
    if (eMin > sMin) {
      return nMin >= sMin && nMin < eMin;
    }

    if (!allowMidnightWrap) return false;
    return nMin >= sMin || nMin < eMin;
  }
}

String formatHourMinute(TimeOfDay t) {
  final h12 = t.hour == 0 ? 12 : (t.hour > 12 ? t.hour - 12 : t.hour);
  final suffix = t.hour < 12 ? 'AM' : 'PM';
  if (t.minute == 0) return '$h12 $suffix';
  return '$h12:${t.minute.toString().padLeft(2, '0')} $suffix';
}
