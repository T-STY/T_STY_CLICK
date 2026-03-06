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
  final String userId;

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
    required this.userId,
  });

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
      userId: parseString(data['userId']),
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

  OrderItem({
    required this.objectId,
    required this.name,
    required this.quantity,
    required this.price,
    required this.imageUrl,
    required this.isBulk,
  });

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

    bool parseBool(dynamic value) {
      if (value is bool) {
        return value;
      } else {
        return false;
      }
    }

    return OrderItem(
      objectId: parseString(data['objectId']),
      name: parseString(data['nombre']),
      quantity: parseDouble(data['quantity']),
      price: parseDouble(data['price']),
      imageUrl: parseString(data['imageUrl']),
      isBulk: parseBool(data['isBulk']),
    );
  }
}
