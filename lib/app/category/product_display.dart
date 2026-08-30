import 'dart:async';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../components/bottom_fade.dart';
import '../../components/shimmer_placeholder.dart';
import '../../constants/app_images.dart';
import '../cart/cart_provider.dart';
import '../../auth/login_page.dart';
import '../../custom_page_route.dart';

class ProductDisplayPage extends StatefulWidget {
  final String? selectedCategory;
  final String? brand;
  final String? distributorName;
  final List<String>? productIds;
  final double? minPrice;
  final double? maxPrice;
  final String? title;
  final String? imageUrl;
  final VoidCallback? onBack;

  const ProductDisplayPage({
    super.key,
    this.selectedCategory,
    this.brand,
    this.distributorName,
    this.productIds,
    this.minPrice,
    this.maxPrice,
    this.title,
    this.imageUrl,
    this.onBack,
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

  Query<Map<String, dynamic>> _buildProductsQuery() {
    Query<Map<String, dynamic>> q =
        FirebaseFirestore.instance.collection('products');

    final ids = widget.productIds;
    if (ids != null && ids.isNotEmpty) {
      return q.where(FieldPath.documentId, whereIn: ids.take(30).toList());
    }

    final category = widget.selectedCategory;
    if (category != null && category.isNotEmpty) {
      q = q.where('category', isEqualTo: category);
    }
    final brand = widget.brand;
    if (brand != null && brand.isNotEmpty) {
      q = q.where('brand', isEqualTo: brand);
    }
    final distributor = widget.distributorName;
    if (distributor != null && distributor.isNotEmpty) {
      q = q.where('distribuitor_name', isEqualTo: distributor);
    }
    if (widget.minPrice != null) {
      q = q.where('price', isGreaterThanOrEqualTo: widget.minPrice);
    }
    if (widget.maxPrice != null) {
      q = q.where('price', isLessThanOrEqualTo: widget.maxPrice);
    }
    return q;
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final Color bg = isDarkMode ? const Color(0xFF1A1A1D) : Colors.white;
    final Widget content = _buildContent(context, isDarkMode);

    if (widget.onBack == null) {
      return Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          scrolledUnderElevation: 0,
          backgroundColor: Colors.transparent,
          automaticallyImplyLeading: false,
          centerTitle: true,
          title: SizedBox(
            height: 44,
            child: Image.asset(
              isDarkMode ? AppImages.logowhite : AppImages.logo,
              fit: BoxFit.contain,
            ),
          ),
        ),
        body: SafeArea(top: false, child: content),
      );
    }

    return Container(color: bg, child: content);
  }

  Widget _buildContent(BuildContext context, bool isDarkMode) {
    final Color titleColor =
        isDarkMode ? Colors.white : const Color(0xFF1A1A1A);
    final Color mutedColor =
        isDarkMode ? Colors.grey[400]! : Colors.grey[600]!;

    final String header = widget.imageUrl ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (header.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: CachedNetworkImage(
                imageUrl: header,
                height: 170,
                width: double.infinity,
                fit: BoxFit.cover,
                placeholder: (c, u) =>
                    Container(height: 170, color: Colors.grey[200]),
                errorWidget: (c, u, e) => const SizedBox.shrink(),
              ),
            ),
          ),
        if (widget.title != null && widget.title!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 16, 0),
            child: Text(
              widget.title!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                color: titleColor,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
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
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: isDarkMode ? Colors.grey[850] : Colors.grey[200],
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _buildProductsQuery().snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return _buildShimmerList();
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }

              final docs = (snapshot.data?.docs ?? []).where((product) {
                final data = product.data();
                if ((data['hide_online'] as bool?) == true) return false;
                if (_searchQuery.isEmpty) return true;
                final name =
                    data['nombre']?.toString().toLowerCase() ?? '';
                if (name.contains(_searchQuery)) return true;
                final variante =
                    data['variante']?.toString().toLowerCase() ?? '';
                if (variante.contains(_searchQuery)) return true;

                if (data['has_variants'] == true && data['variants'] is Map) {
                  for (final v in (data['variants'] as Map).values) {
                    if (v is Map) {
                      final vn = (v['name'] ?? '').toString().toLowerCase();
                      if (vn.contains(_searchQuery)) return true;
                    }
                  }
                }
                return false;
              }).toList();

