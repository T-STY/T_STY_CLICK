import '../../utils/coupon_filter.dart' as cf;

class AppliedCoupon {
  final String code;
  final double maxDiscount;
  final double percentage;
  /// Snapshot of the coupon's productFilter at order-placement time. Null
  /// when the coupon applied to the full cart. Shape:
  /// `{mode: 'include'|'exclude', subcategories, provedores, productIds}`.
  /// Kept as a raw map (no model class) so future field additions stay
  /// backward-compatible in stored orders.
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

  /// Short label used in order_detail + history cards.
  /// Returns an empty string when no filter snapshot is present.
  String get productFilterSummary => cf.productFilterSummary(productFilter);
}
