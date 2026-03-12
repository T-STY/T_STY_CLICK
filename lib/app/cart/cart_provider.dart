import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CartProvider extends ChangeNotifier {
  Map<String, CartItem> _items = {};

  List<Map<String, dynamic>> _activePromotions = [];
  double _promoDiscount = 0.0;
  List<String> _appliedPromosList = [];

  List<String> get appliedPromosList => _appliedPromosList;
  double get promoDiscount => _promoDiscount;

  CartProvider() {
    _loadCartFromStorage();
    fetchActivePromotions();
  }

  Map<String, CartItem> get items => {..._items};

  double get totalPrice {
    double total = 0.0;
    _items.forEach((key, cartItem) {
      total += cartItem.price * cartItem.quantity;
    });
    return total;
  }

  double get discountAmount => _promoDiscount;

  double get totalPriceAfterDiscount {
    final result = totalPrice - discountAmount;
    return result < 0 ? 0 : result;
  }

  int get totalItemCount {
    return _items.length;
  }

  Future<void> fetchActivePromotions() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('promotions')
          .where('active', isEqualTo: true)
          .get();

      _activePromotions = snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
      _evaluatePromotions();
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print("Error fetching promos: $e");
    }
  }

  void _evaluatePromotions() {
    double totalPromoDiscount = 0.0;
    List<String> applied = [];

    // Virtual copy of quantities to safely consume them
    Map<String, double> availableQuantities = {};
    _items.forEach((key, item) {
      availableQuantities[key] = item.quantity;
    });

    for (var promo in _activePromotions) {

      // TYPE 1: EXACT COMBO
      if (promo['type'] == 'combo_exact') {
        List<dynamic> rawIds = promo['requiredProductIds'] ?? [];
        List<String> requiredIds = rawIds.map((e) => e.toString()).toList();
        double comboPrice = (promo['comboPrice'] as num?)?.toDouble() ?? 0.0;

        Map<String, int> requiredCounts = {};
        for (String id in requiredIds) {
          requiredCounts[id] = (requiredCounts[id] ?? 0) + 1;
        }

        bool canApply = true;
        int timesToApply = 999999;

        requiredCounts.forEach((reqId, reqQty) {
          int available = (availableQuantities[reqId] ?? 0).toInt();
          if (available < reqQty) {
            canApply = false;
          } else {
            timesToApply = min(timesToApply, available ~/ reqQty);
          }
        });

        if (canApply && timesToApply > 0) {
          double normalPrice = 0.0;
          requiredCounts.forEach((reqId, reqQty) {
            normalPrice += (_items[reqId]!.price * reqQty);
            availableQuantities[reqId] = availableQuantities[reqId]! - (reqQty * timesToApply);
          });

          double discount = (normalPrice - comboPrice) * timesToApply;
          if (discount > 0) {
            totalPromoDiscount += discount;
            applied.add("${promo['name']} (x$timesToApply)");
          }
        }
      }

      // TYPE 2: BRAND COMBO
      else if (promo['type'] == 'combo_brand') {
        String triggerId = promo['triggerProductId']?.toString() ?? '';
        String targetBrand = (promo['targetBrand']?.toString() ?? '').toLowerCase().trim();
        double comboPrice = (promo['comboPrice'] as num?)?.toDouble() ?? 0.0;

        int triggersAvailable = (availableQuantities[triggerId] ?? 0).toInt();

        while (triggersAvailable > 0) {
          String? pairedId;
          for (String id in availableQuantities.keys) {
            if (availableQuantities[id]! > 0 && id != triggerId) {
              String itemBrand = _items[id]!.brand.toLowerCase().trim();
              if (itemBrand == targetBrand || itemBrand.contains(targetBrand)) {
                pairedId = id;
                break;
              }
            }
          }

          if (pairedId != null) {
            double normalPrice = _items[triggerId]!.price + _items[pairedId]!.price;
            double discount = normalPrice - comboPrice;

            if (discount > 0) {
              totalPromoDiscount += discount;
              applied.add(promo['name']);
            }
            availableQuantities[triggerId] = availableQuantities[triggerId]! - 1;
            availableQuantities[pairedId] = availableQuantities[pairedId]! - 1;
            triggersAvailable--;
          } else {
            break;
          }
        }
      }

      // TYPE 3: BxGy
      else if (promo['type'] == 'bxgy') {
        String targetId = promo['targetProductId']?.toString() ?? '';
        int buyQty = promo['buyQuantity'] ?? 3;
        int payQty = promo['payQuantity'] ?? 2;

        if (availableQuantities.containsKey(targetId)) {
          int qty = availableQuantities[targetId]!.toInt();
          int freeItemsCount = qty ~/ buyQty;

          if (freeItemsCount > 0) {
            int itemsFreePerCombo = buyQty - payQty;
            double discount = (freeItemsCount * itemsFreePerCombo) * _items[targetId]!.price;

            if (discount > 0) {
              totalPromoDiscount += discount;
              availableQuantities[targetId] = availableQuantities[targetId]! - (freeItemsCount * buyQty);
              applied.add("${promo['name']} (x$freeItemsCount)");
            }
          }
        }
      }

      // TYPE 4: COMBO CHOICE
      else if (promo['type'] == 'combo_choice') {
        String triggerId = promo['triggerProductId']?.toString() ?? '';
        List<dynamic> rawTargetIds = promo['targetProductIds'] ?? [];
        List<String> targetIds = rawTargetIds.map((e) => e.toString()).toList();
        double comboPrice = (promo['comboPrice'] as num?)?.toDouble() ?? 0.0;

        int triggersAvailable = (availableQuantities[triggerId] ?? 0).toInt();

        while (triggersAvailable > 0) {
          String? pairedId;
          for (String id in targetIds) {
            if ((availableQuantities[id] ?? 0) > 0) {
              pairedId = id;
              break;
            }
          }

          if (pairedId != null) {
            double normalPrice = _items[triggerId]!.price + _items[pairedId]!.price;
            double discount = normalPrice - comboPrice;

            if (discount > 0) {
              totalPromoDiscount += discount;
              applied.add(promo['name']);
            }
            availableQuantities[triggerId] = availableQuantities[triggerId]! - 1;
            availableQuantities[pairedId] = availableQuantities[pairedId]! - 1;
            triggersAvailable--;
          } else {
            break;
          }
        }
      }
    }

    _promoDiscount = totalPromoDiscount;
    _appliedPromosList = applied;
  }

  Future<void> _saveCartToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String encodedData = jsonEncode(
        _items.map((key, item) => MapEntry(key, item.toMap())),
      );
      await prefs.setString('tsty_cart_data', encodedData);
    } catch (e) {
      if (kDebugMode) {
        print('Error al guardar el carrito: $e');
      }
    }
  }

  Future<void> _loadCartFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? savedData = prefs.getString('tsty_cart_data');

      if (savedData != null) {
        Map<String, dynamic> decodedData = jsonDecode(savedData);
        _items = decodedData.map((key, value) =>
            MapEntry(key, CartItem.fromJson(value as Map<String, dynamic>))
        );
        _evaluatePromotions();
        notifyListeners();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error al cargar el carrito: $e');
      }
    }
  }

  void addItem(String productId, String name, double price, String imageUrl,
      {double quantity = 1.0, required bool isBulk, required double stock, String? typeSpecific, String? variante, String brand = ''}) {
    if (_items.containsKey(productId)) {
      _items.update(
        productId,
            (existingCartItem) {
          double newQuantity = existingCartItem.quantity + quantity;

          if (newQuantity > stock) {
            newQuantity = stock;
            _showStockExceededDialog(existingCartItem.nombre);
          }

          return CartItem(
            nombre: existingCartItem.nombre,
            price: existingCartItem.price,
            quantity: newQuantity,
            imageUrl: existingCartItem.imageUrl,
            objectID: existingCartItem.objectID,
            isBulk: existingCartItem.isBulk,
            stock: existingCartItem.stock,
            typeSpecific: existingCartItem.typeSpecific,
            variante: existingCartItem.variante,
            brand: existingCartItem.brand,
          );
        },
      );
    } else {
      double initialQuantity = quantity;
      if (initialQuantity > stock) {
        initialQuantity = stock;
        _showStockExceededDialog(name);
      }

      _items.putIfAbsent(
        productId,
            () => CartItem(
          nombre: name,
          price: price,
          quantity: initialQuantity,
          imageUrl: imageUrl,
          objectID: productId,
          isBulk: isBulk,
          stock: stock,
          typeSpecific: typeSpecific ?? '',
          variante: variante ?? '',
          brand: brand,
        ),
      );
    }
    _evaluatePromotions();
    notifyListeners();
    _saveCartToStorage();
  }

  void setItem(String productId, String name, double price, String imageUrl,
      double quantity, {required bool isBulk, required double stock, String? typeSpecific, String? variante, String brand = ''}) {
    if (quantity > stock) {
      quantity = stock;
      _showStockExceededDialog(name);
    }

    if (quantity > 0) {
      _items.update(
        productId,
            (existingCartItem) => CartItem(
          nombre: name,
          price: price,
          quantity: quantity,
          imageUrl: imageUrl,
          objectID: productId,
          isBulk: isBulk,
          stock: stock,
          typeSpecific: typeSpecific ?? existingCartItem.typeSpecific,
          variante: variante ?? existingCartItem.variante,
          brand: brand.isNotEmpty ? brand : existingCartItem.brand,
        ),
        ifAbsent: () => CartItem(
          nombre: name,
          price: price,
          quantity: quantity,
          imageUrl: imageUrl,
          objectID: productId,
          isBulk: isBulk,
          stock: stock,
          typeSpecific: typeSpecific ?? '',
          variante: variante ?? '',
          brand: brand,
        ),
      );
    } else {
      _items.remove(productId);
    }
    _evaluatePromotions();
    notifyListeners();
    _saveCartToStorage();
  }

  void removeItem(String productId, {required bool isBulk}) {
    if (_items.containsKey(productId)) {
      if (_items[productId]!.quantity > 1) {
        _items.update(
          productId,
              (existingCartItem) {
            double newQuantity = existingCartItem.quantity - 1;
            if (isBulk) {
              newQuantity = existingCartItem.quantity - 0.5;
            }
            return CartItem(
              nombre: existingCartItem.nombre,
              price: existingCartItem.price,
              quantity: newQuantity > 0 ? newQuantity : 0,
              imageUrl: existingCartItem.imageUrl,
              objectID: existingCartItem.objectID,
              isBulk: existingCartItem.isBulk,
              stock: existingCartItem.stock,
              typeSpecific: existingCartItem.typeSpecific,
              variante: existingCartItem.variante,
              brand: existingCartItem.brand,
            );
          },
        );
      } else {
        _items.remove(productId);
      }
    }
    _evaluatePromotions();
    notifyListeners();
    _saveCartToStorage();
  }

  void removeItemCompletely(String productId) {
    _items.remove(productId);
    _evaluatePromotions();
    notifyListeners();
    _saveCartToStorage();
  }

  CartItem? getItem(String productId) {
    return _items[productId];
  }

  void clearCart() {
    _items.clear();
    _promoDiscount = 0.0;
    _appliedPromosList.clear();
    notifyListeners();
    _saveCartToStorage();
  }

  void _showStockExceededDialog(String productName) {
    if (kDebugMode) {
      print('Stock excedido para el producto: $productName');
    }
  }
}

