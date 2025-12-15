import '../../main.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

import '../components/horizontal_line.dart';
import '../constants/app_colors.dart';
import '../constants/app_images.dart';

class AddProductPage extends StatefulWidget {
  const AddProductPage({super.key});

  @override
  AddProductPageState createState() => AddProductPageState();
}

class AddProductPageState extends State<AddProductPage> {
  List<String> apparelTypes = [];
  List<String> targetAudience = [];
  List<String> categoryKeys = [];
  String? selectedApparelType;
  String? selectedTargetAudience;

  @override
  void initState() {
    super.initState();
    fetchApparelTypes();
  }

  Future<void> fetchApparelTypes() async {
    try {
      DocumentSnapshot doc = await FirebaseFirestore.instance
          .collection('private')
          .doc('categories')
          .get();
      setState(() {
        apparelTypes = List.from(doc['apparel_type']);
        apparelTypes.sort();
      });
    } catch (e) {
      print("Error fetching apparel types: $e");
    }
  }

  Future<void> fetchTargetAudience(String apparelType) async {
    try {
      QuerySnapshot querySnapshot = await FirebaseFirestore.instance
          .collection('private')
          .doc('categories')
          .collection(apparelType)
          .get();
      setState(() {
        targetAudience = querySnapshot.docs.map((doc) => doc.id).toList();
      });
    } catch (e) {
      print("Error fetching target audience: $e");
    }
  }

  Future<void> fetchCategoryKeys(String apparelType, String audience) async {
    try {
      DocumentSnapshot doc = await FirebaseFirestore.instance
          .collection('private')
          .doc('categories')
          .collection(apparelType)
          .doc(audience)
          .get();
      if (doc.exists) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        setState(() {
          categoryKeys = data.keys
              .where((key) => data[key] is List) // Check if the field is an array
              .toList();
        });
      }
    } catch (e) {
      print("Error fetching categories: $e");
    }
  }

  String capitalize(String s) => s.isNotEmpty ? '${s[0].toUpperCase()}${s.substring(1)}' : s;

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final themeNotifier = Provider.of<ThemeNotifier>(context, listen: false);
    final selectedItemColor = isDarkMode ? Colors.grey[200] : AppColors.primary;
    final unselectedItemColor = isDarkMode ? AppColors.primary : Colors.grey[200];
    final backgroundColor = isDarkMode ? Colors.grey[800] : Colors.white;
    final textColor = isDarkMode ? Colors.white : Colors.black;

    return Scaffold(
      appBar: AppBar(
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        title: Padding(
          padding: const EdgeInsets.all(0),
          child: SizedBox(
            height: 45,
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
        padding: const EdgeInsets.fromLTRB(16.0, 10, 16, 16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  const HorizontalLine(width: 100),
                  TextButton(
                    onPressed: () {
                      themeNotifier.toggleTheme();
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        themeNotifier.isDark
                            ? Icon(Icons.nights_stay, color: Theme.of(context).iconTheme.color)
                            : Icon(Icons.wb_sunny, color: Theme.of(context).iconTheme.color)
                      ],
                    ),
                  ),
                  const HorizontalLine(width: 100),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                '¿Qué tipo de artículo quieres agregar?',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor),
              ),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.start,
                spacing: 10,
                runSpacing: 10,
                children: apparelTypes
                    .map((type) => GestureDetector(
                  onTap: () {
                    setState(() {
                      selectedApparelType = type;
                      selectedTargetAudience = null;
                      categoryKeys = [];
                      fetchTargetAudience(type);
                    });
                  },
                  child: Chip(
                    label: Text(capitalize(type)),
                    backgroundColor: selectedApparelType == type
                        ? selectedItemColor
                        : unselectedItemColor,
                    labelStyle: TextStyle(
                      color: selectedApparelType == type
                          ? (isDarkMode ? Colors.black : Colors.white)
                          : (isDarkMode ? Colors.white : Colors.black),
                    ),
                  ),
                ))
                    .toList(),
              ),
              if (selectedApparelType != null) ...[
                const SizedBox(height: 10),
                Text(
                  '¿Público objetivo?',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor),
                ),
                const SizedBox(height: 10),
                Wrap(
                  alignment: WrapAlignment.start,
                  spacing: 10,
                  runSpacing: 10,
                  children: targetAudience
                      .map((audience) => GestureDetector(
                    onTap: () {
                      setState(() {
                        selectedTargetAudience = audience;
                        fetchCategoryKeys(selectedApparelType!, audience);
                      });
                    },
                    child: Chip(
                      label: Text(capitalize(audience)),
                      backgroundColor: selectedTargetAudience == audience
                          ? selectedItemColor
                          : unselectedItemColor,
                      labelStyle: TextStyle(
                        color: selectedTargetAudience == audience
                            ? (isDarkMode ? Colors.black : Colors.white)
                            : (isDarkMode ? Colors.white : Colors.black),
                      ),
                    ),
                  ))
                      .toList(),
                ),
              ],
              if (selectedTargetAudience != null) ...[
                const SizedBox(height: 10),
                Text(
                  'Selecciona la categoria',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor),
                ),
                const SizedBox(height: 10),
                Wrap(
                  alignment: WrapAlignment.start,
                  spacing: 10,
                  runSpacing: 10,
                  children: categoryKeys
                      .map((category) => Chip(
                    label: Text(capitalize(category)),
                    backgroundColor: unselectedItemColor,
                    labelStyle: TextStyle(color: textColor),
                  ))
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

