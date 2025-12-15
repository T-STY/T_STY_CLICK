import 'dart:ui';

import 'package:flutter/material.dart';

class FilterDialog extends StatefulWidget {
  final Map<String, dynamic> initialFilters;

  const FilterDialog({Key? key, required this.initialFilters}) : super(key: key);

  @override
  _FilterDialogState createState() => _FilterDialogState();
}

class _FilterDialogState extends State<FilterDialog> {
  String? selectedMainCategory;
  String? selectedSubCategory;
  double minPrice = 5;
  double maxPrice = 120;

  // Categories and subcategories
  final Map<String, List<String>> categories = {
    "Alimentos y Bebidas": [
      "Abarrotes",
      "Carnes y Salchichonería",
      "Congelados",
      "Especies",
      "Jugos y Refrescos",
      "Lácteos",
      "Panadería y Tortillería",
      "Papeleria",
      "Verdura/Fruta",
    ],
    "Cuidado del Hogar": [
      "Cuidado de la Ropa",
      "Limpieza del Hogar",
    ],
    "Cuidado Personal": [
      "Higiene y Belleza",
    ],
    "Bebés y Salud": [
      "Bebés",
      "Farmacia",
    ],
    "Botanería": [
      "Dulces",
      "Galletas",
      "Papas",
    ],
    "Otros": [
      "Ferretería",]
  };

  @override
  void initState() {
    super.initState();
    _initializeFilters();
  }

  void _initializeFilters() {
    // Initialize selectedMainCategory and selectedSubCategory based on initialFilters
    selectedMainCategory = widget.initialFilters['mainCategory'];
    selectedSubCategory = widget.initialFilters['subCategory'];

    // Initialize price range
    RangeValues priceRange =
        widget.initialFilters['priceRange'] ?? RangeValues(5, 200);
    minPrice = priceRange.start;
    maxPrice = priceRange.end;
  }

  void _resetFilters() {
    setState(() {
      selectedMainCategory = null;
      selectedSubCategory = null;
      minPrice = 5;
      maxPrice = 120;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Define neutral colors
    final Color backgroundColor = Colors.white;
    final Color primaryTextColor = Colors.black87;
    final Color secondaryTextColor = Colors.black54;
    final Color chipSelectedColor = Colors.grey.shade300;
    final Color chipUnselectedColor = Colors.grey.shade200;

    return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
    child: Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      elevation: 10,
      backgroundColor: backgroundColor,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Text(
              'Opciones de Filtro',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: primaryTextColor,
              ),
            ),
            SizedBox(height: 10),
            Divider(
              color: Colors.grey.shade400,
              thickness: 1,
            ),
            SizedBox(height: 20),

            // Categorías
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Categorías',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: primaryTextColor,
                ),
              ),
            ),
            SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: categories.keys.map((category) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: ChoiceChip(
                      label: Text(
                        category,
                        style: TextStyle(
                          color: selectedMainCategory == category
                              ? Colors.black
                              : Colors.black87,
                        ),
                      ),
                      selected: selectedMainCategory == category,
                      selectedColor: chipSelectedColor,
                      backgroundColor: chipUnselectedColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      onSelected: (selected) {
                        setState(() {
                          selectedMainCategory = selected ? category : null;
                          selectedSubCategory = null; // Reset subcategory
                        });
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
            SizedBox(height: 20),

            // Subcategorías
            if (selectedMainCategory != null) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Subcategorías',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: primaryTextColor,
                  ),
                ),
              ),
              SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children:
                  categories[selectedMainCategory]!.map((subCategory) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: ChoiceChip(
                        label: Text(
                          subCategory,
                          style: TextStyle(
                            color: selectedSubCategory == subCategory
                                ? Colors.black
                                : Colors.black87,
                          ),
                        ),
                        selected: selectedSubCategory == subCategory,
                        selectedColor: chipSelectedColor,
                        backgroundColor: chipUnselectedColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        onSelected: (selected) {
                          setState(() {
                            selectedSubCategory =
                            selected ? subCategory : null;
                          });
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
              SizedBox(height: 20),
            ],

            // Precio
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Precio (MXN)',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: primaryTextColor,
                ),
              ),
            ),
            RangeSlider(
              values: RangeValues(minPrice, maxPrice),
              min: 5,
              max: 200,
              divisions: 195,
              labels: RangeLabels(
                  '\$${minPrice.toInt()}', '\$${maxPrice.toInt()}'),
              activeColor: Colors.grey.shade600,
              inactiveColor: Colors.grey.shade300,
              onChanged: (RangeValues values) {
                setState(() {
                  minPrice = values.start.roundToDouble();
                  maxPrice = values.end.roundToDouble();
                });
              },
            ),
            SizedBox(height: 20),

            // Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Clear Filters
                TextButton(
                  onPressed: () {
                    _resetFilters();
                    Navigator.of(context).pop({'clear': true});
                  },
                  child: Text(
                    'Limpiar Filtros',
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                // Apply Filters
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop({
                      'mainCategory': selectedMainCategory,
                      'subCategory': selectedSubCategory,
                      'priceRange': RangeValues(minPrice, maxPrice),
                    });
                  },
                  child: Text(
                    'Aplicar Filtro',
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    )
    );
  }
}
