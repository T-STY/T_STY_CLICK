import '../../utils/coupon_filter.dart' as cf;

class AppliedCoupon {
  final String code;
  final double maxDiscount;
  final double percentage;

  final Map<String, dynamic>? productFilter;

  AppliedCoupon({
    required this.code,
    required this.maxDiscount,
    required this.percentage,
    this.productFilter,
  });

  factory AppliedCoupon.fromMap(Map<String, dynamic> data) {
    final pf = data['productFilter'];
    return AppliedCoupon(
      code: data['code'] ?? 'N/A',
      maxDiscount: (data['max_discount'] ?? 0).toDouble(),
      percentage: (data['percentage'] ?? 0).toDouble(),
      productFilter: pf is Map ? Map<String, dynamic>.from(pf) : null,
    );
  }

  String get productFilterSummary => cf.productFilterSummary(productFilter);
}
