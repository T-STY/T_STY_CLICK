import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class NewProductPage extends StatefulWidget {
  const NewProductPage({super.key});

  @override
  NewProductPageState createState() => NewProductPageState();
}

class NewProductPageState extends State<NewProductPage> {
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();
  File? _image;

  // Controllers for text fields
  final TextEditingController _nombreController = TextEditingController();
  final TextEditingController _varianteController = TextEditingController();
  final TextEditingController _stockController = TextEditingController();
  final TextEditingController _minStockController = TextEditingController();
  final TextEditingController _maxStockController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _costController = TextEditingController();
  final TextEditingController _barcodeController = TextEditingController();
  final TextEditingController _typeSpecificController = TextEditingController();
  final TextEditingController _newBrandController = TextEditingController();
  final TextEditingController _newDistributorController = TextEditingController();
  final TextEditingController _newCategoryController = TextEditingController();

  String? _selectedType;
  List<String> _types = [];
  String? _selectedBrand;
  List<String> _brands = [];
  String? _selectedCategory;
  List<String> _categories = [];
  String? _selectedDistributor;
  List<String> _distributors = [];

  bool _currentDay = false;
  bool _recommended = false;
  bool _isBulk = false;

  @override
  void initState() {
    super.initState();
    fetchSpecifics();
    checkAuthentication();
  }

