import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CartProvider extends ChangeNotifier {
  Map<String, CartItem> _items = {};

  CartProvider() {
    _loadCartFromStorage();
  }

  Map<String, CartItem> get items => {..._items};

  double get totalPrice {
    double total = 0.0;
    _items.forEach((key, cartItem) {
      total += cartItem.price * cartItem.quantity;
    });
    return total;
  }

  int get totalItemCount {
    return _items.length;
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
        notifyListeners();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error al cargar el carrito: $e');
      }
    }
  }

  void addItem(String productId, String name, double price, String imageUrl,
      {double quantity = 1.0, required bool isBulk, required double stock, String? typeSpecific, String? variante}) {
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
        ),
      );
    }
    notifyListeners();
    _saveCartToStorage();
  }

  void setItem(String productId, String name, double price, String imageUrl,
      double quantity, {required bool isBulk, required double stock, String? typeSpecific, String? variante}) {
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
        ),
      );
    } else {
      _items.remove(productId);
    }
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
            );
          },
        );
      } else {
        _items.remove(productId);
      }
    }
    notifyListeners();
    _saveCartToStorage();
  }

  void removeItemCompletely(String productId) {
    _items.remove(productId);
    notifyListeners();
    _saveCartToStorage();
  }

  CartItem? getItem(String productId) {
    return _items[productId];
  }

  void clearCart() {
    _items.clear();
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
    );
  }
}