import 'package:click/app/category/product_display.dart';
import 'package:flutter/material.dart';
import '../../constants/app_images.dart';

class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key});

  @override
  CategoriesPageState createState() => CategoriesPageState();
}

class CategoriesPageState extends State<CategoriesPage> {

  final Map<String, List<String>> mainCategories = {
    "Alimentos y Bebidas": [
      "Abarrotes",
      "Carnes y Salchichonería",
      "Cereales",
      "Especies",
      "Jugos y Refrescos",
      "Lácteos",
      "Mariscos",
      "Panadería y Tortillería",
      "Verdura/Fruta",
    ],
    "Bebés y Salud": [
      "Bebés",
      "Farmacia",
    ],
    "Botanería": [
      "Dulces",
      "Galletas",
      "Helados",
      "Pan Dulce",
      "Papas",
    ],
    "Cuidado del Hogar": [
      "Cuidado de la Ropa",
      "Limpieza del Hogar",
    ],
    "Cuidado Personal": [
      "Higiene y Belleza",
    ],
    "Otros": [
      "Ferretería",
      "Mascotas",
      "Papeleria",
    ]
  };

  int _selectedIndex = 0;
  String _selectedSubcategory = "";

  void _onCategorySelected(String subcategory) {
    setState(() {
      _selectedIndex = 1;
      _selectedSubcategory = subcategory;
    });
  }

  void _goBackToCategories() {
    setState(() {
      _selectedIndex = 0;
    });
  }

  List<Widget> _buildPages() {
    return [
      _buildCategoriesPage(),
      ProductDisplayPage(
        selectedCategory: _selectedSubcategory,
        onBack: _goBackToCategories,
      ),
    ];
  }

  Widget _buildCategoriesPage() {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
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
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: ListView.builder(
          itemCount: mainCategories.keys.length + 1,
          itemBuilder: (context, index) {
            if (index == mainCategories.keys.length) {
              return const SizedBox(
                height: 100,
              );
            }

            String mainCategory = mainCategories.keys.elementAt(index);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
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
                  margin: const EdgeInsets.only(left: 10, top: 10, bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Text(
                      mainCategory,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[800],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 30.0, right: 10),
                  child: _buildSubcategories(mainCategory),
                ),
              ],
            );
          },
        ),
      ),
      backgroundColor: Colors.white,
    );
  }

  Widget _buildSubcategories(String mainCategory) {
    final subcategories = mainCategories[mainCategory]!;

    return Column(
      children: subcategories.map((subcategory) {
        return GestureDetector(
          onTap: () {
            _onCategorySelected(subcategory);
          },
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withValues(alpha: 0.1),
                  spreadRadius: 3,
                  blurRadius: 5,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.arrow_right, color: Colors.grey[600]),
                const SizedBox(width: 10),
                Text(
                  subcategory,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _buildPages(),
      ),
    );
  }
}
