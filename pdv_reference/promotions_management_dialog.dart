import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../providers/cart_provider.dart';
import 'product_management.dart';
import 'returns_management_dialog.dart'; // Needed for ProductsDialog1

class PromotionsManagementDialog extends StatefulWidget {
  const PromotionsManagementDialog({super.key});

  @override
  State<PromotionsManagementDialog> createState() => _PromotionsManagementDialogState();
}

class _PromotionsManagementDialogState extends State<PromotionsManagementDialog> {
  final _formKey = GlobalKey<FormState>();

  // Form State
  String? _editingPromoId;
  final TextEditingController _nameController = TextEditingController();
  String _selectedType = 'combo_exact';
  bool _isActive = true;
  List<Product> _choiceTargetProducts = [];
  // Type: Combo Exact
  List<Product> _exactProducts = [];
  final TextEditingController _comboPriceController = TextEditingController();

  // Type: Combo Brand
  Product? _triggerProduct;
  final TextEditingController _targetBrandController = TextEditingController();

  // Type: BxGy (3x2, etc)
  Product? _bxgyTargetProduct;
  final TextEditingController _buyQtyController = TextEditingController(text: '3');
  final TextEditingController _payQtyController = TextEditingController(text: '2');

  // Image upload
  File? _selectedImage;
  String? _existingImageURL;
  bool _isUploadingImage = false;
  final ImagePicker _imagePicker = ImagePicker();

  void _resetForm() {
    setState(() {
      _editingPromoId = null;
      _nameController.clear();
      _selectedType = 'combo_exact';
      _isActive = true;
      _exactProducts.clear();
      _comboPriceController.clear();
      _triggerProduct = null;
      _targetBrandController.clear();
      _bxgyTargetProduct = null;
      _buyQtyController.text = '3';
      _payQtyController.text = '2';
      _choiceTargetProducts.clear();
      _selectedImage = null;
      _existingImageURL = null;
    });
  }

  void _refreshCarts() {
    if (!mounted) return;
    final multiCart = Provider.of<MultiCartProvider>(context, listen: false);
    for (var cart in multiCart.carts) {
      cart.fetchActivePromotions();
    }
  }

  Future<void> _pickImage() async {
    final XFile? pickedFile = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (pickedFile != null) {
      setState(() {
        _selectedImage = File(pickedFile.path);
      });
    }
  }

  Future<String?> _uploadImage(File imageFile) async {
    try {
      final fileName = 'promo_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = FirebaseStorage.instance.ref().child('promotions/$fileName');
      final uploadTask = await ref.putFile(imageFile);
      return await uploadTask.ref.getDownloadURL();
    } catch (e) {
      debugPrint('Error uploading promo image: $e');
      return null;
    }
  }

  Future<void> _selectProduct(Function(Product) onSelected) async {
    final Product? product = await showDialog<Product>(
      context: context,
      builder: (context) => const ProductsDialog1(selectionMode: true),
    );
    if (product != null) {
      onSelected(product);
      setState(() {});
    }
  }

