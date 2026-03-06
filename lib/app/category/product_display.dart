import 'dart:async';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../components/shimmer_placeholder.dart';
import '../../constants/app_images.dart';
import '../cart/cart_provider.dart';
import '../../auth/login_page.dart';
import '../../custom_page_route.dart';

class ProductDisplayPage extends StatefulWidget {
  final String selectedCategory;
  final VoidCallback onBack;

  const ProductDisplayPage({
    super.key,
    required this.selectedCategory,
    required this.onBack,
  });

  @override
  ProductDisplayPageState createState() => ProductDisplayPageState();
}

class ProductDisplayPageState extends State<ProductDisplayPage> {

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.toLowerCase();
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        widget.onBack();
      },
      child: Scaffold(
        appBar: AppBar(
          scrolledUnderElevation: 0,
          title: Padding(
            padding: const EdgeInsets.all(0),
            child: SizedBox(
              height: 180,
              width: 300,
              child: AspectRatio(
                aspectRatio: 1 / 1,
                child: Image.asset(
                  isDarkMode ? AppImages.logowhite : AppImages.logo,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          backgroundColor: Colors.transparent,
          automaticallyImplyLeading:
          true,
        ),
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 70),
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Buscar productos...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      _onSearchChanged();
                    },
                  )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: isDarkMode ? Colors.grey[850] : Colors.grey[200],
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: StreamBuilder(
                  stream: FirebaseFirestore.instance
                      .collection('products')
                      .where('category', isEqualTo: widget.selectedCategory)
                      .snapshots(),
                  builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return GridView.builder(
                        padding: const EdgeInsets.only(bottom: 20),
                        gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 20,
                          childAspectRatio: 7 / 10,
                        ),
                        itemCount: 6,
                        itemBuilder: (context, index) {
                          return Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(15),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.grey.withValues(alpha: 0.1),
                                  spreadRadius: 5,
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: ShimmerPlaceholder(
                                    shapeBorder: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.only(
                                        topLeft: Radius.circular(15),
                                        topRight: Radius.circular(15),
                                      ),
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: EdgeInsets.all(8.0),
                                  child: Column(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    children: [
                                      ShimmerPlaceholder(
                                          width: 100, height: 16),
                                      SizedBox(height: 8),
                                      ShimmerPlaceholder(width: 60, height: 14),
                                      SizedBox(height: 8),
                                      ShimmerPlaceholder(
                                          width: double.infinity,
                                          height: 36),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    }
                    if (snapshot.hasError) {
                      return Center(child: Text('Error: ${snapshot.error}'));
                    }

                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return const Center(child: Text('No products found'));
                    }

                    final products = snapshot.data!.docs.where((product) {
                      final data = product.data() as Map<String, dynamic>;
                      final productName =
                          data['nombre']?.toString().toLowerCase() ?? '';
                      return productName.contains(_searchQuery);
                    }).toList();

                    products.sort((a, b) {
                      final dataA = a.data() as Map<String, dynamic>;
                      final dataB = b.data() as Map<String, dynamic>;

                      final nameA =
                      (dataA['nombre'] as String? ?? '').toLowerCase();
                      final nameB =
                      (dataB['nombre'] as String? ?? '').toLowerCase();

                      return nameA.compareTo(nameB);
                    });

                    return GridView.builder(

                      padding: const EdgeInsets.only(bottom: 50),
                      gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 20,
                        childAspectRatio: 7 / 10,
                      ),
                      itemCount: products.length,
                      itemBuilder: (context, index) {
                        final product = products[index];

                        return GestureDetector(
                          onTap: () {
                          },
                          child: _buildProductCard(context, product),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        backgroundColor: isDarkMode
            ? Colors.grey[850]
            : Colors.white,
      ),
    );
  }

  Widget _buildProductCard(BuildContext context, DocumentSnapshot product) {
    final data = product.data() as Map<String, dynamic>? ?? {};
    final String name = data['nombre'] ?? 'Unknown Product';
    final double price = (data['price'] as num?)?.toDouble() ?? 0.0;
    final String imageUrl = data['image_url'] ?? '';
    final bool isBulk = data['bulk'] as bool? ?? false;
    final double stock = (data['stock'] as num?)?.toDouble() ?? 0.0;
    final String? typeSpecific = data['type_specific'] as String?;
    final String? variante = data['variante'] as String?;
    final bool isGuest = FirebaseAuth.instance.currentUser == null;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            spreadRadius: 5,
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(15),
                topRight: Radius.circular(15),
              ),
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.contain,
                  width: double.infinity,
                  placeholder: (context, url) =>
                  const ShimmerPlaceholder(width: double.infinity),
                  errorWidget: (context, url, error) => const Icon(Icons.error),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 4),
                ImageFiltered(
                  imageFilter: ImageFilter.blur(
                    sigmaX: isGuest ? 6.0 : 0.0,
                    sigmaY: isGuest ? 6.0 : 0.0,
                  ),
                  child: Text(
                    '\$${price.toString()}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  data['variante'] ?? '',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                  ),
                ),
                const SizedBox(height: 4),
                _AddToCartButton(
                  data: {
                    'docId': product.id,
                    'nombre': name,
                    'price': price,
                    'image_url': imageUrl,
                    'bulk': isBulk,
                    'stock': stock,
                    'type_specific': typeSpecific,
                    'variante': variante,
                  },
                  textColor: Colors.black,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AddToCartButton extends StatefulWidget {
  final Map<String, dynamic> data;
  final Color textColor;

  const _AddToCartButton(
      {required this.data, required this.textColor});

  @override
  __AddToCartButtonState createState() => __AddToCartButtonState();
}

class __AddToCartButtonState extends State<_AddToCartButton> {
  bool _showSwitchTile = false;
  bool _showAgregadoButton = false;
  double _quantity = 1;
  Timer? _timer;
  late double stock;
  CartProvider? cartProvider;

  @override
  void initState() {
    super.initState();
    _initializeCartState();

    cartProvider = Provider.of<CartProvider>(context, listen: false);
    cartProvider!.addListener(_checkCartState);

    stock = widget.data['stock'] as double? ?? 0.0;
  }

  void _initializeCartState() {
    final cartProvider = Provider.of<CartProvider>(context, listen: false);
    final String? docId = widget.data['docId'] as String?;

    if (docId != null) {
      final cartItem = cartProvider.getItem(docId);

      if (cartItem != null) {
        setState(() {
          _quantity = cartItem.quantity;
          _showSwitchTile = true;
          _showAgregadoButton = true;
        });
      }
    }
  }


  void _checkCartState() {
    if (!mounted) return;

    final cartProvider = Provider.of<CartProvider>(context, listen: false);
    final String? docId = widget.data['docId'] as String?;

    if (docId != null) {
      final cartItem = cartProvider.getItem(docId);

      if (cartItem != null && cartItem.quantity > 0) {
        setState(() {
          _quantity = cartItem.quantity;
          _showSwitchTile = true;
          _showAgregadoButton = true;
        });
      } else {
        setState(() {
          _showSwitchTile = false;
          _showAgregadoButton = false;
        });
      }
    }
  }

  void _onAddToCartPressed() {
    if (FirebaseAuth.instance.currentUser == null) {
      Navigator.push(context, customPageRoute(const LoginPage()));
      return;
    }

    if (stock == 0) {
      return;
    }

    final cartProvider = Provider.of<CartProvider>(context, listen: false);

    final String? docId = widget.data['docId'] as String?;
    final String? name = widget.data['nombre'] as String?;
    final double? price = widget.data['price'] as double?;
    final String? imageUrl = widget.data['image_url'] as String?;
    final bool isBulk = widget.data['bulk'] as bool? ?? false;
    final String? typeSpecific = widget.data['type_specific'] as String?;
    final String? variante = widget.data['variante'] as String?;

    if (docId != null && name != null && price != null && imageUrl != null) {
      if (isBulk) {
        _showBulkOrderDialog();
      } else {
        setState(() {
          _showSwitchTile = true;
          _quantity = 1;
          _showAgregadoButton = false;
        });

        _resetAndStartTimer(docId, name, price, imageUrl, cartProvider, isBulk,
            typeSpecific, variante);
      }
    }
  }

  void _resetAndStartTimer(
      String docId,
      String name,
      double price,
      String imageUrl,
      CartProvider cartProvider,
      bool isBulk,
      String? typeSpecific,
      String? variante) {
    _timer?.cancel();

    _timer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          if (_quantity > 0) {
            cartProvider.setItem(
              docId,
              name,
              price,
              imageUrl,
              _quantity,
              isBulk: isBulk,
              stock: stock,
              typeSpecific: typeSpecific,
              variante: variante,
            );
          } else {
            cartProvider.removeItemCompletely(docId);
          }
          _showSwitchTile = false;
          _showAgregadoButton = true;
          if (kDebugMode) {
            print('Set quantity of $name to $_quantity in cart');
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    cartProvider?.removeListener(_checkCartState);
    super.dispose();
  }

  void _incrementQuantity() {
    if (_quantity < stock) {
      setState(() {
        _quantity++;
      });

      final String? docId = widget.data['docId'] as String?;
      final String? name = widget.data['nombre'] as String?;
      final double? price = widget.data['price'] as double?;
      final String? imageUrl = widget.data['image_url'] as String?;
      final bool isBulk = widget.data['bulk'] as bool? ?? false;
      final cartProvider = Provider.of<CartProvider>(context, listen: false);
      final String? typeSpecific = widget.data['type_specific'] as String?;
      final String? variante = widget.data['variante'] as String?;

      _resetAndStartTimer(docId!, name!, price!, imageUrl!, cartProvider,
          isBulk, typeSpecific, variante);
    }
  }

  void _decrementQuantity() {
    if (_quantity > 1) {
      setState(() {
        _quantity--;
      });

      final String? docId = widget.data['docId'] as String?;
      final String? name = widget.data['nombre'] as String?;
      final double? price = widget.data['price'] as double?;
      final String? imageUrl = widget.data['image_url'] as String?;
      final bool isBulk = widget.data['bulk'] as bool? ?? false;
      final cartProvider = Provider.of<CartProvider>(context, listen: false);
      final String? typeSpecific = widget.data['type_specific'] as String?;
      final String? variante = widget.data['variante'] as String?;

      _resetAndStartTimer(docId!, name!, price!, imageUrl!, cartProvider,
          isBulk, typeSpecific, variante);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    if (stock == 0) {
      return ElevatedButton(
        onPressed: null,
        style: ElevatedButton.styleFrom(
          padding: EdgeInsets.zero,
          foregroundColor: isDarkMode ? Colors.white : Colors.black,
          backgroundColor: isDarkMode ? Colors.grey[800] : Colors.grey[200],
          minimumSize: const Size(double.infinity, 36),
          maximumSize: const Size(double.infinity, 36),
          textStyle: const TextStyle(fontSize: 12),
        ),
        child: Text('Agotado', style: TextStyle(color: widget.textColor)),
      );
    }

    if (_showAgregadoButton) {
      return ElevatedButton(
        onPressed: () {
          setState(() {
            _showSwitchTile = true;
            _showAgregadoButton = false;
            if (widget.data['bulk'] == true) {
              _showBulkOrderDialog(
                  prefill: true);
            }
          });
        },
        style: ElevatedButton.styleFrom(
          padding: EdgeInsets.zero,
          foregroundColor: isDarkMode ? Colors.white : Colors.black,
          backgroundColor: isDarkMode ? Colors.grey[800] : Colors.grey[200],
          minimumSize: const Size(double.infinity, 36),
          maximumSize: const Size(double.infinity, 36),
          textStyle: const TextStyle(fontSize: 12),
        ),
        child: Text('Agregado ($_quantity)',
            style: TextStyle(color: widget.textColor)),
      );
    } else if (_showSwitchTile) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.remove),
                onPressed: _quantity > 1 ? _decrementQuantity : null,
              ),
              Text('$_quantity', style: TextStyle(color: widget.textColor)),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: _incrementQuantity,
              ),
            ],
          ),
        ],
      );
    } else {
      return ElevatedButton.icon(
        onPressed: _onAddToCartPressed,
        icon: const Icon(Icons.shopping_cart, size: 16),
        label: const Text('Agregar'),
        style: ElevatedButton.styleFrom(
          padding: EdgeInsets.zero,
          foregroundColor: isDarkMode ? Colors.white : Colors.black,
          backgroundColor: isDarkMode ? Colors.grey[800] : Colors.grey[200],
          minimumSize: const Size(double.infinity, 36),
          maximumSize: const Size(double.infinity, 36),
          textStyle: const TextStyle(fontSize: 12),
        ),
      );
    }
  }

  void _showBulkOrderDialog({bool prefill = false}) {
    final pesosController = TextEditingController();
    final kilosController = TextEditingController();
    final FocusNode pesosFocusNode = FocusNode();
    final FocusNode kilosFocusNode = FocusNode();
    final pricePerKilo = widget.data['price'] ?? 0.0;

    if (prefill && _quantity > 0) {
      kilosController.text = _quantity.toStringAsFixed(3);
      pesosController.text =
      '\$${(_quantity * pricePerKilo).toStringAsFixed(2)}';
    }

    final cartProvider = Provider.of<CartProvider>(context, listen: false);
    final cartItem = cartProvider.getItem(widget.data['docId']);
    final currentQuantity = cartItem?.quantity ?? 0.0;
    kilosController.text = currentQuantity.toStringAsFixed(3);
    pesosController.text =
    '\$${(currentQuantity * pricePerKilo).toStringAsFixed(2)}';

    pesosFocusNode.addListener(() {
      if (!pesosFocusNode.hasFocus) {
        final pesos =
        double.tryParse(pesosController.text.replaceAll('\$', ''));
        if (pesos != null && pricePerKilo != null) {
          kilosController.text = (pesos / pricePerKilo).toStringAsFixed(3);
          pesosController.text = '\$${pesos.toStringAsFixed(2)}';
        }
      }
    });

    kilosFocusNode.addListener(() {
      if (!kilosFocusNode.hasFocus) {
        final kilos = double.tryParse(kilosController.text);
        if (kilos != null && pricePerKilo != null) {
          pesosController.text =
          '\$${(kilos * pricePerKilo).toStringAsFixed(2)}';
        }
      }
    });

    showDialog(
        context: context,
        builder: (context) {
          return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: AlertDialog(
              title: const Center(child: Text("Producto a Granel")),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8.0),
                          child: Image.network(
                            widget.data['image_url'] ??
                                '/images/placeholder.png',
                            fit: BoxFit.contain,
                            width: 50,
                            height: 50,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.data['nombre'] ?? 'Unnamed',
                              style:
                              const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(widget.data['variante'] ?? 'No variant'),
                            Text(
                              _formatPrice(widget.data['price']),
                              style: const TextStyle(color: Colors.green),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    RichText(
                      textAlign: TextAlign.justify,
                      text: const TextSpan(
                        style: TextStyle(color: Colors.black),
                        children: [
                          TextSpan(
                            text:
                            "Este producto se vende a granel, por favor indique la cantidad que desea recibir.\n",
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Valor en pesos',
                        style: TextStyle(color: Colors.black),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: pesosController,
                            keyboardType: TextInputType.number,
                            focusNode: pesosFocusNode,
                            textAlign: TextAlign.center,
                            decoration: InputDecoration(
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          flex: 1,
                          child: Text(
                            'MXN',
                            style: TextStyle(color: Colors.black),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Peso en kilo',
                        style: TextStyle(color: Colors.black),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: kilosController,
                            keyboardType: TextInputType.number,
                            focusNode: kilosFocusNode,
                            textAlign: TextAlign.center,
                            decoration: InputDecoration(
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          flex: 1,
                          child: Text(
                            'kg',
                            style: TextStyle(color: Colors.black),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    RichText(
                      textAlign: TextAlign.justify,
                      text: const TextSpan(
                        style: TextStyle(color: Colors.black),
                        children: [
                          TextSpan(
                            text:
                            "\n*Tenga en cuenta que la cantidad recibida puede variar ligeramente.",
                            style: TextStyle(fontStyle: FontStyle.italic),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    final kilos = double.tryParse(kilosController.text) ?? 0.0;
                    if (kilos > stock) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('No hay suficiente stock disponible'),
                        ),
                      );
                    } else {
                      Navigator.of(context).pop();
                      if (widget.data['docId'] != null &&
                          widget.data['nombre'] != null) {
                        cartProvider.setItem(
                          widget.data['docId'],
                          widget.data['nombre'],
                          widget.data['price'],
                          widget.data['image_url'] ?? '/images/placeholder.png',
                          kilos,
                          isBulk: true,
                          stock: stock,
                          typeSpecific:
                          widget.data['type_specific'],
                          variante: widget.data['variante'],
                        );
                      }
                      if (kDebugMode) {
                        print('Bulk order set: $kilos kg');
                      }
                    }
                  },
                  child: const Text('Agregar'),
                ),
              ],
            ),
          );
        });
  }

  String _formatPrice(dynamic price) {
    if (price == null) return 'N/A';
    return '\$${(price as num).toStringAsFixed(2)}';
  }
}
