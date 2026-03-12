import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CartItem {
  final String id;
  final String name;
  final String brand; // <-- ADDED BRAND
  final double price;
  final double cost;
  final String imageUrl;
  final double quantity;
  final bool isBulk;
  final double stock;
  final String? typeSpecific;
  final String? variante;

  CartItem({
    required this.id,
    required this.name,
    required this.brand, // <-- ADDED BRAND
    required this.price,
    required this.cost,
    required this.imageUrl,
    required this.quantity,
    required this.isBulk,
    required this.stock,
    this.typeSpecific,
    this.variante,
  });

  double get total => price * quantity;
  double get totalCost => cost * quantity;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'brand': brand,
    'price': price,
    'cost': cost,
    'imageUrl': imageUrl,
    'quantity': quantity,
    'isBulk': isBulk,
    'stock': stock,
    'typeSpecific': typeSpecific,
    'variante': variante,
  };

  factory CartItem.fromJson(Map<String, dynamic> json) => CartItem(
    id: json['id'] as String,
    name: json['name'] as String,
    brand: json['brand'] as String? ?? '',
    price: (json['price'] as num).toDouble(),
    cost: (json['cost'] as num).toDouble(),
    imageUrl: json['imageUrl'] as String,
    quantity: (json['quantity'] as num).toDouble(),
    isBulk: json['isBulk'] as bool? ?? false,
    stock: (json['stock'] as num).toDouble(),
    typeSpecific: json['typeSpecific'] as String?,
    variante: json['variante'] as String?,
  );

  CartItem copyWith({
    String? id,
    String? name,
    String? brand, // <-- ADDED BRAND
    double? price,
    double? cost,
    String? imageUrl,
    double? quantity,
    bool? isBulk,
    double? stock,
    String? typeSpecific,
    String? variante,
  }) {
    return CartItem(
      id: id ?? this.id,
      name: name ?? this.name,
      brand: brand ?? this.brand, // <-- ADDED BRAND
      price: price ?? this.price,
      cost: cost ?? this.cost,
      imageUrl: imageUrl ?? this.imageUrl,
      quantity: quantity ?? this.quantity,
      isBulk: isBulk ?? this.isBulk,
      stock: stock ?? this.stock,
      typeSpecific: typeSpecific ?? this.typeSpecific,
      variante: variante ?? this.variante,
    );
  }
}

class MultiCartProvider with ChangeNotifier {
  final List<CartProvider> _carts = [
    CartProvider(),
    CartProvider(),
    CartProvider(),
  ];

  int _currentCartIndex = 0;
  Timer? _saveDebouncer;

  List<CartProvider> get carts => _carts;

  int get currentCartIndex => _currentCartIndex;

  MultiCartProvider() {
    // Wire up each cart's onModified to trigger disk persistence
    for (final cart in _carts) {
      cart.onModified = saveCartsToDisk;
    }
    _restoreCartsFromDisk();
  }

