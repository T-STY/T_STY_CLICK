import 'dart:math';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../auth/login_page.dart';
import '../../components/bottom_fade.dart';
import '../../components/shimmer_placeholder.dart';
import '../../custom_page_route.dart';
import '../cart/cart_provider.dart';

class ComboDetailPage extends StatefulWidget {
  final String comboId;
  final VoidCallback? onBack;

  const ComboDetailPage({super.key, required this.comboId, this.onBack});

  @override
  State<ComboDetailPage> createState() => _ComboDetailPageState();
}

class _ComboDetailPageState extends State<ComboDetailPage> {
  bool _loading = true;
  bool _error = false;
  Map<String, dynamic> _combo = {};
  final Map<String, Map<String, dynamic>> _products = {};
  final Map<int, Map<String, int>> _slotSelections = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('promotions')
          .doc(widget.comboId)
          .get();
      if (!doc.exists || doc.data() == null) {
        setState(() {
          _error = true;
          _loading = false;
        });
        return;
      }
      _combo = doc.data()!;

      final ids = <String>{};
      for (final f in (_combo['fixedItems'] as List? ?? const [])) {
        if (f is Map && f['productId'] != null) ids.add(f['productId'].toString());
      }
      final slots = _combo['slots'] as List? ?? const [];
      for (final s in slots) {
        for (final o in (s['options'] as List? ?? const [])) {
          ids.add(o.toString());
        }
      }

      await Future.wait(ids.map((id) async {
        try {
          final p = await FirebaseFirestore.instance
              .collection('products')
              .doc(id)
              .get();
          if (p.exists && p.data() != null) _products[id] = p.data()!;
        } catch (_) {}
      }));

