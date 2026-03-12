import 'dart:async';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../components/shimmer_placeholder.dart';

class RecipeGrid extends StatefulWidget {
  final String title;
  final Query<Map<String, dynamic>> query;
  final Function(String) onRecipeSelected;
  final Function(String)? onPromotionSelected;

  const RecipeGrid({
    super.key,
    required this.title,
    required this.query,
    required this.onRecipeSelected,
    this.onPromotionSelected,
  });

  @override
  State<RecipeGrid> createState() => RecipeGridState();
}

class RecipeGridState extends State<RecipeGrid> {
  final PageController _pageController = PageController();
  final PageController _promoPageController = PageController();
  int _currentPage = 0;
  int _currentPromoPage = 0;
  Timer? _timer;
  Timer? _promoTimer;
  bool _showingPromos = false;

  @override
  void initState() {
    super.initState();
    _startAutoSlide();
  }

  void _startAutoSlide() {
    _timer = Timer.periodic(const Duration(seconds: 5), (Timer timer) {
      if (_pageController.hasClients) {
        if (_currentPage < _pageController.page!.round() + 1) {
          _currentPage++;
        } else {
          _currentPage = 0;
        }

        _pageController.animateToPage(
          _currentPage,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void _startPromoAutoSlide() {
    _promoTimer?.cancel();
    _promoTimer = Timer.periodic(const Duration(seconds: 5), (Timer timer) {
      if (_promoPageController.hasClients) {
        if (_currentPromoPage < _promoPageController.page!.round() + 1) {
          _currentPromoPage++;
        } else {
          _currentPromoPage = 0;
        }

        _promoPageController.animateToPage(
          _currentPromoPage,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _promoTimer?.cancel();
    _pageController.dispose();
    _promoPageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildSectionWithToggle(context),
        _showingPromos ? _buildPromoPageView(context) : _buildPageView(context),
      ],
    );
  }

  Widget _buildSectionWithToggle(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDarkMode ? Colors.white : Colors.black;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 8.0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _showingPromos ? 'Promociones 🏷️' : widget.title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
          ),
          if (widget.onPromotionSelected != null)
            GestureDetector(
              onTap: () {
                setState(() {
                  _showingPromos = !_showingPromos;
                  if (_showingPromos) {
                    _startPromoAutoSlide();
                  } else {
                    _promoTimer?.cancel();
                  }
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _showingPromos
                      ? Colors.deepOrange.withValues(alpha: 0.15)
                      : Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _showingPromos ? Colors.deepOrange : Colors.blue,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _showingPromos ? Icons.restaurant_menu : Icons.local_offer,
                      size: 16,
                      color: _showingPromos ? Colors.deepOrange : Colors.blue,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _showingPromos ? 'Recetas' : 'Promos',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _showingPromos ? Colors.deepOrange : Colors.blue,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPageView(BuildContext context) {
    return SizedBox(
      height: 240,
      child: StreamBuilder<QuerySnapshot>(
        stream: widget.query.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildShimmerCarousel();
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("No se encontraron recetas"));
          }

          final docs = snapshot.data!.docs;

          return PageView.builder(
            controller: _pageController,
            itemCount: docs.length,
            itemBuilder: (context, index) {
              return GestureDetector(
                onTap: () => widget.onRecipeSelected(docs[index].id),
                child: _buildPageItem(context, docs[index]),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildPromoPageView(BuildContext context) {
    return SizedBox(
      height: 240,
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('promotions')
            .where('active', isEqualTo: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildShimmerCarousel();
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("No hay promociones activas"));
          }

          final docs = snapshot.data!.docs;

          return PageView.builder(
            controller: _promoPageController,
            itemCount: docs.length,
            itemBuilder: (context, index) {
              return GestureDetector(
                onTap: () => widget.onPromotionSelected?.call(docs[index].id),
                child: _buildPromoItem(context, docs[index]),
              );
            },
          );
        },
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

  Widget _buildPageItem(BuildContext context, DocumentSnapshot doc) {
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
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(43),
                topRight: Radius.circular(24),
                bottomLeft: Radius.circular(14),
                bottomRight: Radius.circular(14),
              ),
              child: CachedNetworkImage(
                imageUrl: data['imageURL'] ?? '',
                fit: BoxFit.cover,
                width: double.infinity,
                height: 150,
                placeholder: (context, url) =>
                const ShimmerPlaceholder(height: 150),
                errorWidget: (context, url, error) => Container(
                  height: 150,
                  color: Colors.grey[300],
                  child: const Icon(Icons.broken_image),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
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
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDarkMode ? Colors.white : Colors.black;
    final screenWidth = MediaQuery.of(context).size.width;
    final type = data['type'] as String? ?? '';
    final bool isGuest = FirebaseAuth.instance.currentUser == null;

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
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(43),
                topRight: Radius.circular(24),
                bottomLeft: Radius.circular(14),
                bottomRight: Radius.circular(14),
              ),
              child: (data['imageURL'] != null && (data['imageURL'] as String).isNotEmpty)
                  ? CachedNetworkImage(
                      imageUrl: data['imageURL'],
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: 150,
                      placeholder: (context, url) =>
                      const ShimmerPlaceholder(height: 150),
                      errorWidget: (context, url, error) => Container(
                        height: 150,
                        color: Colors.grey[300],
                        child: const Icon(Icons.broken_image),
                      ),
                    )
                  : Container(
                      width: double.infinity,
                      height: 150,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.deepOrange.shade400, Colors.orange.shade300],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.local_offer, size: 40, color: Colors.white),
                          const SizedBox(height: 8),
                          Text(
                            _promoTypeLabel(type),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    data['name'] ?? 'Promoción',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: textColor),
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
                      subtitle,
                      style: const TextStyle(
                        color: Colors.deepOrange,
                        fontWeight: FontWeight.w600,
                      ),
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
