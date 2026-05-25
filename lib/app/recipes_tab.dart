import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../components/bottom_fade.dart';
import '../components/shimmer_placeholder.dart';
import '../constants/app_images.dart';
import 'recipes.dart';

class RecetasScreen extends StatefulWidget {
  const RecetasScreen({super.key});

  @override
  RecetasScreenState createState() => RecetasScreenState();
}

class RecetasScreenState extends State<RecetasScreen> {
  String? _selectedRecipeId;
  bool _showDetail = false;

  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream =
      FirebaseFirestore.instance.collection('recipes').snapshots();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _open(String id) => setState(() {
        _selectedRecipeId = id;
        _showDetail = true;
      });

  void _close() => setState(() => _showDetail = false);

  bool handleBack() {
    if (_showDetail) {
      _close();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: SizedBox(
          height: 180,
          width: 300,
          child: AspectRatio(
            aspectRatio: 1 / 1,
            child: Image.asset(
              isDark ? AppImages.logowhite : AppImages.logo,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
      body: IndexedStack(
        index: _showDetail ? 1 : 0,
        children: [
          _buildList(context),
          _showDetail && _selectedRecipeId != null
              ? RecipeDetailPage(
                  recipeId: _selectedRecipeId!,
                  onBackPressed: _close,
                )
              : const SizedBox.shrink(),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v.toLowerCase().trim()),
            decoration: InputDecoration(
              hintText: 'Buscar recetas...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: isDark ? Colors.grey[850] : Colors.grey[200],
            ),
          ),
        ),
        Expanded(
          child: BottomFade(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _stream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return _buildShimmerList();
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Center(child: Text('No se encontraron recetas'));
              }
              final docs = snapshot.data!.docs.where((d) {
                if (_query.isEmpty) return true;
                final title =
                    (d.data()['title'] ?? '').toString().toLowerCase();
                return title.contains(_query);
              }).toList();
              if (docs.isEmpty) {
                return const Center(child: Text('No se encontraron recetas'));
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  return GestureDetector(
                    onTap: () => _open(docs[index].id),
                    child: _buildRecipeCard(context, docs[index]),
                  );
                },
              );
            },
          ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecipeCard(BuildContext context, DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final bool isGuest = FirebaseAuth.instance.currentUser == null;
    final String title = (data['title'] ?? 'Receta').toString();
    final String precio = data['precio']?.toString() ?? 'N/A';
    final int ingredientCount =
        (data['ingredients'] is List) ? (data['ingredients'] as List).length : 0;
    final String imageUrl = (data['imageURL'] ?? '').toString();

    return Container(
      height: 230,
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.cover,
              placeholder: (context, url) =>
                  const ShimmerPlaceholder(height: 230),
              errorWidget: (context, url, error) => Container(
                color: Colors.grey[300],
                child: const Center(
                  child: Icon(Icons.restaurant_menu,
                      size: 46, color: Colors.white70),
                ),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.transparent,
                    Color(0xE0000000),
                  ],
                  stops: [0.0, 0.42, 1.0],
                ),
              ),
            ),
            Positioned(top: 14, left: 14, child: _recipePill()),
            Positioned(
              left: 18,
              right: 18,
              bottom: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                      height: 1.12,
                      shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
                    ),
                  ),
                  const SizedBox(height: 8),
                  _recipeMetaLine(ingredientCount, precio, isGuest),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _recipePill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.restaurant_menu, size: 13, color: Colors.black87),
          SizedBox(width: 5),
          Text(
            'Receta',
            style: TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.w800,
              fontSize: 11.5,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _recipeMetaLine(int ingredientCount, String precio, bool isGuest) {
    return Row(
      children: [
        Icon(Icons.local_grocery_store_outlined,
            size: 14, color: Colors.white.withValues(alpha: 0.85)),
        const SizedBox(width: 5),
        Text(
          '$ingredientCount ${ingredientCount == 1 ? 'ingrediente' : 'ingredientes'}',
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 12.5,
              fontWeight: FontWeight.w500),
        ),
        const SizedBox(width: 10),
        Container(
          width: 3,
          height: 3,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.55),
          ),
        ),
        const SizedBox(width: 10),
        const Icon(Icons.sell_outlined, size: 14, color: Color(0xFFB9F6CA)),
        const SizedBox(width: 5),
        ImageFiltered(
          imageFilter: ImageFilter.blur(
            sigmaX: isGuest ? 5.0 : 0.0,
            sigmaY: isGuest ? 5.0 : 0.0,
          ),
          child: Text(
            '≈ \$$precio',
            style: const TextStyle(
              color: Color(0xFFB9F6CA),
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildShimmerList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      itemCount: 4,
      itemBuilder: (context, index) {
        return Container(
          height: 230,
          margin: const EdgeInsets.only(bottom: 18),
          child: const ShimmerPlaceholder(
            width: double.infinity,
            height: 230,
            shapeBorder: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(24)),
            ),
          ),
        );
      },
    );
  }
}
