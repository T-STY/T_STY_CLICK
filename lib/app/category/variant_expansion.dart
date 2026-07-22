import 'package:cloud_firestore/cloud_firestore.dart';

class VariantEntry {

  final DocumentSnapshot doc;

  Map<String, dynamic> get parentData {
    final raw = doc.data();
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return const <String, dynamic>{};
  }

  final String? variantKey;

  final Map<String, dynamic>? variantData;

  const VariantEntry({
    required this.doc,
    this.variantKey,
    this.variantData,
  });

  bool get isVariant => variantKey != null;

  String get lineKey =>
      variantKey == null ? doc.id : '${doc.id}#$variantKey';

  double effectivePrice(double parentPrice) =>
      (variantData?['price'] as num?)?.toDouble() ?? parentPrice;

  double effectiveCost(double parentCost) =>
      (variantData?['cost'] as num?)?.toDouble() ?? parentCost;

  double effectiveStock(double parentStock) {
    if (!isVariant) return parentStock;
    return (variantData?['stock'] as num?)?.toDouble() ?? 0.0;
  }

  String effectiveImageUrl(String parentImageUrl) {
    final v = (variantData?['image_url'] as String?) ?? '';
    return v.isNotEmpty ? v : parentImageUrl;
  }

  String? get variantName {
    if (variantData == null) return null;
    return (variantData!['name'] ?? variantKey).toString();
  }
}

List<VariantEntry> expandVariantEntries(Iterable<DocumentSnapshot> docs) {
  final out = <VariantEntry>[];
  for (final doc in docs) {
    final raw = doc.data();
    final Map<String, dynamic> data = raw is Map<String, dynamic>
        ? raw
        : raw is Map
            ? Map<String, dynamic>.from(raw)
            : const <String, dynamic>{};
    if (data['has_variants'] != true) {
      out.add(VariantEntry(doc: doc));
      continue;
    }
    final variants = data['variants'];
    if (variants is! Map) {
      out.add(VariantEntry(doc: doc));
      continue;
    }
    final order = (data['variant_order'] as List?)
            ?.map((e) => e.toString())
            .where(variants.containsKey)
            .toList() ??
        variants.keys.map((e) => e.toString()).toList();
    for (final k in variants.keys) {
      final s = k.toString();
      if (!order.contains(s)) order.add(s);
    }
    for (final key in order) {
      final v = variants[key];
      if (v is! Map) continue;
      if (v['hide_online'] == true) continue;
      out.add(VariantEntry(
        doc: doc,
        variantKey: key,
        variantData: Map<String, dynamic>.from(v),
      ));
    }
  }
  return out;
}