  Future<void> _editPromotion(DocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;

    setState(() {
      _editingPromoId = doc.id;
      _nameController.text = data['name'] ?? '';
      _selectedType = data['type'] ?? 'combo_exact';
      _isActive = data['active'] ?? true;
      _existingImageURL = data['imageURL'] as String?;
      _selectedImage = null;

      if (data['comboPrice'] != null) {
        _comboPriceController.text = data['comboPrice'].toString();
      } else {
        _comboPriceController.clear();
      }

      _targetBrandController.text = data['targetBrand'] ?? '';
      _buyQtyController.text = (data['buyQuantity'] ?? '3').toString();
      _payQtyController.text = (data['payQuantity'] ?? '2').toString();

      _exactProducts.clear();
      _triggerProduct = null;
      _bxgyTargetProduct = null;
      _choiceTargetProducts.clear();
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const Center(child: CircularProgressIndicator()),
    );

    try {
      if (_selectedType == 'combo_exact') {
        List<dynamic> ids = data['requiredProductIds'] ?? [];
        for (String id in ids) {
          final pDoc = await FirebaseFirestore.instance.collection('products').doc(id).get();
          if (pDoc.exists) {
            _exactProducts.add(Product.fromMap(pDoc.data() as Map<String, dynamic>, id: pDoc.id));
          }
        }
      }
      else if (_selectedType == 'combo_brand') {
        String triggerId = data['triggerProductId'] ?? '';
        if (triggerId.isNotEmpty) {
          final pDoc = await FirebaseFirestore.instance.collection('products').doc(triggerId).get();
          if (pDoc.exists) {
            _triggerProduct = Product.fromMap(pDoc.data() as Map<String, dynamic>, id: pDoc.id);
          }
        }
      }
      else if (_selectedType == 'bxgy') {
        String targetId = data['targetProductId'] ?? '';
        if (targetId.isNotEmpty) {
          final pDoc = await FirebaseFirestore.instance.collection('products').doc(targetId).get();
          if (pDoc.exists) {
            _bxgyTargetProduct = Product.fromMap(pDoc.data() as Map<String, dynamic>, id: pDoc.id);
          }
        }
      }
      else if (_selectedType == 'combo_choice') {
        String triggerId = data['triggerProductId'] ?? '';
        if (triggerId.isNotEmpty) {
          final pDoc = await FirebaseFirestore.instance.collection('products').doc(triggerId).get();
          if (pDoc.exists) {
            _triggerProduct = Product.fromMap(pDoc.data() as Map<String, dynamic>, id: pDoc.id);
          }
        }
        List<dynamic> targetIds = data['targetProductIds'] ?? [];
        for (String id in targetIds) {
          final pDoc = await FirebaseFirestore.instance.collection('products').doc(id).get();
          if (pDoc.exists) {
            _choiceTargetProducts.add(Product.fromMap(pDoc.data() as Map<String, dynamic>, id: pDoc.id));
          }
        }
      }
    } catch (e) {
      debugPrint("Error fetching products for edit: $e");
    }

    if (mounted) {
      Navigator.pop(context);
      setState(() {});
    }
  }

  Future<void> _savePromotion() async {
    if (!_formKey.currentState!.validate()) return;

    Map<String, dynamic> promoData = {
      'name': _nameController.text.trim(),
      'type': _selectedType,
      'active': _isActive,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // Handle image upload
    if (_selectedImage != null) {
      setState(() => _isUploadingImage = true);
      final url = await _uploadImage(_selectedImage!);
      setState(() => _isUploadingImage = false);
      if (url != null) {
        promoData['imageURL'] = url;
      } else {
        _showError('Error al subir la imagen. Intenta de nuevo.');
        return;
      }
    } else if (_existingImageURL != null) {
      promoData['imageURL'] = _existingImageURL;
    }

    if (_selectedType == 'combo_exact') {
      if (_exactProducts.isEmpty) {
        _showError('Selecciona al menos un producto para el combo.');
        return;
      }
      promoData['requiredProductIds'] = _exactProducts.map((p) => p.id).toList();
      promoData['comboPrice'] = double.parse(_comboPriceController.text);
    }
    else if (_selectedType == 'combo_brand') {
      if (_triggerProduct == null) {
        _showError('Selecciona el producto detonador.');
        return;
      }
      promoData['triggerProductId'] = _triggerProduct!.id;
      promoData['targetBrand'] = _targetBrandController.text.trim();
      promoData['comboPrice'] = double.parse(_comboPriceController.text);
    }
    else if (_selectedType == 'bxgy') {
      if (_bxgyTargetProduct == null) {
        _showError('Selecciona el producto para la promoción.');
        return;
      }
      promoData['targetProductId'] = _bxgyTargetProduct!.id;
      promoData['buyQuantity'] = int.parse(_buyQtyController.text);
      promoData['payQuantity'] = int.parse(_payQtyController.text);
    }
    else if (_selectedType == 'combo_choice') {
      if (_triggerProduct == null) {
        _showError('Selecciona el producto principal (Detonador).');
        return;
      }
      if (_choiceTargetProducts.isEmpty) {
        _showError('Selecciona al menos un producto para las opciones.');
        return;
      }
      promoData['triggerProductId'] = _triggerProduct!.id;
      promoData['targetProductIds'] = _choiceTargetProducts.map((p) => p.id).toList();
      promoData['comboPrice'] = double.parse(_comboPriceController.text);
    }

    try {
      if (_editingPromoId == null) {
        promoData['createdAt'] = FieldValue.serverTimestamp();
        await FirebaseFirestore.instance.collection('promotions').add(promoData);
      } else {
        await FirebaseFirestore.instance.collection('promotions').doc(_editingPromoId).update(promoData);
      }

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_editingPromoId == null ? 'Promoción creada' : 'Promoción actualizada'),
          backgroundColor: Colors.green
      ));

      _resetForm();
      _refreshCarts();

    } catch (e) {
      _showError('Error guardando la promoción: $e');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  void _deletePromotion(String id) async {
    // Also delete the image from storage if it exists
    final doc = await FirebaseFirestore.instance.collection('promotions').doc(id).get();
    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>;
      final imageURL = data['imageURL'] as String?;
      if (imageURL != null && imageURL.isNotEmpty) {
        try {
          await FirebaseStorage.instance.refFromURL(imageURL).delete();
        } catch (e) {
          debugPrint('Error deleting promo image: $e');
        }
      }
    }

    await FirebaseFirestore.instance.collection('promotions').doc(id).delete();
    if (_editingPromoId == id) {
      _resetForm();
    }
    _refreshCarts();
  }

