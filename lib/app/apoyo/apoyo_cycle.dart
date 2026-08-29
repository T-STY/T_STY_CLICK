import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// ── APOYO SOCIAL — the week, the frozen list, the member's order ───────────
///
/// Models for what the SERVER wrote: `apoyo_cycles/{cycleId}` (the three
/// instants that define the week), its `catalog_snapshot` (the frozen price
/// list every screen prices from), its `commitments` (what is already spoken
/// for) and `apoyo_orders/{cycleId}_{uid}`.
///
/// Two rules this file exists to enforce:
///
///  * A DATE IS NEVER DERIVED ON THE CLIENT. The cycle id looks like a date
///    ('2026-09-04') but `DateTime.parse` of it yields UTC midnight, which
///    renders as *Thursday* in Mexico — the day before the delivery the
///    member is being promised. Every date and weekday shown comes from a
///    `Timestamp` the server computed in store time.
///  * A PRICE IS NEVER COMPUTED FROM ANYTHING BUT THE SNAPSHOT. The live
///    `apoyo_catalog` can be edited mid-week; the snapshot is what the member
///    committed to and what `placeApoyoOrder` prices from.

/// The pickup window, as the program states it everywhere else (the rules
/// card on the join screen says the same words). Not server data — it is a
/// property of the program, while `deliveryAt` (3:00 PM) is the instant the
/// server computes for the delivery run.
const String kApoyoPickupWindow = 'de 4:00 a 7:00 PM';

// ── formatting ──────────────────────────────────────────────────────────────

/// "viernes 4 de septiembre" — straight from a server Timestamp, never from
/// the 'YYYY-MM-DD' cycle id.
String apoyoLongDate(DateTime d) =>
    DateFormat("EEEE d 'de' MMMM", 'es').format(d);

/// "3:00 PM". `DateFormat.jm('es')` renders "3:00 p. m.", which reads wrong
/// next to the rest of the program copy.
String apoyoClock(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '$h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
}

/// Live countdown copy: "2 días 5 h", "5 h 12 min", "42 s".
String apoyoCountdown(Duration left) {
  if (left.isNegative || left.inSeconds <= 0) return 'Cerrado';
  final d = left.inDays;
  final h = left.inHours % 24;
  final m = left.inMinutes % 60;
  final s = left.inSeconds % 60;
  if (d > 0) return '$d ${d == 1 ? 'día' : 'días'} $h h';
  if (h > 0) return '$h h $m min';
  if (m > 0) return '$m min $s s';
  return '$s s';
}

/// Quantities are doubles because bulk moves in half kilos. "2", "1.5".
String apoyoQty(num q) {
  final v = q.toDouble();
  return (v - v.roundToDouble()).abs() < 0.001
      ? v.round().toString()
      : v.toStringAsFixed(1);
}

String apoyoQtyUnit(num q, String unidad) =>
    '${apoyoQty(q)} ${unidad == 'kg' ? 'kg' : 'pz'}';

/// Mirrors the server's cent rounding EXACTLY (`Math.round(x * 100) / 100`),
/// so the `expectedTotal` we send matches the total it prices and the
/// mismatch guard never fires on a rounding difference.
double apoyoRound2(num v) => (v.toDouble() * 100).roundToDouble() / 100;

// ── cycle ───────────────────────────────────────────────────────────────────

class ApoyoCycle {
  final String id;
  final String state;
  final DateTime? opensAt;
  final DateTime? closesAt;
  final DateTime? deliveryAt;

  const ApoyoCycle({
    required this.id,
    required this.state,
    this.opensAt,
    this.closesAt,
    this.deliveryAt,
  });

  static DateTime? _ts(Object? v) =>
      v is Timestamp ? v.toDate().toLocal() : null;

