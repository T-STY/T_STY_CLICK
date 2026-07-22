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

  // Lazy cache of product metadata (category + distribuitor_name) keyed by
  // productId. Populated by fire-and-forget Firestore reads from `addItem`,
  // `setItem`, and `_loadCartFromStorage`. Read by `eligibleSubtotalFor` to
  // evaluate coupon product-filter restrictions without async work in the
  // build path. NOTE: products store the typo'd field `distribuitor_name`.
  final Map<String, _ProductMeta> _productMeta = {};
  final Set<String> _productMetaInFlight = {};

  /// Bumped each time a `_ensureProductMeta` fetch resolves. Checkout's
  /// coupon row listens to this directly so it can re-evaluate
  /// `eligibleSubtotalFor` without forcing every Consumer<CartProvider>
  /// in the app to rebuild. Important on the search/home screen, where
  /// each visible search hit registers an `_AddToCartButton` listener on
  /// CartProvider — fanning out a full `notifyListeners` per meta read
  /// stutters the search results during typing.
  final ValueNotifier<int> productMetaVersion = ValueNotifier<int>(0);

  List<String> get appliedPromosList => _groups.map((g) => g.name).toList();
  double get promoDiscount => _totalDiscount;

  List<CartGroup> get groups => List.unmodifiable(_groups);

  final Completer<void> _readyCompleter = Completer<void>();

  /// Resolves once the initial async setup (`fetchActivePromotions` +
  /// `_loadCartFromStorage`) has completed. Callers can optionally await this
  /// before reading [items], [groups], or combo data to avoid the race where
  /// they observe empty state before the constructor's fire-and-forget `_init`
  /// resolves. Awaiting is optional — existing fire-and-forget behavior is
  /// unchanged.
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

  /// Sum of (price × quantity) over the cart items that satisfy a coupon's
  /// `productFilter`. Mirrors the server-side math in
  /// click-main/functions/index.js `_computeEligibleSubtotal` so the on-screen
  /// preview matches the order's recomputed discount.
  ///
  /// Pass `null` (or a filter map with `mode != 'include'/'exclude'`) to get
  /// the raw subtotal — legacy "no filter" behavior. The caller (checkout)
  /// is responsible for clamping the result to `totalPriceAfterDiscount` so
  /// combos and the coupon discount don't compound past the cart's value.
  ///
  /// Returns `null` IFF an active filter needs category/provedor data and at
  /// least one in-cart item's metadata hasn't loaded yet — the UI should
  /// render a neutral "verifying eligibility" state in that case instead of
  /// the misleading "No aplica" badge that would result from treating
  /// missing meta as "no match".
  double? eligibleSubtotalFor(Map<String, dynamic>? filterMap) {
    if (filterMap == null) return totalPrice;
    final mode = (filterMap['mode'] ?? 'all').toString();
    if (mode != 'include' && mode != 'exclude') return totalPrice;

    List<String> readList(dynamic v) =>
        (v is List) ? v.map((e) => e.toString()).toList() : const <String>[];
    final subs = readList(filterMap['subcategories']).toSet();
    final provs = readList(filterMap['provedores']).toSet();
    final ids = readList(filterMap['productIds']).toSet();
    // If the filter only matches by productId (no category/provedor lists),
    // we don't need product metadata at all — productId is already on the
    // cart line. Skip the loading-state check in that case.
    final needsMeta = subs.isNotEmpty || provs.isNotEmpty;

    double eligible = 0.0;
    for (final item in _items.values) {
      final meta = _productMeta[item.productId];
      if (needsMeta && meta == null) {
        // Metadata still loading for at least one in-cart item; refuse to
        // give a partial answer.
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
      if (pass) eligible += item.price * item.quantity;
    }
    return eligible;
  }

  /// Fire-and-forget product metadata fetch — populates `_productMeta` so a
  /// subsequent synchronous `eligibleSubtotalFor` call has the data it needs.
  /// Called from `addItem` / `setItem` and from cart-storage reload.
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
      // SCOPED notification — checkout's coupon row listens via
      // `productMetaVersion` so it can refresh eligibility without
      // waking every CartProvider listener (e.g. every search-result
      // row's `_AddToCartButton`).
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

  /// Drop cached product metadata for any productId that is no longer in
  /// the cart. Keeps the cache from leaking, and — more importantly —
  /// guarantees that the next time the user re-adds the product, a fresh
  /// Firestore read picks up any admin re-categorization that happened
  /// since the last time the item was in cart.
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
      // Backfill product metadata for everything in the restored cart so a
      // freshly opened checkout has eligibility data ready without waiting
      // for the user to interact with the cart.
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
      String? variantName}) {
    if (quantity > stock) {
      quantity = stock;
      _showStockExceededDialog(name);
    }

    final lineId = buildCartLineId(productId, variantKey);

    if (quantity > 0) {
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
  }) : productId = productId ?? objectID;

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
