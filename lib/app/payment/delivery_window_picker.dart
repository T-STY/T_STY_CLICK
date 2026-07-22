import 'package:flutter/material.dart';

import '../../utils/order_window.dart';

/// Same-day 30-min delivery/pickup slot picker.
///
/// Generates slots from `max(now + 30min buffer, hours start)` — rounded UP
/// to the next :00/:30 — through the hours end, where "hours" are the
/// delivery window (`todayOpen..todayClose`) or, for pickup, the store's
/// open span (the complement of quiet hours). `now` should be the
/// skew-corrected NETWORK time; the placeOrder CF re-validates every rule
/// server-side, so a stale device clock only costs the user a rejection
/// message, never a bad order.
///
/// `selected == null` means "Lo antes posible" (no window on the order).
class DeliveryWindowPicker extends StatelessWidget {
  final OrderWindow window;
  final bool isPickup;
  final DateTime now;
  final TimeOfDay? selected;
  final ValueChanged<TimeOfDay?> onChanged;

  const DeliveryWindowPicker({
    super.key,
    required this.window,
    required this.isPickup,
    required this.now,
    required this.selected,
    required this.onChanged,
  });

  static int _min(TimeOfDay t) => t.hour * 60 + t.minute;

  static int _ceil30(int minutes) => ((minutes + 29) ~/ 30) * 30;

  /// The valid slot starts for the current mode, or empty when the rest of
  /// the day has no room (the picker then renders only "Lo antes posible").
  List<TimeOfDay> slots() {
    int startBound;
    int endBound;
    if (isPickup) {
      // Store hours = complement of quiet hours (e.g. 08:00 → 22:00).
      startBound = _min(window.quietEnd);
      endBound = _min(window.quietStart);
    } else {
      final open = window.todayOpen;
      final close = window.todayClose;
      if (open == null || close == null || window.deliveryRestToday) {
        return const [];
      }
      startBound = _min(open);
      endBound = _min(close);
    }
    if (endBound <= startBound) return const [];

    var first = _ceil30(_min(TimeOfDay.fromDateTime(now)) + 30);
    if (first < startBound) first = _ceil30(startBound);

    final out = <TimeOfDay>[];
    for (var s = first; s + 30 <= endBound; s += 30) {
      out.add(TimeOfDay(hour: s ~/ 60, minute: s % 60));
    }
    return out;
  }

  static String _fmt(TimeOfDay t) => formatHourMinute(t);

  static TimeOfDay _end(TimeOfDay s) {
    final m = s.hour * 60 + s.minute + 30;
    return TimeOfDay(hour: (m ~/ 60) % 24, minute: m % 60);
  }

  @override
  Widget build(BuildContext context) {
    final available = slots();
    // Keep the selection honest: if the chosen slot fell out of range
    // (pickup toggled, time passed), snap back to "Lo antes posible".
    final TimeOfDay? effective = (selected != null &&
            available.any((s) =>
                s.hour == selected!.hour && s.minute == selected!.minute))
        ? selected
        : null;
    if (effective == null && selected != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => onChanged(null));
    }

    // Agenda rows: "Lo antes posible" first, then each 30-min slot as a
    // full-width, tappable time row.
    final rows = <Widget>[
      _AgendaRow(
        label: 'Lo antes posible',
        icon: Icons.bolt_rounded,
        selected: effective == null,
        onTap: () => onChanged(null),
      ),
      for (final s in available)
        _AgendaRow(
          label: '${_fmt(s)} – ${_fmt(_end(s))}',
          selected: effective != null &&
              effective.hour == s.hour &&
              effective.minute == s.minute,
          onTap: () => onChanged(s),
        ),
    ];
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) {
        children.add(Divider(height: 1, color: Colors.grey.shade200));
      }
      children.add(rows[i]);
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.schedule, size: 18, color: Colors.grey.shade800),
              const SizedBox(width: 8),
              Text(
                isPickup ? '¿A qué hora pasas?' : '¿Cuándo lo quieres?',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Bounded + scrollable so a full day of slots reads like an agenda
          // without pushing the rest of checkout down.
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 268),
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: children,
            ),
          ),
          if (available.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 4),
              child: Text(
                isPickup
                    ? 'No hay más horarios de recolección hoy.'
                    : 'No hay más horarios de entrega hoy; se preparará lo '
                        'antes posible.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ),
        ],
      ),
    );
  }
}

class _AgendaRow extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  const _AgendaRow({
    required this.label,
    this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 13),
          decoration: BoxDecoration(
            color: selected
                ? Colors.black.withValues(alpha: 0.04)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon,
                    size: 18,
                    color: selected ? Colors.black : Colors.grey.shade600),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight:
                        selected ? FontWeight.w800 : FontWeight.w500,
                    color: selected ? Colors.black : Colors.grey.shade800,
                  ),
                ),
              ),
              // Radio indicator: filled black check when chosen, ring when not.
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? Colors.black : Colors.transparent,
                  border: Border.all(
                    color: selected ? Colors.black : Colors.grey.shade400,
                    width: 2,
                  ),
                ),
                child: selected
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