              _sortProducts(docs);

              final entries = _expandIntoEntries(docs);
              final filteredEntries = _searchQuery.isEmpty
                  ? entries
                  : _narrowEntriesBySearch(entries, _searchQuery);

              if (filteredEntries.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inventory_2_outlined,
                          size: 48, color: mutedColor),
                      const SizedBox(height: 12),
                      Text('No hay productos',
                          style: TextStyle(color: mutedColor, fontSize: 15)),
                    ],
                  ),
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 6, 16, 8),
                    child: Text(
                      '${filteredEntries.length} ${filteredEntries.length == 1 ? 'producto' : 'productos'}',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: mutedColor),
                    ),
                  ),
                  Expanded(
                    child: BottomFade(
                      child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                      itemCount: filteredEntries.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) =>
                          _buildEntry(context, filteredEntries[index]),
                    ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  void _sortProducts(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final ids = widget.productIds;
    if (ids != null && ids.isNotEmpty) {
      final indexById = <String, int>{
        for (int i = 0; i < ids.length; i++) ids[i]: i,
      };
      const last = 1 << 30;
      docs.sort((a, b) =>
          (indexById[a.id] ?? last).compareTo(indexById[b.id] ?? last));
    } else {
      docs.sort((a, b) {
        final nameA = (a.data()['nombre'] as String? ?? '').toLowerCase();
        final nameB = (b.data()['nombre'] as String? ?? '').toLowerCase();
        return nameA.compareTo(nameB);
      });
    }
  }

  Widget _buildShimmerList() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          children: [
            ShimmerPlaceholder(width: 88, height: 88),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShimmerPlaceholder(width: 150, height: 14),
                  SizedBox(height: 8),
                  ShimmerPlaceholder(width: 80, height: 12),
                  SizedBox(height: 10),
                  ShimmerPlaceholder(width: 100, height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<_CatalogueEntry> _expandIntoEntries(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final out = <_CatalogueEntry>[];
    for (final doc in docs) {
      final data = doc.data();
      if (data['has_variants'] != true) {
        out.add(_CatalogueEntry(doc: doc));
        continue;
      }
      final variants = data['variants'];
      if (variants is! Map) {
        out.add(_CatalogueEntry(doc: doc));
        continue;
      }
      final order = (data['variant_order'] as List?)
              ?.map((e) => e.toString())
              .where(variants.containsKey)
              .toList() ??
          variants.keys.map((e) => e.toString()).toList();

      for (final k in variants.keys) {
        final s = k.toString();
        if (!order.contains(s)) order.add(s);
      }
      for (final key in order) {
        final v = variants[key];
        if (v is! Map) continue;
        if (v['hide_online'] == true) continue;
        out.add(_CatalogueEntry(
          doc: doc,
          variantKey: key,
          variantData: Map<String, dynamic>.from(v),
        ));
      }
    }
    return out;
  }

  List<_CatalogueEntry> _narrowEntriesBySearch(
      List<_CatalogueEntry> entries, String query) {
    final q = query.toLowerCase();
    final List<_CatalogueEntry> out = [];

    final Map<String, List<_CatalogueEntry>> byParent = {};
    for (final e in entries) {
      byParent.putIfAbsent(e.doc.id, () => []).add(e);
    }
    for (final group in byParent.values) {
      final first = group.first;
      final data = first.doc.data();
      final parentName =
          (data['nombre'] ?? '').toString().toLowerCase();
      final parentVariante =
          (data['variante'] ?? '').toString().toLowerCase();
      final bool parentMatches =
          parentName.contains(q) || parentVariante.contains(q);
      if (parentMatches) {

        out.addAll(group);
        continue;
      }

      for (final e in group) {
        if (e.variantKey == null) {
          out.add(e);
          continue;
        }
        final vn =
            (e.variantData?['name'] ?? '').toString().toLowerCase();
        if (vn.contains(q)) out.add(e);
      }
    }
    return out;
  }

  Widget _buildEntry(BuildContext context, _CatalogueEntry entry) {
    if (entry.variantKey == null) {
      return _buildProductListItem(context, entry.doc);
    }
    return _buildVariantListItem(context, entry);
  }

  Widget _buildProductListItem(BuildContext context,
      QueryDocumentSnapshot<Map<String, dynamic>> product) {
    final data = product.data();
    final String name = data['nombre'] ?? 'Producto';
    final double price = (data['price'] as num?)?.toDouble() ?? 0.0;
    final String imageUrl = data['image_url'] ?? '';
    final bool isBulk = data['bulk'] as bool? ?? false;
    final double stock = (data['stock'] as num?)?.toDouble() ?? 0.0;
    final String? typeSpecific = data['type_specific'] as String?;
    final String? variante = data['variante'] as String?;
    final String sub = [variante, typeSpecific]
        .where((s) => (s ?? '').trim().isNotEmpty)
        .map((s) => s!.trim())
        .join(' · ');
    final bool isGuest = FirebaseAuth.instance.currentUser == null;
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 88,
              height: 88,
              child: imageUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.contain,
                      placeholder: (context, url) =>
                          const ShimmerPlaceholder(width: 88, height: 88),
                      errorWidget: (context, url, error) => Icon(
                          Icons.image_not_supported, color: Colors.grey[300]),
                    )
                  : Icon(Icons.image, color: Colors.grey[300]),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: isDarkMode ? Colors.white : const Color(0xFF1A1A1A),
                  ),
                ),
                if (sub.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: Colors.grey[600]),
                  ),
                ],
                const SizedBox(height: 6),
                ImageFiltered(
                  imageFilter: ImageFilter.blur(
                    sigmaX: isGuest ? 6.0 : 0.0,
                    sigmaY: isGuest ? 6.0 : 0.0,
                  ),
                  child: Text(
                    '\$${price.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF2E7D32),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 104,
            child: AddToCartButton(
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
              textColor: isDarkMode ? Colors.white : Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVariantListItem(
      BuildContext context, _CatalogueEntry entry) {
    final pd = entry.doc.data();
    final v = entry.variantData!;
    final String parentName = pd['nombre'] ?? 'Producto';
    final String variantName = (v['name'] ?? entry.variantKey!).toString();
    final double parentPrice = (pd['price'] as num?)?.toDouble() ?? 0.0;
    final double parentCost = (pd['cost'] as num?)?.toDouble() ?? 0.0;
    final double price =
        (v['price'] as num?)?.toDouble() ?? parentPrice;
    final String imageUrl = ((v['image_url'] ?? '') as String).isNotEmpty
        ? v['image_url'] as String
        : (pd['image_url'] ?? '') as String;
    final bool isBulk =
        (v['bulk'] as bool?) ?? (pd['bulk'] as bool? ?? false);
    final double stock = (v['stock'] as num?)?.toDouble() ?? 0.0;
    final String? typeSpecific = pd['type_specific'] as String?;
    final bool isGuest = FirebaseAuth.instance.currentUser == null;
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    // ignore: unused_local_variable
    final double effectiveCost =
        (v['cost'] as num?)?.toDouble() ?? parentCost;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 88,
              height: 88,
              child: imageUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.contain,
                      placeholder: (context, url) =>
                          const ShimmerPlaceholder(width: 88, height: 88),
                      errorWidget: (context, url, error) => Icon(
                          Icons.image_not_supported,
                          color: Colors.grey[300]),
                    )
                  : Icon(Icons.image, color: Colors.grey[300]),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  parentName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: isDarkMode ? Colors.white : const Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  variantName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 6),
                ImageFiltered(
                  imageFilter: ImageFilter.blur(
                    sigmaX: isGuest ? 6.0 : 0.0,
                    sigmaY: isGuest ? 6.0 : 0.0,
                  ),
                  child: Text(
                    '\$${price.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF2E7D32),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 104,
            child: AddToCartButton(

              key: ValueKey('${entry.doc.id}#${entry.variantKey}'),
              data: {
                'docId': entry.doc.id,
                'nombre': parentName,
                'price': price,
                'image_url': imageUrl,
                'bulk': isBulk,
                'stock': stock,
                'type_specific': typeSpecific,
                'variante': variantName,
                'variantKey': entry.variantKey,
                'variantName': variantName,
              },
              textColor: isDarkMode ? Colors.white : Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}

class _CatalogueEntry {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final String? variantKey;
  final Map<String, dynamic>? variantData;

  _CatalogueEntry({
    required this.doc,
    this.variantKey,
    this.variantData,
  });
}

class AddToCartButton extends StatefulWidget {
  final Map<String, dynamic> data;
  final Color textColor;

  const AddToCartButton(
      {super.key, required this.data, required this.textColor});

  @override
  State<AddToCartButton> createState() => _AddToCartButtonState();
}

class _AddToCartButtonState extends State<AddToCartButton> {
  bool _showSwitchTile = false;
  bool _showAgregadoButton = false;
  bool _pendingCommit = false;
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

  String? _lineId() {
    final String? productId = widget.data['docId'] as String?;
    if (productId == null) return null;
    final String? variantKey = widget.data['variantKey'] as String?;
    return buildCartLineId(productId, variantKey);
  }

  void _initializeCartState() {
    final cartProvider = Provider.of<CartProvider>(context, listen: false);
    final lineId = _lineId();

    if (lineId != null) {
      final cartItem = cartProvider.getItem(lineId);

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
    final lineId = _lineId();

    if (lineId != null) {
      final cartItem = cartProvider.getItem(lineId);

      if (cartItem != null && cartItem.quantity > 0) {
        setState(() {
          _quantity = cartItem.quantity;
          if (!_pendingCommit) {
            _showSwitchTile = true;
            _showAgregadoButton = true;
          }
        });
      } else {
        setState(() {
          _showSwitchTile = false;
          _showAgregadoButton = false;
          _pendingCommit = false;
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
    final String? variantKey = widget.data['variantKey'] as String?;
    final String? variantName = widget.data['variantName'] as String?;

    if (docId != null && name != null && price != null && imageUrl != null) {
      if (isBulk) {
        _showBulkOrderDialog();
      } else {
        setState(() {
          _showSwitchTile = true;
          _quantity = 1;
          _showAgregadoButton = false;
          _pendingCommit = true;
        });

        _commitToCart(docId, name, price, imageUrl, cartProvider, isBulk,
            typeSpecific, variante,
            variantKey: variantKey, variantName: variantName);
        _resetAndStartTimer();
      }
    }
  }

  void _commitToCart(
      String docId,
      String name,
      double price,
      String imageUrl,
      CartProvider cartProvider,
      bool isBulk,
      String? typeSpecific,
      String? variante,
      {String? variantKey,
      String? variantName}) {
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
        variantKey: variantKey,
        variantName: variantName,
      );
    } else {
      cartProvider.removeItemCompletely(buildCartLineId(docId, variantKey));
    }
  }

  void _resetAndStartTimer() {
    _timer?.cancel();

    _timer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _pendingCommit = false;
          _showSwitchTile = false;
          _showAgregadoButton = true;
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
        _pendingCommit = true;
      });

      final String? docId = widget.data['docId'] as String?;
      final String? name = widget.data['nombre'] as String?;
      final double? price = widget.data['price'] as double?;
      final String? imageUrl = widget.data['image_url'] as String?;
      final bool isBulk = widget.data['bulk'] as bool? ?? false;
      final cartProvider = Provider.of<CartProvider>(context, listen: false);
      final String? typeSpecific = widget.data['type_specific'] as String?;
      final String? variante = widget.data['variante'] as String?;

      _commitToCart(docId!, name!, price!, imageUrl!, cartProvider, isBulk,
          typeSpecific, variante,
          variantKey: widget.data['variantKey'] as String?,
          variantName: widget.data['variantName'] as String?);
      _resetAndStartTimer();
    }
  }

  void _decrementQuantity() {
    if (_quantity > 1) {
      setState(() {
        _quantity--;
        _pendingCommit = true;
      });

      final String? docId = widget.data['docId'] as String?;
      final String? name = widget.data['nombre'] as String?;
      final double? price = widget.data['price'] as double?;
      final String? imageUrl = widget.data['image_url'] as String?;
      final bool isBulk = widget.data['bulk'] as bool? ?? false;
      final cartProvider = Provider.of<CartProvider>(context, listen: false);
      final String? typeSpecific = widget.data['type_specific'] as String?;
      final String? variante = widget.data['variante'] as String?;

      _commitToCart(docId!, name!, price!, imageUrl!, cartProvider, isBulk,
          typeSpecific, variante,
          variantKey: widget.data['variantKey'] as String?,
          variantName: widget.data['variantName'] as String?);
      _resetAndStartTimer();
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
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.remove, size: 18),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: _quantity > 1 ? _decrementQuantity : null,
              ),
              Text('$_quantity', style: TextStyle(color: widget.textColor)),
              IconButton(
                icon: const Icon(Icons.add, size: 18),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
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
    final cartProvider = Provider.of<CartProvider>(context, listen: false);
    final pricePerKilo = (widget.data['price'] as num?)?.toDouble() ?? 0.0;
    final cartItem = cartProvider.getItem(widget.data['docId']);

    final double initialKilos = cartItem?.quantity ??
        (prefill && _quantity > 0 ? _quantity.toDouble() : 0.0);

    showDialog(
      context: context,
      builder: (context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: _BulkOrderDialog(
            imageUrl: widget.data['image_url'] ?? '/images/placeholder.png',
            nombre: widget.data['nombre'] ?? 'Unnamed',
            variante: widget.data['variante'] ?? 'No variant',
            priceLabel: _formatPrice(widget.data['price']),
            pricePerKilo: pricePerKilo,
            initialKilos: initialKilos,
            stock: stock,
            onConfirm: (kilos) {
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
                  variantKey: widget.data['variantKey'] as String?,
                  variantName: widget.data['variantName'] as String?,
                );
              }
              if (kDebugMode) {
                print('Bulk order set: $kilos kg');
              }
            },
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

class _BulkOrderDialog extends StatefulWidget {
  final String imageUrl;
  final String nombre;
  final String variante;
  final String priceLabel;
  final double pricePerKilo;
  final double initialKilos;
  final double stock;
  final ValueChanged<double> onConfirm;

  const _BulkOrderDialog({
    required this.imageUrl,
    required this.nombre,
    required this.variante,
    required this.priceLabel,
    required this.pricePerKilo,
    required this.initialKilos,
    required this.stock,
    required this.onConfirm,
  });

  @override
  State<_BulkOrderDialog> createState() => _BulkOrderDialogState();
}

class _BulkOrderDialogState extends State<_BulkOrderDialog> {
  final TextEditingController pesosController = TextEditingController();
  final TextEditingController kilosController = TextEditingController();
  final FocusNode pesosFocusNode = FocusNode();
  final FocusNode kilosFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    kilosController.text = widget.initialKilos.toStringAsFixed(3);
    pesosController.text =
    '\$${(widget.initialKilos * widget.pricePerKilo).toStringAsFixed(2)}';

    pesosFocusNode.addListener(_handlePesosFocus);
    kilosFocusNode.addListener(_handleKilosFocus);
  }

  void _handlePesosFocus() {
    if (!pesosFocusNode.hasFocus) {
      final pesos =
      double.tryParse(pesosController.text.replaceAll('\$', ''));
      if (pesos != null) {
        kilosController.text =
            (pesos / widget.pricePerKilo).toStringAsFixed(3);
        pesosController.text = '\$${pesos.toStringAsFixed(2)}';
      }
    }
  }

  void _handleKilosFocus() {
    if (!kilosFocusNode.hasFocus) {
      final kilos = double.tryParse(kilosController.text);
      if (kilos != null) {
        pesosController.text =
        '\$${(kilos * widget.pricePerKilo).toStringAsFixed(2)}';
      }
    }
  }

  @override
  void dispose() {
    pesosFocusNode.removeListener(_handlePesosFocus);
    kilosFocusNode.removeListener(_handleKilosFocus);
    pesosFocusNode.dispose();
    kilosFocusNode.dispose();
    pesosController.dispose();
    kilosController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
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
                    widget.imageUrl,
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
                      widget.nombre,
                      style:
                      const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(widget.variante),
                    Text(
                      widget.priceLabel,
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
            if (kilos > widget.stock) {
              return;
            }
            widget.onConfirm(kilos);
          },
          child: const Text('Agregar'),
        ),
      ],
    );
  }
}
