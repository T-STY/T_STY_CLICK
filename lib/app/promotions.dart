import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../components/bottom_fade.dart';
import '../components/custom_loader.dart';
import '../components/shimmer_placeholder.dart';
import 'cart/cart_provider.dart';
import '../../auth/login_page.dart';
import '../../custom_page_route.dart';

class PromotionDetailPage extends StatefulWidget {
  final String promotionId;
  final VoidCallback onBackPressed;

  const PromotionDetailPage({
    super.key,
    required this.promotionId,
    required this.onBackPressed,
  });

  @override
  State<PromotionDetailPage> createState() => _PromotionDetailPageState();
}

class _PromotionDetailPageState extends State<PromotionDetailPage> {
  Map<String, dynamic>? promoData;
  Map<String, dynamic>? triggerProductData;
  String? triggerProductId;
  List<Map<String, dynamic>> optionProducts = [];
  List<Map<String, dynamic>> requiredProducts = [];
  String? selectedOptionProductId;

  @override
  void initState() {
    super.initState();
    _fetchPromotion();
  }

  Future<void> _fetchPromotion() async {
    final docSnapshot = await FirebaseFirestore.instance
        .collection('promotions')
        .doc(widget.promotionId)
        .get();

    if (!docSnapshot.exists) return;

    final data = docSnapshot.data()!;
    setState(() {
      promoData = data;
    });

    final type = data['type'] as String? ?? '';

    if (type == 'combo_exact') {
      await _fetchRequiredProducts(data['requiredProductIds'] ?? []);
    } else if (type == 'combo_brand') {
      await _fetchTriggerProduct(data['triggerProductId'] ?? '');
      await _fetchBrandProducts(data['targetBrand'] ?? '');
    } else if (type == 'combo_choice') {
      await _fetchTriggerProduct(data['triggerProductId'] ?? '');
      await _fetchOptionProducts(data['targetProductIds'] ?? []);
    } else if (type == 'bxgy') {
      await _fetchBxgyProduct(data['targetProductId'] ?? '');
    }

    if (mounted) setState(() {});
  }

  Future<void> _fetchTriggerProduct(String id) async {
    if (id.isEmpty) return;
    final doc = await FirebaseFirestore.instance.collection('products').doc(id).get();
    if (doc.exists) {
      triggerProductId = doc.id;
      triggerProductData = doc.data()!..['id'] = doc.id;
    }
  }

  Future<void> _fetchRequiredProducts(List<dynamic> ids) async {
    for (String id in ids) {
      final doc = await FirebaseFirestore.instance.collection('products').doc(id).get();
      if (doc.exists) {
        requiredProducts.add(doc.data()!..['id'] = doc.id);
      }
    }
  }

  Future<void> _fetchOptionProducts(List<dynamic> ids) async {
    for (String id in ids) {
      final doc = await FirebaseFirestore.instance.collection('products').doc(id).get();
      if (doc.exists) {
        optionProducts.add(doc.data()!..['id'] = doc.id);
      }
    }
  }

  Future<void> _fetchBrandProducts(String brand) async {
    if (brand.isEmpty) return;
    final query = await FirebaseFirestore.instance
        .collection('products')
        .where('brand', isEqualTo: brand)
        .get();
    for (var doc in query.docs) {
      if (doc.id != triggerProductId) {
        optionProducts.add(doc.data()..['id'] = doc.id);
      }
    }
  }

  Future<void> _fetchBxgyProduct(String id) async {
    if (id.isEmpty) return;
    final doc = await FirebaseFirestore.instance.collection('products').doc(id).get();
    if (doc.exists) {
      triggerProductId = doc.id;
      triggerProductData = doc.data()!..['id'] = doc.id;
    }
  }

  String _getPromoDescription() {
    return '¡Aprovecha esta promoción especial! Agrega los productos indicados a tu carrito y el descuento se aplicará automáticamente. Las promociones están sujetas a disponibilidad de inventario.';
  }

  double _getDisplayPrice() {
    final type = promoData?['type'] ?? '';
    if (type == 'bxgy') {
      final payQty = (promoData?['payQuantity'] ?? 2) as int;
      final price = (triggerProductData?['price'] as num?)?.toDouble() ?? 0;
      return payQty * price;
    }
    return (promoData?['comboPrice'] as num?)?.toDouble() ?? 0;
  }

  String? _firstVariantProductName() {
    final type = promoData?['type'] ?? '';
    final List<Map<String, dynamic>> involved = [];
    if (type == 'combo_exact') {
      involved.addAll(requiredProducts.cast<Map<String, dynamic>>());
    } else if (type == 'combo_choice' || type == 'combo_brand') {
      if (triggerProductData != null) involved.add(triggerProductData!);
      if (selectedOptionProductId != null) {
        try {
          involved.add(optionProducts
              .firstWhere((p) => p['id'] == selectedOptionProductId));
        } catch (_) {}
      }
    } else if (type == 'bxgy') {
      if (triggerProductData != null) involved.add(triggerProductData!);
    }
    for (final p in involved) {
      if (p['has_variants'] == true) {
        return (p['nombre'] as String?) ?? 'Producto';
      }
    }
    return null;
  }