  /// Save all carts to SharedPreferences for power-cut recovery.
  /// Debounced to avoid excessive writes on rapid cart changes.
  void saveCartsToDisk() {
    _saveDebouncer?.cancel();
    _saveDebouncer = Timer(const Duration(seconds: 1), () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final cartsData = _carts.map((cart) {
          return cart.items.values.map((item) => item.toJson()).toList();
        }).toList();
        await prefs.setString('saved_carts', jsonEncode(cartsData));
        await prefs.setInt('saved_cart_index', _currentCartIndex);
      } catch (e) {
        if (kDebugMode) debugPrint('Error saving carts to disk: $e');
      }
    });
  }

  /// Restore carts from SharedPreferences after app restart (e.g., power cut).
  Future<void> _restoreCartsFromDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedData = prefs.getString('saved_carts');
      if (savedData == null) return;

      final List<dynamic> cartsData = jsonDecode(savedData);
      for (int i = 0; i < cartsData.length && i < _carts.length; i++) {
        final List<dynamic> cartItems = cartsData[i];
        for (final itemJson in cartItems) {
          final item = CartItem.fromJson(itemJson as Map<String, dynamic>);
          _carts[i].setItem(
            item.id,
            item.name,
            item.price,
            item.cost,
            item.imageUrl,
            item.quantity,
            brand: item.brand,
            isBulk: item.isBulk,
            stock: item.stock,
            typeSpecific: item.typeSpecific,
            variante: item.variante,
          );
        }
      }

      _currentCartIndex = prefs.getInt('saved_cart_index') ?? 0;
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('Error restoring carts from disk: $e');
    }
  }

  /// Clear saved cart data from disk (call after successful checkout).
  Future<void> clearSavedCarts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('saved_carts');
      await prefs.remove('saved_cart_index');
    } catch (e) {
      if (kDebugMode) debugPrint('Error clearing saved carts: $e');
    }
  }

  void setCurrentCartIndex(int index) {
    if (index >= 0 && index < _carts.length) {
      _currentCartIndex = index;
      notifyListeners();
      saveCartsToDisk();
    }
  }

  /// Call this after any cart modification to persist state.
  void onCartChanged() {
    notifyListeners();
    saveCartsToDisk();
  }

  CartProvider getCart(int index) {
    if (index < 0 || index >= _carts.length) {
      throw ArgumentError('Invalid cart index');
    }
    return _carts[index];
  }

  // Clear all carts
  void clearAllCarts() {
    for (var cart in _carts) {
      cart.clearCart();
    }
    notifyListeners();
  }

  // Transfer items between carts
  void transferItem({
    required int fromCartIndex,
    required int toCartIndex,
    required String itemId,
  }) {
    final fromCart = _carts[fromCartIndex];
    final toCart = _carts[toCartIndex];

    final item = fromCart.getItem(itemId);
    if (item == null) return;

    // Remove from source cart
    fromCart.removeItemCompletely(itemId);

    // Add to destination cart
    toCart.setItem(
      item.id,
      item.name,
      item.price,
      item.cost, // Include cost
      item.imageUrl,
      item.quantity,
      brand: item.brand,
      isBulk: item.isBulk,
      stock: item.stock,
      typeSpecific: item.typeSpecific,
      variante: item.variante, // Include variante
    );

    notifyListeners();
  }

// Merge all carts
  void mergeAllCarts({int? targetCartIndex}) {
    // If no target cart is specified, use the first cart
    final target = targetCartIndex != null
        ? _carts[targetCartIndex]
        : _carts[0];

    // Iterate through other carts and transfer their items
    for (var cart in _carts) {
      if (cart == target) continue;

      cart.items.forEach((id, item) {
        target.setItem(
          item.id,
          item.name,
          item.price,
          item.cost, // Include cost
          item.imageUrl,
          item.quantity,
          brand: item.brand,
          isBulk: item.isBulk,
          stock: item.stock,
          typeSpecific: item.typeSpecific,
          variante: item.variante, // Include variante
        );
      });

      // Clear the source cart after transferring
      cart.clearCart();
    }

    notifyListeners();
  }

  // Calculate total items across all carts
  int get totalItemsAcrossCarts {
    return _carts.fold(0, (sum, cart) => sum + cart.itemCount);
  }

  // Calculate total amount across all carts
  double get totalAmountAcrossCarts {
    return _carts.fold(0.0, (sum, cart) => sum + cart.totalAmount);
  }
}

class CartProvider with ChangeNotifier {
  final Map<String, CartItem> _items = {};
  final StreamController<void> _cartClearedController = StreamController<void>.broadcast();
  Stream<void> get onCartCleared => _cartClearedController.stream;

  /// Optional callback to notify parent (MultiCartProvider) to persist cart state.
  VoidCallback? onModified;

  List<Map<String, dynamic>> _activePromotions = [];
  double _promoDiscount = 0.0;
  List<String> _appliedPromosList = [];

  List<String> get appliedPromosList => _appliedPromosList;
  double get promoDiscount => _promoDiscount;

