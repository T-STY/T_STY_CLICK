import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CartGroup {
  final String name;
  final String? comboInstanceId;
  final Map<String, double> claimed;
  final double savings;

  CartGroup({
    required this.name,
    required this.claimed,
    required this.savings,
    this.comboInstanceId,
  });
}

class ComboInstance {
  final String instanceId;
  final String comboId;
  final String name;
  final List<Map<String, dynamic>> components;
  final double savings;

  ComboInstance({
    required this.instanceId,
    required this.comboId,
    required this.name,
    required this.components,
    required this.savings,
  });

  Map<String, dynamic> toMap() => {
        'instanceId': instanceId,
        'comboId': comboId,
        'name': name,
        'components': components,
        'savings': savings,
      };

  factory ComboInstance.fromJson(Map<String, dynamic> j) => ComboInstance(
        instanceId: j['instanceId'] as String,
        comboId: j['comboId'] as String? ?? '',
        name: j['name'] as String? ?? 'Combo',
        components: (j['components'] as List?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            const [],
        savings: (j['savings'] as num?)?.toDouble() ?? 0.0,
      );
}

class CartProvider extends ChangeNotifier {
  Map<String, CartItem> _items = {};
  List<ComboInstance> _comboInstances = [];

  List<Map<String, dynamic>> _activePromotions = [];
  double _totalDiscount = 0.0;
  List<CartGroup> _groups = [];

  List<String> get appliedPromosList => _groups.map((g) => g.name).toList();
  double get promoDiscount => _totalDiscount;

  List<CartGroup> get groups => List.unmodifiable(_groups);

  CartProvider() {
    _init();
  }

  Future<void> _init() async {
    await fetchActivePromotions();
    await _loadCartFromStorage();
  }

  Map<String, CartItem> get items => {..._items};

  double get totalPrice {
    double total = 0.0;
    _items.forEach((key, cartItem) {
      total += cartItem.price * cartItem.quantity;
    });
    return total;
  }

  double get discountAmount => _totalDiscount;

  double get totalPriceAfterDiscount {
    final result = totalPrice - discountAmount;
    return result < 0 ? 0 : result;
  }

  int get totalItemCount => _items.length;

  double ungroupedQuantity(String productId) {
    final item = _items[productId];
    if (item == null) return 0;
    double claimed = 0;
    for (final g in _groups) {
      claimed += g.claimed[productId] ?? 0;
    }
    final remaining = item.quantity - claimed;
    return remaining < 0 ? 0 : remaining;
  }

  Future<void> fetchActivePromotions() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('promotions')
          .where('active', isEqualTo: true)
          .get();