  factory ApoyoCycle.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return ApoyoCycle(
      id: doc.id,
      state: (d['state'] ?? '').toString(),
      opensAt: _ts(d['opensAt']),
      closesAt: _ts(d['closesAt']),
      deliveryAt: _ts(d['deliveryAt']),
    );
  }

  /// The stored instant is authoritative — the same check `placeApoyoOrder`
  /// makes inside its transaction. A cron that failed to flip `state` must
  /// never leave the catalog tappable past the cutoff.
  ///
  /// A cycle missing `closesAt` is treated as open: we cannot prove it is
  /// closed, and the callable re-checks everything anyway. Dead-ending a
  /// member on a data glitch is the worse failure.
  bool isOpenAt(DateTime now) =>
      state == 'abierto' && (closesAt == null || !now.isAfter(closesAt!));

  Duration timeLeftAt(DateTime now) =>
      closesAt == null ? Duration.zero : closesAt!.difference(now);

  /// "viernes 4 de septiembre" — the delivery Friday this cycle is named by.
  String get deliveryLabel =>
      deliveryAt == null ? '' : apoyoLongDate(deliveryAt!);

  /// "el viernes 4 de septiembre" — the form every sentence needs. A cycle
  /// that somehow arrived without its delivery instant degrades to a bare
  /// "el viernes" instead of leaving a hole in the middle of a promise.
  String get elDeliveryLabel =>
      deliveryAt == null ? 'el viernes' : 'el ${apoyoLongDate(deliveryAt!)}';

  /// "3:00 PM" — when the delivery run starts.
  String get deliveryClock => deliveryAt == null ? '' : apoyoClock(deliveryAt!);

  /// The one line that answers "when and how do I get this?".
  String handoffLine(String fulfillment) {
    final day = deliveryLabel;
    if (day.isEmpty) return '';
    return fulfillment == 'domicilio'
        ? 'Te llega el $day después de las $deliveryClock.'
        : 'Recoges en la tienda el $day $kApoyoPickupWindow.';
  }
}

// ── frozen catalog ──────────────────────────────────────────────────────────

class ApoyoComponent {
  final String nombre;
  final double quantity;

  const ApoyoComponent({required this.nombre, required this.quantity});

  factory ApoyoComponent.fromMap(Map<String, dynamic> m) => ApoyoComponent(
        nombre: (m['nombre'] ?? '').toString(),
        quantity: (m['quantity'] as num?)?.toDouble() ?? 1,
      );
}

class ApoyoCatalogItem {
  final String id;
  final String nombre;
  final String unidad;
  final String imageUrl;
  final double memberPrice;

  /// 0 means "sin límite" for both caps.
  final double maxPerMember;
  final double cycleCap;
  final int orden;
  final List<ApoyoComponent> components;

  const ApoyoCatalogItem({
    required this.id,
    required this.nombre,
    required this.unidad,
    required this.imageUrl,
    required this.memberPrice,
    required this.maxPerMember,
    required this.cycleCap,
    required this.orden,
    required this.components,
  });

  factory ApoyoCatalogItem.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    final raw = d['components'];
    return ApoyoCatalogItem(
      id: doc.id,
      nombre: (d['nombre'] ?? '').toString(),
      unidad: (d['unidad'] ?? 'pz').toString() == 'kg' ? 'kg' : 'pz',
      imageUrl: (d['imageUrl'] ?? '').toString(),
      memberPrice: (d['memberPrice'] as num?)?.toDouble() ?? 0,
      maxPerMember: (d['maxPerMember'] as num?)?.toDouble() ?? 0,
      cycleCap: (d['cycleCap'] as num?)?.toDouble() ?? 0,
      orden: (d['orden'] as num?)?.toInt() ?? 0,
      components: raw is List
          ? [
              for (final c in raw)
                if (c is Map)
                  ApoyoComponent.fromMap(Map<String, dynamic>.from(c)),
            ]
          : const [],
    );
  }

  /// Bulk moves in half kilos — the same 0.5 steps the owner's shopping list
  /// aggregates in. Pieces move in whole units.
  double get step => unidad == 'kg' ? 0.5 : 1;

  bool get isBundle => components.length > 1;

  String get priceLabel => unidad == 'kg' ? '/ kg' : 'c/u';
}

// ── the member's order ──────────────────────────────────────────────────────

class ApoyoOrderItem {
  final String catalogItemId;
  final String nombre;
  final String unidad;
  final String imageUrl;
  final double price;
  final double quantity;
  final double total;