      for (int i = 0; i < slots.length; i++) {
        _slotSelections[i] = {};
      }
      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = true;
          _loading = false;
        });
      }
    }
  }

  List<dynamic> get _fixedItems => _combo['fixedItems'] as List? ?? const [];
  List<dynamic> get _slots => _combo['slots'] as List? ?? const [];
  bool get _isFixedPrice =>
      (_combo['pricingMode'] as String? ?? 'fixed') == 'fixed';

  double _priceOf(String id) =>
      (_products[id]?['price'] as num?)?.toDouble() ?? 0.0;

  double _basePrice() {
    double base = 0;
    for (final f in _fixedItems) {
      if (f is Map) {
        final id = f['productId'].toString();
        final qty = (f['quantity'] as num?)?.toDouble() ?? 1.0;
        base += _priceOf(id) * qty;
      }
    }
    _slotSelections.forEach((_, sel) {
      sel.forEach((id, qty) {
        base += _priceOf(id) * qty;
      });
    });
    return base;
  }

  double _comboPrice() {
    if (_isFixedPrice) {
      return (_combo['fixedPrice'] as num?)?.toDouble() ?? 0.0;
    }
    final discount = (_combo['discountAmount'] as num?)?.toDouble() ?? 0.0;
    return max(0, _basePrice() - discount);
  }

  Map<String, int> _componentNeeds() {
    final need = <String, int>{};
    for (final f in _fixedItems) {
      if (f is Map && f['productId'] != null) {
        final id = f['productId'].toString();
        final qty = (f['quantity'] as num?)?.toInt() ?? 1;
        need[id] = (need[id] ?? 0) + qty;
      }
    }
    _slotSelections.forEach((_, sel) {
      sel.forEach((id, qty) {
        need[id] = (need[id] ?? 0) + qty;
      });
    });
    return need;
  }

  int _slotCount(int i) {
    final sel = _slotSelections[i];
    if (sel == null) return 0;
    int t = 0;
    for (final q in sel.values) {
      t += q;
    }
    return t;
  }

  int _maxQty() {
    final need = _componentNeeds();
    if (need.isEmpty) return 0;
    int m = 99;
    need.forEach((id, q) {
      final stock = (_products[id]?['stock'] as num?)?.toDouble() ?? 0.0;
      final avail = q <= 0 ? 0 : (stock ~/ q);
      m = min(m, avail);
    });
    return m;
  }

  bool get _allSlotsChosen {
    for (int i = 0; i < _slots.length; i++) {
      final pick = (_slots[i]['pick'] as num?)?.toInt() ?? 1;
      if (_slotCount(i) != pick) return false;
    }
    return true;
  }

  int _optionStockCap(String id) {
    final stock = (_products[id]?['stock'] as num?)?.toDouble() ?? 0.0;
    return stock.floor();
  }

  void _selectSingle(int slotIndex, String productId) {
    final current = _slotSelections[slotIndex] ?? const {};
    setState(() {
      if (current[productId] == 1) {
        _slotSelections[slotIndex] = {};
      } else {
        _slotSelections[slotIndex] = {productId: 1};
      }
    });
  }

  void _incOption(int slotIndex, String productId) {
    final pick = (_slots[slotIndex]['pick'] as num?)?.toInt() ?? 1;
    if (_slotCount(slotIndex) >= pick) return;
    final sel = Map<String, int>.from(_slotSelections[slotIndex] ?? const {});
    final next = (sel[productId] ?? 0) + 1;
    if (next > _optionStockCap(productId)) return;
    sel[productId] = next;
    setState(() => _slotSelections[slotIndex] = sel);
  }

  void _decOption(int slotIndex, String productId) {
    final sel = Map<String, int>.from(_slotSelections[slotIndex] ?? const {});
    final next = (sel[productId] ?? 0) - 1;
    if (next <= 0) {
      sel.remove(productId);
    } else {
      sel[productId] = next;
    }
    setState(() => _slotSelections[slotIndex] = sel);
  }

  Future<void> _showInfo(String title, String msg) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(title),
          content: Text(msg),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Entendido')),
          ],
        ),
      );

  void _addToCart() {
    if (FirebaseAuth.instance.currentUser == null) {
      Navigator.push(context, customPageRoute(const LoginPage()));
      return;
    }
    if (!_allSlotsChosen) {
      _showInfo('Completa tu combo', 'Elige las opciones de cada apartado.');
      return;
    }
    final maxQty = _maxQty();
    if (maxQty < 1) {
      _showInfo('Sin stock', 'No hay stock suficiente para este combo.');
      return;
    }

    final merged = <String, Map<String, dynamic>>{};
    void addComp(String id, int qty) {
      final p = _products[id] ?? const {};
      final existing = merged[id];
      final prevQty = (existing?['quantity'] as num?)?.toInt() ?? 0;
      merged[id] = {
        'productId': id,
        'nombre': p['nombre'] ?? 'Producto',
        'imageUrl': p['image_url'] ?? '',
        'price': (p['price'] as num?)?.toDouble() ?? 0.0,
        'stock': (p['stock'] as num?)?.toDouble() ?? 0.0,
        'isBulk': p['bulk'] as bool? ?? false,
        'typeSpecific': p['type_specific'] as String?,
        'variante': p['variante'] as String?,
        'brand': (p['brand'] ?? '') as String,
        'quantity': prevQty + qty,
      };
    }

    for (final f in _fixedItems) {
      if (f is Map && f['productId'] != null) {
        addComp(f['productId'].toString(),
            (f['quantity'] as num?)?.toInt() ?? 1);
      }
    }
    _slotSelections.forEach((_, sel) {
      sel.forEach((id, qty) {
        addComp(id, qty);
      });
    });

    final name = (_combo['name'] as String?)?.trim().isNotEmpty == true
        ? _combo['name'] as String
        : 'Combo';
    final double savings = _basePrice() - _comboPrice();

    Provider.of<CartProvider>(context, listen: false).addCombo(
      comboId: widget.comboId,
      name: name,
      savings: savings < 0 ? 0 : savings,
      components: merged.values.toList(),
    );

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Combo agregado'),
        content: const Text('Tu combo se agregó al carrito.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.onBack?.call();
            },
            child: const Text('Seguir comprando'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bg = isDark ? const Color(0xFF1A1A1D) : Colors.white;
    final content = _buildBody(context, isDark);

    if (widget.onBack == null) {
      return Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          scrolledUnderElevation: 0,
          backgroundColor: Colors.transparent,
          title: const Text('Combo',
              style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700)),
          iconTheme: const IconThemeData(color: Colors.black),
        ),
        body: SafeArea(top: false, child: content),
      );
    }
    return Container(color: bg, child: content);
  }

  Widget _buildBody(BuildContext context, bool isDark) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error) {
      return const Center(child: Text('No se pudo cargar el combo.'));
    }

    final name = (_combo['name'] as String?) ?? 'Combo';
    final description = (_combo['description'] as String?) ?? '';
    final image = (_combo['imageURL'] ?? _combo['imageUrl'] ?? '').toString();
    final bool isGuest = FirebaseAuth.instance.currentUser == null;
    final Color titleColor = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final bool canAdd = _allSlotsChosen && _maxQty() >= 1;

    return Stack(
      children: [
        BottomFade(
          clearHeight: 150,
          fadeHeight: 90,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 210),
            children: [
              if (image.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: CachedNetworkImage(
                    imageUrl: image,
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    placeholder: (c, u) =>
                        const ShimmerPlaceholder.rectangular(height: 200),
                    errorWidget: (c, u, e) =>
                        Container(height: 200, color: Colors.grey[200]),
                  ),
                ),
              const SizedBox(height: 14),
              Text(name,
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: titleColor)),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(description,
                    style: TextStyle(
                        fontSize: 14, height: 1.35, color: Colors.grey[600])),
              ],
              if (_fixedItems.isNotEmpty) ...[
                const SizedBox(height: 20),
                _sectionLabel('Incluye'),
                const SizedBox(height: 8),
                ..._fixedItems.whereType<Map>().map((f) {
                  final id = f['productId'].toString();
                  final qty = (f['quantity'] as num?)?.toInt() ?? 1;
                  return _fixedRow(id, qty, isDark);
                }),
              ],
              for (int i = 0; i < _slots.length; i++) ...[
                const SizedBox(height: 20),
                _slotSection(i, isDark),
              ],
            ],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _buildBottomBar(context, isDark, isGuest, canAdd),
        ),
      ],
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: const TextStyle(
            fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.2),
      );

  Widget _fixedRow(String id, int qty, bool isDark) {
    final p = _products[id];
    final name = (p?['nombre'] as String?) ?? 'Producto';
    final img = (p?['image_url'] as String?) ?? '';
    final sub = p != null ? _detailLine(p) : '';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 64,
              height: 64,
              child: img.isNotEmpty
                  ? CachedNetworkImage(imageUrl: img, fit: BoxFit.contain)
                  : const Icon(Icons.image, color: Colors.grey),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(qty > 1 ? '$name  x$qty' : name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
                if (sub.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: Colors.grey[600])),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.check_circle, color: Color(0xFF2E7D32), size: 20),
        ],
      ),
    );
  }

  Widget _slotSection(int i, bool isDark) {
    final slot = _slots[i] as Map;
    final title = (slot['title'] as String?)?.trim();
    final pick = (slot['pick'] as num?)?.toInt() ?? 1;
    final options =
        (slot['options'] as List? ?? const []).map((e) => e.toString()).toList();
    final int count = _slotCount(i);
    final bool complete = count == pick;
    final String badge = complete
        ? 'Listo'
        : (pick > 1 ? '$count/$pick' : 'Elige 1');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
                child: _sectionLabel(
                    title?.isNotEmpty == true ? title! : 'Elige tu opción')),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: complete
                    ? const Color(0xFF2E7D32).withValues(alpha: 0.12)
                    : Colors.orange.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                badge,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: complete
                        ? const Color(0xFF2E7D32)
                        : Colors.orange[800]),
              ),
            ),
          ],
        ),
        if (pick > 1) ...[
          const SizedBox(height: 4),
          Text(
            'Puedes repetir la misma opción.',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
        const SizedBox(height: 8),
        ...options.map((id) => _optionTile(i, id, isDark)),
      ],
    );
  }

  Widget _optionTile(int slotIndex, String id, bool isDark) {
    final p = _products[id];
    if (p == null) return const SizedBox.shrink();
    final name = (p['nombre'] as String?) ?? 'Producto';
    final img = (p['image_url'] as String?) ?? '';
    final stock = (p['stock'] as num?)?.toDouble() ?? 0.0;
    final sub = _detailLine(p);
    final pick = (_slots[slotIndex]['pick'] as num?)?.toInt() ?? 1;
    final bool multi = pick > 1;
    final int qty = _slotSelections[slotIndex]?[id] ?? 0;
    final bool selected = qty > 0;
    final bool outOfStock = stock <= 0;
    final bool slotFull = _slotCount(slotIndex) >= pick;
    final bool canInc = !outOfStock && !slotFull && qty < _optionStockCap(id);

    return Opacity(
      opacity: outOfStock ? 0.45 : 1,
      child: GestureDetector(
        onTap: (outOfStock || multi) ? null : () => _selectSingle(slotIndex, id),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isDark ? Colors.grey[850] : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? const Color(0xFF1A1A1A) : Colors.grey.shade300,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 76,
                  height: 76,
                  child: img.isNotEmpty
                      ? CachedNetworkImage(imageUrl: img, fit: BoxFit.contain)
                      : const Icon(Icons.image, color: Colors.grey),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(outOfStock ? '$name (agotado)' : name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    if (sub.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              TextStyle(fontSize: 12.5, color: Colors.grey[600])),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (multi)
                _optionStepper(slotIndex, id, qty: qty, canInc: canInc)
              else
                Icon(
                  selected ? Icons.check_circle : Icons.circle_outlined,
                  color: selected ? const Color(0xFF1A1A1A) : Colors.grey[400],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _optionStepper(int slotIndex, String id,
      {required int qty, required bool canInc}) {
    final bool active = qty > 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _stepButton(
          icon: Icons.remove,
          enabled: qty > 0,
          onTap: () => _decOption(slotIndex, id),
        ),
        Container(
          constraints: const BoxConstraints(minWidth: 26),
          alignment: Alignment.center,
          child: Text(
            '$qty',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: active ? const Color(0xFF1A1A1A) : Colors.grey[400],
            ),
          ),
        ),
        _stepButton(
          icon: Icons.add,
          enabled: canInc,
          onTap: () => _incOption(slotIndex, id),
        ),
      ],
    );
  }

  Widget _stepButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled ? const Color(0xFF1A1A1A) : Colors.grey[200],
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(icon,
            size: 18, color: enabled ? Colors.white : Colors.grey[400]),
      ),
    );
  }

  String _detailLine(Map<String, dynamic> p) {
    final variante = (p['variante'] as String?)?.trim() ?? '';
    final typeSpecific = (p['type_specific'] as String?)?.trim() ?? '';
    return [variante, typeSpecific].where((s) => s.isNotEmpty).join(' · ');
  }

  Widget _buildBottomBar(
      BuildContext context, bool isDark, bool isGuest, bool canAdd) {
    final price = _comboPrice();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 110),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[850] : Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Precio combo',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600])),
              ImageFiltered(
                imageFilter: ImageFilter.blur(
                  sigmaX: isGuest ? 6.0 : 0.0,
                  sigmaY: isGuest ? 6.0 : 0.0,
                ),
                child: Text('\$${price.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF2E7D32))),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: canAdd ? _addToCart : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey[300],
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: const Text('Agregar combo',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }
}
