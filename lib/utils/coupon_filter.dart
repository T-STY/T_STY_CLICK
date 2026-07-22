/// Shared coupon `productFilter` helpers — the single source of truth for
/// rendering a filter's scope as a short label.
///
/// ╔══════════════════════════════════════════════════════════════════════╗
/// ║  MIRROR FILE — must stay byte-identical with                         ║
/// ║  t_sty_delivery/lib/utils/coupon_filter.dart.                        ║
/// ║                                                                      ║
/// ║  The two repos can't share Dart code directly, so this helper is     ║
/// ║  vendored into both. If you edit one, copy it to the other and       ║
/// ║  confirm with `diff`. (Same pattern as firestore.rules.)             ║
/// ╚══════════════════════════════════════════════════════════════════════╝
///
/// Canonical filter shape (see also functions/index.js):
/// ```
/// { mode: 'include' | 'exclude',
///   subcategories: List<String>,
///   provedores:    List<String>,
///   productIds:    List<String> }
/// ```
///
/// The field is OMITTED entirely when the filter is inactive — callers should
/// treat `null` and any other non-active mode as "no filter".
library;

bool _isActiveMode(String mode) => mode == 'include' || mode == 'exclude';

List<String> _readList(dynamic v) =>
    (v is List) ? v.map((e) => e.toString()).toList() : const <String>[];

/// Returns the canonical 'mode' string from a filter map, or null if the
/// filter is missing or inactive.
String? activeFilterMode(Map? filterMap) {
  if (filterMap == null) return null;
  final mode = (filterMap['mode'] ?? 'all').toString();
  return _isActiveMode(mode) ? mode : null;
}

/// One-line summary used everywhere ("Sólo en 3 subcat. · 2 prov.",
/// "Excepto en 5 prod."). Returns empty string when the filter is inactive.
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

/// Same data, broken apart for screens that want to render the lists as
/// chips instead of a roll-up count.
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

/// Returns parsed details, or null when the filter is missing/inactive.
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
