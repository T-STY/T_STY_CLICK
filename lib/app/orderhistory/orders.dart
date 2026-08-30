import 'package:cloud_firestore/cloud_firestore.dart';
import 'applied_coupon.dart';

class UserOrder {
  final String id;
  final DateTime timestamp;
  final double subtotal;
  final double deliveryFee;
  final double discount;
  final double total;
  final String paymentMethod;
  String status;
  final String addressId;
  final AppliedCoupon? appliedCoupon;
  final List<OrderItem> items;
  final bool useRewardsBalance;
  final double appliedRewards;
  final String userId;

  final bool isInstorePickup;

  final Map<String, dynamic>? deliveryWindow;

  final String notes;

  final double cashPaidWith;

  UserOrder({
    required this.id,
    required this.timestamp,
    required this.subtotal,
    required this.deliveryFee,
    required this.discount,
    required this.total,
    required this.paymentMethod,
    required this.status,
    required this.addressId,
    this.appliedCoupon,
    required this.items,
    required this.useRewardsBalance,
    this.appliedRewards = 0.0,
    required this.userId,
    this.isInstorePickup = false,
    this.deliveryWindow,
    this.notes = '',
    this.cashPaidWith = 0,
  });

  String? get deliveryWindowLabel {
    final dw = deliveryWindow;
    if (dw == null) return null;
    String? fmt(Object? hhmm) {
      if (hhmm is! String) return null;
      final p = hhmm.split(':');
      if (p.length != 2) return null;
      final h = int.tryParse(p[0]);
      final m = int.tryParse(p[1]);
      if (h == null || m == null) return null;
      final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
      final sfx = h < 12 ? 'AM' : 'PM';
      return m == 0 ? '$h12 $sfx' : '$h12:${m.toString().padLeft(2, '0')} $sfx';
    }

    final s = fmt(dw['start']);
    final e = fmt(dw['end']);
    if (s == null || e == null) return null;
    return '$s – $e';
  }

  String get displayStatus {
    if (isInstorePickup && status.toLowerCase() == 'enviado') {
      return 'Listo';
    }
    return status;
  }

  factory UserOrder.fromDocument(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    double parseDouble(dynamic value) {
      if (value is int) {
        return value.toDouble();
      } else if (value is double) {
        return value;
      } else {
        return 0.0;
      }
    }

    String parseString(dynamic value) {
      if (value is String) {
        return value;
      } else {
        return 'N/A';
      }
    }

    bool parseBool(dynamic value) {
      if (value is bool) {
        return value;
      } else {
        return false;
      }
    }

    AppliedCoupon? parseCoupon(dynamic value) {
      if (value is Map<String, dynamic>) {
        return AppliedCoupon.fromMap(value);
      } else {
        return null;
      }
    }

    return UserOrder(
      id: doc.id,
      timestamp: (data['timestamp'] as Timestamp).toDate(),
      subtotal: parseDouble(data['subtotal']),
      deliveryFee: parseDouble(data['deliveryFee']),
      discount: parseDouble(data['discount']),
      total: parseDouble(data['total']),
      paymentMethod: parseString(data['paymentMethod']),
      status: parseString(data['state']),
      addressId: parseString(data['addressId']),
      appliedCoupon: parseCoupon(data['appliedCoupon']),
      items: (data['items'] as List<dynamic>?)?.map((item) => OrderItem.fromMap(item)).toList() ?? [],
      useRewardsBalance: parseBool(data['useRewardsBalance']),
      appliedRewards: parseDouble(data['appliedRewards']),
      userId: parseString(data['userId']),
      isInstorePickup: parseBool(data['isInstorePickup']),
      deliveryWindow: data['deliveryWindow'] is Map
          ? (data['deliveryWindow'] as Map).cast<String, dynamic>()
          : null,
      notes: (data['notes'] ?? '').toString().trim(),
      cashPaidWith: parseDouble(data['cashPaidWith']),
    );
  }
}

class OrderItem {
  final String objectId;
  final String name;
  final double quantity;
  final double price;
  final String imageUrl;
  final bool isBulk;
  /// Piezas pedidas y kilos que salieron de la báscula, cuando se pidió por
  /// pieza. El cliente pidió piezas pero paga por lo que pesaron, así que el
  /// ticket enseña las dos cosas.
  final double? pieces;
  final double? weightKg;

  final String productId;
  final String? variantKey;
  final String? variantName;

  OrderItem({
    required this.objectId,
    required this.name,
    required this.quantity,
    required this.price,
    required this.imageUrl,
    required this.isBulk,
    this.pieces,
    this.weightKg,
    String? productId,
    this.variantKey,
    this.variantName,
  }) : productId = productId ?? objectId;

  factory OrderItem.fromMap(Map<String, dynamic> data) {
    double parseDouble(dynamic value) {
      if (value is int) {
        return value.toDouble();
      } else if (value is double) {
        return value;
      } else {
        return 0.0;
      }
    }

    String parseString(dynamic value) {
      if (value is String) {
        return value;
      } else {
        return 'Unnamed';
      }
    }

    String? parseOptString(dynamic value) =>
        value is String && value.isNotEmpty ? value : null;

    bool parseBool(dynamic value) {
      if (value is bool) {
        return value;
      } else {
        return false;
      }
    }

    return OrderItem(
      objectId: parseString(data['objectID'] ?? data['objectId']),
      name: parseString(data['nombre']),
      quantity: parseDouble(data['quantity']),
      price: parseDouble(data['price']),
      imageUrl: parseString(data['imageUrl']),
      isBulk: parseBool(data['isBulk']),
      pieces: (data['pieces'] as num?)?.toDouble(),
      weightKg: (data['weightKg'] as num?)?.toDouble(),
      productId: parseOptString(data['productId']),
      variantKey: parseOptString(data['variantKey']),
      variantName: parseOptString(data['variantName']),
    );
  }
}
