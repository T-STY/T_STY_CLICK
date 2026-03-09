import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:algolia/algolia.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:click/app/recipes.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../auth/login_page.dart';
import '../../custom_page_route.dart';
import '../components/custom_loader.dart';
import '../components/shimmer_placeholder.dart';
import '../constants/app_images.dart';
import 'cart/cart_provider.dart';
import 'category/filter_dialog.dart';
import 'game/arcade_center_screen.dart';
import 'constants/gridview.dart';

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
    applicationId: '55OV27NTPC',
    apiKey: 'c72bcb855854751e436dd24b54844233',
  );

  Algolia get algolia => _algolia;
}

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with TickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  String _searchText = '';
  List<AlgoliaObjectSnapshot> _searchResults = [];
  bool _isSearching = false;
  bool _showRecipeDetail = false;
  Map<String, dynamic> _selectedFilters = {};
  String? selectedRecipeId;
  List<DocumentSnapshot> _filteredProducts = [];

  final PageController _pageController = PageController();

  // ─── Game entry ────────────────────────────────────────────────────────────
  bool _showGameHint = true;       // hint callout near logo
  bool _shaking = false;           // prevent double-taps during shake
  late AnimationController _shakeCtrl;   // logo horizontal shake
  late Animation<double> _shakeAnim;
  late AnimationController _hintBobCtrl; // hint character bobbing

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);

    // Logo shake: horizontal oscillation → 7 snaps over 550ms
    _shakeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 550));
    _shakeAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -10.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -10.0, end: 10.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 10.0, end: -8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -8.0, end: 8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8.0, end: -4.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -4.0, end: 0.0), weight: 1),
    ]).animate(CurvedAnimation(parent: _shakeCtrl, curve: Curves.linear));

    // Hint character: slow continuous bob (up/down 6px)
    _hintBobCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _pageController.dispose();
    _shakeCtrl.dispose();
    _hintBobCtrl.dispose();
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
      _selectedFilters = {};
      _filteredProducts = [];
      _searchController.clear();
    });
  }

  void _applyFilters(Map<String, dynamic> filters) {
    setState(() {
      _selectedFilters = filters;
    });

    final subCategory = filters['subCategory'];
    final priceRange = filters['priceRange'] as RangeValues;

    Query query = FirebaseFirestore.instance.collection('products');

    if (subCategory != null && subCategory.isNotEmpty) {
      query = query.where('category', isEqualTo: subCategory);
    }

    query = query
        .where('price', isGreaterThanOrEqualTo: priceRange.start)
        .where('price', isLessThanOrEqualTo: priceRange.end);

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

  void _navigateToRecipeDetail(String recipeId) {
    setState(() {
      selectedRecipeId = recipeId;
      _showRecipeDetail = true;
    });
  }

  void _navigateBackToGrid() {
    setState(() {
      _showRecipeDetail = false;
    });
  }

  // ─── Game entry ─────────────────────────────────────────────────────────────

  void _handleLogoTap() {
    if (_shaking) return;
    _shaking = true;
    setState(() => _showGameHint = false);
    _shakeCtrl.forward(from: 0).then((_) {
      _shaking = false;
      _launchGame();
    });
  }

  Future<void> _launchGame() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final uid = user.uid;

    final cardDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('rewardsCard')
        .doc('cardInfo')
        .get();
    if (!cardDoc.exists) return;

    final cardNumber = cardDoc.data()?['cardNumber'] as String?;
    if (cardNumber == null) return;

    final rewardsSnap = await FirebaseFirestore.instance
        .collection('rewards')
        .where('cardNumber', isEqualTo: cardNumber)
        .limit(1)
        .get();
    if (rewardsSnap.docs.isEmpty) return;

    final rewardsDoc = rewardsSnap.docs.first;
    final raw = rewardsDoc.data()['saldo'];
    final double saldo = raw is String
        ? double.tryParse(raw) ?? 0.0
        : raw is int
            ? raw.toDouble()
            : (raw as double? ?? 0.0);

    if (saldo < 10) return;

    if (!mounted) return;

    // Launch via animated transition screen
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (ctx, _, __) => _ArcadeLaunchPage(
          userId: uid,
          rewardsDocRef: rewardsDoc.reference,
          currentSaldo: saldo,
        ),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: !_showRecipeDetail,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_showRecipeDetail) {
          _navigateBackToGrid();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          scrolledUnderElevation: 0,
          backgroundColor: Colors.transparent,
          title: SizedBox(
            height: 180,
            width: 300,
            child: AspectRatio(
              aspectRatio: 1 / 1,
              child: GestureDetector(
                onTap: _handleLogoTap,
                behavior: HitTestBehavior.opaque,
                child: AnimatedBuilder(
                  animation: _shakeAnim,
                  builder: (_, child) => Transform.translate(
                    offset: Offset(_shakeAnim.value, 0),
                    child: child,
                  ),
                  child: Image.asset(
                    isDarkMode ? AppImages.logowhite : AppImages.logo,
                    fit: BoxFit.contain,
                  ),
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
            // ── Game hint callout ──────────────────────────────────────────
            if (_showGameHint) _buildGameHint(),
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
                            _onSearchChanged();
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
                          initialFilters: _selectedFilters,
                        ),
                      );

                      if (result != null) {
                        if (result['clear'] == true) {
                          _clearFilters();
                        } else {
                          setState(() {
                            _selectedFilters = result;
                          });
                          _applyFilters(result);
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: _isSearching
                  ? const CustomLoader()
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
        return _buildListItem(context, product);
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
              onRecipeSelected: _navigateToRecipeDetail,
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
                fontSize: 14,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 115),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_searchResults.isEmpty) {
      return const Center(child: Text('No products found.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 120),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        var product = _searchResults[index];
        return _buildListItem(context, product);
      },
    );
  }

  Widget _buildListItem(BuildContext context, dynamic doc) {
    Map<String, dynamic> data;
    String? docId;
    String? name;
    double? price;
    String? imageUrl;
    bool isBulk;
    double stock;
    String? typeSpecific;
    String? variante;

    if (doc is AlgoliaObjectSnapshot) {
      data = doc.data;
      docId = doc.objectID;
      name = data['nombre'] as String?;
      price = (data['price'] as num?)?.toDouble();
      imageUrl = data['image_url'] as String?;
      isBulk = data['bulk'] as bool? ?? false;
      stock = (data['stock'] as num?)?.toDouble() ?? 0.0;
      typeSpecific = data['type_specific'] as String?;
      variante = data['variante'] as String?;
    } else if (doc is DocumentSnapshot) {
      data = doc.data() as Map<String, dynamic>;
      docId = doc.id;
      name = data['nombre'] as String?;
      price = (data['price'] as num?)?.toDouble();
      imageUrl = data['image_url'] as String?;
      isBulk = data['bulk'] as bool? ?? false;
      stock = (data['stock'] as num?)?.toDouble() ?? 0.0;
      typeSpecific = data['type_specific'] as String?;
      variante = data['variante'] as String?;
    } else {
      return const SizedBox.shrink();
    }

    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDarkMode ? Colors.white : Colors.black;
    final bool isGuest = FirebaseAuth.instance.currentUser == null;

    return Container(
      margin: const EdgeInsets.fromLTRB(8.0, 8.0, 5.0, 5.0),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.grey[800] : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(4, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding:
        const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8.0),
          child: CachedNetworkImage(
            imageUrl: imageUrl ?? '',
            width: 50,
            height: 50,
            fit: BoxFit.contain,
            placeholder: (context, url) =>
            const ShimmerPlaceholder(width: 50, height: 50),
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
            if (variante != null && variante.isNotEmpty)
              Text(
                variante,
                style: TextStyle(color: textColor, fontSize: 12),
              ),
            ImageFiltered(
              imageFilter: ImageFilter.blur(
                sigmaX: isGuest ? 6.0 : 0.0,
                sigmaY: isGuest ? 6.0 : 0.0,
              ),
              child: Text(
                _formatPrice(price),
                style: const TextStyle(color: Colors.green),
              ),
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
              'type_specific': typeSpecific,
              'variante': variante,
            },
            textColor: textColor,
          ),
        ),
      ),
    );
  }

  // ─── Game hint callout ──────────────────────────────────────────────────────
  Widget _buildGameHint() {
    return AnimatedBuilder(
      animation: _hintBobCtrl,
      builder: (_, __) {
        final bob = (_hintBobCtrl.value - 0.5) * 8;
        return Transform.translate(
          offset: Offset(0, bob),
          child: GestureDetector(
            onTap: _handleLogoTap,
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 2, 16, 0),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF07000F),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFF00FF88).withValues(alpha: 0.55),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00FF88).withValues(alpha: 0.15),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _PixelCharacter(phase: _hintBobCtrl.value),
                  const SizedBox(width: 10),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            '▲',
                            style: TextStyle(
                              color: Color(0xFF00FF88),
                              fontSize: 11,
                              shadows: [Shadow(color: Color(0xFF00FF88), blurRadius: 8)],
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '¡Presióname para un buen rato!',
                            style: TextStyle(
                              color: const Color(0xFF00FF88).withValues(alpha: 0.90),
                              fontSize: 11,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'toca el logo  ·  10 pts mínimo',
                        style: TextStyle(
                          color: const Color(0xFF00FF88).withValues(alpha: 0.45),
                          fontSize: 9,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  const Text('🕹️', style: TextStyle(fontSize: 22)),
                ],
              ),
            ),
          ),
        );
      },
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
            fontSize: 20,
            fontWeight: FontWeight.bold,
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

    final String docId = doc.id;
    final String? name = data['nombre'] as String?;
    final double? price = (data['price'] as num?)?.toDouble();
    final String? imageUrl = data['image_url'] as String?;
    final bool isBulk = data['bulk'] as bool? ?? false;
    final double stock = (data['stock'] as num?)?.toDouble() ?? 0.0;
    final String? typeSpecific = data['type_specific'] as String?;
    final String? variante = data['variante'] as String?;

    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDarkMode ? Colors.white : Colors.black;
    final bool isGuest = FirebaseAuth.instance.currentUser == null;

    return SizedBox(
      width: 150,
      child: Container(
        margin: const EdgeInsets.fromLTRB(8.0, 8.0, 5.0, 8.0),
        decoration: BoxDecoration(
          color: isDarkMode ? Colors.grey[800] : Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 6,
              offset: const Offset(2, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Column(
              children: [
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
                  child: SizedBox(
                    height: 136,
                    width: double.infinity,
                    child: CachedNetworkImage(
                      imageUrl: imageUrl ?? '',
                      fit: BoxFit.contain,
                      placeholder: (context, url) =>
                      const ShimmerPlaceholder(height: 80),
                      errorWidget: (context, url, error) =>
                      const Icon(Icons.error, size: 30),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding:
              const EdgeInsets.symmetric(horizontal: 6.0, vertical: 6.0),
              child: Column(
                children: [
                  Text(
                    name ?? 'Unnamed',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: textColor,
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (variante != null && variante.isNotEmpty)
                    Text(
                      variante,
                      style: TextStyle(
                          color: textColor.withValues(alpha: 0.8),
                          fontSize: 12),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ImageFiltered(
                    imageFilter: ImageFilter.blur(
                      sigmaX: isGuest ? 6.0 : 0.0,
                      sigmaY: isGuest ? 6.0 : 0.0,
                    ),
                    child: Text(
                      _formatPrice(price),
                      style: const TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                          fontSize: 12),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                    ),
                  ),
                  Text(
                    typeSpecific ?? '',
                    style: const TextStyle(color: Colors.grey, fontSize: 10),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Spacer(),
            Padding(
              padding:
              const EdgeInsets.only(left: 6.0, right: 6.0, bottom: 6.0),
              child: SizedBox(
                width: double.infinity,
                height: 40,
                child: _AddToCartButton(
                  data: {
                    'docId': docId,
                    'nombre': name,
                    'price': price,
                    'image_url': imageUrl,
                    'bulk': isBulk,
                    'stock': stock,
                    'type_specific': typeSpecific,
                    'variante': variante,
                  },
                  textColor: textColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

}

class _AddToCartButton extends StatefulWidget {
  final Map<String, dynamic> data;
  final Color textColor;

  const _AddToCartButton({required this.data, required this.textColor});

  @override
  _AddToCartButtonState createState() => _AddToCartButtonState();
}

class _AddToCartButtonState extends State<_AddToCartButton> {
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
    final String? typeSpecific = widget.data['type_specific'];
    final String? variante = widget.data['variante'];

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
      final String? typeSpecific = widget.data['type_specific'];
      final String? variante = widget.data['variante'];

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
      final String? typeSpecific = widget.data['type_specific'];
      final String? variante = widget.data['variante'];

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
              _showBulkOrderDialog(prefill: true);
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
                          child: CachedNetworkImage(
                            imageUrl: widget.data['image_url'] ?? '',
                            width: 50,
                            height: 50,
                            fit: BoxFit.contain,
                            placeholder: (context, url) =>
                            const ShimmerPlaceholder(width: 50, height: 50),
                            errorWidget: (context, url, error) =>
                            const Icon(Icons.error),
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
                          typeSpecific: widget.data['type_specific'],
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
// ─── Pixel character hint widget ─────────────────────────────────────────────
class _PixelCharacter extends StatelessWidget {
  final double phase; // 0..1 animation phase for arm wave

  const _PixelCharacter({required this.phase});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(28, 36),
      painter: _PixelCharacterPainter(phase: phase),
    );
  }
}

class _PixelCharacterPainter extends CustomPainter {
  final double phase;
  const _PixelCharacterPainter({required this.phase});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final px = w / 7; // ~4px per pixel unit

    void rect(double x, double y, double pw, double ph, Color c) {
      canvas.drawRect(
        Rect.fromLTWH(x * px, y * px, pw * px, ph * px),
        Paint()..color = c,
      );
    }

    // Head
    rect(2, 0, 3, 3, const Color(0xFF00FF88));
    // Eyes
    rect(2.4, 0.6, 0.6, 0.6, const Color(0xFF07000F));
    rect(3.8, 0.6, 0.6, 0.6, const Color(0xFF07000F));
    // Smile
    rect(2.6, 1.8, 1.6, 0.4, const Color(0xFF07000F));

    // Body
    rect(2, 3, 3, 3, const Color(0xFF00CC66));

    // Arms — left arm static, right arm waves with phase
    final armRaise = (phase * 2.0).clamp(0.0, 1.0); // 0..1 pointing up
    rect(0.5, 3 + 1.5 * (1 - armRaise), 1.5, 0.8, const Color(0xFF00FF88));
    rect(5, 3, 1.5, 0.8, const Color(0xFF00FF88));

    // Legs
    rect(2.2, 6, 1.0, 2.5, const Color(0xFF00AA55));
    rect(3.8, 6, 1.0, 2.5, const Color(0xFF00AA55));
  }

  @override
  bool shouldRepaint(_PixelCharacterPainter old) => old.phase != phase;
}

// ─── Arcade launch transition page ───────────────────────────────────────────
class _ArcadeLaunchPage extends StatefulWidget {
  final String userId;
  final DocumentReference rewardsDocRef;
  final double currentSaldo;

  const _ArcadeLaunchPage({
    required this.userId,
    required this.rewardsDocRef,
    required this.currentSaldo,
  });

  @override
  State<_ArcadeLaunchPage> createState() => _ArcadeLaunchPageState();
}

class _ArcadeLaunchPageState extends State<_ArcadeLaunchPage> {
  // Phase 0: flicker; Phase 1: boot lines; Phase 2: navigate
  int _phase = 0;
  bool _screenLight = true;
  int _flickerCount = 0;
  final List<String> _visibleLines = [];
  Timer? _flickerTimer;
  Timer? _bootTimer;

  static const _bootLines = [
    'ARCADE OS v2.4.1 [BUILD 20260309]',
    'Initializing display adapter........OK',
    'Loading cartridge ROM................OK',
    'Scanning input controllers...........OK',
    'Mounting game filesystem.............OK',
    'Checking high score database.........OK',
    'Allocating framebuffer (240×160).....OK',
    'Starting audio subsystem.............OK',
    '> BIENVENIDO AL ARCADE CENTER <',
    '',
    '¡QUE EMPIECE EL JUEGO!',
  ];

  @override
  void initState() {
    super.initState();
    _startFlicker();
  }

  void _startFlicker() {
    _flickerTimer = Timer.periodic(const Duration(milliseconds: 80), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _screenLight = !_screenLight);
      _flickerCount++;
      if (_flickerCount >= 12) {
        t.cancel();
        setState(() {
          _screenLight = false;
          _phase = 1;
        });
        _startBootLines();
      }
    });
  }

  void _startBootLines() {
    int lineIdx = 0;
    _bootTimer = Timer.periodic(const Duration(milliseconds: 120), (t) {
      if (!mounted) { t.cancel(); return; }
      if (lineIdx < _bootLines.length) {
        setState(() => _visibleLines.add(_bootLines[lineIdx]));
        lineIdx++;
      } else {
        t.cancel();
        Future.delayed(const Duration(milliseconds: 500), _launchArcade);
      }
    });
  }

  void _launchArcade() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (ctx, _, __) => ArcadeCenterScreen(
          userId: widget.userId,
          rewardsDocRef: widget.rewardsDocRef,
          currentSaldo: widget.currentSaldo,
        ),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  @override
  void dispose() {
    _flickerTimer?.cancel();
    _bootTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Phase 0: flicker — alternating white/black
    if (_phase == 0) {
      return Scaffold(
        backgroundColor: _screenLight ? Colors.white : Colors.black,
        body: const SizedBox.expand(),
      );
    }

    // Phase 1: black terminal with scrolling boot lines
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              ..._visibleLines.map((line) => _TermLine(text: line)),
              // blinking cursor
              const _BlinkCursor(),
            ],
          ),
        ),
      ),
    );
  }
}

// Single terminal output line
class _TermLine extends StatelessWidget {
  final String text;
  const _TermLine({required this.text});

  @override
  Widget build(BuildContext context) {
    final isHighlight = text.startsWith('>') || text.startsWith('¡');
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Text(
        text,
        style: TextStyle(
          color: isHighlight ? const Color(0xFF00FF88) : const Color(0xFF22DD66),
          fontSize: isHighlight ? 13 : 11,
          fontFamily: 'monospace',
          fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal,
          letterSpacing: 0.5,
          shadows: isHighlight
              ? [const Shadow(color: Color(0xFF00FF88), blurRadius: 10)]
              : null,
        ),
      ),
    );
  }
}

// Blinking underscore cursor
class _BlinkCursor extends StatefulWidget {
  const _BlinkCursor();
  @override
  State<_BlinkCursor> createState() => _BlinkCursorState();
}

class _BlinkCursorState extends State<_BlinkCursor> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Text(
        _ctrl.value > 0.5 ? '_' : ' ',
        style: const TextStyle(
          color: Color(0xFF00FF88),
          fontSize: 12,
          fontFamily: 'monospace',
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
