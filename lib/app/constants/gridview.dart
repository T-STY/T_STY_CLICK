import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("No recipes found"));
          }

          List<Widget> items = snapshot.data!.docs.map((doc) => _buildPageItem(context, doc)).toList();
          return PageView.builder(
            controller: _pageController,
            itemCount: items.length,
            itemBuilder: (context, index) {
              return GestureDetector(
                onTap: () => widget.onRecipeSelected(snapshot.data!.docs[index].id), // Pass recipe ID on tap
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
                child: Image.network(
                  data['imageURL'] ?? '/images/placeholder.png',
                  fit: BoxFit.cover,
                  width: double.infinity, // Make the image fill the container width
                  height: 150, // Set a fixed height for the image container
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
