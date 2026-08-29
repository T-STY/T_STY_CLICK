import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ── APOYO SOCIAL — the weekly selection ─────────────────────────────────────
///
/// Deliberately NOT the store's [CartProvider]: that one carries prices,
/// promotions, combos and coupons, and a member browsing the program list must
/// never touch the cart they may already have waiting for a normal delivery.
///
/// What is persisted is only `{cycleId, lines:[{catalogItemId, quantity}]}` —
/// ids and quantities, nothing else. No price, no name, no snapshot copy: the
/// frozen `catalog_snapshot` is the only place a price may come from, and a
/// price cached in SharedPreferences would eventually contradict it.
///
/// The cycle id is stored WITH the lines because a selection has no meaning
/// outside its week. When the week changes, the lines are kept and the member
/// is asked what to do with them — never silently dropped.
class ApoyoCartProvider extends ChangeNotifier {
  static const String storageKey = 'tsty_apoyo_cart';

  /// Insertion-ordered: `Map` literals and `[]=` preserve order in Dart, so
  /// the order the member added things in survives a rebuild. Display order
  /// still comes from the catalog, not from here.
  final Map<String, double> _lines = <String, double>{};
  String? _cycleId;
  bool _loaded = false;

  final Completer<void> _readyCompleter = Completer<void>();

  ApoyoCartProvider() {
    unawaited(_load());
  }

  /// Resolves once SharedPreferences has been read. Screens await this before
  /// deciding whether the stored selection belongs to another cycle — asking
  /// "¿la paso al viernes N?" against a cart that simply had not loaded yet
  /// would be a lie.
  Future<void> get ready => _readyCompleter.future;

  bool get isLoaded => _loaded;

  String? get cycleId => _cycleId;

  bool get isEmpty => _lines.isEmpty;

  bool get isNotEmpty => _lines.isNotEmpty;

  /// Distinct catalog entries, not units.
  int get lineCount => _lines.length;

  Map<String, double> get lines => Map.unmodifiable(_lines);

  double qtyOf(String catalogItemId) => _lines[catalogItemId] ?? 0;

  /// Sets (or removes, at <= 0) one line and tags the selection with
  /// [cycleId]. Re-tagging without clearing is intentional: it is how "sí,
  /// pásala al viernes 4" carries a selection into the new week.
  void setQty({
    required String cycleId,
    required String catalogItemId,
    required double quantity,
  }) {
    if (catalogItemId.isEmpty) return;
    _cycleId = cycleId;
    if (quantity <= 0) {
      if (_lines.remove(catalogItemId) == null) return;
    } else {
      final rounded = (quantity * 100).roundToDouble() / 100;
      if (_lines[catalogItemId] == rounded) return;
      _lines[catalogItemId] = rounded;
    }
    _persist();
    notifyListeners();
  }

  /// "Sí, pásala al viernes N" — same lines, new week.
  void adoptCycle(String cycleId) {
    if (_cycleId == cycleId) return;
    _cycleId = cycleId;
    _persist();
    notifyListeners();
  }

  /// "No, empiezo de nuevo" — and the entry point for a cart that belongs to
  /// a week that is over.
  void startFresh(String cycleId) {
    if (_cycleId == cycleId && _lines.isEmpty) return;
    _cycleId = cycleId;
    _lines.clear();
    _persist();
    notifyListeners();
  }

  /// Seeds the selection from an order the member already placed, so "Editar"
  /// opens the catalog on what they actually ordered instead of an empty
  /// list. Quantities come from the ORDER (server-written), not from a cached
  /// price list.
  void replaceAll(String cycleId, Map<String, double> quantities) {
    _cycleId = cycleId;
    _lines
      ..clear()
      ..addEntries(quantities.entries.where((e) => e.value > 0));
    _persist();
    notifyListeners();
  }

  /// Drops lines whose catalog entry is not in this week's snapshot — an item
  /// the owner deactivated between two cycles. Silent because there is
  /// nothing the member could decide here: the entry does not exist to be
  /// ordered. Returns the names-less ids it removed so the caller can tell
  /// them what happened.
  List<String> pruneTo(Set<String> availableIds) {
    final gone = _lines.keys.where((id) => !availableIds.contains(id)).toList();
    if (gone.isEmpty) return const [];
    for (final id in gone) {
      _lines.remove(id);
    }
    _persist();
    notifyListeners();
    return gone;
  }

  /// After a successful `placeApoyoOrder`: the order document is now the
  /// source of truth for what was asked for, and leaving the selection behind
  /// would show the member the same basket twice.
  void clear() {
    if (_lines.isEmpty && _cycleId == null) return;
    _lines.clear();
    _cycleId = null;
    _persist();
    notifyListeners();
  }

  // ── persistence ───────────────────────────────────────────────────────────

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final cycle = decoded['cycleId'];
          _cycleId = cycle is String && cycle.isNotEmpty ? cycle : null;
          final lines = decoded['lines'];
          if (lines is List) {
            for (final l in lines) {
              if (l is! Map) continue;
              final id = (l['catalogItemId'] ?? '').toString();
              final qty = (l['quantity'] as num?)?.toDouble() ?? 0;
              if (id.isEmpty || qty <= 0) continue;
              _lines[id] = qty;
            }
          }
          // A selection with no week is unusable — it could not be priced
          // against any snapshot.
          if (_cycleId == null) _lines.clear();
        }
      }
    } catch (e) {
      if (kDebugMode) print('Apoyo: no se pudo leer la selección: $e');
    } finally {
      _loaded = true;
      if (!_readyCompleter.isCompleted) _readyCompleter.complete();
      notifyListeners();
    }
  }

  void _persist() => unawaited(_save());

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_cycleId == null || _lines.isEmpty) {
        await prefs.remove(storageKey);
        return;
      }
      await prefs.setString(
        storageKey,
        jsonEncode(<String, dynamic>{
          'cycleId': _cycleId,
          'lines': [
            for (final e in _lines.entries)
              {'catalogItemId': e.key, 'quantity': e.value},
          ],
        }),
      );
    } catch (e) {
      if (kDebugMode) print('Apoyo: no se pudo guardar la selección: $e');
    }
  }
}
