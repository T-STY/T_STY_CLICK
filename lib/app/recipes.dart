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

class RecipeDetailPage extends StatefulWidget {
  final String recipeId;
  final VoidCallback onBackPressed;

  const RecipeDetailPage({
    super.key,
    required this.recipeId,
    required this.onBackPressed,
  });

  @override
  RecipeDetailPageState createState() => RecipeDetailPageState();
}

class RecipeDetailPageState extends State<RecipeDetailPage> {
  Map<String, dynamic>? recipeData;

  bool _isAddingToCart = false;

  @override
  void initState() {
    super.initState();
    _fetchRecipe();
  }

  Future<void> _fetchRecipe() async {
    final docSnapshot = await FirebaseFirestore.instance
        .collection('recipes')
        .doc(widget.recipeId)
        .get();

    if (docSnapshot.exists) {
      setState(() {
        recipeData = docSnapshot.data();
      });
    }
  }

  Future<void> _addItemsToCart() async {
    if (_isAddingToCart) return;
    if (recipeData == null || recipeData!['ingredients'] == null) return;

    setState(() {
      _isAddingToCart = true;
    });
    try {
      final ingredients = recipeData!['ingredients'] as List<dynamic>;
      final cartProvider = Provider.of<CartProvider>(context, listen: false);
      List<Map<String, dynamic>> availableItems = [];
      List<Map<String, dynamic>> insufficientStockItems = [];
      List<Map<String, dynamic>> missingItems = [];

      for (var ingredient in ingredients) {
        final String productId = ingredient['productId'];
        final double requestedQuantity =
            (ingredient['quantity'] as num?)?.toDouble() ?? 0;

        final productDoc = await FirebaseFirestore.instance
            .collection('products')
            .doc(productId)
            .get();

        if (!productDoc.exists) {
          missingItems.add(ingredient);
        } else {
          final productData = productDoc.data();
          if (productData != null) {
            final double? productPrice =
            (productData['price'] as num?)?.toDouble();
            final double? availableStock =
            (productData['stock'] as num?)?.toDouble();
            final String productName =
                productData['nombre'] ?? 'Producto desconocido';
            final String imageUrl = productData['image_url'] ?? '';

            final String typeSpecific =
                productData['type_specific'] as String? ?? '';
            final String variante = productData['variante'] as String? ?? '';

            if (productPrice == null || availableStock == null) {
              continue;
            }

            if (requestedQuantity > availableStock) {
              insufficientStockItems.add({
                'productId': productId,
                'name': productName,
                'imageUrl': imageUrl,
                'availableStock': availableStock,
                'requestedQuantity': requestedQuantity,
                'price': productPrice,
                'isBulk': ingredient['isBulk'] ?? false,
                'stock': availableStock,
                'typeSpecific': typeSpecific,
                'variante': variante,
              });
            } else {
              availableItems.add({
                'productId': productId,
                'name': productName,
                'imageUrl': imageUrl,
                'quantity': requestedQuantity,
                'price': productPrice,
                'isBulk': ingredient['isBulk'] ?? false,
                'stock': availableStock,
                'typeSpecific': typeSpecific,
                'variante': variante,
              });
            }
          }
        }
      }

      if (missingItems.isNotEmpty || insufficientStockItems.isNotEmpty) {
        if (!mounted) return;
        _showStockAndMissingDialog(
          availableItems,
          insufficientStockItems,
          missingItems,
          cartProvider,
        );
      } else {
        await _addAvailableItemsToCart(availableItems, cartProvider);
        if (!mounted) return;
        _showSuccessDialog();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAddingToCart = false;
        });
      }
    }
  }

  void _showStockAndMissingDialog(
      List<Map<String, dynamic>> availableItems,
      List<Map<String, dynamic>> insufficientStockItems,
      List<Map<String, dynamic>> missingItems,
      CartProvider cartProvider,
      ) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: AlertDialog(
              title: const Text('Problemas con el inventario'),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (missingItems.isNotEmpty) ...[
                      const Text(
                        'Los siguientes productos no están disponibles:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      ...missingItems.map((item) => Row(
                        children: [
                          CachedNetworkImage(
                            imageUrl: item['imageUrl'] ?? '',
                            width: 50,
                            height: 50,
                            fit: BoxFit.contain,
                            placeholder: (context, url) =>
                            const SizedBox(width: 50, height: 50),
                            errorWidget: (context, url, error) =>
                            const Icon(Icons.broken_image),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(
                                  item['name'] ?? 'Producto desconocido')),
                        ],
                      )),
                    ],
                    if (insufficientStockItems.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text(
                        'Los siguientes productos no tienen suficiente stock:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      ...insufficientStockItems.map((item) => Row(
                        children: [
                          CachedNetworkImage(
                            imageUrl: item['imageUrl'] ?? '',
                            width: 50,
                            height: 50,
                            fit: BoxFit.contain,
                            placeholder: (context, url) =>
                            const SizedBox(width: 50, height: 50),
                            errorWidget: (context, url, error) =>
                            const Icon(Icons.broken_image),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${item['name']} (Stock disponible: ${item['availableStock']}, solicitado: ${item['requestedQuantity']})',
                            ),
                          ),
                        ],
                      )),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    await _addAvailableItemsToCart(
                        availableItems, cartProvider);

                    if (!context.mounted) return;
                    Navigator.of(context).pop();
                    widget.onBackPressed();
                  },
                  child: const Text('Excluir'),
                ),
                TextButton(
                  onPressed: () async {
                    await _addAllIncludingInsufficient(availableItems,
                        insufficientStockItems, cartProvider);

                    if (!context.mounted) return;
                    Navigator.of(context).pop();
                    widget.onBackPressed();
                  },
                  child: const Text('Agregar'),
                ),
              ],
            ));
      },
    );
  }

  Future<void> _addAllIncludingInsufficient(
      List<Map<String, dynamic>> availableItems,
      List<Map<String, dynamic>> insufficientStockItems,
      CartProvider cartProvider,
      ) async {
    await _addAvailableItemsToCart(availableItems, cartProvider);

    for (var item in insufficientStockItems) {
      double availableStock = item['availableStock'];
      if (availableStock <= 0) continue;
      double price = item['price'];

      cartProvider.addItem(
        item['productId'],
        item['name'],
        price,
        item['imageUrl'],
        quantity: availableStock,
        isBulk: item['isBulk'] ?? false,
        stock: availableStock,
        typeSpecific: item['typeSpecific'],
        variante: item['variante'],
      );
    }
  }

  Future<void> _addAvailableItemsToCart(
      List<Map<String, dynamic>> availableItems,
      CartProvider cartProvider,
      ) async {
    for (var item in availableItems) {
      cartProvider.addItem(
        item['productId'],
        item['name'],
        item['price'],
        item['imageUrl'],
        quantity: item['quantity'],
        isBulk: item['isBulk'] ?? false,
        stock: (item['stock'] as num?)?.toDouble() ?? 0.0,
        typeSpecific: item['typeSpecific'],
        variante: item['variante'],
      );
    }
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
                  'Todos los productos disponibles han sido agregados exitosamente al carrito.'),
              actions: <Widget>[
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onBackPressed();
                  },
                  child: const Text('OK'),
                ),
              ],
            ));
      },
    );
  }

  List<Widget> _buildIngredients(List<dynamic> ingredients) {
    final bool isGuest = FirebaseAuth.instance.currentUser == null;

    return ingredients.map((ingredient) => FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('products')
          .doc(ingredient['productId'])
          .get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                ShimmerPlaceholder(width: 50, height: 50),
                SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShimmerPlaceholder(
                          width: double.infinity, height: 16),
                      SizedBox(height: 4),
                      ShimmerPlaceholder(width: 100, height: 14),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: ingredient['imageUrl'] ?? '',
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
                  child: Text(
                    '${ingredient['quantity']} x ${ingredient['name']} (Producto no disponible)',
                    style: const TextStyle(fontSize: 16, color: Colors.red),
                  ),
                ),
              ],
            ),
          );
        }

        final productData = snapshot.data!.data() as Map<String, dynamic>;
        final double price = (productData['price'] as num).toDouble();
        final String productName =
            productData['nombre'] ?? 'Producto desconocido';
        final double quantity = (ingredient['quantity'] as num).toDouble();
        final double totalPrice = price * quantity;

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: ingredient['imageUrl'] ?? '',
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
                      '${quantity.toStringAsFixed(0)} x $productName',
                      style: const TextStyle(fontSize: 16),
                    ),
                    ImageFiltered(
                      imageFilter: ImageFilter.blur(
                        sigmaX: isGuest ? 6.0 : 0.0,
                        sigmaY: isGuest ? 6.0 : 0.0,
                      ),
                      child: Text(
                        'Precio unitario: \$${price.toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontSize: 14, color: Colors.grey),
                      ),
                    ),
                  ],
                ),
              ),
              ImageFiltered(
                imageFilter: ImageFilter.blur(
                  sigmaX: isGuest ? 6.0 : 0.0,
                  sigmaY: isGuest ? 6.0 : 0.0,
                ),
                child: Text(
                  '\$${totalPrice.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
      },
    )).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (recipeData == null) {
      return const Scaffold(
        body: CustomLoader(),
      );
    }

    final textTheme = Theme.of(context).textTheme;
    final bool isGuest = FirebaseAuth.instance.currentUser == null;
    final String title = (recipeData!['title'] ?? 'Receta').toString();
    final String precio = recipeData!['precio']?.toString() ?? 'N/A';
    final int ingredientCount = (recipeData!['ingredients'] is List)
        ? (recipeData!['ingredients'] as List).length
        : 0;
    final String body = (recipeData!['body'] ?? '').toString();
    final String imageUrl = (recipeData!['imageURL'] ?? '').toString();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        widget.onBackPressed();
      },
      child: Scaffold(
        body: BottomFade(
          clearHeight: 100,
          fadeHeight: 40,
          child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: SizedBox(
                  height: 270,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        placeholder: (c, u) =>
                            const ShimmerPlaceholder.rectangular(height: 270),
                        errorWidget: (c, u, e) => Container(
                          color: Colors.grey[300],
                          child: const Center(
                            child: Icon(Icons.restaurant_menu,
                                size: 54, color: Colors.white70),
                          ),
                        ),
                      ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.transparent,
                              Color(0xE0000000),
                            ],
                            stops: [0.0, 0.42, 1.0],
                          ),
                        ),
                      ),
                      Positioned(
                        top: 14,
                        left: 14,
                        child: _detailTag(Icons.restaurant_menu, 'Receta'),
                      ),
                      Positioned(
                        left: 18,
                        right: 18,
                        bottom: 16,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 24,
                                height: 1.1,
                                shadows: [
                                  Shadow(color: Colors.black54, blurRadius: 8),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Icon(Icons.local_grocery_store_outlined,
                                    size: 15,
                                    color:
                                        Colors.white.withValues(alpha: 0.85)),
                                const SizedBox(width: 5),
                                Text(
                                  '$ingredientCount ${ingredientCount == 1 ? 'ingrediente' : 'ingredientes'}',
                                  style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.85),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500),
                                ),
                                const SizedBox(width: 10),
                                Container(
                                  width: 3,
                                  height: 3,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color:
                                        Colors.white.withValues(alpha: 0.55),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Icon(Icons.sell_outlined,
                                    size: 15, color: Color(0xFFB9F6CA)),
                                const SizedBox(width: 5),
                                ImageFiltered(
                                  imageFilter: ImageFilter.blur(
                                    sigmaX: isGuest ? 6.0 : 0.0,
                                    sigmaY: isGuest ? 6.0 : 0.0,
                                  ),
                                  child: Text(
                                    '≈ \$$precio',
                                    style: const TextStyle(
                                      color: Color(0xFFB9F6CA),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (body.trim().isNotEmpty) ...[
                const SizedBox(height: 22),
                _sectionHeader(Icons.notes_rounded, 'Descripción'),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: _cardDecoration(),
                  child: Text(
                    body,
                    textAlign: TextAlign.justify,
                    style: textTheme.bodyMedium?.copyWith(height: 1.45),
                  ),
                ),
              ],
              const SizedBox(height: 22),
              _sectionHeader(
                  Icons.local_grocery_store_rounded, 'Ingredientes'),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
                decoration: _cardDecoration(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _buildIngredients(recipeData!['ingredients']),
                ),
              ),
              const SizedBox(height: 22),
              _sectionHeader(Icons.menu_book_rounded, 'Preparación'),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: _cardDecoration(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _buildBulletPoints(recipeData!['bullet_points']),
                ),
              ),
              const SizedBox(height: 28),
              ElevatedButton(
                onPressed: _isAddingToCart
                    ? null
                    : () {
                        if (FirebaseAuth.instance.currentUser == null) {
                          Navigator.push(
                              context, customPageRoute(const LoginPage()));
                        } else {
                          _addItemsToCart();
                        }
                      },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.black,
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child: _isAddingToCart
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                          SizedBox(width: 12),
                          Flexible(
                            child: Text(
                              'Agregando...',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_shopping_cart,
                              color: Colors.white, size: 20),
                          SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Agregar productos disponibles al carrito',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 140),
            ],
          ),
        ),
        ),
      ),
    );
  }

  List<Widget> _buildBulletPoints(List<dynamic> bulletPoints) {
    return List<Widget>.generate(bulletPoints.length, (index) {
      final bool isLast = index == bulletPoints.length - 1;
      return Padding(
        padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: Colors.black,
                shape: BoxShape.circle,
              ),
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  bulletPoints[index],
                  textAlign: TextAlign.justify,
                  style: const TextStyle(fontSize: 15, height: 1.4),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _sectionHeader(IconData icon, String title) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: const Color(0x14000000),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: Colors.black),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.08),
          blurRadius: 12,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }

  Widget _detailTag(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.black87),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.w800,
                  fontSize: 11.5,
                  letterSpacing: 0.3)),
        ],
      ),
    );
  }
}
