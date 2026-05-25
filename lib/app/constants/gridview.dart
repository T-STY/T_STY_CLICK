import 'dart:async';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../components/shimmer_placeholder.dart';

const int _kCarouselLoopBase = 100000;

class RecipeCarousel extends StatefulWidget {
  final String title;
  final Query<Map<String, dynamic>> query;
  final void Function(String recipeId) onRecipeSelected;
  final VoidCallback? onSeeAll;

  const RecipeCarousel({
    super.key,
    required this.title,
    required this.query,
    required this.onRecipeSelected,
    this.onSeeAll,
  });

  @override
  State<RecipeCarousel> createState() => _RecipeCarouselState();
}

class _RecipeCarouselState extends State<RecipeCarousel> {
  final PageController _pageController =
      PageController(initialPage: _kCarouselLoopBase);
  Timer? _timer;
  int _count = 0;
  late final Stream<QuerySnapshot> _stream = widget.query.snapshots();

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _ensureAutoSlide(int count) {
    _count = count;
    if (count <= 1) return;
    _timer ??= Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_pageController.hasClients || _count <= 1) return;
      _pageController.nextPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _sectionHeader(context, widget.title, onSeeAll: widget.onSeeAll),
        SizedBox(
          height: 240,
          child: StreamBuilder<QuerySnapshot>(
            stream: _stream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return _buildShimmerCarousel();
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Center(child: Text("No se encontraron recetas"));
              }
              final docs = snapshot.data!.docs;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _ensureAutoSlide(docs.length);
              });
              return PageView.builder(
                controller: _pageController,
                itemBuilder: (context, index) {
                  final doc = docs[(index - _kCarouselLoopBase) % docs.length];
                  return GestureDetector(
                    onTap: () => widget.onRecipeSelected(doc.id),
                    child: _buildRecipeItem(context, doc),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class PromoCarousel extends StatefulWidget {
  final String title;
  final void Function(String promoId) onPromotionSelected;

  const PromoCarousel({
    super.key,
    this.title = 'Promociones 🏷️',
    required this.onPromotionSelected,
  });

  @override
  State<PromoCarousel> createState() => _PromoCarouselState();
}

class _PromoCarouselState extends State<PromoCarousel> {
  final PageController _pageController =
      PageController(initialPage: _kCarouselLoopBase);
  Timer? _timer;
  int _count = 0;
  late final Stream<QuerySnapshot> _stream = FirebaseFirestore.instance
      .collection('promotions')
      .where('active', isEqualTo: true)
      .snapshots();

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _ensureAutoSlide(int count) {
    _count = count;
    if (count <= 1) return;
    _timer ??= Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_pageController.hasClients || _count <= 1) return;
      _pageController.nextPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _sectionHeader(context, widget.title),
        SizedBox(
          height: 240,
          child: StreamBuilder<QuerySnapshot>(
            stream: _stream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return _buildShimmerCarousel();
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Center(child: Text("No hay promociones activas"));
              }
              final docs = snapshot.data!.docs
                  .where((d) =>
                      ((d.data() as Map<String, dynamic>?)?['type']
                          as String?) !=
                      'combo')
                  .toList();
              if (docs.isEmpty) {
                return const Center(child: Text("No hay promociones activas"));
              }
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _ensureAutoSlide(docs.length);
              });
              return PageView.builder(
                controller: _pageController,
                itemBuilder: (context, index) {
                  final doc = docs[(index - _kCarouselLoopBase) % docs.length];
                  return GestureDetector(
                    onTap: () => widget.onPromotionSelected(doc.id),
                    child: _buildPromoItem(context, doc),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

Widget _sectionHeader(BuildContext context, String title,
    {VoidCallback? onSeeAll}) {
  final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
  final Color fg = isDarkMode ? Colors.white : Colors.black;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 8.0),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: fg,
            ),
          ),
        ),
        if (onSeeAll != null)
          TextButton(
            onPressed: onSeeAll,
            style: TextButton.styleFrom(
              foregroundColor: fg,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Ver más',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                Icon(Icons.chevron_right, size: 18),
              ],
            ),
          ),
      ],
    ),
  );
}