class CartItem {
  final String nombre;
  final double price;
  final double quantity;
  final String imageUrl;
  final String objectID;
  final bool isBulk;
  final double stock;
  final String typeSpecific;
  final String variante;
  final String brand;

  CartItem({
    required this.nombre,
    required this.price,
    required this.quantity,
    required this.imageUrl,
    required this.objectID,
    required this.isBulk,
    required this.stock,
    this.typeSpecific = '',
    this.variante = '',
    this.brand = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'nombre': nombre,
      'price': price,
      'quantity': quantity,
      'imageUrl': imageUrl,
      'objectID': objectID,
      'isBulk': isBulk,
      'stock': stock,
      'type_specific': typeSpecific,
      'variante': variante,
      'brand': brand,
    };
  }

  factory CartItem.fromJson(Map<String, dynamic> json) {
    return CartItem(
      nombre: json['nombre'] as String,
      price: (json['price'] as num).toDouble(),
      quantity: (json['quantity'] as num).toDouble(),
      imageUrl: json['imageUrl'] as String,
      objectID: json['objectID'] as String,
      isBulk: json['isBulk'] as bool,
      stock: (json['stock'] as num).toDouble(),
      typeSpecific: json['type_specific'] as String? ?? '',
      variante: json['variante'] as String? ?? '',
      brand: json['brand'] as String? ?? '',
    );
  }
}