  const ApoyoOrderItem({
    required this.catalogItemId,
    required this.nombre,
    required this.unidad,
    required this.imageUrl,
    required this.price,
    required this.quantity,
    required this.total,
  });

  factory ApoyoOrderItem.fromMap(Map<String, dynamic> m) => ApoyoOrderItem(
        catalogItemId: (m['catalogItemId'] ?? '').toString(),
        nombre: (m['nombre'] ?? '').toString(),
        unidad: (m['unidad'] ?? 'pz').toString() == 'kg' ? 'kg' : 'pz',
        imageUrl: (m['imageUrl'] ?? '').toString(),
        price: (m['price'] as num?)?.toDouble() ?? 0,
        quantity: (m['quantity'] as num?)?.toDouble() ?? 0,
        total: (m['total'] as num?)?.toDouble() ?? 0,
      );
}

class ApoyoOrder {
  final String cycleId;
  final String folio;
  final String state;
  final String fulfillment;
  final String addressId;
  final String addressLine;
  final String colonia;
  final String notes;
  final double subtotal;
  final double deliveryFee;
  final double total;
  final double? cashPaidWith;
  final String cancelReason;
  final List<ApoyoOrderItem> items;

  const ApoyoOrder({
    required this.cycleId,
    required this.folio,
    required this.state,
    required this.fulfillment,
    required this.addressId,
    required this.addressLine,
    required this.colonia,
    required this.notes,
    required this.subtotal,
    required this.deliveryFee,
    required this.total,
    required this.cashPaidWith,
    required this.cancelReason,
    required this.items,
  });

  factory ApoyoOrder.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    final raw = d['items'];
    return ApoyoOrder(
      cycleId: (d['cycleId'] ?? '').toString(),
      folio: (d['folio'] ?? '').toString(),
      state: (d['state'] ?? '').toString(),
      fulfillment:
          (d['fulfillment'] ?? 'tienda').toString() == 'domicilio'
              ? 'domicilio'
              : 'tienda',
      addressId: (d['addressId'] ?? '').toString(),
      addressLine: (d['addressLine'] ?? '').toString(),
      colonia: (d['colonia'] ?? '').toString(),
      notes: (d['notes'] ?? '').toString(),
      subtotal: (d['subtotal'] as num?)?.toDouble() ?? 0,
      deliveryFee: (d['deliveryFee'] as num?)?.toDouble() ?? 0,
      total: (d['total'] as num?)?.toDouble() ?? 0,
      cashPaidWith: (d['cashPaidWith'] as num?)?.toDouble(),
      cancelReason: (d['cancelReason'] ?? '').toString(),
      items: raw is List
          ? [
              for (final it in raw)
                if (it is Map)
                  ApoyoOrderItem.fromMap(Map<String, dynamic>.from(it)),
            ]
          : const [],
    );
  }

  bool get isCancelled => state == 'Cancelado';

  /// What the member owes on Friday, as a map the cart can be rebuilt from
  /// when they tap "Editar".
  Map<String, double> get quantities => {
        for (final it in items)
          if (it.catalogItemId.isNotEmpty) it.catalogItemId: it.quantity,
      };
}

// ── the draft the member is building ────────────────────────────────────────

/// One line of the selection, resolved against the frozen snapshot. Built on
/// the catalog screen and handed to the confirm screen so both show the same
/// numbers — and so the confirm screen never has to price anything itself.
class ApoyoDraftLine {
  final ApoyoCatalogItem item;
  final double quantity;

  const ApoyoDraftLine(this.item, this.quantity);

  /// Same order of operations as the server's
  /// `Math.round(memberPrice * qty * 100) / 100`.
  double get total => apoyoRound2(item.memberPrice * quantity);
}

/// Sum of the lines, rounded once at the end — again exactly as the server
/// does it, so `expectedTotal` agrees with what `placeApoyoOrder` computes.
double apoyoDraftSubtotal(List<ApoyoDraftLine> lines) {
  var subtotal = 0.0;
  for (final l in lines) {
    subtotal += l.total;
  }
  return apoyoRound2(subtotal);
}