  Widget _buildImagePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Imagen de la Promoción:', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _pickImage,
          child: Container(
            width: double.infinity,
            height: 160,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: _selectedImage != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: kIsWeb
                        ? Image.network(_selectedImage!.path, fit: BoxFit.cover, width: double.infinity)
                        : Image.file(_selectedImage!, fit: BoxFit.cover, width: double.infinity),
                  )
                : (_existingImageURL != null && _existingImageURL!.isNotEmpty)
                    ? Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              _existingImageURL!,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                            ),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _existingImageURL = null;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.close, color: Colors.white, size: 18),
                              ),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate_outlined, size: 40, color: Colors.grey[400]),
                          const SizedBox(height: 8),
                          Text('Toca para seleccionar imagen', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                          Text('(Opcional)', style: TextStyle(color: Colors.grey[400], fontSize: 11)),
                        ],
                      ),
          ),
        ),
        if (_selectedImage != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => setState(() => _selectedImage = null),
              icon: const Icon(Icons.close, size: 16, color: Colors.red),
              label: const Text('Quitar imagen', style: TextStyle(color: Colors.red, fontSize: 12)),
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    // Calculate dynamic values for analysis
    double totalExactPrice = 0.0;
    double totalExactCost = 0.0;
    for (var p in _exactProducts) {
      totalExactPrice += p.price;
      totalExactCost += p.cost;
    }
    double currentComboPrice = double.tryParse(_comboPriceController.text) ?? 0.0;
    double currentProfit = currentComboPrice - totalExactCost;

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: isDarkMode ? Colors.grey[900] : Colors.white,
        child: Container(
          width: MediaQuery.of(context).size.width * 0.85,
          height: MediaQuery.of(context).size.height * 0.85,
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Gestión de Promociones y Combos', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
              const Divider(),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // LEFT: List of Promotions
                    Expanded(
                      flex: 1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Promociones Activas', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          Expanded(
                            child: StreamBuilder<QuerySnapshot>(
                              stream: FirebaseFirestore.instance.collection('promotions').orderBy('active', descending: true).snapshots(),
                              builder: (context, snapshot) {
                                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                                final docs = snapshot.data!.docs;

                                if (docs.isEmpty) return const Center(child: Text('No hay promociones.'));

                                return ListView.builder(
                                  itemCount: docs.length,
                                  itemBuilder: (context, index) {
                                    final data = docs[index].data() as Map<String, dynamic>;
                                    final bool isEditingThis = _editingPromoId == docs[index].id;
                                    final hasImage = data['imageURL'] != null && (data['imageURL'] as String).isNotEmpty;

                                    return Card(
                                      color: isEditingThis
                                          ? Colors.blue.withOpacity(isDarkMode ? 0.3 : 0.1)
                                          : (data['active'] ? (isDarkMode ? Colors.grey[800] : Colors.white) : Colors.grey.withOpacity(0.2)),
                                      shape: isEditingThis
                                          ? RoundedRectangleBorder(side: const BorderSide(color: Colors.blue, width: 2), borderRadius: BorderRadius.circular(12))
                                          : null,
                                      child: ListTile(
                                        leading: hasImage
                                            ? ClipRRect(
                                                borderRadius: BorderRadius.circular(6),
                                                child: Image.network(
                                                  data['imageURL'],
                                                  width: 40,
                                                  height: 40,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (_, __, ___) => const Icon(Icons.local_offer, size: 24),
                                                ),
                                              )
                                            : null,
                                        title: Text(data['name'] ?? 'Sin nombre', style: const TextStyle(fontWeight: FontWeight.bold)),
                                        subtitle: Text('Tipo: ${data['type']}'),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Switch(
                                              value: data['active'] ?? false,
                                              onChanged: (val) async {
                                                await FirebaseFirestore.instance.collection('promotions').doc(docs[index].id).update({'active': val});
                                                _refreshCarts();
                                              },
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.delete, color: Colors.red),
                                              onPressed: () => _deletePromotion(docs[index].id),
                                            )
                                          ],
                                        ),
                                        onTap: () => _editPromotion(docs[index]),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const VerticalDivider(width: 32),

                    // RIGHT: Form
                    Expanded(
                      flex: 1,
                      child: Form(
                        key: _formKey,
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                      _editingPromoId == null ? 'Crear Nueva Promoción' : 'Editando Promoción',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: _editingPromoId == null ? null : Colors.blue,
                                      )
                                  ),
                                  if (_editingPromoId != null)
                                    TextButton.icon(
                                      onPressed: _resetForm,
                                      icon: const Icon(Icons.close, size: 16),
                                      label: const Text("Cancelar"),
                                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                                    )
                                ],
                              ),
                              const SizedBox(height: 16),

                              TextFormField(
                                controller: _nameController,
                                decoration: const InputDecoration(labelText: 'Nombre de la Promoción (Ej. Combo Refresco+Papas)', border: OutlineInputBorder()),
                                validator: (v) => v!.isEmpty ? 'Requerido' : null,
                              ),
                              const SizedBox(height: 16),

                              // Image picker section
                              _buildImagePicker(),

                              DropdownButtonFormField<String>(
                                value: _selectedType,
                                decoration: const InputDecoration(labelText: 'Tipo de Promoción', border: OutlineInputBorder()),
                                items: const [
                                  DropdownMenuItem(value: 'combo_exact', child: Text('Combo Exacto (Prod A + Prod B = Precio)')),
                                  DropdownMenuItem(value: 'combo_choice', child: Text('Combo Opción (Prod A + [Lista de Opciones] = Precio)')),
                                  DropdownMenuItem(value: 'combo_brand', child: Text('Combo Marca (Prod A + Marca B = Precio)')),
                                  DropdownMenuItem(value: 'bxgy', child: Text('Cantidad (Lleva X, Paga Y)')),
                                ],
                                onChanged: (v) => setState(() {
                                  _selectedType = v!;
                                  _exactProducts.clear();
                                  _triggerProduct = null;
                                  _bxgyTargetProduct = null;
                                  _choiceTargetProducts.clear();
                                  _comboPriceController.clear();
                                }),
                              ),
                              const SizedBox(height: 24),

                              // --- DYNAMIC FORM FIELDS BASED ON TYPE ---

                              if (_selectedType == 'combo_exact') ...[
                                const Text('Productos Requeridos:', style: TextStyle(fontWeight: FontWeight.bold)),
                                ..._exactProducts.map((p) => ListTile(
                                  title: Text(p.nombre),
                                  subtitle: Text('Precio: \$${p.price.toStringAsFixed(2)} | Costo: \$${p.cost.toStringAsFixed(2)}'),
                                  trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _exactProducts.remove(p))),
                                )),
                                OutlinedButton.icon(
                                  onPressed: () => _selectProduct((p) => _exactProducts.add(p)),
                                  icon: const Icon(Icons.add),
                                  label: const Text('Agregar Producto al Combo'),
                                ),
                                const SizedBox(height: 16),

                                // REAL TIME FINANCIAL ANALYSIS BOX
                                if (_exactProducts.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    margin: const EdgeInsets.only(bottom: 16),
                                    decoration: BoxDecoration(
                                        color: currentProfit > 0 ? Colors.blue.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: currentProfit > 0 ? Colors.blue.shade200 : Colors.red.shade300)
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('Análisis del Margen (Combos Exactos):', style: TextStyle(fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 6),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            const Text('Precio de venta normal (Suma):'),
                                            Text('\$${totalExactPrice.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            const Text('Costo de inventario (Suma):'),
                                            Text('\$${totalExactCost.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                        const Divider(),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            const Text('Ganancia estimada por combo:'),
                                            Text(
                                                '\$${currentProfit.toStringAsFixed(2)}',
                                                style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    color: currentProfit > 0 ? Colors.green : Colors.red
                                                )
                                            ),
                                          ],
                                        ),
                                        if (currentProfit <= 0 && _comboPriceController.text.isNotEmpty)
                                          const Padding(
                                            padding: EdgeInsets.only(top: 8.0),
                                            child: Text('¡Cuidado! El precio del combo es menor al costo de los productos.', style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold)),
                                          )
                                      ],
                                    ),
                                  ),

                                TextFormField(
                                  controller: _comboPriceController,
                                  decoration: const InputDecoration(labelText: 'Precio Final del Combo (\$)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.attach_money)),
                                  keyboardType: TextInputType.number,
                                  validator: (v) => v!.isEmpty ? 'Requerido' : null,
                                  onChanged: (value) => setState((){}),
                                ),
                              ],

                              if (_selectedType == 'combo_brand') ...[
                                const Text('Producto Detonador:', style: TextStyle(fontWeight: FontWeight.bold)),
                                ListTile(
                                  title: Text(_triggerProduct?.nombre ?? 'Ninguno seleccionado'),
                                  trailing: IconButton(icon: const Icon(Icons.search), onPressed: () => _selectProduct((p) => _triggerProduct = p)),
                                ),

                                // INFO BOX FOR BRAND COMBOS
                                if (_triggerProduct != null)
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    margin: const EdgeInsets.only(bottom: 16),
                                    decoration: BoxDecoration(
                                        color: Colors.orange.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.orange.shade200)
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('Datos del Producto Detonador:', style: TextStyle(fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 4),
                                        Text('Precio normal: \$${_triggerProduct!.price.toStringAsFixed(2)} | Costo: \$${_triggerProduct!.cost.toStringAsFixed(2)}'),
                                        const SizedBox(height: 4),
                                        const Text('Nota: Considera el costo de los productos de la marca al fijar el precio, ya que variará dependiendo del artículo extra que tome el cliente.', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                                      ],
                                    ),
                                  ),

                                TextFormField(
                                  controller: _targetBrandController,
                                  decoration: const InputDecoration(labelText: 'Marca Objetivo (Ej. Sabritas)', border: OutlineInputBorder()),
                                  validator: (v) => v!.isEmpty ? 'Requerido' : null,
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _comboPriceController,
                                  decoration: const InputDecoration(labelText: 'Precio Final del Combo (\$)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.attach_money)),
                                  keyboardType: TextInputType.number,
                                  validator: (v) => v!.isEmpty ? 'Requerido' : null,
                                ),
                              ],

                              if (_selectedType == 'bxgy') ...[
                                const Text('Producto Objetivo:', style: TextStyle(fontWeight: FontWeight.bold)),
                                ListTile(
                                  title: Text(_bxgyTargetProduct?.nombre ?? 'Ninguno seleccionado'),
                                  trailing: IconButton(icon: const Icon(Icons.search), onPressed: () => _selectProduct((p) => _bxgyTargetProduct = p)),
                                ),

                                // INFO BOX FOR 3x2, etc.
                                if (_bxgyTargetProduct != null)
                                  Builder(
                                      builder: (context) {
                                        int buyQ = int.tryParse(_buyQtyController.text) ?? 3;
                                        int payQ = int.tryParse(_payQtyController.text) ?? 2;
                                        double totalRev = payQ * _bxgyTargetProduct!.price;
                                        double totalCos = buyQ * _bxgyTargetProduct!.cost;
                                        double promoProfit = totalRev - totalCos;

                                        return Container(
                                          padding: const EdgeInsets.all(12),
                                          margin: const EdgeInsets.only(bottom: 16),
                                          decoration: BoxDecoration(
                                              color: promoProfit > 0 ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: promoProfit > 0 ? Colors.green.shade200 : Colors.red.shade300)
                                          ),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Text('Análisis de Rentabilidad:', style: TextStyle(fontWeight: FontWeight.bold)),
                                              const SizedBox(height: 4),
                                              Text('Ingreso (Cobras $payQ): \$${totalRev.toStringAsFixed(2)}'),
                                              Text('Costo (Entregas $buyQ): \$${totalCos.toStringAsFixed(2)}'),
                                              const Divider(),
                                              Text(
                                                  'Ganancia por promoción: \$${promoProfit.toStringAsFixed(2)}',
                                                  style: TextStyle(fontWeight: FontWeight.bold, color: promoProfit > 0 ? Colors.green : Colors.red)
                                              ),
                                              if (promoProfit <= 0)
                                                const Padding(
                                                  padding: EdgeInsets.only(top: 4.0),
                                                  child: Text('¡Pérdida! Estás cobrando menos de lo que cuestan los productos entregados.', style: TextStyle(color: Colors.red, fontSize: 12)),
                                                )
                                            ],
                                          ),
                                        );
                                      }
                                  ),

                                Row(
                                  children: [
                                    Expanded(
                                        child: TextFormField(
                                          controller: _buyQtyController,
                                          decoration: const InputDecoration(labelText: 'Lleva (Cantidad)', border: OutlineInputBorder()),
                                          keyboardType: TextInputType.number,
                                          onChanged: (val) => setState((){}),
                                        )
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                        child: TextFormField(
                                          controller: _payQtyController,
                                          decoration: const InputDecoration(labelText: 'Paga (Cantidad)', border: OutlineInputBorder()),
                                          keyboardType: TextInputType.number,
                                          onChanged: (val) => setState((){}),
                                        )
                                    ),
                                  ],
                                ),
                              ],
                              // -----------------------------------------
                              // COMBO CHOICE (TRIGGER + MULTIPLE OPTIONS)
                              // -----------------------------------------
                              if (_selectedType == 'combo_choice') ...[
                                const Text('Producto Principal (Fijo):', style: TextStyle(fontWeight: FontWeight.bold)),
                                ListTile(
                                  title: Text(_triggerProduct?.nombre ?? 'Ninguno seleccionado'),
                                  trailing: IconButton(icon: const Icon(Icons.search), onPressed: () => _selectProduct((p) => _triggerProduct = p)),
                                ),
                                const Divider(),
                                const Text('Opciones Permitidas (El cliente elige 1):', style: TextStyle(fontWeight: FontWeight.bold)),
                                ..._choiceTargetProducts.map((p) => ListTile(
                                  title: Text(p.nombre),
                                  subtitle: Text('Variante: ${p.variante} | Precio normal: \$${p.price.toStringAsFixed(2)} | Costo: \$${p.cost.toStringAsFixed(2)}'),
                                  trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _choiceTargetProducts.remove(p))),
                                )),
                                OutlinedButton.icon(
                                  onPressed: () => _selectProduct((p) => _choiceTargetProducts.add(p)),
                                  icon: const Icon(Icons.add),
                                  label: const Text('Agregar Opción Permitida'),
                                ),
                                const SizedBox(height: 16),

                                // Analysis Box for safety
                                if (_triggerProduct != null && _choiceTargetProducts.isNotEmpty)
                                  Builder(
                                      builder: (context) {
                                        double minCost = _triggerProduct!.cost + _choiceTargetProducts.map((e) => e.cost).reduce((a, b) => a < b ? a : b);
                                        double maxCost = _triggerProduct!.cost + _choiceTargetProducts.map((e) => e.cost).reduce((a, b) => a > b ? a : b);
                                        double cPrice = double.tryParse(_comboPriceController.text) ?? 0.0;

                                        bool isSafe = cPrice > maxCost;

                                        return Container(
                                          padding: const EdgeInsets.all(12),
                                          margin: const EdgeInsets.only(bottom: 16),
                                          decoration: BoxDecoration(
                                              color: isSafe ? Colors.blue.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: isSafe ? Colors.blue.shade200 : Colors.red.shade300)
                                          ),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Text('Análisis del Margen (Opción Múltiple):', style: TextStyle(fontWeight: FontWeight.bold)),
                                              const SizedBox(height: 6),
                                              Text('Costo más bajo posible (Fijo + Opción más barata): \$${minCost.toStringAsFixed(2)}'),
                                              Text('Costo más alto posible (Fijo + Opción más cara): \$${maxCost.toStringAsFixed(2)}'),
                                              const Divider(),
                                              if (!isSafe && _comboPriceController.text.isNotEmpty)
                                                const Padding(
                                                  padding: EdgeInsets.only(top: 4.0),
                                                  child: Text('¡Cuidado! El precio del combo genera pérdidas con algunas de las opciones.', style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold)),
                                                )
                                            ],
                                          ),
                                        );
                                      }
                                  ),

                                TextFormField(
                                  controller: _comboPriceController,
                                  decoration: const InputDecoration(labelText: 'Precio Final del Combo (\$)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.attach_money)),
                                  keyboardType: TextInputType.number,
                                  validator: (v) => v!.isEmpty ? 'Requerido' : null,
                                  onChanged: (value) => setState((){}),
                                ),
                              ],

                              const SizedBox(height: 32),
                              SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: ElevatedButton(
                                  onPressed: _isUploadingImage ? null : _savePromotion,
                                  style: ElevatedButton.styleFrom(backgroundColor: _editingPromoId == null ? Colors.black : Colors.blue, foregroundColor: Colors.white),
                                  child: _isUploadingImage
                                      ? const Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                                            SizedBox(width: 12),
                                            Text('Subiendo imagen...', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                          ],
                                        )
                                      : Text(_editingPromoId == null ? 'Crear Promoción' : 'Actualizar Promoción', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                ),
                              )
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
