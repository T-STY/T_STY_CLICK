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
  // Whether this order was placed for in-store pickup. Drives the
  // "Recoger en tienda" label on the detail screen and swaps the
  // displayed address from the user's home address to the store's
  // address (`settings/address`).
  final bool isInstorePickup;

  /// Client-chosen 30-min slot {date, start, end} (HH:mm), or null =
  /// "lo antes posible". Written server-side by placeOrder.
  final Map<String, dynamic>? deliveryWindow;

  /// Free-text note the customer left at checkout (may be empty).
  final String notes;

  /// Cash the customer chose to pay with (efectivo only), 0 when unspecified.
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

  /// "4:00 PM – 4:30 PM", or null when no window was chosen.
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

  /// Status label as the user should see it. Firestore still stores the
  /// canonical workflow value (so PDV, admin and CFs keep agreeing on
  /// state), but a pickup order in "Enviado" really means the package is
  /// waiting at the counter for the customer — so we display "Listo"
  /// instead. Single-word label sits naturally next to "Enviado",
  /// "Entregado", "Cancelado" in the same status slot, and the chip
  /// directly above already says "Recoger en tienda" so context makes
  /// "Listo" unambiguously mean "ready to collect".
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
      productId: parseOptString(data['productId']),
      variantKey: parseOptString(data['variantKey']),
      variantName: parseOptString(data['variantName']),
    );
  }
}
