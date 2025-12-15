import 'package:flutter/material.dart';

class CartProvider extends ChangeNotifier {
  Map<String, CartItem> _items = {};

  Map<String, CartItem> get items => {..._items};

  double get totalPrice {
    double total = 0.0;
    _items.forEach((key, cartItem) {
      total += cartItem.price * cartItem.quantity;
    });
    return total;
  }

  void addItem(String productId, String name, double price, String imageUrl,
      {double quantity = 1.0, required bool isBulk, required double stock}) {
    if (_items.containsKey(productId)) {
      _items.update(
        productId,
            (existingCartItem) {
          double newQuantity = existingCartItem.quantity + quantity;

          // Ensure the new quantity does not exceed available stock
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
          );
        },
      );
    } else {
      // Ensure the initial quantity does not exceed available stock
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
        ),
      );
    }
    notifyListeners();
  }

  void setItem(String productId, String name, double price, String imageUrl,
      double quantity, {required bool isBulk, required double stock}) {
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
        ),
        ifAbsent: () => CartItem(
          nombre: name,
          price: price,
          quantity: quantity,
          imageUrl: imageUrl,
          objectID: productId,
          isBulk: isBulk,
          stock: stock,
        ),
      );
    } else {
      _items.remove(productId);
    }
    notifyListeners();
  }

  void removeItem(String productId, {required bool isBulk}) {
    if (_items.containsKey(productId)) {
      if (_items[productId]!.quantity > 1) {
        _items.update(
          productId,
              (existingCartItem) {
            double newQuantity = existingCartItem.quantity - 1;
            if (isBulk) {
              // For bulk items, handle decrement accordingly
              newQuantity = existingCartItem.quantity - 0.5; // Example for half reduction
            }
            return CartItem(
              nombre: existingCartItem.nombre,
              price: existingCartItem.price,
              quantity: newQuantity > 0 ? newQuantity : 0,
              imageUrl: existingCartItem.imageUrl,
              objectID: existingCartItem.objectID,
              isBulk: existingCartItem.isBulk,
              stock: existingCartItem.stock,
            );
          },
        );
      } else {
        _items.remove(productId);
      }
    }
    notifyListeners();
  }

  void removeItemCompletely(String productId) {
    _items.remove(productId);
    notifyListeners();
  }

  CartItem? getItem(String productId) {
    return _items[productId];
  }

  // Clear the cart
  void clearCart() {
    _items.clear();
    notifyListeners();
  }

  // Method to show stock exceeded dialog
  void _showStockExceededDialog(String productName) {
    print('Stock exceeded for product: $productName');
    // You can implement a dialog or use a ScaffoldMessenger here to notify the user.
  }
}

class CartItem {
  final String nombre;
  final double price;
  final double quantity;
  final String imageUrl;
  final String objectID;
  final bool isBulk;
  final double stock; // Add the available stock field

  CartItem({
    required this.nombre,
    required this.price,
    required this.quantity,
    required this.imageUrl,
    required this.objectID,
    required this.isBulk,
    required this.stock, // Initialize available stock
  });

  Map<String, dynamic> toMap() {
    return {
      'nombre': nombre,
      'price': price,
      'quantity': quantity,
      'imageUrl': imageUrl,
      'objectID': objectID,
      'isBulk': isBulk,
      'stock': stock, // Include stock in the map
    };
  }
}