  String? _rewardsCardNumber;
  String? _rewardsCardHolderName;
  double _rewardsPointsAvailable = 0.0; // Changed from int
  double _rewardsPointsToUse = 0.0;     // Changed from int
  bool _rewardsCvvVerified = false;
  DocumentReference? _rewardsDocRef;
  String? _rewardsCvvCode;
  double _rewardsRawBalance = 0.0; // For display purposes

  Map<String, CartItem> get items => {..._items};
  double get totalCost {
    return _items.values.fold(0.0, (sum, item) => sum + item.totalCost);
  }
  int get itemCount => _items.length;

  // Rewards getters - CHANGED TO DOUBLE
  String? get rewardsCardNumber => _rewardsCardNumber;
  String? get rewardsCardHolderName => _rewardsCardHolderName;
  double get rewardsPointsAvailable => _rewardsPointsAvailable; // Changed return type
  double get rewardsPointsToUse => _rewardsPointsToUse;         // Changed return type
  bool get rewardsCvvVerified => _rewardsCvvVerified;
  DocumentReference? get rewardsDocRef => _rewardsDocRef;
  double get rewardsRawBalance => _rewardsRawBalance;

  // Base total amount (before discounts)
  double get totalAmount {
    return _items.values.fold(0.0, (sum, item) => sum + item.total);
  }

  // In CartProvider
  double get discountAmount {
    double promotionDiscount = _promoDiscount; // ADDED
    double pointsDiscount = _rewardsPointsToUse; // No division needed for double
    return promotionDiscount + pointsDiscount;
  }

  // Total after discount
  double get totalAmountAfterDiscount {
    return totalAmount - discountAmount;
  }

  CartItem? getItem(String id) {
    return _items[id];
  }

  // CHANGED: pointsAvailable to double
  void setRewardsInfo(String cardNumber, String cardHolderName, double pointsAvailable,
      [DocumentReference? docRef, String? cvvCode, double? rawBalance]) {
    _rewardsCardNumber = cardNumber;
    _rewardsCardHolderName = cardHolderName;
    _rewardsPointsAvailable = pointsAvailable;
    _rewardsRawBalance = rawBalance ?? pointsAvailable; // Removed .toDouble() as it is already double
    _rewardsDocRef = docRef;
    _rewardsCvvCode = cvvCode;
    _rewardsCvvVerified = false;
    _rewardsPointsToUse = 0.0; // Initialize as double
    notifyListeners();
  }

  // Method to verify CVV
  bool verifyCvv(bool isVerified) {
    _rewardsCvvVerified = isVerified;
    notifyListeners();
    return _rewardsCvvVerified;
  }

  // Method to check CVV against stored value
  bool checkCvv(String enteredCvv) {
    // If we have the CVV code stored, check against it
    if (_rewardsCvvCode != null) {
      return enteredCvv == _rewardsCvvCode;
    }

    // If no stored CVV, we can't verify
    return false;
  }

  // CHANGED: points to double
  void setRewardsPointsToUse(double points) {
    if (!_rewardsCvvVerified) return;

    // Calculate max points that can be used (removed .toInt())
    final maxPointsUsable = min(_rewardsPointsAvailable, totalAmount);
    _rewardsPointsToUse = min(points, maxPointsUsable);

    // Ensure we don't try to use more points than the cart total
    if (_rewardsPointsToUse > totalAmount) {
      _rewardsPointsToUse = totalAmount; // Kept as double
    }

    notifyListeners();
  }

  // Method to reset rewards info
  void resetRewardsInfo() {
    _rewardsCardNumber = null;
    _rewardsCardHolderName = null;
    _rewardsPointsAvailable = 0.0; // Reset to 0.0
    _rewardsPointsToUse = 0.0;     // Reset to 0.0
    _rewardsCvvVerified = false;
    _rewardsDocRef = null;
    _rewardsCvvCode = null;
    notifyListeners();
  }

