import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../components/custom_loader.dart';
import '../components/shimmer_placeholder.dart';
import 'cart/cart_provider.dart';

class RecipeDetailPage extends StatefulWidget {
  final String recipeId;
  final VoidCallback onBackPressed;

  const RecipeDetailPage({
    super.key,
    required this.recipeId,
    required this.onBackPressed,
  });

  @override
  _RecipeDetailPageState createState() => _RecipeDetailPageState();
}

class _RecipeDetailPageState extends State<RecipeDetailPage> {
  Map<String, dynamic>? recipeData;

  @override
  void initState() {
    super.initState();
    _fetchRecipe();
  }

  /// Fetches the recipe data from Firestore
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

    // Iterate through ingredients and add each item to the cart
    for (var ingredient in ingredients) {
      final String productId = ingredient['productId'];
      final double requestedQuantity = (ingredient['quantity'] as num?)?.toDouble() ?? 0;

      // Fetch the product document from Firebase
      final productDoc = await FirebaseFirestore.instance
          .collection('products')
          .doc(productId)
          .get();

      if (!productDoc.exists) {
        // If the product does not exist, add it to the missing items list
        missingItems.add(ingredient);
      } else {
        // Extract the product data
        final productData = productDoc.data();
        if (productData != null) {
          final double? productPrice = (productData['price'] as num?)?.toDouble();
          final double? availableStock = (productData['stock'] as num?)?.toDouble();
          final String productName = productData['nombre'] ?? 'Producto desconocido';
          final String imageUrl = productData['image_url'] ?? '';

          // 1. EXTRACT NEW FIELDS
          final String typeSpecific = productData['type_specific'] as String? ?? '';
          final String variante = productData['variante'] as String? ?? '';

          // Ensure that the price and stock are non-null before proceeding
          if (productPrice == null || availableStock == null) {
            // If the product data is incomplete, skip it or handle the error
            continue;
          }

          // Check if there's enough stock
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
              'typeSpecific': typeSpecific, // <--- ADD THIS
              'variante': variante,         // <--- ADD THIS
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
              'typeSpecific': typeSpecific, // <--- ADD THIS
              'variante': variante,         // <--- ADD THIS
            });
          }
        }
      }
    }

    // Handle missing or insufficient stock items
    if (missingItems.isNotEmpty || insufficientStockItems.isNotEmpty) {
      _showStockAndMissingDialog(
        availableItems,
        insufficientStockItems,
        missingItems,
        cartProvider,
      );
    } else {
      await _addAvailableItemsToCart(availableItems, cartProvider);
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
                // ... (El contenido del diálogo se mantiene igual)
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
                            placeholder: (context, url) => const SizedBox(width: 50, height: 50),
                            errorWidget: (context, url, error) => const Icon(Icons.broken_image),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(item['name'] ?? 'Producto desconocido')),
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
                            placeholder: (context, url) => const SizedBox(width: 50, height: 50),
                            errorWidget: (context, url, error) => const Icon(Icons.broken_image),
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
                    // Opción 1: Agregar solo lo disponible y salir
                    await _addAvailableItemsToCart(availableItems, cartProvider);

                    Navigator.of(context).pop(); // 1. Cierra el diálogo
                    widget.onBackPressed();      // 2. Regresa a la pantalla principal
                  },
                  child: const Text('Excluir'),
                ),
                TextButton(
                  onPressed: () async {
                    // Opción 2: Agregar todo lo que se pueda y salir
                    await _addAllIncludingInsufficient(availableItems, insufficientStockItems, cartProvider);

                    Navigator.of(context).pop(); // 1. Cierra el diálogo
                    widget.onBackPressed();      // 2. Regresa a la pantalla principal
                  },
                  child: const Text('Agregar'),
                ),
              ],
            )
        );
      },
    );
  }

  Future<void> _addAllIncludingInsufficient(
      List<Map<String, dynamic>> availableItems,
      List<Map<String, dynamic>> insufficientStockItems,
      CartProvider cartProvider,
      ) async {
    // Add items with sufficient stock
    await _addAvailableItemsToCart(availableItems, cartProvider);

    // Add items with insufficient stock
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
        typeSpecific: item['typeSpecific'], // <--- PASS HERE
        variante: item['variante'],         // <--- PASS HERE
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
        typeSpecific: item['typeSpecific'], // <--- PASS HERE
        variante: item['variante'],         // <--- PASS HERE
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
              content: const Text('Todos los productos disponibles han sido agregados exitosamente al carrito.'),
              actions: <Widget>[
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(); // 1. Cierra el diálogo
                    widget.onBackPressed();      // 2. Regresa a la pantalla principal
                  },
                  child: const Text('OK'),
                ),
              ],
            )
        );
      },
    );
  }

  List<Widget> _buildIngredients(List<dynamic> ingredients) {
    return ingredients.map((ingredient) => FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('products').doc(ingredient['productId']).get(),
      builder: (context, snapshot) {
        // LOADING STATE: Shimmer Skeleton Row
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                // Shimmer for Image
                const ShimmerPlaceholder(width: 50, height: 50),
                const SizedBox(width: 8),
                // Shimmer for Text details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      ShimmerPlaceholder(width: double.infinity, height: 16),
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
                    placeholder: (context, url) => const ShimmerPlaceholder(width: 50, height: 50),
                    errorWidget: (context, url, error) => const Icon(Icons.broken_image),
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

        // Fetch the product data from the document
        final productData = snapshot.data!.data() as Map<String, dynamic>;
        final double price = (productData['price'] as num).toDouble();
        final String productName = productData['nombre'] ?? 'Producto desconocido';
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
                  placeholder: (context, url) => const ShimmerPlaceholder(width: 50, height: 50),
                  errorWidget: (context, url, error) => const Icon(Icons.broken_image),
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
                    Text(
                      'Precio unitario: \$${price.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              Text(
                '\$${totalPrice.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
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
        // Replaced Center(child: CircularProgressIndicator())
        body: CustomLoader(),
      );
    }

    final textTheme = Theme.of(context).textTheme;
    final neutralColor = Colors.grey[200];
    final elevatedColor = Colors.white;

    return WillPopScope(
      onWillPop: () async {
        widget.onBackPressed(); // Llama a la función que cambia _showRecipeDetail a false en home.dart
        return false; // Retornamos false porque la navegación la maneja el padre manualmente
      },
      child: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image section
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: CachedNetworkImage(
                  imageUrl: recipeData!['imageURL'],
                  width: double.infinity,
                  height: 250,
                  fit: BoxFit.fill,
                  // NEW: Rectangular Shimmer Placeholder
                  placeholder: (context, url) => const ShimmerPlaceholder.rectangular(height: 250),
                  errorWidget: (context, url, error) => const Icon(Icons.error),
                ),
              ),
              const SizedBox(height: 20),

              // Title section with price
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: elevatedColor,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
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
                    Text(
                      'Precio: ${recipeData!['precio']} MXN',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Body section (recipe description)
              Text(
                recipeData!['body'],
                textAlign: TextAlign.justify,
                style: textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),

              // Instructions section
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: neutralColor,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
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

              // Ingredients section
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: elevatedColor,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
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

              // Add to cart button
              ElevatedButton(
                onPressed: _addItemsToCart,
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

  /// Builds a list of numbered instructions
  List<Widget> _buildBulletPoints(List<dynamic> bulletPoints) {
    return List<Widget>.generate(bulletPoints.length, (index) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${index + 1}. ', style: const TextStyle(fontWeight: FontWeight.bold)),
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
