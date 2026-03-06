class AppliedCoupon {
  final String code;
  final double maxDiscount;
  final double percentage;

  AppliedCoupon({
    required this.code,
    required this.maxDiscount,
    required this.percentage,
  });

  factory AppliedCoupon.fromMap(Map<String, dynamic> data) {
    return AppliedCoupon(
      code: data['code'] ?? 'N/A',
      maxDiscount: (data['max_discount'] ?? 0).toDouble(),
      percentage: (data['percentage'] ?? 0).toDouble(),
    );
  }
}
