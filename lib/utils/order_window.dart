import 'package:flutter/material.dart';

/// Single source of truth for "can the user place an order right now?".
///
/// There are three states, ranked from most permissive to least:
///
///   - [OrderingStatus.open]       Both delivery and in-store pickup OK.
///   - [OrderingStatus.pickupOnly] Outside today's delivery window OR the
///                                 day is configured "no delivery" — but
///                                 pickup is still available because the
///                                 physical store is open.
///   - [OrderingStatus.closed]     Inside the global "quiet hours" window
///                                 (default 22:00 → 08:00). The physical
///                                 store is actually closed; nothing can
///                                 be ordered.
///
/// The cart and checkout both consume this; `placeOrder` (CF) mirrors the
/// same logic server-side as the security half of the rule, so a stale
/// client clock or tampered app can't sneak a delivery through.
enum OrderingStatus { open, pickupOnly, closed }

/// Resolved schedule for "right now". Created via [OrderWindow.evaluate]
/// from the raw `settings/store` doc + a [now] reference.
class OrderWindow {
  /// Default global quiet-hours window. Hardcoded to 22:00 → 08:00 unless
  /// the admin overrides via `settings/store.quietHours: {start, end}`.
  static const TimeOfDay defaultQuietStart = TimeOfDay(hour: 22, minute: 0);
  static const TimeOfDay defaultQuietEnd = TimeOfDay(hour: 8, minute: 0);

  final OrderingStatus status;

  /// Today's delivery window (or whatever the schedule said). Useful for
  /// the cart banner ("disponibles entre 9 AM y 6 PM"). Null when [status]
  /// is closed and we want to surface quiet hours instead.
  final TimeOfDay? todayOpen;
  final TimeOfDay? todayClose;

  /// Set true when today is explicitly flagged "no delivery" in the
  /// schedule (vs just being outside the window).
  final bool deliveryRestToday;

  /// Quiet hours actually in effect — used for messaging.
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

  /// Permissive default used while the store-settings stream is still
  /// loading. We don't want a momentary network blip to look like the
  /// store is closed — once real data arrives the StreamBuilder rebuild
  /// replaces this in the next frame with the real evaluation.
  static const OrderWindow openPlaceholder = OrderWindow._(
    status: OrderingStatus.open,
    todayOpen: TimeOfDay(hour: 9, minute: 0),
    todayClose: TimeOfDay(hour: 18, minute: 0),
    deliveryRestToday: false,
    quietStart: defaultQuietStart,
    quietEnd: defaultQuietEnd,
  );

  /// Build from a raw `settings/store` doc + [now].
  ///
  /// Falls back gracefully:
  ///   - `weeklySchedule[weekday]` first (new per-day schema).
  ///   - `open_hour` + `close_hour` integers next (legacy fallback).
  ///   - 09:00 → 18:00 last.
  factory OrderWindow.evaluate({
    required Map<String, dynamic> doc,
    required DateTime now,
  }) {
    final local = now.toLocal();

    // ── 1. Resolve quiet hours (admin-overridable). ─────────────
    final quietRaw = doc['quietHours'];
    final qStart = (quietRaw is Map
            ? _parseHhMm(quietRaw['start'])
            : null) ??
        defaultQuietStart;
    final qEnd = (quietRaw is Map ? _parseHhMm(quietRaw['end']) : null) ??
        defaultQuietEnd;

    // ── 2. In quiet hours → hard "closed". ──────────────────────
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

    // ── 3. Resolve today's delivery entry. ──────────────────────
    final weekday = local.weekday; // 1=Mon … 7=Sun
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
      // Legacy fallback — single open/close hour for every day.
      final legacyOpen = (doc['open_hour'] as num?)?.toInt();
      final legacyClose = (doc['close_hour'] as num?)?.toInt();
      if (legacyOpen != null) open = TimeOfDay(hour: legacyOpen, minute: 0);
      if (legacyClose != null) {
        close = TimeOfDay(hour: legacyClose, minute: 0);
      }
    }

    // ── 4. Inside delivery window? ──────────────────────────────
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

  // ───────────────────────────────────────────────────────────────
  // Helpers
  // ───────────────────────────────────────────────────────────────

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

  /// Returns true when [now] is in [start..end). When [allowMidnightWrap]
  /// is true and end ≤ start, the window crosses midnight (so e.g.
  /// 22:00 → 08:00 spans the night, and 03:00 is inside it).
  static bool _isInWindow(
    DateTime now,
    TimeOfDay start,
    TimeOfDay end, {
    required bool allowMidnightWrap,
  }) {
    final nMin = now.hour * 60 + now.minute;
    final sMin = start.hour * 60 + start.minute;
    var eMin = end.hour * 60 + end.minute;
    if (eMin == sMin) return false; // explicit "no window"
    if (eMin > sMin) {
      return nMin >= sMin && nMin < eMin;
    }
    // Wraps midnight.
    if (!allowMidnightWrap) return false;
    return nMin >= sMin || nMin < eMin;
  }
}

// ───────────────────────────────────────────────────────────────────────
// Pure helpers for human-readable copy. Kept outside the class so a
// caller can render messaging without holding an OrderWindow instance.
// ───────────────────────────────────────────────────────────────────────

String formatHourMinute(TimeOfDay t) {
  final h12 = t.hour == 0 ? 12 : (t.hour > 12 ? t.hour - 12 : t.hour);
  final suffix = t.hour < 12 ? 'AM' : 'PM';
  if (t.minute == 0) return '$h12 $suffix';
  return '$h12:${t.minute.toString().padLeft(2, '0')} $suffix';
}
