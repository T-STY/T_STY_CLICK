import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../components/shimmer_placeholder.dart';

class RecipeGrid extends StatefulWidget {
  final String title;
  final Query<Map<String, dynamic>> query;
  final Function(String) onRecipeSelected; // Callback to trigger navigation

  const RecipeGrid({
    Key? key,
    required this.title,
    required this.query,
    required this.onRecipeSelected,
  }) : super(key: key);

  @override
  _RecipeGridState createState() => _RecipeGridState();
}

class _RecipeGridState extends State<RecipeGrid> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startAutoSlide();
  }

  void _startAutoSlide() {
    _timer = Timer.periodic(const Duration(seconds: 5), (Timer timer) {
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
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildSection(context, widget.title),
        _buildPageView(context),
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

  Widget _buildPageView(BuildContext context) {
    return SizedBox(
      height: 240,
      child: StreamBuilder<QuerySnapshot>(
        stream: widget.query.snapshots(),
        builder: (context, snapshot) {
          // NEW: Shimmer PageView Loading State
          if (snapshot.connectionState == ConnectionState.waiting) {
            return PageView.builder(
              controller: PageController(viewportFraction: 0.9), // Match the width of your items
              itemCount: 3, // Show 3 dummy items
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
                        color: Colors.black.withOpacity(0.1), // Lighter shadow for placeholder
                        blurRadius: 10,
                        offset: const Offset(4, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Image Shimmer (Matching the unique shape)
                      const ShimmerPlaceholder(
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
                      // Text Shimmers
                      Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          children: const [
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

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("No recipes found"));
          }

          List<Widget> items = snapshot.data!.docs
              .map((doc) => _buildPageItem(context, doc))
              .toList();

          return PageView.builder(
            controller: _pageController,
            itemCount: items.length,
            itemBuilder: (context, index) {
              return GestureDetector(
                onTap: () => widget.onRecipeSelected(snapshot.data!.docs[index].id),
                child: items[index],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildPageItem(BuildContext context, DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDarkMode ? Colors.white : Colors.black;
    final screenWidth = MediaQuery.of(context).size.width;

    return SizedBox(
      width: screenWidth * 0.9, // Set width to 90% of screen width
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
              color: Colors.black.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(4, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Container(
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(43),
                  topRight: Radius.circular(10),
                ),
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(43),
                  topRight: Radius.circular(24),
                  bottomLeft: Radius.circular(14),
                  bottomRight: Radius.circular(14),
                ),
                // Inside _buildPageItem:
                child: CachedNetworkImage(
                  imageUrl: data['imageURL'] ?? '',
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: 150,
                  // NEW: Shimmer Placeholder
                  placeholder: (context, url) => const ShimmerPlaceholder(height: 150),
                  errorWidget: (context, url, error) => Container(
                    height: 150,
                    color: Colors.grey[300],
                    child: const Icon(Icons.broken_image),
                  ),
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
                    style: TextStyle(fontWeight: FontWeight.bold, color: textColor),
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    'Costo approx. \$${data['precio']?.toString() ?? 'N/A'}',
                    style: const TextStyle(color: Colors.green),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