  Future<void> _addPromoToCart() async {
    final cartProvider = Provider.of<CartProvider>(context, listen: false);
    final type = promoData?['type'] ?? '';

    final variantBlocker = _firstVariantProductName();
    if (variantBlocker != null) {
      await _showVariantBlockedDialog(variantBlocker);
      return;
    }

    if (type == 'combo_exact') {
      for (var product in requiredProducts) {
        cartProvider.addItem(
          product['id'],
          product['nombre'] ?? '',
          (product['price'] as num).toDouble(),
          product['image_url'] ?? '',
          quantity: 1,
          isBulk: product['isBulk'] ?? false,
          stock: (product['stock'] as num?)?.toDouble() ?? 0,
          typeSpecific: product['type_specific'] as String?,
          variante: product['variante'] as String?,
          brand: product['brand'] as String? ?? '',
        );
      }
    } else if (type == 'combo_choice' || type == 'combo_brand') {
      if (triggerProductData != null) {
        cartProvider.addItem(
          triggerProductData!['id'],
          triggerProductData!['nombre'] ?? '',
          (triggerProductData!['price'] as num).toDouble(),
          triggerProductData!['image_url'] ?? '',
          quantity: 1,
          isBulk: triggerProductData!['isBulk'] ?? false,
          stock: (triggerProductData!['stock'] as num?)?.toDouble() ?? 0,
          typeSpecific: triggerProductData!['type_specific'] as String?,
          variante: triggerProductData!['variante'] as String?,
          brand: triggerProductData!['brand'] as String? ?? '',
        );
      }
      if (selectedOptionProductId != null) {
        final selected = optionProducts.firstWhere(
              (p) => p['id'] == selectedOptionProductId,
        );
        cartProvider.addItem(
          selected['id'],
          selected['nombre'] ?? '',
          (selected['price'] as num).toDouble(),
          selected['image_url'] ?? '',
          quantity: 1,
          isBulk: selected['isBulk'] ?? false,
          stock: (selected['stock'] as num?)?.toDouble() ?? 0,
          typeSpecific: selected['type_specific'] as String?,
          variante: selected['variante'] as String?,
          brand: selected['brand'] as String? ?? '',
        );
      }
    } else if (type == 'bxgy') {
      if (triggerProductData != null) {
        final buyQty = (promoData?['buyQuantity'] ?? 3) as int;
        cartProvider.addItem(
          triggerProductData!['id'],
          triggerProductData!['nombre'] ?? '',
          (triggerProductData!['price'] as num).toDouble(),
          triggerProductData!['image_url'] ?? '',
          quantity: buyQty.toDouble(),
          isBulk: triggerProductData!['isBulk'] ?? false,
          stock: (triggerProductData!['stock'] as num?)?.toDouble() ?? 0,
          typeSpecific: triggerProductData!['type_specific'] as String?,
          variante: triggerProductData!['variante'] as String?,
          brand: triggerProductData!['brand'] as String? ?? '',
        );
      }
    }

    if (!mounted) return;
    _showSuccessDialog();
  }