  Future<void> addRewardPoints() async {
    if (_rewardsDocRef != null) {
      try {
        // Calculate points to add as 1% of total, keeping decimal precision
        final pointsToAdd = totalAmountAfterDiscount * 0.01;

        if (kDebugMode) {
          print('Adding $pointsToAdd points to rewards account $_rewardsCardNumber');
          print('Total amount after discount: $totalAmountAfterDiscount');
          print('Document reference: ${_rewardsDocRef!.path}');
        }

        await _rewardsDocRef!.update({
          'saldo': FieldValue.increment(pointsToAdd)
        });

        if (kDebugMode) {
          print('Successfully added $pointsToAdd points');
        }
      } catch (e) {
        // Error handling
        if (kDebugMode) {
          print('Error adding reward points: $e');
        }
        rethrow;
      }
    }
  }

  // Method to deduct points used
  Future<void> deductRewardPoints() async {
    if (_rewardsDocRef != null && _rewardsPointsToUse > 0) {
      try {
        // Deduct the points from Firestore
        await _rewardsDocRef!.update({
          'saldo': FieldValue.increment(-_rewardsPointsToUse)
        });

        if (kDebugMode) {
          print('Deducted $_rewardsPointsToUse points from rewards account $_rewardsCardNumber');
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error deducting reward points: $e');
        }
        // Rethrow to handle in UI
        rethrow;
      }
    }
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

      // -----------------------------------------
      // TYPE 1: EXACT COMBO
      // -----------------------------------------
      if (promo['type'] == 'combo_exact') {
        // Safely parse Firestore arrays to avoid Cast errors
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

      // -----------------------------------------
      // TYPE 2: BRAND COMBO (e.g. Coke + ANY Sabritas)
      // -----------------------------------------
      else if (promo['type'] == 'combo_brand') {
        String triggerId = promo['triggerProductId']?.toString() ?? '';
        // Make the target brand string safe for comparison
        String targetBrand = (promo['targetBrand']?.toString() ?? '').toLowerCase().trim();
        double comboPrice = (promo['comboPrice'] as num?)?.toDouble() ?? 0.0;

        int triggersAvailable = (availableQuantities[triggerId] ?? 0).toInt();

        while (triggersAvailable > 0) {
          String? pairedId;
          for (String id in availableQuantities.keys) {
            if (availableQuantities[id]! > 0 && id != triggerId) {
              // Safely compare the item's brand
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
            // Consume the trigger and the paired brand item
            availableQuantities[triggerId] = availableQuantities[triggerId]! - 1;
            availableQuantities[pairedId] = availableQuantities[pairedId]! - 1;
            triggersAvailable--;
          } else {
            break; // No more items matching the target brand
          }
        }
      }

      // -----------------------------------------
      // TYPE 3: BxGy (e.g., 3x2)
      // -----------------------------------------
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
      // -----------------------------------------
      // TYPE 4: COMBO CHOICE (Trigger + Any 1 from a List)
      // -----------------------------------------
      else if (promo['type'] == 'combo_choice') {
        String triggerId = promo['triggerProductId']?.toString() ?? '';
        List<dynamic> rawTargetIds = promo['targetProductIds'] ?? [];
        List<String> targetIds = rawTargetIds.map((e) => e.toString()).toList();
        double comboPrice = (promo['comboPrice'] as num?)?.toDouble() ?? 0.0;

        int triggersAvailable = (availableQuantities[triggerId] ?? 0).toInt();

        while (triggersAvailable > 0) {
          String? pairedId;
          // Look for any available product from the allowed targets list
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
            // Consume the trigger and the selected target item
            availableQuantities[triggerId] = availableQuantities[triggerId]! - 1;
            availableQuantities[pairedId] = availableQuantities[pairedId]! - 1;
            triggersAvailable--;
          } else {
            break; // No more valid target items available to complete the combo
          }
        }
      }
    }

    _promoDiscount = totalPromoDiscount;
    _appliedPromosList = applied;
  }

