import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:click/app/recipes.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:algolia/algolia.dart';
import 'package:provider/provider.dart';
import '../components/custom_loader.dart';
import '../components/shimmer_placeholder.dart';
import '../constants/app_images.dart';
import 'cart/cart_provider.dart';
import 'category/filter_dialog.dart';
import 'constants/gridview.dart';
import 'dart:io';
import 'dart:async';

void testNetworkAccess() async {
  try {
    final result =
        await InternetAddress.lookup('pdtyztlt1bpdtyztlt1b-3.algolianet.com');
    if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
      if (kDebugMode) {
        print('Algolia host is reachable');
      }
    }
  } on SocketException catch (_) {
    if (kDebugMode) {
      print('Algolia host is not reachable');
    }
  }
}

class AlgoliaService {
  static const Algolia _algolia = Algolia.init(
    applicationId: '55OV27NTPC', // Replace with your Algolia Application ID
    apiKey:
        'c72bcb855854751e436dd24b54844233', // Replace with your Algolia Search-Only API Key
  );

  Algolia get algolia => _algolia;
}

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  _HomeState createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final TextEditingController _searchController = TextEditingController();
  String _searchText = '';
  List<AlgoliaObjectSnapshot> _searchResults = [];
  bool _isSearching = false;
  bool _showRecipeDetail = false; // Flag to show the recipe detail or grid
  Map<String, dynamic> _selectedFilters = {};
  String? selectedRecipeId;
  List<DocumentSnapshot> _filteredProducts = [];

  // PageController to manage page transitions
  final PageController _pageController = PageController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _pageController.dispose(); // Dispose of the page controller
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchText = _searchController.text;
      if (_searchText.isNotEmpty) {
        _searchAlgolia(_searchText);
      } else {
        _searchResults = [];
      }
    });
  }

  void _clearFilters() {
    setState(() {
      _selectedFilters = {}; // Clear the filters
      _filteredProducts = []; // Reset the filtered products
      _searchController.clear();
    });
    // Removed fetching all products to allow grid view to display
  }

  void _applyFilters(Map<String, dynamic> filters) {
    setState(() {
      _selectedFilters = filters;
    });

    final subCategory = filters['subCategory'];
    final priceRange = filters['priceRange'] as RangeValues;

    // Start a query using the 'category' field for subCategory filtering
    Query query = FirebaseFirestore.instance.collection('products');

    // Apply the subCategory filter to the 'category' field in Firestore
    if (subCategory != null && subCategory.isNotEmpty) {
      query = query.where('category', isEqualTo: subCategory);
    }

    // Apply the price range filter
    query = query
        .where('price', isGreaterThanOrEqualTo: priceRange.start)
        .where('price', isLessThanOrEqualTo: priceRange.end);

    // Get the filtered products
    query.get().then((snapshot) {
      setState(() {
        _filteredProducts = snapshot.docs;
      });
    });
  }

  Future<void> _searchAlgolia(String searchText) async {
    setState(() {
      _isSearching = true;
    });
    Algolia algolia = AlgoliaService().algolia;
    AlgoliaQuery query = algolia.instance.index('t_sty.db').query(searchText);

    try {
      if (kDebugMode) {
        print('Querying Algolia with: $searchText');
      }
      AlgoliaQuerySnapshot snapshot = await query.getObjects();
      setState(() {
        _searchResults = snapshot.hits;
        _isSearching = false;
      });
    } catch (e) {
      if (kDebugMode) {
        print("Error: $e");
      }
      setState(() {
        _isSearching = false;
      });
    }
  }

  // Function to handle navigation to recipe detail
  void _navigateToRecipeDetail(String recipeId) {
    setState(() {
      selectedRecipeId = recipeId;
      _showRecipeDetail = true; // Set flag to show recipe detail
    });
  }

  // Function to navigate back to the recipe grid
  void _navigateBackToGrid() {
    setState(() {
      _showRecipeDetail = false; // Set flag to show grid view
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return WillPopScope(
      onWillPop: () async {
        if (_showRecipeDetail) {
          _navigateBackToGrid();
          return false; // Prevent default behavior
        }
        return true; // Allow default behavior if not showing recipe detail
      },
      child: Scaffold(
        appBar: AppBar(
          scrolledUnderElevation: 0,
          backgroundColor: Colors.transparent,
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
          centerTitle: true,
        ),
        body: _showRecipeDetail
            ? RecipeDetailPage(
                recipeId: selectedRecipeId!,
                onBackPressed: _navigateBackToGrid,
              )
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText: 'Buscar...',
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: _searchController.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear),
                                      onPressed: () {
                                        _searchController.clear();
                                        _onSearchChanged(); // Clear search results
                                      },
                                    )
                                  : null,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                              filled: true,
                              fillColor: isDarkMode
                                  ? Colors.grey[850]
                                  : Colors.grey[200],
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.filter_list),
                          onPressed: () async {
                            final result = await showDialog(
                              context: context,
                              builder: (context) => FilterDialog(
                                initialFilters:
                                    _selectedFilters, // Pass the currently applied filters
                              ),
                            );

                            if (result != null) {
                              if (result['clear'] == true) {
                                _clearFilters(); // Clear filters if 'clear' was pressed
                              } else {
                                setState(() {
                                  _selectedFilters =
                                      result; // Update the selected filters
                                });
                                _applyFilters(result); // Apply the new filters
                              }
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _isSearching
                        ? const CustomLoader() // <--- Replaced CircularProgressIndicator
                        : (_searchText.isNotEmpty
                        ? _buildSearchResults()
                        : (_selectedFilters.isNotEmpty
                        ? _buildFilteredProductList()
                        : _buildProductGrids())),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildSearchResultsOrFilteredProducts() {
    if (_filteredProducts.isNotEmpty) {
      return _buildFilteredProductList(); // If there are filtered products, show them
    } else {
      return _buildSearchResults(); // Otherwise, show search results
    }
  }

  Widget _buildFilteredProductList() {
    if (_filteredProducts.isEmpty) {
      return const Center(
          child: Text('No products found for the applied filters.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 120),
      itemCount: _filteredProducts.length,
      itemBuilder: (context, index) {
        var product = _filteredProducts[index];
        return _buildListItem(context, product); // Passing Firestore document
      },
    );
  }

  Widget _buildProductGrids() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(5.0),
        child: Column(
          children: [
            RecipeGrid(
              title: "Rincon de Recetas 🌞",
              query: FirebaseFirestore.instance.collection('recipes'),
              onRecipeSelected:
                  _navigateToRecipeDetail, // Add the appropriate query for recipes
            ),
            FirestoreProductGrid(
              title: "¡Lo más top! 🔥",
              query: FirebaseFirestore.instance
                  .collection('products')
                  .orderBy('sales_in_past', descending: true)
                  .limit(15),
            ),
            FirestoreProductGrid(
              title: "¡Descuentos del Dia! ✨",
              query: FirebaseFirestore.instance
                  .collection('products')
                  .where('current_day', isEqualTo: true)
                  .limit(15),
            ),
            FirestoreProductGrid(
              title: "Nuestras Recomendaciones ✨",
              query: FirebaseFirestore.instance
                  .collection('products')
                  .where('recommended', isEqualTo: true)
                  .limit(15),
            ),
            Text(
              'Isaías 45:7–9 ',
              style: TextStyle(
                fontSize: 14, // Smaller font size for subtlety
                color: Colors.grey[600], // Subdued color for elegance
                fontStyle: FontStyle.italic, // Italic style for emphasis
              ),
            ),
            const SizedBox(height: 115),
          ],
        ),
      ),
    );
  }

  // Algolia-based search results
  Widget _buildSearchResults() {
    if (_searchResults.isEmpty) {
      return const Center(child: Text('No products found.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 120),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        var product = _searchResults[index];
        return _buildListItem(context, product); // Passing Algolia snapshot
      },
    );
  }

  // Updated method to handle both Algolia and Firestore objects
  Widget _buildListItem(BuildContext context, dynamic doc) {
    Map<String, dynamic> data;
    String? docId;
    String? name;
    double? price;
    String? imageUrl;
    bool isBulk;
    double stock;
    // New variables
    String? typeSpecific;
    String? variante;

    // Handle Algolia snapshot
    if (doc is AlgoliaObjectSnapshot) {
      data = doc.data;
      docId = doc.objectID;
      name = data['nombre'] as String?;
      price = (data['price'] as num?)?.toDouble();
      imageUrl = data['image_url'] as String?;
      isBulk = data['bulk'] as bool? ?? false;
      stock = (data['stock'] as num?)?.toDouble() ?? 0.0;
      typeSpecific = data['type_specific'] as String?; // Extract
      variante = data['variante'] as String?;          // Extract

      // Handle Firestore snapshot
    } else if (doc is DocumentSnapshot) {
      data = doc.data() as Map<String, dynamic>;
      docId = doc.id;
      name = data['nombre'] as String?;
      price = (data['price'] as num?)?.toDouble();
      imageUrl = data['image_url'] as String?;
      isBulk = data['bulk'] as bool? ?? false;
      stock = (data['stock'] as num?)?.toDouble() ?? 0.0;
      typeSpecific = data['type_specific'] as String?; // Extract
      variante = data['variante'] as String?;          // Extract
    } else {
      return const SizedBox.shrink();
    }

    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDarkMode ? Colors.white : Colors.black;

    return Container(
      margin: const EdgeInsets.fromLTRB(8.0, 8.0, 5.0, 5.0),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.grey[800] : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(4, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        // Replace the existing ClipRRect with this:
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8.0),
          child: CachedNetworkImage(
            imageUrl: imageUrl ?? '',
            width: 50,
            height: 50,
            fit: BoxFit.contain,
            // NEW: Shimmer Placeholder
            placeholder: (context, url) => const ShimmerPlaceholder(width: 50, height: 50),
            errorWidget: (context, url, error) => const Icon(Icons.error),
          ),
        ),
        title: Text(
          name ?? 'Unnamed',
          style: TextStyle(fontWeight: FontWeight.bold, color: textColor),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Display Variant and Type Specific in Search List
            if (variante != null && variante.isNotEmpty)
              Text(
                variante,
                style: TextStyle(color: textColor, fontSize: 12),
              ),
            Text(
              _formatPrice(price),
              style: const TextStyle(color: Colors.green),
            ),
            if (typeSpecific != null && typeSpecific.isNotEmpty)
              Text(
                typeSpecific,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
          ],
        ),
        trailing: SizedBox(
          width: 100,
          child: _AddToCartButton(
            data: {
              'docId': docId,
              'nombre': name,
              'price': price,
              'image_url': imageUrl,
              'bulk': isBulk,
              'stock': stock,
              'type_specific': typeSpecific, // Pass to button
              'variante': variante,          // Pass to button
            },
            textColor: textColor,
          ),
        ),
      ),
    );
  }

  String _formatPrice(dynamic price) {
    if (price == null) return 'N/A';
    return '\$${(price as num).toStringAsFixed(2)}';
  }
}

class FirestoreProductGrid extends StatelessWidget {
  final String title;
  final Query<Map<String, dynamic>> query;

  const FirestoreProductGrid({
    super.key,
    required this.title,
    required this.query,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildSection(context, title),
        _buildHorizontalGridView(context),
      ],
    );
  }

  Widget _buildSection(BuildContext context, String title) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDarkMode ? Colors.white : Colors.black;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 8.0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: TextStyle(
            fontSize: 20, // Change this value to adjust the text size
            fontWeight: FontWeight.bold, // Optional: add font weight
            color: textColor,
          ),
        ),
      ),
    );
  }

  Widget _buildHorizontalGridView(BuildContext context) {
    return SizedBox(
      height: 300,
      child: StreamBuilder<QuerySnapshot>(
        stream: query.snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("No se encontraron productos"));
          }
          List<Widget> items = snapshot.data!.docs
              .map((doc) => _buildGridItem(context, doc))
              .toList();
          return ListView(
            scrollDirection: Axis.horizontal,
            children: items,
          );
        },
      ),
    );
  }

  Widget _buildGridItem(BuildContext context, DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // Ensure that objectID is retrieved correctly for grid view
    final String? docId =
        doc.id; // Firebase document ID as fallback if objectID isn't available
    final String? name = data['nombre'] as String?;
    final double? price =
        (data['price'] as num?)?.toDouble(); // Ensure price is a double
    final String? imageUrl = data['image_url'] as String?;
    final bool isBulk =
        data['bulk'] as bool? ?? false; // Check if the item is bulk
    final double stock = (data['stock'] as num?)?.toDouble() ?? 0.0;
    // 1. EXTRACT NEW FIELDS
    final String? typeSpecific = data['type_specific'] as String?;
    final String? variante = data['variante'] as String?;

    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDarkMode ? Colors.white : Colors.black;

    return SizedBox(
      width: 150,
      child: Container(
        margin: const EdgeInsets.fromLTRB(8.0, 8.0, 5.0, 15),
        decoration: BoxDecoration(
          color: isDarkMode ? Colors.grey[800] : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(4, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            SizedBox(height: 5,),
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(10),
                  topRight: Radius.circular(10),
                ),
                child: CachedNetworkImage(
                  imageUrl: imageUrl ?? '',
                  fit: BoxFit.contain,
                  // NEW: Shimmer Placeholder
                  placeholder: (context, url) => const ShimmerPlaceholder(height: 120),
                  errorWidget: (context, url, error) => const Icon(Icons.error),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    name ?? 'Unnamed',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: textColor),
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    data['variante'] ?? 'No variant',
                    style: TextStyle(color: textColor),
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    _formatPrice(price),
                    style: const TextStyle(color: Colors.green),
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    data['type_specific'] ?? 'N/A',
                    style: const TextStyle(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: _AddToCartButton(
                      data: {
                        'docId': docId,
                        'nombre': name,
                        'price': price,
                        'image_url': imageUrl,
                        'bulk': isBulk,
                        'stock': stock, // Pass stock information
                        'type_specific': typeSpecific, // <--- ADD THIS
                        'variante': variante,
                      },
                      textColor: textColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatPrice(dynamic price) {
    if (price == null) return 'N/A';
    return '\$${(price as num).toStringAsFixed(2)}';
  }
}

class _AddToCartButton extends StatefulWidget {
  final Map<String, dynamic> data;
  final Color textColor;

  const _AddToCartButton(
      {super.key, required this.data, required this.textColor});

  @override
  __AddToCartButtonState createState() => __AddToCartButtonState();
}

class __AddToCartButtonState extends State<_AddToCartButton> {
  bool _showSwitchTile = false;
  bool _showAgregadoButton = false;
  double _quantity = 1;
  Timer? _timer;
  late double stock; // Add stock as a state variable
  CartProvider? cartProvider;

  @override
  void initState() {
    super.initState();
    _initializeCartState();

    cartProvider = Provider.of<CartProvider>(context, listen: false);
    cartProvider!.addListener(_checkCartState);

    // Initialize stock
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

  // Method to continuously check the cart state
  void _checkCartState() {
    if (!mounted) return; // Prevent execution if the widget is unmounted

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
    if (stock == 0) {
      // Do nothing if stock is 0
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

        // Update timer call to include new fields if needed, or pass via widget.data in closure
        _resetAndStartTimer(docId, name, price, imageUrl, cartProvider, isBulk, typeSpecific, variante);
      }
    }
  }

  void _resetAndStartTimer(String docId, String name, double price,
      String imageUrl, CartProvider cartProvider, bool isBulk, String? typeSpecific, String? variante) {
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
              typeSpecific: typeSpecific, // Pass new field
              variante: variante,         // Pass new field
            );
          } else {
            cartProvider.removeItemCompletely(docId);
          }
          // ... rest of logic
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel(); // Cancel any timers
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

      // Extract the new fields
      final String? typeSpecific = widget.data['type_specific'] as String?;
      final String? variante = widget.data['variante'] as String?;

      final cartProvider = Provider.of<CartProvider>(context, listen: false);

      _resetAndStartTimer(
          docId!, name!, price!, imageUrl!, cartProvider, isBulk, typeSpecific, variante);
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

      // Extract the new fields
      final String? typeSpecific = widget.data['type_specific'] as String?;
      final String? variante = widget.data['variante'] as String?;

      final cartProvider = Provider.of<CartProvider>(context, listen: false);

      _resetAndStartTimer(
          docId!, name!, price!, imageUrl!, cartProvider, isBulk, typeSpecific, variante);
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
                  prefill: true); // Prefill the dialog if it's bulk
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

    // Pre-fill the dialog with the current cart quantity
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
                        // Inside the Row children:
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8.0),
                          child: CachedNetworkImage(
                            imageUrl: widget.data['image_url'] ?? '',
                            width: 50,
                            height: 50,
                            fit: BoxFit.contain,
                            placeholder: (context, url) => const ShimmerPlaceholder(width: 50, height: 50),
                            errorWidget: (context, url, error) => const Icon(Icons.error),
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
                      // Optionally, show a snackbar or alert indicating insufficient stock
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('No hay suficiente stock disponible'),
                        ),
                      );
                    } else {
                      Navigator.of(context).pop();
                      if (widget.data['docId'] != null && widget.data['nombre'] != null) {
                        cartProvider.setItem(
                          widget.data['docId'],
                          widget.data['nombre'],
                          widget.data['price'],
                          widget.data['image_url'] ?? '/images/placeholder.png',
                          kilos,
                          isBulk: true,
                          stock: stock,
                          typeSpecific: widget.data['type_specific'], // Pass field
                          variante: widget.data['variante'],          // Pass field
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