      _activePromotions =
          snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
      _evaluatePromotions();
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print("Error fetching promos: $e");
    }
  }

  void _evaluatePromotions() {
    final available = <String, double>{};
    _items.forEach((k, v) => available[k] = v.quantity);
    final groups = <CartGroup>[];
    double totalDiscount = 0.0;

    final kept = <ComboInstance>[];
    for (final inst in _comboInstances) {
      bool ok = inst.components.isNotEmpty;
      for (final c in inst.components) {
        final pid = c['productId'] as String;
        final q = (c['quantity'] as num).toDouble();
        if ((available[pid] ?? 0) < q) {
          ok = false;
          break;
        }
      }
      if (!ok) continue;
      final claimed = <String, double>{};
      for (final c in inst.components) {
        final pid = c['productId'] as String;
        final q = (c['quantity'] as num).toDouble();
        available[pid] = (available[pid] ?? 0) - q;
        claimed[pid] = (claimed[pid] ?? 0) + q;
      }
      groups.add(CartGroup(
        name: inst.name,
        comboInstanceId: inst.instanceId,
        claimed: claimed,
        savings: inst.savings,
      ));
      totalDiscount += inst.savings;
      kept.add(inst);
    }
    _comboInstances = kept;

    for (var promo in _activePromotions) {
      final type = promo['type'];
      final name = (promo['name'] ?? 'Promoción').toString();

      if (type == 'combo_exact') {
        final rawIds = (promo['requiredProductIds'] as List?) ?? [];
        final requiredIds = rawIds.map((e) => e.toString()).toList();
        final comboPrice = (promo['comboPrice'] as num?)?.toDouble() ?? 0.0;
        final requiredCounts = <String, int>{};
        for (final id in requiredIds) {
          requiredCounts[id] = (requiredCounts[id] ?? 0) + 1;
        }
        bool canApply = requiredCounts.isNotEmpty;
        int timesToApply = 999999;
        requiredCounts.forEach((reqId, reqQty) {
          final avail = (available[reqId] ?? 0).toInt();
          if (avail < reqQty) {
            canApply = false;
          } else {
            timesToApply = min(timesToApply, avail ~/ reqQty);
          }
        });
        if (canApply && timesToApply > 0) {
          double normalPrice = 0.0;
          final claimed = <String, double>{};
          requiredCounts.forEach((reqId, reqQty) {
            normalPrice += (_items[reqId]!.price * reqQty);
            available[reqId] = available[reqId]! - (reqQty * timesToApply);
            claimed[reqId] = (claimed[reqId] ?? 0) + (reqQty * timesToApply);
          });
          final discount = (normalPrice - comboPrice) * timesToApply;
          if (discount > 0) {
            groups.add(CartGroup(
              name: timesToApply > 1 ? '$name (x$timesToApply)' : name,
              claimed: claimed,
              savings: discount,
            ));
            totalDiscount += discount;
          }
        }
      }

      else if (type == 'combo_brand') {
        final triggerId = promo['triggerProductId']?.toString() ?? '';
        final targetBrand =
            (promo['targetBrand']?.toString() ?? '').toLowerCase().trim();
        final comboPrice = (promo['comboPrice'] as num?)?.toDouble() ?? 0.0;
        int triggersAvailable = (available[triggerId] ?? 0).toInt();
        final claimed = <String, double>{};
        double savings = 0;
        while (triggersAvailable > 0) {
          String? pairedId;
          for (final id in available.keys) {
            if ((available[id] ?? 0) > 0 && id != triggerId) {
              final itemBrand = (_items[id]?.brand ?? '').toLowerCase().trim();
              if (itemBrand == targetBrand || itemBrand.contains(targetBrand)) {
                pairedId = id;
                break;
              }
            }
          }
          if (pairedId != null) {
            final normalPrice =
                _items[triggerId]!.price + _items[pairedId]!.price;
            final discount = normalPrice - comboPrice;
            if (discount > 0) savings += discount;
            available[triggerId] = available[triggerId]! - 1;
            available[pairedId] = available[pairedId]! - 1;
            claimed[triggerId] = (claimed[triggerId] ?? 0) + 1;
            claimed[pairedId] = (claimed[pairedId] ?? 0) + 1;
            triggersAvailable--;
          } else {
            break;
          }
        }
        if (savings > 0) {
          groups.add(
              CartGroup(name: name, claimed: claimed, savings: savings));
          totalDiscount += savings;
        }
      }

      else if (type == 'bxgy') {
        final targetId = promo['targetProductId']?.toString() ?? '';
        final buyQty = (promo['buyQuantity'] as num?)?.toInt() ?? 3;
        final payQty = (promo['payQuantity'] as num?)?.toInt() ?? 2;
        final qty = (available[targetId] ?? 0).toInt();
        final freeItemsCount = buyQty > 0 ? qty ~/ buyQty : 0;
        if (freeItemsCount > 0 && _items[targetId] != null) {
          final itemsFreePerCombo = buyQty - payQty;
          final discount =
              (freeItemsCount * itemsFreePerCombo) * _items[targetId]!.price;
          final consumed = (freeItemsCount * buyQty).toDouble();
          if (discount > 0) {
            available[targetId] = (available[targetId] ?? 0) - consumed;
            groups.add(CartGroup(
              name: freeItemsCount > 1 ? '$name (x$freeItemsCount)' : name,
              claimed: {targetId: consumed},
              savings: discount,
            ));
            totalDiscount += discount;
          }
        }
      }

      else if (type == 'combo_choice') {
        final triggerId = promo['triggerProductId']?.toString() ?? '';
        final rawTargetIds = (promo['targetProductIds'] as List?) ?? [];
        final targetIds = rawTargetIds.map((e) => e.toString()).toList();
        final comboPrice = (promo['comboPrice'] as num?)?.toDouble() ?? 0.0;
        int triggersAvailable = (available[triggerId] ?? 0).toInt();
        final claimed = <String, double>{};
        double savings = 0;
        while (triggersAvailable > 0) {
          String? pairedId;
          for (final id in targetIds) {
            if ((available[id] ?? 0) > 0) {
              pairedId = id;
              break;
            }
          }
          if (pairedId != null) {
            final normalPrice =
                _items[triggerId]!.price + _items[pairedId]!.price;
            final discount = normalPrice - comboPrice;
            if (discount > 0) savings += discount;
            available[triggerId] = available[triggerId]! - 1;
            available[pairedId] = available[pairedId]! - 1;
            claimed[triggerId] = (claimed[triggerId] ?? 0) + 1;
            claimed[pairedId] = (claimed[pairedId] ?? 0) + 1;
            triggersAvailable--;
          } else {
            break;
          }
        }
        if (savings > 0) {
          groups.add(
              CartGroup(name: name, claimed: claimed, savings: savings));
          totalDiscount += savings;
        }
      }
    }

    _groups = groups;
    _totalDiscount = totalDiscount;
  }

  Future<void> _saveCartToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'tsty_cart_data',
        jsonEncode(_items.map((key, item) => MapEntry(key, item.toMap()))),
      );
      await prefs.setString(
        'tsty_combo_instances',
        jsonEncode(_comboInstances.map((c) => c.toMap()).toList()),
      );
    } catch (e) {
      if (kDebugMode) print('Error al guardar el carrito: $e');
    }
  }

  Future<void> _loadCartFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedData = prefs.getString('tsty_cart_data');
      if (savedData != null) {
        final decoded = jsonDecode(savedData) as Map<String, dynamic>;
        _items = decoded.map(
            (key, value) => MapEntry(key, CartItem.fromJson(value as Map<String, dynamic>)));
        _items.removeWhere((key, _) => key.startsWith('combo_'));
      }
      final combosData = prefs.getString('tsty_combo_instances');
      if (combosData != null) {
        final list = jsonDecode(combosData) as List;
        _comboInstances = list
            .map((e) => ComboInstance.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
      _evaluatePromotions();
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('Error al cargar el carrito: $e');
    }
  }

  void _mergeItem(String productId, String name, double price, String imageUrl,
      double quantity,
      {required bool isBulk,
      required double stock,
      String? typeSpecific,
      String? variante,
      String brand = ''}) {
    final existing = _items[productId];
    double newQty = (existing?.quantity ?? 0) + quantity;
    if (stock > 0 && newQty > stock) newQty = stock;
    if (newQty <= 0) {
      _items.remove(productId);
      return;
    }
    _items[productId] = CartItem(
      nombre: name,
      price: price,
      quantity: newQty,
      imageUrl: imageUrl,
      objectID: productId,
      isBulk: isBulk,
      stock: stock,
      typeSpecific: typeSpecific ?? existing?.typeSpecific ?? '',
      variante: variante ?? existing?.variante ?? '',
      brand: brand.isNotEmpty ? brand : (existing?.brand ?? ''),
    );
  }

  void addItem(String productId, String name, double price, String imageUrl,
      {double quantity = 1.0,
      required bool isBulk,
      required double stock,
      String? typeSpecific,
      String? variante,
      String brand = ''}) {
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
    fetchActivePromotions();
  }

  void setItem(String productId, String name, double price, String imageUrl,
      double quantity,
      {required bool isBulk,
      required double stock,
      String? typeSpecific,
      String? variante,
      String brand = ''}) {
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
    fetchActivePromotions();
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
    fetchActivePromotions();
  }

  void removeItemCompletely(String productId) {
    _items.remove(productId);
    _evaluatePromotions();
    notifyListeners();
    _saveCartToStorage();
    fetchActivePromotions();
  }

  void _reduceItemBy(String productId, double amount) {
    final item = _items[productId];
    if (item == null) return;
    final remaining = item.quantity - amount;
    if (remaining <= 0.0001) {
      _items.remove(productId);
      return;
    }
    _items[productId] = CartItem(
      nombre: item.nombre,
      price: item.price,
      quantity: remaining,
      imageUrl: item.imageUrl,
      objectID: item.objectID,
      isBulk: item.isBulk,
      stock: item.stock,
      typeSpecific: item.typeSpecific,
      variante: item.variante,
      brand: item.brand,
    );
  }

  void clearGroup(CartGroup group) {
    if (group.comboInstanceId != null) {
      _comboInstances
          .removeWhere((c) => c.instanceId == group.comboInstanceId);
    }
    group.claimed.forEach((pid, qty) => _reduceItemBy(pid, qty));
    _evaluatePromotions();
    notifyListeners();
    _saveCartToStorage();
    fetchActivePromotions();
  }

  void clearUngrouped() {
    for (final id in _items.keys.toList()) {
      final ungrouped = ungroupedQuantity(id);
      if (ungrouped > 0) _reduceItemBy(id, ungrouped);
    }
    _evaluatePromotions();
    notifyListeners();
    _saveCartToStorage();
    fetchActivePromotions();
  }

  void addCombo({
    required String comboId,
    required String name,
    required double savings,
    required List<Map<String, dynamic>> components,
  }) {
    for (final c in components) {
      _mergeItem(
        c['productId'] as String,
        (c['nombre'] ?? 'Producto') as String,
        (c['price'] as num?)?.toDouble() ?? 0.0,
        (c['imageUrl'] ?? '') as String,
        (c['quantity'] as num?)?.toDouble() ?? 1.0,
        isBulk: c['isBulk'] as bool? ?? false,
        stock: (c['stock'] as num?)?.toDouble() ?? 0.0,
        typeSpecific: c['typeSpecific'] as String?,
        variante: c['variante'] as String?,
        brand: (c['brand'] ?? '') as String,
      );
    }
    _comboInstances.add(ComboInstance(
      instanceId:
          '${comboId}_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(99999)}',
      comboId: comboId,
      name: name,
      components: components
          .map((c) => {
                'productId': c['productId'],
                'quantity': (c['quantity'] as num?)?.toDouble() ?? 1.0,
              })
          .toList(),
      savings: savings,
    ));
    _evaluatePromotions();
    notifyListeners();
    _saveCartToStorage();
  }

  CartItem? getItem(String productId) {
    return _items[productId];
  }

  void clearCart() {
    _items.clear();
    _comboInstances.clear();
    _groups = [];
    _totalDiscount = 0.0;
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