  void setItem(
      String id,
      String name,
      double price,
      double cost,
      String imageUrl,
      double quantity, {
        String brand = '', // <-- ADDED THIS
        bool isBulk = false,
        required double stock,
        String? typeSpecific,
        String? variante,
      }) {
    var adjustedQuantity = quantity;

    if (adjustedQuantity <= 0) {
      removeItemCompletely(id);
      return;
    }

    if (adjustedQuantity > stock) {
      _showStockExceededMessage(name);
      adjustedQuantity = stock;
    }

    final newItems = <String, CartItem>{};

    newItems[id] = CartItem(
      id: id,
      name: name,
      brand: brand, // <-- ADDED THIS
      price: price,
      cost: cost,
      imageUrl: imageUrl,
      quantity: adjustedQuantity,
      isBulk: isBulk,
      stock: stock,
      typeSpecific: typeSpecific,
      variante: variante,
    );

    _items.forEach((key, value) {
      if (key != id) newItems[key] = value;
    });

    _items.clear();
    _items.addAll(newItems);
    _evaluatePromotions();
    notifyListeners();
    onModified?.call();
  }

  void updateQuantity(String id, double quantity) {
    if (!_items.containsKey(id)) return;

    final item = _items[id]!;

    if (quantity <= 0) {
      removeItemCompletely(id);
      return;
    }

    if (quantity > item.stock) {
      _showStockExceededMessage(item.name);
      quantity = item.stock;
    }

    _items[id] = item.copyWith(quantity: quantity);
    _evaluatePromotions();
    notifyListeners();
    onModified?.call();
  }

  void incrementQuantity(String id, {double amount = 1.0}) {
    if (!_items.containsKey(id)) return;

    final item = _items[id]!;
    updateQuantity(id, item.quantity + amount);
  }

  void decrementQuantity(String id, {double amount = 1.0}) {
    if (!_items.containsKey(id)) return;

    final item = _items[id]!;
    updateQuantity(id, item.quantity - amount);
  }

  void removeItemCompletely(String id) {
    _items.remove(id);
    _evaluatePromotions();
    notifyListeners();
    onModified?.call();
  }

  void clearCart() {
    _items.clear();
    resetRewardsInfo();
    _promoDiscount = 0.0;
    _appliedPromosList.clear();
    notifyListeners();
    _cartClearedController.add(null);
    onModified?.call();
  }

  bool hasItemInCart(String id) {
    return _items.containsKey(id);
  }

  bool hasStockAvailable(String id) {
    if (!_items.containsKey(id)) return true;
    final item = _items[id]!;
    return item.quantity < item.stock;
  }

  void _showStockExceededMessage(String productName) {
    if (kDebugMode) {
      print('Stock limit reached for $productName');
    }
  }

