import 'dart:ui';

import 'package:flutter/material.dart';

Future<Map<String, dynamic>?> showFilterSheet(
  BuildContext context,
  Map<String, dynamic> initialFilters,
) {
  return showGeneralDialog<Map<String, dynamic>>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Filtro',
    barrierColor: Colors.black.withValues(alpha: 0.12),
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (context, animation, secondaryAnimation) {
      return FilterDialog(initialFilters: initialFilters);
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved =
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return Stack(
        children: [
          FadeTransition(
            opacity: animation,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          ),
        ],
      );
    },
  );
}

class FilterDialog extends StatefulWidget {
  final Map<String, dynamic> initialFilters;

  const FilterDialog({super.key, required this.initialFilters});

  @override
  State<FilterDialog> createState() => _FilterDialogState();
}

class _FilterDialogState extends State<FilterDialog> {
  String? selectedMainCategory;
  String? selectedSubCategory;
  double minPrice = 5;
  double maxPrice = 400;

  final Map<String, List<String>> categories = {
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

  @override
  void initState() {
    super.initState();
    _initializeFilters();
  }

  void _initializeFilters() {
    selectedMainCategory = widget.initialFilters['mainCategory'];
    selectedSubCategory = widget.initialFilters['subCategory'];

    RangeValues priceRange =
        widget.initialFilters['priceRange'] ?? const RangeValues(5, 400);
    minPrice = priceRange.start;
    maxPrice = priceRange.end;
  }

  void _resetFilters() {
    setState(() {
      selectedMainCategory = null;
      selectedSubCategory = null;
      minPrice = 5;
      maxPrice = 400;
    });
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryTextColor = Colors.black87;

    return Material(
      type: MaterialType.transparency,
      child: Container(
      height: MediaQuery.of(context).size.height * 0.72,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade400,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Opciones de Filtro',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: primaryTextColor,
            ),
          ),
          const SizedBox(height: 12),
          Divider(color: Colors.grey.shade300, thickness: 1, height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Categorías',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: primaryTextColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...categories.keys.expand((category) {
                    final bool selected = selectedMainCategory == category;
                    return [
                      InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () {
                          setState(() {
                            selectedMainCategory = selected ? null : category;
                            selectedSubCategory = null;
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 12, horizontal: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  category,
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: Colors.black87,
                                    fontWeight: selected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                              ),
                              Icon(
                                selected
                                    ? Icons.expand_less
                                    : Icons.expand_more,
                                color: Colors.grey.shade600,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (selected)
                        Padding(
                          padding: const EdgeInsets.only(left: 8, bottom: 4),
                          child: Column(
                            children:
                                categories[category]!.map((subCategory) {
                              final bool subSelected =
                                  selectedSubCategory == subCategory;
                              return InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () {
                                  setState(() {
                                    selectedSubCategory =
                                        subSelected ? null : subCategory;
                                  });
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 9, horizontal: 8),
                                  child: Row(
                                    children: [
                                      Icon(
                                        subSelected
                                            ? Icons.radio_button_checked
                                            : Icons.radio_button_off,
                                        size: 19,
                                        color: subSelected
                                            ? Colors.black
                                            : Colors.grey.shade500,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          subCategory,
                                          style: TextStyle(
                                            color: subSelected
                                                ? Colors.black
                                                : Colors.black87,
                                            fontWeight: subSelected
                                                ? FontWeight.w600
                                                : FontWeight.normal,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      Divider(height: 1, color: Colors.grey.shade200),
                    ];
                  }),
                  const SizedBox(height: 8),
                  const Text(
                    'Precio (MXN)',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: primaryTextColor,
                    ),
                  ),
                  RangeSlider(
                    values: RangeValues(minPrice, maxPrice),
                    min: 5,
                    max: 400,
                    divisions: 395,
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
                ],
              ),
            ),
          ),
          Divider(color: Colors.grey.shade200, thickness: 1, height: 1),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(
                    onPressed: () {
                      _resetFilters();
                      Navigator.of(context).pop({'clear': true});
                    },
                    child: const Text(
                      'Limpiar Filtros',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop({
                        'mainCategory': selectedMainCategory,
                        'subCategory': selectedSubCategory,
                        'priceRange': RangeValues(minPrice, maxPrice),
                      });
                    },
                    child: const Text(
                      'Aplicar Filtro',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }
}
