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
    if (recipeData == null || recipeData!['ingredients'] == null) return;

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
    final neutralColor = Colors.grey[200];
    const elevatedColor = Colors.white;
    final bool isGuest = FirebaseAuth.instance.currentUser == null;

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
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: CachedNetworkImage(
                  imageUrl: recipeData!['imageURL'],
                  width: double.infinity,
                  height: 250,
                  fit: BoxFit.fill,
                  placeholder: (context, url) =>
                  const ShimmerPlaceholder.rectangular(height: 250),
                  errorWidget: (context, url, error) => const Icon(Icons.error),
                ),
              ),
              const SizedBox(height: 20),
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
                    Text(
                      recipeData!['title'],
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
                        'Precio: ${recipeData!['precio']} MXN',
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                recipeData!['body'],
                textAlign: TextAlign.justify,
                style: textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
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
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._buildBulletPoints(recipeData!['bullet_points']),
                  ],
                ),
              ),
              const SizedBox(height: 20),
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
                    const Text(
                      'Ingredientes:',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._buildIngredients(recipeData!['ingredients']),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () {
                  if (FirebaseAuth.instance.currentUser == null) {
                    Navigator.push(context, customPageRoute(const LoginPage()));
                  } else {
                    _addItemsToCart();
                  }
                },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.black,
                  elevation: 5,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child: const Center(
                  child: Text(
                    'Agregar productos disponibles al carrito',
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

  List<Widget> _buildBulletPoints(List<dynamic> bulletPoints) {
    return List<Widget>.generate(bulletPoints.length, (index) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${index + 1}. ',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Expanded(
              child: Text(
                bulletPoints[index],
                textAlign: TextAlign.justify,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      );
    });
  }
}