  // Method to reduce product stock in Firestore
  Future<void> reduceProductsStock() async {
    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        // First, read all current product stocks to ensure we have the absolute latest data
        Map<String, DocumentSnapshot> productDocs = {};
        for (final item in _items.values) {
          final productRef = FirebaseFirestore.instance.collection('products').doc(item.id);
          final doc = await transaction.get(productRef);
          if (!doc.exists) {
            throw Exception('Producto no encontrado: ${item.name}');
          }
          productDocs[item.id] = doc;
        }

        // Second, verify stock is sufficient and apply updates
        for (final item in _items.values) {
          final doc = productDocs[item.id]!;
          final productData = doc.data() as Map<String, dynamic>;

          // Get the real, current stock from Firebase
          final dynamic rawStock = productData['stock'];
          final double currentStock = rawStock is int ? rawStock.toDouble() : (rawStock as double? ?? 0.0);

          // Ensure we don't oversell if stock changed between the time it was added to cart and checkout
          if (currentStock < item.quantity) {
            throw Exception('Stock insuficiente para ${item.name}. Disponible: $currentStock, Requerido: ${item.quantity}');
          }

          // Update using the freshly fetched stock value minus the quantity in the cart
          transaction.update(doc.reference, {
            'stock': currentStock - item.quantity
          });
        }
      });

      if (kDebugMode) {
        print('All product stocks updated successfully via transaction');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error updating product stocks: $e');
      }
      rethrow; // Throws to the UI so the SnackBar displays the issue.
    }
  }

  // Method to calculate change for payment
  Map<String, double> calculateChange(double amountPaid) {
    final total = totalAmountAfterDiscount; // Use total after discount
    final change = amountPaid - total;

    return {
      'total': total,
      'paid': amountPaid,
      'change': change,
    };
  }

  // Method to create order summary
  Map<String, dynamic> createOrderSummary() {
    return {
      'items': _items.values.map((item) => {
        'id': item.id,
        'name': item.name,
        'price': item.price,
        'cost': item.cost, // Include cost
        'quantity': item.quantity,
        'total': item.total,
        'totalCost': item.totalCost, // Include totalCost
        'isBulk': item.isBulk,
        'variante': item.variante, // Include variante
      }).toList(),
      'subtotal': totalAmount,
      'totalCost': totalCost, // Include total cost
      'profit': totalAmount - totalCost, // Calculate profit
      'profitMargin': totalAmount > 0 ? ((totalAmount - totalCost) / totalAmount * 100) : 0, // Calculate profit margin
      'discount': discountAmount,
      'totalAfterDiscount': totalAmountAfterDiscount,
      'profitAfterDiscount': totalAmountAfterDiscount - totalCost, // Calculate profit after discount
      'itemCount': itemCount,
      'timestamp': DateTime.now().toIso8601String(),
      'rewardsInfo': _rewardsCardNumber != null ? {
        'cardNumber': _rewardsCardNumber,
        'cardHolderName': _rewardsCardHolderName,
        'pointsUsed': _rewardsPointsToUse, // Stores exact double
        // Stores exact double, removed .toInt()
        'pointsEarned': _rewardsPointsToUse > 0 ? 0.0 : (totalAmountAfterDiscount * 0.01),
      } : null,
    };
  }

  // Method to fetch rewards account
  static Future<Map<String, dynamic>?> searchRewardsAccount({String? name, String? cardNumber}) async {
    try {
      QuerySnapshot queryResults;

      if (name != null && name.isNotEmpty && cardNumber != null && cardNumber.isNotEmpty) {
        // Search by both name and card number
        final formattedCardNumber = cardNumber.startsWith("T_STY-") ? cardNumber : "T_STY-$cardNumber";
        queryResults = await FirebaseFirestore.instance
            .collection('rewards')
            .where('cardHolderName', isEqualTo: name.toUpperCase())
            .where('cardNumber', isEqualTo: formattedCardNumber)
            .limit(1)
            .get();
      } else if (name != null && name.isNotEmpty) {
        // Search by name only
        queryResults = await FirebaseFirestore.instance
            .collection('rewards')
            .where('cardHolderName', isEqualTo: name.toUpperCase())
            .limit(1)
            .get();
      } else if (cardNumber != null && cardNumber.isNotEmpty) {
        // Search by card number only
        final formattedCardNumber = cardNumber.startsWith("T_STY-") ? cardNumber : "T_STY-$cardNumber";
        queryResults = await FirebaseFirestore.instance
            .collection('rewards')
            .where('cardNumber', isEqualTo: formattedCardNumber)
            .limit(1)
            .get();
      } else {
        // No search parameters provided
        return null;
      }

      if (queryResults.docs.isNotEmpty) {
        final doc = queryResults.docs.first;
        final data = doc.data() as Map<String, dynamic>;

        // Ensure points are parsed as double from Firestore
        if (data.containsKey('saldo')) {
          final dynamic val = data['saldo'];
          if (val is int) {
            data['saldo'] = val.toDouble();
          }
        }

        // Add the document reference to the data
        return {
          ...data,
          'docRef': doc.reference,
        };
      }

      return null;
    } catch (e) {
      if (kDebugMode) {
        print('Error searching rewards account: $e');
      }
      rethrow;
    }
  }

  // New method for barcode scanning functionality
  Future<bool> addProductByBarcode(String barcode) async {
    // Clean the barcode to remove whitespace, newlines, etc.
    final cleanBarcode = barcode.trim();

    if (kDebugMode) {
      print('Attempting to add product with barcode: "$cleanBarcode"');
    }

    try {
      // Query Firestore to find the product with the matching barcode
      final QuerySnapshot result = await FirebaseFirestore.instance
          .collection('products')
          .where('barcode', isEqualTo: cleanBarcode)
          .limit(1)
          .get();

      // Check if we got results
      if (kDebugMode) {
        print('Firestore query returned ${result.docs.length} documents');
      }

      // Check if a product was found
      if (result.docs.isEmpty) {
        if (kDebugMode) {
          print('No product found with barcode: "$cleanBarcode"');

          // RESTORED DEBUG BLOCK: Try to debug what might be wrong with a sample product
          try {
            final sampleProducts = await FirebaseFirestore.instance
                .collection('products')
                .limit(1)
                .get();

            if (sampleProducts.docs.isNotEmpty) {
              final sampleData = sampleProducts.docs.first.data();
              print('Sample product fields: ${sampleData.keys.toList()}');

              // Look for possible barcode fields
              final possibleFields = ['barcode', 'Barcode', 'code', 'Code', 'sku', 'SKU', 'barra', 'codigo'];
              for (final field in possibleFields) {
                if (sampleData.containsKey(field)) {
                  print('Found potential barcode field: "$field" with value: ${sampleData[field]}');
                }
              }
            }
          } catch (e) {
            print('Error getting sample product: $e');
          }
        }
        return false;
      }

      // Get the product data
      final productDoc = result.docs.first;
      final productData = productDoc.data() as Map<String, dynamic>;

      if (kDebugMode) {
        print('Found product: ${productData['nombre']}');
      }

      // Extract fields safely
      final String id = productDoc.id;
      final String name = productData['nombre'] ?? 'Unknown Product';
      final String brand = productData['brand'] ?? '';

      // Handle different types for numeric fields
      double price = 0.0;
      if (productData.containsKey('price')) {
        if (productData['price'] is int) {
          price = (productData['price'] as int).toDouble();
        } else if (productData['price'] is double) {
          price = productData['price'] as double;
        }
      }
      // Extract cost - NEW
      double cost = 0.0;
      if (productData.containsKey('cost')) {
        if (productData['cost'] is int) {
          cost = (productData['cost'] as int).toDouble();
        } else if (productData['cost'] is double) {
          cost = productData['cost'] as double;
        }
      }
      double stock = 0.0;
      if (productData.containsKey('stock')) {
        if (productData['stock'] is int) {
          stock = (productData['stock'] as int).toDouble();
        } else if (productData['stock'] is double) {
          stock = productData['stock'] as double;
        }
      }

      final String imageUrl = productData['image_url'] ?? '';
      final bool isBulk = productData['bulk'] ?? false;
      final String? typeSpecific = productData['type_specific'];
      final String? variante = productData['variante']; // Extract variante

      if (stock <= 0) {
        if (kDebugMode) {
          print('Product out of stock: $name');
        }
        return false;
      }

      // If product is already in cart, increment quantity by 1
      if (hasItemInCart(id)) {
        if (kDebugMode) {
          print('Product already in cart, incrementing quantity');
        }

        final currentItem = getItem(id);
        if (currentItem != null) {
          // Check if incrementing would exceed stock
          if (currentItem.quantity + 1 <= stock) {
            incrementQuantity(id);
            if (kDebugMode) {
              print('Successfully incremented quantity');
            }
          } else {
            _showStockExceededMessage(name);
            return false;
          }
        }
      } else {
        if (kDebugMode) {
          print('Adding new product to cart');
        }

        // Add the product to the cart with quantity 1
        setItem(
          id,
          name,
          price,
          cost, // Include cost
          imageUrl,
          1, // Default quantity when adding new item
          brand: brand,
          isBulk: isBulk,
          stock: stock,
          typeSpecific: typeSpecific,
          variante: variante, // Include variante
        );


        if (kDebugMode) {
          print('Successfully added product to cart');
        }
      }

      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Error adding product by barcode: $e');
        print('Stack trace: ${StackTrace.current}');
      }
      return false;
    }
  }
  @override
  void dispose() {
    _cartClearedController.close();
    super.dispose();
  }
}