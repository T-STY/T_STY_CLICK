import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

const String kApoyoPickupWindow = 'de 4:00 a 7:00 PM';

String apoyoLongDate(DateTime d) =>
    DateFormat("EEEE d 'de' MMMM", 'es').format(d);

String apoyoClock(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '$h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
}

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

String apoyoQty(num q) {
  final v = q.toDouble();
  return (v - v.roundToDouble()).abs() < 0.001
      ? v.round().toString()
      : v.toStringAsFixed(1);
}

String apoyoQtyUnit(num q, String unidad) =>
    '${apoyoQty(q)} ${unidad == 'kg' ? 'kg' : 'pz'}';

double apoyoRound2(num v) => (v.toDouble() * 100).roundToDouble() / 100;

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

  bool isOpenAt(DateTime now) =>
      state == 'abierto' && (closesAt == null || !now.isAfter(closesAt!));

  Duration timeLeftAt(DateTime now) =>
      closesAt == null ? Duration.zero : closesAt!.difference(now);

  String get deliveryLabel =>
      deliveryAt == null ? '' : apoyoLongDate(deliveryAt!);

  String get elDeliveryLabel =>
      deliveryAt == null ? 'el viernes' : 'el ${apoyoLongDate(deliveryAt!)}';

  String get deliveryClock => deliveryAt == null ? '' : apoyoClock(deliveryAt!);

  String handoffLine(String fulfillment) {
    final day = deliveryLabel;
    if (day.isEmpty) return '';
    return fulfillment == 'domicilio'
        ? 'Te llega el $day después de las $deliveryClock.'
        : 'Recoges en la tienda el $day $kApoyoPickupWindow.';
  }
}

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

  double get step => unidad == 'kg' ? 0.5 : 1;

  bool get isBundle => components.length > 1;

  String get priceLabel => unidad == 'kg' ? '/ kg' : 'c/u';
}

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
  final String id;
  final String cancelRequestState;
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
    required this.id,
    required this.cancelRequestState,
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
      id: doc.id,
      cancelRequestState: d['cancelRequest'] is Map
          ? ((d['cancelRequest'] as Map)['state'] ?? '').toString()
          : '',
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

  Map<String, double> get quantities => {
        for (final it in items)
          if (it.catalogItemId.isNotEmpty) it.catalogItemId: it.quantity,
      };
}

class ApoyoDraftLine {
  final ApoyoCatalogItem item;
  final double quantity;

  const ApoyoDraftLine(this.item, this.quantity);

  double get total => apoyoRound2(item.memberPrice * quantity);
}

double apoyoDraftSubtotal(List<ApoyoDraftLine> lines) {
  var subtotal = 0.0;
  for (final l in lines) {
    subtotal += l.total;
  }
  return apoyoRound2(subtotal);
}
