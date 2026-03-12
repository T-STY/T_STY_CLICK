import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

  List<String> _getInstructions() {
    final type = promoData?['type'] ?? '';
    switch (type) {
      case 'combo_exact':
        return [
          'Presiona "Agregar combo al carrito" para añadir todos los productos.',
          'El precio especial del combo se aplicará en tu carrito.',
        ];
      case 'combo_choice':
        return [
          'Selecciona una de las opciones disponibles de la lista.',
          'Presiona "Agregar combo al carrito" para añadir ambos productos.',
          'El precio especial se aplicará en tu carrito.',
        ];
      case 'combo_brand':
        return [
          'Elige un producto de la marca participante de la lista.',
          'Presiona "Agregar combo al carrito" para añadir ambos productos.',
          'El precio especial se aplicará en tu carrito.',
        ];
      case 'bxgy':
        final buyQty = promoData?['buyQuantity'] ?? 3;
        final payQty = promoData?['payQuantity'] ?? 2;
        return [
          'Solo pagas $payQty unidades.',
          'Presiona "Agregar combo al carrito" para añadir las $buyQty unidades.',
          'El descuento se reflejará en tu carrito.',
        ];
      default:
        return ['Agrega los productos al carrito para disfrutar la promoción.'];
    }
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

  Future<void> _addPromoToCart() async {
    final cartProvider = Provider.of<CartProvider>(context, listen: false);
    final type = promoData?['type'] ?? '';

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

  Widget _buildProductTile(Map<String, dynamic> product, {bool isMain = false}) {
    final bool isGuest = FirebaseAuth.instance.currentUser == null;
    final price = (product['price'] as num?)?.toDouble() ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: product['image_url'] ?? '',
              width: 50,
              height: 50,
              fit: BoxFit.contain,
              placeholder: (context, url) =>
              const ShimmerPlaceholder(width: 50, height: 50),
              errorWidget: (context, url, error) =>
              const Icon(Icons.broken_image),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product['nombre'] ?? 'Producto',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: isMain ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                if (product['variante'] != null && (product['variante'] as String).isNotEmpty)
                  Text(
                    product['variante'],
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ImageFiltered(
                  imageFilter: ImageFilter.blur(
                    sigmaX: isGuest ? 6.0 : 0.0,
                    sigmaY: isGuest ? 6.0 : 0.0,
                  ),
                  child: Text(
                    'Precio unitario: \$${price.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ),
              ],
            ),
          ),
          if (isMain)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Principal',
                style: TextStyle(fontSize: 12, color: Colors.black, fontWeight: FontWeight.bold),
              ),
            ),
        ],
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
      return const Scaffold(body: CustomLoader());
    }

    final textTheme = Theme.of(context).textTheme;
    final neutralColor = Colors.grey[200];
    const elevatedColor = Colors.white;
    final bool isGuest = FirebaseAuth.instance.currentUser == null;
    final type = promoData!['type'] as String? ?? '';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        widget.onBackPressed();
      },
      child: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header image — promo banner
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: (promoData!['imageURL'] != null && (promoData!['imageURL'] as String).isNotEmpty)
                    ? CachedNetworkImage(
                        imageUrl: promoData!['imageURL'],
                        width: double.infinity,
                        height: 250,
                        fit: BoxFit.fill,
                        placeholder: (context, url) =>
                        const ShimmerPlaceholder.rectangular(height: 250),
                        errorWidget: (context, url, error) => Container(
                          height: 250,
                          color: Colors.grey[300],
                          child: const Icon(Icons.broken_image),
                        ),
                      )
                    : Container(
                        width: double.infinity,
                        height: 250,
                        decoration: BoxDecoration(
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
                              const Icon(Icons.local_offer, size: 60, color: Colors.white),
                              const SizedBox(height: 12),
                              Text(
                                _promoTypeLabel(type),
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 24),
                                child: Text(
                                  promoData!['name'] ?? 'Promoción',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 26,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 20),

              // Title + price card (mirrors recipe title/precio)
              SizedBox(
                width: double.infinity,
                child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: elevatedColor,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 8,
                      offset: const Offset(2, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      promoData!['name'] ?? 'Promoción',
                      style: textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ImageFiltered(
                      imageFilter: ImageFilter.blur(
                        sigmaX: isGuest ? 6.0 : 0.0,
                        sigmaY: isGuest ? 6.0 : 0.0,
                      ),
                      child: Text(
                        'Precio: \$${_getDisplayPrice().toStringAsFixed(2)} MXN',
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ),
              const SizedBox(height: 20),

              // Description (mirrors recipe body)
              Text(
                _getPromoDescription(),
                textAlign: TextAlign.justify,
                style: textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),

              // Instructions (mirrors recipe bullet_points)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: neutralColor,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(2, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Instrucciones:',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    ..._buildInstructionSteps(),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Products section (mirrors recipe ingredients)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: elevatedColor,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 8,
                      offset: const Offset(2, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Trigger / main product
                    if (triggerProductData != null && type != 'combo_exact') ...[
                      Text(
                        type == 'bxgy' ? 'Producto:' : 'Producto Principal:',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      _buildProductTile(triggerProductData!, isMain: true),
                      if (type == 'bxgy') ...[
                        const SizedBox(height: 4),
                        Text(
                          'Lleva ${promoData!['buyQuantity']}, Paga ${promoData!['payQuantity']}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.deepOrange,
                          ),
                        ),
                      ],
                    ],

                    // Required products (combo_exact)
                    if (type == 'combo_exact') ...[
                      const Text(
                        'Productos Incluidos:',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      ...requiredProducts.map((p) => _buildProductTile(p)),
                    ],

                    // Option products (combo_choice / combo_brand)
                    if ((type == 'combo_choice' || type == 'combo_brand') &&
                        optionProducts.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 8),
                      const Text(
                        'Elige una opción:',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      ...optionProducts.map((product) {
                        final productId = product['id'] as String;
                        final isSelected = selectedOptionProductId == productId;
                        return InkWell(
                          onTap: () {
                            setState(() {
                              selectedOptionProductId = productId;
                            });
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 4),
                            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.black.withValues(alpha: 0.06)
                                  : null,
                              borderRadius: BorderRadius.circular(10),
                              border: isSelected
                                  ? Border.all(color: Colors.black, width: 1.5)
                                  : null,
                            ),
                            child: Row(
                              children: [
                                Checkbox(
                                  value: isSelected,
                                  activeColor: Colors.black,
                                  onChanged: (_) {
                                    setState(() {
                                      selectedOptionProductId = productId;
                                    });
                                  },
                                  shape: const CircleBorder(),
                                ),
                                Expanded(child: _buildProductTile(product)),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Add to cart button
              ElevatedButton(
                onPressed: () {
                  if (FirebaseAuth.instance.currentUser == null) {
                    Navigator.push(context, customPageRoute(const LoginPage()));
                  } else if (_canAddToCart()) {
                    _addPromoToCart();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Selecciona una opción antes de agregar al carrito.'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: _canAddToCart() ? Colors.black : Colors.grey,
                  elevation: 5,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child: const Center(
                  child: Text(
                    'Agregar combo al carrito',
                    style: TextStyle(fontSize: 16, color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 110),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildInstructionSteps() {
    final steps = _getInstructions();
    return List<Widget>.generate(steps.length, (index) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${index + 1}. ',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Expanded(
              child: Text(
                steps[index],
                textAlign: TextAlign.justify,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      );
    });
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
