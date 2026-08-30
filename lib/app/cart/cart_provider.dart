import 'dart:async';
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

  final Map<String, _ProductMeta> _productMeta = {};
  final Set<String> _productMetaInFlight = {};

  final ValueNotifier<int> productMetaVersion = ValueNotifier<int>(0);

  List<String> get appliedPromosList => _groups.map((g) => g.name).toList();
  double get promoDiscount => _totalDiscount;

  List<CartGroup> get groups => List.unmodifiable(_groups);

  final Completer<void> _readyCompleter = Completer<void>();

  Future<void> get ready => _readyCompleter.future;

  CartProvider() {
    _init();
  }

  Future<void> _init() async {
    try {
      await fetchActivePromotions();
      await _loadCartFromStorage();
    } catch (e, st) {
      if (!_readyCompleter.isCompleted) {
        _readyCompleter.completeError(e, st);
      }
    } finally {
      if (!_readyCompleter.isCompleted) {
        _readyCompleter.complete();
      }
    }
  }

  Map<String, CartItem> get items => {..._items};

  double get totalPrice {
    double total = 0.0;
    _items.forEach((key, cartItem) {
      total += cartItem.lineTotal;
    });
    return total;
  }

  /// Líneas pedidas por pieza cuyo precio depende de la báscula. No suman al
  /// total todavía, así que hay que decirlo en pantalla: si no, el cliente ve
  /// un total que no es lo que va a pagar.
  int get pendingWeighCount =>
      _items.values.where((i) => i.pricePending).length;

  bool get hasPendingWeigh => pendingWeighCount > 0;

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

  double? eligibleSubtotalFor(Map<String, dynamic>? filterMap) {
    if (filterMap == null) return totalPrice;
    final mode = (filterMap['mode'] ?? 'all').toString();
    if (mode != 'include' && mode != 'exclude') return totalPrice;

    List<String> readList(dynamic v) =>
        (v is List) ? v.map((e) => e.toString()).toList() : const <String>[];
    final subs = readList(filterMap['subcategories']).toSet();
    final provs = readList(filterMap['provedores']).toSet();
    final ids = readList(filterMap['productIds']).toSet();

    final needsMeta = subs.isNotEmpty || provs.isNotEmpty;

    double eligible = 0.0;
    for (final item in _items.values) {
      final meta = _productMeta[item.productId];
      if (needsMeta && meta == null) {

        return null;
      }
      final cat = meta?.category ?? '';
      final prov = meta?.distribuitorName ?? '';
      final matchedCategory = cat.isNotEmpty && subs.contains(cat);
      final matchedProvedor = prov.isNotEmpty && provs.contains(prov);
      final matchedId =
          item.productId.isNotEmpty && ids.contains(item.productId);
      final matched = matchedCategory || matchedProvedor || matchedId;
      final pass = mode == 'include' ? matched : !matched;
      if (pass) eligible += item.lineTotal;
    }
    return eligible;
  }

  void _ensureProductMeta(String productId) {
    if (productId.isEmpty) return;
    if (_productMeta.containsKey(productId)) return;
    if (_productMetaInFlight.contains(productId)) return;
    _productMetaInFlight.add(productId);
    FirebaseFirestore.instance
        .collection('products')
        .doc(productId)
        .get()
        .then((snap) {
      _productMetaInFlight.remove(productId);
      if (!snap.exists) return;
      final d = snap.data() ?? {};
      _productMeta[productId] = _ProductMeta(
        category: (d['category'] ?? '').toString(),
        distribuitorName: (d['distribuitor_name'] ?? '').toString(),
      );

      productMetaVersion.value++;
    }).catchError((_) {
      _productMetaInFlight.remove(productId);
    });
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
    _pruneProductMeta();
  }

  void _pruneProductMeta() {
    if (_productMeta.isEmpty) return;
    final live = _items.values.map((i) => i.productId).toSet();
    _productMeta.removeWhere((pid, _) => !live.contains(pid));
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

      for (final item in _items.values) {
        _ensureProductMeta(item.productId);
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
      String brand = '',
      String? variantKey,
      String? variantName}) {
    final lineId = buildCartLineId(productId, variantKey);
    final existing = _items[lineId];
    double newQty = (existing?.quantity ?? 0) + quantity;
    if (stock > 0 && newQty > stock) newQty = stock;
    if (newQty <= 0) {
      _items.remove(lineId);
      return;
    }
    _items[lineId] = CartItem(
      nombre: name,
      price: price,
      quantity: newQty,
      imageUrl: imageUrl,
      objectID: lineId,
      isBulk: isBulk,
      stock: stock,
      typeSpecific: typeSpecific ?? existing?.typeSpecific ?? '',
      variante: variante ?? existing?.variante ?? '',
      brand: brand.isNotEmpty ? brand : (existing?.brand ?? ''),
      productId: productId,
      variantKey: variantKey ?? existing?.variantKey,
      variantName: variantName ?? existing?.variantName,
    );
    _ensureProductMeta(productId);
  }

  void addItem(String productId, String name, double price, String imageUrl,
      {double quantity = 1.0,
      required bool isBulk,
      required double stock,
      String? typeSpecific,
      String? variante,
      String brand = '',
      String? variantKey,
      String? variantName}) {
    final lineId = buildCartLineId(productId, variantKey);
    if (_items.containsKey(lineId)) {
      _items.update(
        lineId,
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
            productId: existingCartItem.productId,
            variantKey: existingCartItem.variantKey,
            variantName: existingCartItem.variantName,
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
        lineId,
        () => CartItem(
          nombre: name,
          price: price,
          quantity: initialQuantity,
          imageUrl: imageUrl,
          objectID: lineId,
          isBulk: isBulk,
          stock: stock,
          typeSpecific: typeSpecific ?? '',
          variante: variante ?? '',
          brand: brand,
          productId: productId,
          variantKey: variantKey,
          variantName: variantName,
        ),
      );
    }
    _ensureProductMeta(productId);
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
      String brand = '',
      String? variantKey,
      String? variantName,
      double? pieces,
      bool pricePending = false,
      List<double> fracciones = const [],
      String fraccionUnidad = 'pieza',
      bool permitePorPieza = false,
      double? avgPieceKg}) {
    if (!pricePending && quantity > stock) {
      quantity = stock;
      _showStockExceededDialog(name);
    }

    final lineId = buildCartLineId(productId, variantKey);

    // Una línea por pesar llega con cantidad 0 —todavía no hay kilos— y la
    // guarda de "quantity > 0" la borraba en el acto.
    if (quantity > 0 || pricePending) {
      _items.update(
        lineId,
        (existingCartItem) => CartItem(
          nombre: name,
          price: price,
          quantity: quantity,
          imageUrl: imageUrl,
          objectID: lineId,
          isBulk: isBulk,
          stock: stock,
          typeSpecific: typeSpecific ?? existingCartItem.typeSpecific,
          variante: variante ?? existingCartItem.variante,
          brand: brand.isNotEmpty ? brand : existingCartItem.brand,
          productId: productId,
          variantKey: variantKey ?? existingCartItem.variantKey,
          variantName: variantName ?? existingCartItem.variantName,
          pieces: pieces ?? existingCartItem.pieces,
          pricePending: pricePending,
          fracciones: fracciones.isNotEmpty
              ? fracciones
              : existingCartItem.fracciones,
          fraccionUnidad: fraccionUnidad,
          permitePorPieza: permitePorPieza,
          avgPieceKg: avgPieceKg,
        ),
        ifAbsent: () => CartItem(
          nombre: name,
          price: price,
          quantity: quantity,
          imageUrl: imageUrl,
          objectID: lineId,
          isBulk: isBulk,
          stock: stock,
          typeSpecific: typeSpecific ?? '',
          variante: variante ?? '',
          brand: brand,
          productId: productId,
          variantKey: variantKey,
          variantName: variantName,
          pieces: pieces,
          pricePending: pricePending,
          fracciones: fracciones,
          fraccionUnidad: fraccionUnidad,
          permitePorPieza: permitePorPieza,
          avgPieceKg: avgPieceKg,
        ),
      );
      _ensureProductMeta(productId);
    } else {
      _items.remove(lineId);
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
    _productMeta.clear();
    _productMetaInFlight.clear();
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

  final String productId;
  final String? variantKey;
  final String? variantName;

  /// Piezas pedidas cuando el cliente pidió "3 manzanas" en vez de un peso.
  /// Null cuando la línea se pidió por kilo.
  final double? pieces;

  /// Cómo se vende el producto, guardado en la línea porque el carrito ya no
  /// tiene el documento a la mano y los botones + y − necesitan saber qué
  /// diálogo abrir.
  final List<double> fracciones;
  final String fraccionUnidad;
  final bool permitePorPieza;
  /// Peso promedio por pieza aprendido en el mostrador.
  final double? avgPieceKg;

  /// El total todavía no se puede cobrar: depende de lo que pesen esas piezas.
  /// La línea entra al pedido igual, pero no suma al total hasta que la tienda
  /// las pese y cierre el precio.
  final bool pricePending;

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
    String? productId,
    this.variantKey,
    this.variantName,
    this.pieces,
    this.pricePending = false,
    this.fracciones = const [],
    this.fraccionUnidad = 'pieza',
    this.permitePorPieza = false,
    this.avgPieceKg,
  }) : productId = productId ?? objectID;

  /// Lo que esta línea aporta al total de hoy. Una línea por pesar aporta cero
  /// hasta que alguien la pese: mostrar un número inventado ahí es prometerle
  /// al cliente un precio que la báscula todavía no confirmó.
  double get lineTotal => pricePending ? 0 : price * quantity;

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

      'productId': productId,
      if (variantKey != null) 'variantKey': variantKey,
      if (variantName != null) 'variantName': variantName,
      if (pieces != null) 'pieces': pieces,
      if (pricePending) 'pricePending': true,
      if (fracciones.isNotEmpty) 'fracciones': fracciones,
      'fraccionUnidad': fraccionUnidad,
      if (permitePorPieza) 'permitePorPieza': true,
      if (avgPieceKg != null) 'avgPieceKg': avgPieceKg,
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
      productId: json['productId'] as String?,
      variantKey: json['variantKey'] as String?,
      variantName: json['variantName'] as String?,
      pieces: (json['pieces'] as num?)?.toDouble(),
      pricePending: json['pricePending'] == true,
      fracciones: (json['fracciones'] as List?)
              ?.map((v) => (v as num).toDouble())
              .toList() ??
          const [],
      fraccionUnidad: json['fraccionUnidad'] as String? ?? 'pieza',
      permitePorPieza: json['permitePorPieza'] == true,
      avgPieceKg: (json['avgPieceKg'] as num?)?.toDouble(),
    );
  }
}

String buildCartLineId(String productId, String? variantKey) =>
    variantKey == null || variantKey.isEmpty
        ? productId
        : '$productId#$variantKey';

class _ProductMeta {
  final String category;
  final String distribuitorName;
  const _ProductMeta({required this.category, required this.distribuitorName});
}
