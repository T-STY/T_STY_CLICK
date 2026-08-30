import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../bulk_order_dialog.dart';
import '../fraction_utils.dart';
import 'package:provider/provider.dart';
import '../../components/bottom_fade.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_defaults.dart';
import '../../constants/app_images.dart';
import '../../utils/order_window.dart';
import '../main.dart';
import '../payment/checkout_page.dart';
import '../payment/payment_done_page.dart';
import 'cart_provider.dart';
import 'components/product_tile_cart.dart';

class CartPage extends StatefulWidget {
  const CartPage({super.key});

  @override
  State<CartPage> createState() => CartPageState();
}

class CartPageState extends State<CartPage> {
  int _index = 0;

  OrderWindow _window = OrderWindow.openPlaceholder;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _revalidateStock());
  }

  Future<void> _revalidateStock() async {
    final cart = Provider.of<CartProvider>(context, listen: false);
    for (final item in cart.items.values.toList()) {
      try {

        final doc = await FirebaseFirestore.instance
            .collection('products')
            .doc(item.productId)
            .get();
        if (!doc.exists) {
          cart.removeItemCompletely(item.objectID);
          continue;
        }
        final data = doc.data() ?? const <String, dynamic>{};
        double stock = 0.0;
        if (item.variantKey != null && item.variantKey!.isNotEmpty) {
          final variants = data['variants'];
          if (variants is Map) {
            final v = variants[item.variantKey];
            if (v is Map) {
              stock = (v['stock'] as num?)?.toDouble() ?? 0.0;
            }
          }
        } else {
          stock = (data['stock'] as num?)?.toDouble() ?? 0.0;
        }
        if (stock <= 0) {
          cart.removeItemCompletely(item.objectID);
        } else if (item.quantity > stock) {
          cart.setItem(
            item.productId,
            item.nombre,
            item.price,
            item.imageUrl,
            stock,
            isBulk: item.isBulk,
            stock: stock,
            typeSpecific: item.typeSpecific,
            variante: item.variante,
            variantKey: item.variantKey,
            variantName: item.variantName,
          );
        }
      } catch (_) {
      }
    }
  }

  OrderWindow _windowFromSnapshot(Map<String, dynamic> data) {
    return OrderWindow.evaluate(doc: data, now: DateTime.now());
  }

  bool handleBack() {
    if (_index != 0) {
      setState(() {
        _index = 0;
      });
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: _index,
      children: [
        StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('settings')
              .doc('store')
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasData && snapshot.data!.exists) {
              final data = snapshot.data!.data() as Map<String, dynamic>;
              _window = _windowFromSnapshot(data);
            }

            return _buildCartContent(context,
                isLoading: snapshot.connectionState == ConnectionState.waiting);
          },
        ),
        CheckoutPage(
          onBack: () {
            setState(() {
              _index = 0;
            });
          },
          onOrderPlaced: () {
            setState(() {
              _index = 2;
            });
          },
        ),
        PaymentDonePage(
          onBackToHome: () {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => const MainMenuScreen()),
              (Route<dynamic> route) => false,
            );
          },
        ),
      ],
    );
  }

  Widget _buildCartContent(BuildContext context, {bool isLoading = false}) {

    final OrderingStatus status = _window.status;
    final bool ctaEnabled = status != OrderingStatus.closed;

    String? bannerText;
    Color? bannerColor;
    if (status == OrderingStatus.closed) {
      bannerText = 'Estamos cerrados de '
          '${formatHourMinute(_window.quietStart)} a '
          '${formatHourMinute(_window.quietEnd)}. '
          'Vuelve a hacer tu pedido más tarde.';
      bannerColor = Colors.red[700];
    } else if (status == OrderingStatus.pickupOnly) {
      bannerText = _window.deliveryRestToday
          ? 'Hoy solo aceptamos pedidos para recoger en tienda.'
          : 'Las entregas a domicilio están disponibles entre '
              '${formatHourMinute(_window.todayOpen!)} y '
              '${formatHourMinute(_window.todayClose!)}. '
              'Fuera de ese horario puedes recoger en tienda.';
      bannerColor = Colors.orange[800];
    }

    return Container(
      color: Colors.transparent,
      child: Column(
        children: [
          AppBar(
            automaticallyImplyLeading: false,
            backgroundColor: Colors.white,
            scrolledUnderElevation: 0,
            title: SizedBox(
              height: 180,
              width: 300,
              child: AspectRatio(
                aspectRatio: 1 / 1,
                child: Image.asset(
                  AppImages.logo,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            centerTitle: true,
            actions: [
              Consumer<CartProvider>(
                builder: (context, cart, _) {
                  if (cart.items.isEmpty) return const SizedBox.shrink();
                  return IconButton(
                    tooltip: 'Vaciar carrito',
                    icon: const Icon(Icons.delete_sweep_outlined,
                        color: Colors.black),
                    onPressed: () => _confirmClear(
                      context,
                      'Vaciar carrito',
                      '¿Eliminar todos los productos de tu carrito?',
                      cart.clearCart,
                    ),
                  );
                },
              ),
            ],
          ),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: BottomFade(

                    clearHeight: 0,
                    fadeHeight: 65,
                    child: Consumer<CartProvider>(
                      builder: (context, cartProvider, child) {
                        if (cartProvider.items.isEmpty) {
                          return const Center(
                            child: Text('No hay productos en tu carrito'),
                          );
                        }
                        return ListView(
                          padding: const EdgeInsets.only(bottom: 16),
                          children: _buildCartChildren(context, cartProvider),
                        );
                      },
                    ),
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 5, 16, 112),
                  child: Card(
              elevation: 4,
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey[850]
                  : Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(AppDefaults.padding),
                child: Consumer<CartProvider>(
                  builder: (context, cartProvider, child) {
                    final double subtotal = cartProvider.totalPrice;
                    final double discount = cartProvider.discountAmount;
                    final double total = cartProvider.totalPriceAfterDiscount;

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Subtotal:',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              '\$${subtotal.toStringAsFixed(2)} MXN',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        ),
                        if (discount > 0) ...[
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Descuento:',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                '-\$${discount.toStringAsFixed(2)}',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(color: Colors.red),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Envío:',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              'Pendiente a Calcular',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(color: Colors.orange),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Divider(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.grey[850]
                              : Colors.black,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Total:',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '\$${total.toStringAsFixed(2)} MXN',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (bannerText != null && !isLoading)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Text(
                              bannerText,
                              style: TextStyle(
                                color: bannerColor,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: (cartProvider.items.isEmpty ||
                                !ctaEnabled ||
                                isLoading)
                                ? null
                                : () async {
                              await _revalidateStock();
                              if (mounted && cartProvider.items.isNotEmpty) {
                                setState(() {
                                  _index = 1;
                                });
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: AppColors.defaultBlack,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: isLoading
                                ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                                : const Text(
                              'Finalizar Compra',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: AppColors.defaultWhite,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildCartChildren(
      BuildContext context, CartProvider cart) {
    final children = <Widget>[];

    for (final g in cart.groups) {
      children.add(_groupHeader(g.name));
      g.claimed.forEach((pid, qty) {
        final item = cart.getItem(pid);
        if (item == null || qty <= 0) return;
        children.add(ProductTileCart(
          key: ValueKey('grp_${g.comboInstanceId ?? g.name}_$pid'),
          objectId: pid,
          name: item.nombre,
          price: item.price,
          imageUrl: item.imageUrl,
          quantity: qty,
          isBulk: item.isBulk,
          typeSpecific: item.typeSpecific,
          variante: item.variante,
          onRemove: () => _confirmClear(
            context,
            'Quitar ${g.name}',
            'Se eliminarán todos los productos de "${g.name}" de tu carrito.',
            () => cart.clearGroup(g),
          ),
        ));
      });
    }

    final ungrouped = cart.items.values
        .where((it) => cart.ungroupedQuantity(it.objectID) > 0)
        .toList();

    if (children.isNotEmpty && ungrouped.isNotEmpty) {
      children.add(_sectionDivider(
        'Otros productos',
        onClear: () => _confirmClear(
          context,
          'Vaciar otros productos',
          'Se quitarán los productos que no forman parte de un combo o promoción.',
          cart.clearUngrouped,
        ),
      ));
    }

    for (final item in ungrouped) {
      final q = cart.ungroupedQuantity(item.objectID);
      children.add(ProductTileCart(
        key: ValueKey('std_${item.objectID}'),
        objectId: item.objectID,
        name: item.nombre,
        price: item.price,
        imageUrl: item.imageUrl,
        quantity: q,
        isBulk: item.isBulk,
        typeSpecific: item.typeSpecific,
        variante: item.variante,
        increaseQuantity: () { _editCartLine(context, cart, item); },
        decreaseQuantity: () {
          if (item.fracciones.isNotEmpty ||
              item.isBulk ||
              item.permitePorPieza ||
              item.pricePending) {
            _editCartLine(context, cart, item);
          } else {
            cart.removeItem(item.objectID, isBulk: item.isBulk);
          }
        },
      ));
    }

    return children;
  }

  Widget _groupHeader(String name) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 2),
      child: Row(
        children: [
          const Icon(Icons.local_offer, size: 16, color: Colors.orange),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.orange[800]),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionDivider(String label, {VoidCallback? onClear}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 8, 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  letterSpacing: 0.2,
                  color: Colors.grey[600]),
            ),
          ),
          if (onClear != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              tooltip: 'Vaciar sección',
              icon: Icon(Icons.close, size: 18, color: Colors.grey[500]),
              onPressed: onClear,
            ),
        ],
      ),
    );
  }

  void _confirmClear(
    BuildContext context,
    String title,
    String message,
    VoidCallback onConfirm,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              onConfirm();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  /// Un renglón del carrito se vuelve a editar con el mismo diálogo con el que
  /// se agregó: por peso, por pieza o por fracción según el producto.
  void _showBulkOrderDialog(
      BuildContext context, CartProvider cartProvider, CartItem item) {
    showDialog(
      context: context,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: BulkOrderDialog(
          imageUrl: item.imageUrl,
          nombre: item.nombre,
          variante: item.variante,
          priceLabel: '\$${item.price.toStringAsFixed(2)}',
          pricePerKilo: item.price,
          initialKilos: item.quantity,
          stock: item.stock,
          allowByPiece: item.permitePorPieza,
          avgPieceKg: item.avgPieceKg,
          onConfirmPieces: (pieces) {
            Navigator.of(ctx).pop();
            cartProvider.setItem(
              item.productId,
              item.nombre,
              item.price,
              item.imageUrl,
              0,
              isBulk: true,
              stock: item.stock,
              typeSpecific: item.typeSpecific,
              variante: item.variante,
              variantKey: item.variantKey,
              variantName: item.variantName,
              pieces: pieces.toDouble(),
              pricePending: true,
              fracciones: item.fracciones,
              fraccionUnidad: item.fraccionUnidad,
              permitePorPieza: item.permitePorPieza,
              avgPieceKg: item.avgPieceKg,
            );
          },
          onConfirm: (kilos) {
            Navigator.of(ctx).pop();
            cartProvider.setItem(
              item.productId,
              item.nombre,
              item.price,
              item.imageUrl,
              kilos,
              isBulk: item.isBulk,
              stock: item.stock,
              typeSpecific: item.typeSpecific,
              variante: item.variante,
              variantKey: item.variantKey,
              variantName: item.variantName,
              fracciones: item.fracciones,
              fraccionUnidad: item.fraccionUnidad,
              permitePorPieza: item.permitePorPieza,
              avgPieceKg: item.avgPieceKg,
            );
          },
        ),
      ),
    );
  }

  /// Fracciones: se reabre su propio selector de tamaño y cantidad.
  Future<void> _editFractionLine(
      BuildContext context, CartProvider cartProvider, CartItem item) async {
    final chosen = await pickFraction(
      context: context,
      productName: item.nombre,
      variante: item.variante,
      imageUrl: item.imageUrl,
      fractions: item.fracciones,
      unitPrice: item.price,
      stock: item.stock,
      unit: item.fraccionUnidad,
    );
    if (chosen == null) return;
    cartProvider.setItem(
      item.productId,
      item.nombre,
      item.price,
      item.imageUrl,
      chosen,
      isBulk: true,
      stock: item.stock,
      typeSpecific: item.typeSpecific,
      variante: item.variante,
      variantKey: item.variantKey,
      variantName: item.variantName,
      fracciones: item.fracciones,
      fraccionUnidad: item.fraccionUnidad,
      permitePorPieza: item.permitePorPieza,
      avgPieceKg: item.avgPieceKg,
    );
  }

  /// Un solo lugar decide qué hace + o − en el carrito, para que un producto
  /// por fracciones no acabe abriendo el diálogo de kilos ni sumando de uno.
  ///
  /// La forma de venta se lee del PRODUCTO, no de la línea: un carrito guardado
  /// antes de que existieran las fracciones no la trae, y ahí volveríamos a
  /// abrir el diálogo equivocado. Si la lectura falla, se usa lo que traiga la
  /// línea.
  Future<void> _editCartLine(
      BuildContext context, CartProvider cartProvider, CartItem item) async {
    List<double> fracciones = item.fracciones;
    String unidad = item.fraccionUnidad;
    bool porPieza = item.permitePorPieza;
    bool bulk = item.isBulk;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('products')
          .doc(item.productId)
          .get();
      final data = doc.data();
      if (data != null) {
        fracciones = productFractions(data);
        unidad = fractionUnit(data);
        porPieza = data['permite_por_pieza'] == true;
        bulk = data['bulk'] == true;
      }
    } catch (_) {
      // Sin conexión se queda con lo que la línea ya sabía.
    }
    if (!context.mounted) return;

    final resolved = CartItem(
      nombre: item.nombre,
      price: item.price,
      quantity: item.quantity,
      imageUrl: item.imageUrl,
      objectID: item.objectID,
      isBulk: bulk,
      stock: item.stock,
      typeSpecific: item.typeSpecific,
      variante: item.variante,
      brand: item.brand,
      productId: item.productId,
      variantKey: item.variantKey,
      variantName: item.variantName,
      pieces: item.pieces,
      pricePending: item.pricePending,
      fracciones: fracciones,
      fraccionUnidad: unidad,
      permitePorPieza: porPieza,
      avgPieceKg: item.avgPieceKg,
    );

    if (fracciones.isNotEmpty) {
      await _editFractionLine(context, cartProvider, resolved);
    } else if (bulk || porPieza || item.pricePending) {
      if (!context.mounted) return;
      _showBulkOrderDialog(context, cartProvider, resolved);
    } else {
      cartProvider.addItem(
        item.objectID,
        item.nombre,
        item.price,
        item.imageUrl,
        quantity: 1,
        isBulk: item.isBulk,
        stock: item.stock,
        typeSpecific: item.typeSpecific,
        variante: item.variante,
      );
    }
  }
}