Widget _buildShimmerCarousel() {
  return PageView.builder(
    controller: PageController(viewportFraction: 0.9),
    itemCount: 3,
    itemBuilder: (context, index) {
      return Container(
        margin: const EdgeInsets.fromLTRB(10, 5, 10, 15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(43),
            topRight: Radius.circular(24),
            bottomLeft: Radius.circular(14),
            bottomRight: Radius.circular(14),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(4, 4),
            ),
          ],
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ShimmerPlaceholder(
              height: 150,
              shapeBorder: RoundedRectangleBorder(
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(43),
                  topRight: Radius.circular(24),
                  bottomLeft: Radius.circular(14),
                  bottomRight: Radius.circular(14),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(12.0),
              child: Column(
                children: [
                  ShimmerPlaceholder(width: 150, height: 16),
                  SizedBox(height: 8),
                  ShimmerPlaceholder(width: 100, height: 14),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

Widget _buildRecipeItem(BuildContext context, DocumentSnapshot doc) {
  final data = doc.data() as Map<String, dynamic>;
  final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
  final textColor = isDarkMode ? Colors.white : Colors.black;
  final screenWidth = MediaQuery.of(context).size.width;
  final bool isGuest = FirebaseAuth.instance.currentUser == null;

  return SizedBox(
    width: screenWidth * 0.9,
    child: Container(
      margin: const EdgeInsets.fromLTRB(10, 5, 10, 15),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.grey[800] : Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(43),
          topRight: Radius.circular(24),
          bottomLeft: Radius.circular(14),
          bottomRight: Radius.circular(14),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(4, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(43),
                topRight: Radius.circular(24),
                bottomLeft: Radius.circular(14),
                bottomRight: Radius.circular(14),
              ),
              child: CachedNetworkImage(
                imageUrl: data['imageURL'] ?? data['imageUrl'] ?? '',
                fit: BoxFit.cover,
                width: double.infinity,
                placeholder: (context, url) =>
                    const ShimmerPlaceholder(height: 150),
                errorWidget: (context, url, error) => Container(
                  color: Colors.grey[300],
                  child: const Icon(Icons.broken_image),
                ),
              ),
            ),
          ),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  data['title'] ?? 'Unnamed',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: textColor),
                  textAlign: TextAlign.center,
                ),
                ImageFiltered(
                  imageFilter: ImageFilter.blur(
                    sigmaX: isGuest ? 6.0 : 0.0,
                    sigmaY: isGuest ? 6.0 : 0.0,
                  ),
                  child: Text(
                    'Costo approx. \$${data['precio']?.toString() ?? 'N/A'}',
                    style: const TextStyle(color: Colors.green),
                    textAlign: TextAlign.center,
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

Widget _buildPromoItem(BuildContext context, DocumentSnapshot doc) {
  final data = doc.data() as Map<String, dynamic>;
  final screenWidth = MediaQuery.of(context).size.width;
  final type = data['type'] as String? ?? '';
  final bool isGuest = FirebaseAuth.instance.currentUser == null;
  final String image = (data['imageURL'] ?? data['imageUrl'] ?? '').toString();
  final String name = (data['name'] ?? 'Promoción').toString();

  String subtitle;
  if (type == 'bxgy') {
    final buy = data['buyQuantity'] ?? 3;
    final pay = data['payQuantity'] ?? 2;
    subtitle = 'Lleva $buy, Paga $pay';
  } else {
    final price = (data['comboPrice'] as num?)?.toDouble() ?? 0;
    subtitle = 'Precio: \$${price.toStringAsFixed(2)}';
  }

  return SizedBox(
    width: screenWidth * 0.9,
    child: Container(
      margin: const EdgeInsets.fromLTRB(10, 5, 10, 15),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(2, 4),
          ),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (image.isNotEmpty)
            CachedNetworkImage(
              imageUrl: image,
              fit: BoxFit.cover,
              width: double.infinity,
              placeholder: (context, url) =>
                  const ShimmerPlaceholder(height: 150),
              errorWidget: (context, url, error) => Container(
                color: Colors.grey[300],
                child: const Icon(Icons.broken_image),
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.deepOrange.shade400,
                    Colors.orange.shade300,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const Center(
                child:
                    Icon(Icons.local_offer, size: 46, color: Colors.white70),
              ),
            ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black54,
                  Colors.black87,
                ],
                stops: [0.4, 0.78, 1.0],
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 4),
                ImageFiltered(
                  imageFilter: ImageFilter.blur(
                    sigmaX: isGuest ? 6.0 : 0.0,
                    sigmaY: isGuest ? 6.0 : 0.0,
                  ),
                  child: Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
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