  Future<void> checkAuthentication() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      // Navigate to login screen or show a message
    }
  }

  Future<void> fetchSpecifics() async {
    try {
      DocumentSnapshot doc = await FirebaseFirestore.instance
          .collection('store')
          .doc('specifics')
          .get();
      setState(() {
        _types = List.from(doc['type']);
        _categories = List.from(doc['category']);
        _brands = List.from(doc['brand']);
        _distributors = List.from(doc['distributor']);

        _types.sort();
        _categories.sort();
        _brands.sort();
        _distributors.sort();

        _brands.insert(0, 'Agregar Marca');
        _distributors.insert(0, 'Agregar Distribuidor');
        _categories.insert(0, 'Agregar Categoria');
      });
    } catch (e) {
    }
  }

  Future<void> _pickImage() async {
    final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    setState(() {
      if (pickedFile != null) {
        _image = File(pickedFile.path);
      } else {
      }
    });
  }

  Future<File?> _compressImage(File imageFile) async {
    final tempDir = await getTemporaryDirectory();
    final targetPath = path.join(tempDir.path, '${path.basenameWithoutExtension(imageFile.path)}_compressed.jpg');

    final result = await FlutterImageCompress.compressAndGetFile(
      imageFile.absolute.path,
      targetPath,
      quality: 85,
      minWidth: 800,
      minHeight: 800,
    );
    return result != null ? File(result.path) : null;
  }

  Future<void> _uploadProduct() async {
    if (_formKey.currentState!.validate()) {
      String? imageUrl;
      try {
        if (_image != null) {
          final compressedImage = await _compressImage(_image!);
          if (compressedImage != null) {
            final storageRef = FirebaseStorage.instance
                .ref()
                .child('product_images')
                .child('${DateTime.now().millisecondsSinceEpoch}.jpg');
            final uploadTask = storageRef.putFile(compressedImage);
            final snapshot = await uploadTask.whenComplete(() => null);
            imageUrl = await snapshot.ref.getDownloadURL();
          }
        }

        await FirebaseFirestore.instance.collection('products').add({
          'nombre': _nombreController.text,
          'variante': _varianteController.text,
          'stock': int.parse(_stockController.text),
          'min_stock': int.parse(_minStockController.text),
          'max_stock': int.parse(_maxStockController.text),
          'price': double.parse(_priceController.text),
          'cost': double.parse(_costController.text),
          'type': _selectedType,
          'type_specific': _typeSpecificController.text,
          'brand': _selectedBrand != 'Agregar Marca' ? _selectedBrand : _newBrandController.text,
          'distribuitor_name': _selectedDistributor != 'Agregar Distribuidor' ? _selectedDistributor : _newDistributorController.text,
          'category': _selectedCategory != 'Agregar Categoria' ? _selectedCategory : _newCategoryController.text,
          'barcode': _barcodeController.text,
          'image_url': imageUrl,
          'sales_in_past7': 0,  // Default value
          'current_day': _currentDay,
          'recommended': _recommended,
          'bulk': _isBulk, // Add bulk status
        }).then((value) {
          if (_selectedBrand == 'Agregar Marca') {
            addNewBrand();
          }
          if (_selectedDistributor == 'Agregar Distribuidor') {
            addNewDistributor();
          }
          if (_selectedCategory == 'Agregar Categoria') {
            addNewCategory();
          }
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Product Added')));
          _formKey.currentState!.reset();
          setState(() {
            _image = null;
            _selectedType = null;
            _selectedBrand = null;
            _selectedDistributor = null;
            _selectedCategory = null;
            _brands.remove('Agregar Marca');
            _distributors.remove('Agregar Distribuidor');
            _categories.remove('Agregar Categoria');
          });
        }).catchError((error) => print("Failed to add product: $error"));
      } catch (e) {
      }
    }
  }

  Future<void> addNewBrand() async {
    try {
      await FirebaseFirestore.instance.collection('store').doc('specifics').update({
        'brand': FieldValue.arrayUnion([_newBrandController.text])
      });
    } catch (e) {
    }
  }

  Future<void> addNewDistributor() async {
    try {
      await FirebaseFirestore.instance.collection('store').doc('specifics').update({
        'distributor': FieldValue.arrayUnion([_newDistributorController.text])
      });
    } catch (e) {
    }
  }

  Future<void> addNewCategory() async {
    try {
      await FirebaseFirestore.instance.collection('store').doc('specifics').update({
        'category': FieldValue.arrayUnion([_newCategoryController.text])
      });
    } catch (e) {
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Product Creation'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Center(
                  child: GestureDetector(
                    onTap: _pickImage,
                    child: _image != null
                        ? Image.file(_image!, height: 150, width: 150)
                        : Container(
                      height: 150,
                      width: 150,
                      color: Colors.grey[300],
                      child: Icon(Icons.add_a_photo, color: Colors.grey[700]),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                _buildTextField('Nombre', _nombreController),
                _buildTextField('Variante', _varianteController),
                _buildTextField('Stock', _stockController, isNumber: true),
                _buildTextField('Min Stock', _minStockController, isNumber: true),
                _buildTextField('Max Stock', _maxStockController, isNumber: true),
                _buildTextField('Price', _priceController, isNumber: true),
                _buildTextField('Cost', _costController, isNumber: true),
                _buildDropdownField('Type', _types, _selectedType, (newValue) {
                  setState(() {
                    _selectedType = newValue;
                  });
                }),
                SwitchListTile(
                  title: const Text('Bulk'),
                  value: _isBulk,
                  onChanged: (bool value) {
                    setState(() {
                      _isBulk = value;
                    });
                  },
                ),
                _buildTextField('Type Specific', _typeSpecificController),
                _buildDropdownField('Category', _categories, _selectedCategory, (newValue) {
                  setState(() {
                    _selectedCategory = newValue;
                  });
                }),
                if (_selectedCategory == 'Agregar Categoria')
                  _buildTextField('New Category', _newCategoryController),
                _buildDropdownField('Brand', _brands, _selectedBrand, (newValue) {
                  setState(() {
                    _selectedBrand = newValue;
                  });
                }),
                if (_selectedBrand == 'Agregar Marca')
                  _buildTextField('New Brand', _newBrandController),
                _buildDropdownField('Distributor Name', _distributors, _selectedDistributor, (newValue) {
                  setState(() {
                    _selectedDistributor = newValue;
                  });
                }),
                if (_selectedDistributor == 'Agregar Distribuidor')
                  _buildTextField('New Distributor', _newDistributorController),
                _buildTextField('Barcode', _barcodeController),
                const SizedBox(height: 20),
                CheckboxListTile(
                  title: const Text('Current Day'),
                  value: _currentDay,
                  onChanged: (bool? value) {
                    setState(() {
                      _currentDay = value!;
                    });
                  },
                ),
                CheckboxListTile(
                  title: const Text('Recommended'),
                  value: _recommended,
                  onChanged: (bool? value) {
                    setState(() {
                      _recommended = value!;
                    });
                  },
                ),
                Center(
                  child: ElevatedButton(
                    onPressed: _uploadProduct,
                    child: const Text('Confirm'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, {bool isNumber = false}) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label),
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please enter $label';
        }
        return null;
      },
    );
  }

  Widget _buildDropdownField(
      String label, List<String> items, String? selectedItem, ValueChanged<String?> onChanged) {
    return DropdownButtonFormField<String>(
      decoration: InputDecoration(labelText: label),
      value: selectedItem,
      items: items.map((item) {
        return DropdownMenuItem<String>(
          value: item,
          child: Text(item),
        );
      }).toList(),
      onChanged: onChanged,
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please select $label';
        }
        return null;
      },
    );
  }
}
