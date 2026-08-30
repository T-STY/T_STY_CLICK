import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApoyoCartProvider extends ChangeNotifier {
  static const String storageKey = 'tsty_apoyo_cart';

  final Map<String, double> _lines = <String, double>{};
  String? _cycleId;
  bool _loaded = false;

  final Completer<void> _readyCompleter = Completer<void>();

  ApoyoCartProvider() {
    unawaited(_load());
  }

  Future<void> get ready => _readyCompleter.future;

  bool get isLoaded => _loaded;

  String? get cycleId => _cycleId;

  bool get isEmpty => _lines.isEmpty;

  bool get isNotEmpty => _lines.isNotEmpty;

  int get lineCount => _lines.length;

  Map<String, double> get lines => Map.unmodifiable(_lines);

  double qtyOf(String catalogItemId) => _lines[catalogItemId] ?? 0;

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

  void adoptCycle(String cycleId) {
    if (_cycleId == cycleId) return;
    _cycleId = cycleId;
    _persist();
    notifyListeners();
  }

  void startFresh(String cycleId) {
    if (_cycleId == cycleId && _lines.isEmpty) return;
    _cycleId = cycleId;
    _lines.clear();
    _persist();
    notifyListeners();
  }

  void replaceAll(String cycleId, Map<String, double> quantities) {
    _cycleId = cycleId;
    _lines
      ..clear()
      ..addEntries(quantities.entries.where((e) => e.value > 0));
    _persist();
    notifyListeners();
  }

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

  void clear() {
    if (_lines.isEmpty && _cycleId == null) return;
    _lines.clear();
    _cycleId = null;
    _persist();
    notifyListeners();
  }

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