  Future<void> _showVariantBlockedDialog(String productName) async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: AlertDialog(
            title: const Text('Esta promoción no se puede aplicar'),
            content: Text(
                '"$productName" tiene variantes (sabores, presentaciones, etc.). '
                'Por ahora, agrega esa variante directamente desde el catálogo y la promoción se aplicará automáticamente.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Entendido'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showSuccessDialog() async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: AlertDialog(
            title: const Text('Productos agregados'),
            content: const Text(
                'Los productos de la promoción han sido agregados exitosamente al carrito.'),
            actions: <Widget>[
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  widget.onBackPressed();
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      },
    );
  }

  String _detailLine(Map<String, dynamic> p) {
    final variante = (p['variante'] as String?)?.trim() ?? '';
    final typeSpecific = (p['type_specific'] as String?)?.trim() ?? '';
    return [variante, typeSpecific].where((s) => s.isNotEmpty).join(' · ');
  }

  Widget _includedRow(Map<String, dynamic> product, bool isDark,
      {String? badge}) {
    final name = (product['nombre'] as String?) ?? 'Producto';
    final img = (product['image_url'] as String?) ?? '';
    final sub = _detailLine(product);
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
                Text(name,
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
                if (badge != null) ...[
                  const SizedBox(height: 4),
                  Text(badge,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.deepOrange)),
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

  Widget _optionTile(Map<String, dynamic> product, bool isDark) {
    final id = product['id'] as String;
    final name = (product['nombre'] as String?) ?? 'Producto';
    final img = (product['image_url'] as String?) ?? '';
    final sub = _detailLine(product);
    final bool selected = selectedOptionProductId == id;
    return GestureDetector(
      onTap: () => setState(() => selectedOptionProductId = id),
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
                  Text(name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                  if (sub.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12.5, color: Colors.grey[600])),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(selected ? Icons.check_circle : Icons.circle_outlined,
                color: selected ? const Color(0xFF1A1A1A) : Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  bool _canAddToCart() {
    final type = promoData?['type'] ?? '';
    if (type == 'combo_exact') return requiredProducts.isNotEmpty;
    if (type == 'combo_choice' || type == 'combo_brand') {
      return triggerProductData != null && selectedOptionProductId != null;
    }
    if (type == 'bxgy') return triggerProductData != null;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (promoData == null) {
      return const Center(child: CustomLoader());
    }

    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bg = isDark ? const Color(0xFF1A1A1D) : Colors.white;
    final Color titleColor = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final type = promoData!['type'] as String? ?? '';
    final image =
        (promoData!['imageURL'] ?? promoData!['imageUrl'] ?? '').toString();
    final name = (promoData!['name'] as String?) ?? 'Promoción';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        widget.onBackPressed();
      },
      child: Container(
        color: bg,
        child: Stack(
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
                    )
                  else
                    _fallbackHeader(type),
                  const SizedBox(height: 14),
                  Text(name,
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                          color: titleColor)),
                  const SizedBox(height: 8),
                  Text(_getPromoDescription(),
                      style: TextStyle(
                          fontSize: 14, height: 1.35, color: Colors.grey[600])),
                  ..._buildSections(type, isDark),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildBottomBar(context, isDark),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSections(String type, bool isDark) {
    final widgets = <Widget>[];
    if (type == 'combo_exact') {
      widgets
        ..add(const SizedBox(height: 20))
        ..add(_sectionLabel('Incluye'))
        ..add(const SizedBox(height: 8))
        ..addAll(requiredProducts.map((p) => _includedRow(p, isDark)));
    } else if (type == 'bxgy' && triggerProductData != null) {
      widgets
        ..add(const SizedBox(height: 20))
        ..add(_sectionLabel('Producto'))
        ..add(const SizedBox(height: 8))
        ..add(_includedRow(triggerProductData!, isDark,
            badge:
                'Lleva ${promoData!['buyQuantity']}, Paga ${promoData!['payQuantity']}'));
    } else if (type == 'combo_choice' || type == 'combo_brand') {
      if (triggerProductData != null) {
        widgets
          ..add(const SizedBox(height: 20))
          ..add(_sectionLabel('Incluye'))
          ..add(const SizedBox(height: 8))
          ..add(_includedRow(triggerProductData!, isDark));
      }
      if (optionProducts.isNotEmpty) {
        widgets
          ..add(const SizedBox(height: 20))
          ..add(_sectionLabel('Elige una opción'))
          ..add(const SizedBox(height: 8))
          ..addAll(optionProducts.map((p) => _optionTile(p, isDark)));
      }
    }
    return widgets;
  }

  Widget _sectionLabel(String text) => Text(text,
      style: const TextStyle(
          fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.2));

  Widget _fallbackHeader(String type) {
    return Container(
      width: double.infinity,
      height: 160,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [Colors.deepOrange.shade400, Colors.orange.shade300],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.local_offer, size: 48, color: Colors.white),
            const SizedBox(height: 8),
            Text(_promoTypeLabel(type),
                style: const TextStyle(
                    color: Colors.white70, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context, bool isDark) {
    final bool isGuest = FirebaseAuth.instance.currentUser == null;
    final bool canAdd = _canAddToCart();
    final price = _getDisplayPrice();
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
              Text('Precio',
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
                onPressed: (isGuest || canAdd)
                    ? () {
                        if (FirebaseAuth.instance.currentUser == null) {
                          Navigator.push(
                              context, customPageRoute(const LoginPage()));
                        } else if (canAdd) {
                          _addPromoToCart();
                        }
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      (isGuest || canAdd) ? Colors.black : Colors.grey[300],
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey[300],
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: const Text('Agregar al carrito',
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

  String _promoTypeLabel(String type) {
    switch (type) {
      case 'combo_exact':
        return 'Combo Exacto';
      case 'combo_choice':
        return 'Combo con Opciones';
      case 'combo_brand':
        return 'Combo por Marca';
      case 'bxgy':
        return 'Lleva más, Paga menos';
      default:
        return 'Promoción';
    }
  }
}
