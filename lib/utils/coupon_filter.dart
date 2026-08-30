library;

bool _isActiveMode(String mode) => mode == 'include' || mode == 'exclude';

List<String> _readList(dynamic v) =>
    (v is List) ? v.map((e) => e.toString()).toList() : const <String>[];

String? activeFilterMode(Map? filterMap) {
  if (filterMap == null) return null;
  final mode = (filterMap['mode'] ?? 'all').toString();
  return _isActiveMode(mode) ? mode : null;
}

String productFilterSummary(Map? filterMap) {
  final mode = activeFilterMode(filterMap);
  if (mode == null) return '';
  final subs = _readList(filterMap!['subcategories']);
  final provs = _readList(filterMap['provedores']);
  final ids = _readList(filterMap['productIds']);
  final parts = <String>[];
  if (subs.isNotEmpty) parts.add('${subs.length} subcat.');
  if (provs.isNotEmpty) parts.add('${provs.length} prov.');
  if (ids.isNotEmpty) parts.add('${ids.length} prod.');
  final body = parts.isEmpty ? 'sin selección' : parts.join(' · ');
  return mode == 'include' ? 'Sólo en $body' : 'Excepto en $body';
}

class ProductFilterDetails {
  final String mode;
  final List<String> subcategories;
  final List<String> provedores;
  final List<String> productIds;

  const ProductFilterDetails({
    required this.mode,
    required this.subcategories,
    required this.provedores,
    required this.productIds,
  });

  bool get isInclude => mode == 'include';
  bool get hasAnyChips =>
      subcategories.isNotEmpty || provedores.isNotEmpty || productIds.isNotEmpty;
}

ProductFilterDetails? productFilterDetails(Map? filterMap) {
  final mode = activeFilterMode(filterMap);
  if (mode == null) return null;
  return ProductFilterDetails(
    mode: mode,
    subcategories: _readList(filterMap!['subcategories']),
    provedores: _readList(filterMap['provedores']),
    productIds: _readList(filterMap['productIds']),
  );
}
