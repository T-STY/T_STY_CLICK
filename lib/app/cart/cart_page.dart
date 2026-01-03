import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../components/shimmer_placeholder.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_defaults.dart';
import '../../constants/app_images.dart';
import '../main.dart';
import '../payment/checkout_page.dart';
import '../payment/payment_done_page.dart';
import 'cart_provider.dart';
import 'components/product_tile_cart.dart';

// Removed fixed shippingCost

class CartPage extends StatefulWidget {
  const CartPage({super.key});

  @override
  _CartPageState createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  int _index = 0; // 0 for cart, 1 for checkout, 2 for payment done

// Valores por defecto (se sobrescribirán con Firebase)
  int _openHour = 9;
  int _closeHour = 18;

// Función para verificar si la tienda está abierta
  bool _checkOrderTime() {
    final now = DateTime.now();
    final timeZoneAdjusted = now.toLocal(); // Asume la hora local del usuario

// Usamos las variables dinámicas _openHour y _closeHour
    final startTime = DateTime(timeZoneAdjusted.year, timeZoneAdjusted.month,
        timeZoneAdjusted.day, _openHour);

    final endTime = DateTime(timeZoneAdjusted.year, timeZoneAdjusted.month,
        timeZoneAdjusted.day, _closeHour);

    return timeZoneAdjusted.isAfter(startTime) &&
        timeZoneAdjusted.isBefore(endTime);
  }

// Función auxiliar para formatear hora
  String _formatHour(int hour) {
    if (hour == 12) return '12 PM';
    if (hour == 0 || hour == 24) return '12 AM';
    if (hour > 12) return '${hour - 12} PM';
    return '$hour AM';
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: _index,
      children: [
// StreamBuilder para escuchar cambios de horario
        StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('settings')
              .doc('store')
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasData && snapshot.data!.exists) {
              final data = snapshot.data!.data() as Map<String, dynamic>;
              _openHour = data['open_hour'] ?? 9;
              _closeHour = data['close_hour'] ?? 18;
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
    final bool isOrderTimeValid = _checkOrderTime();
    final String timeNotice =
        'Los pedidos solo pueden realizarse entre ${_formatHour(_openHour)} y ${_formatHour(_closeHour)}.';

    return Container(
      color: Theme.of(context).brightness == Brightness.dark
          ? Colors.grey[900]
          : Colors.white,
      child: Column(
        children: [
          /// Header
          AppBar(
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
          ),

          /// Cart Items
          Expanded(
            child: Consumer<CartProvider>(
              builder: (context, cartProvider, child) {
                if (cartProvider.items.isEmpty) {
                  return const Center(
                    child: Text('No hay productos en tu carrito'),
                  );
                }
                return ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: cartProvider.items.length,
                  itemBuilder: (context, index) {
                    final item = cartProvider.items.values.toList()[index];
                    return ProductTileCart(
                      key: ValueKey(item.objectID),
                      objectId: item.objectID,
                      name: item.nombre,
                      price: item.price,
                      imageUrl: item.imageUrl,
                      quantity: item.quantity,
                      isBulk: item.isBulk,
                      typeSpecific: item.typeSpecific,
                      variante: item.variante,
                      increaseQuantity: () {
                        if (item.isBulk) {
                          _showBulkOrderDialog(context, cartProvider, item);
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
                      },
                      decreaseQuantity: () {
                        cartProvider.removeItem(
                          item.objectID,
                          isBulk: item.isBulk,
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),

          /// Total and Checkout
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 5, 16, 16),
            child: Card(
              elevation: 4,
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
// Total only includes subtotal for now as shipping is pending
                    final double total = subtotal;

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        /// Shipping Cost
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Envío:',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              'Pendiente a Calcular', // Dynamic display
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

                        /// Total Amount
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

                        /// Time Restriction Notice (Dynamic)
                        if (!isOrderTimeValid && !isLoading)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Text(
                              timeNotice,
                              style: TextStyle(
                                color: Colors.red[700],
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),

                        /// Checkout Button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: (cartProvider.items.isEmpty ||
                                    !isOrderTimeValid ||
                                    isLoading)
                                ? null
                                : () {
                                    setState(() {
                                      _index = 1;
                                    });
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
          const SizedBox(height: 100),
        ],
      ),
    );
  }
}

void _showBulkOrderDialog(
    BuildContext context, CartProvider cartProvider, CartItem item) {
  final pesosController = TextEditingController();
  final kilosController = TextEditingController();
  final FocusNode pesosFocusNode = FocusNode();
  final FocusNode kilosFocusNode = FocusNode();
  final pricePerKilo = item.price;

// Pre-fill the dialog
  kilosController.text = item.quantity.toStringAsFixed(3);
  pesosController.text =
      '\$${(item.quantity * pricePerKilo).toStringAsFixed(2)}';

  pesosFocusNode.addListener(() {
    if (!pesosFocusNode.hasFocus) {
      final pesos =
          double.tryParse(pesosController.text.replaceAll('\$', '')) ?? 0.0;
      if (pricePerKilo != 0.0) {
        final kilos = pesos / pricePerKilo;
        kilosController.text = kilos.toStringAsFixed(3);
        pesosController.text = '\$${pesos.toStringAsFixed(2)}';
      }
    }
  });

  kilosFocusNode.addListener(() {
    if (!kilosFocusNode.hasFocus) {
      final kilos = double.tryParse(kilosController.text) ?? 0.0;
      if (pricePerKilo != 0.0) {
        final pesos = kilos * pricePerKilo;
        pesosController.text = '\$${pesos.toStringAsFixed(2)}';
      }
    }
  });

  showDialog(
    context: context,
    builder: (context) {
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: AlertDialog(
          title: const Center(child: Text("Producto a Granel")),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8.0),
                    child: CachedNetworkImage(
                      imageUrl: item.imageUrl,
                      fit: BoxFit.contain,
                      width: 50,
                      height: 50,
                      placeholder: (context, url) =>
                          const ShimmerPlaceholder(width: 50, height: 50),
                      errorWidget: (context, url, error) =>
                          const Icon(Icons.error),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.nombre,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Precio por Kilo: ${pricePerKilo.toStringAsFixed(2)}',
                        style: const TextStyle(color: Colors.green),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
// Rest of dialog...
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Valor en pesos',
                  style: TextStyle(color: Colors.black),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: pesosController,
                      keyboardType: TextInputType.number,
                      focusNode: pesosFocusNode,
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    flex: 1,
                    child: Text(
                      'MXN',
                      style: TextStyle(color: Colors.black),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Peso en kilo',
                  style: TextStyle(color: Colors.black),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: kilosController,
                      keyboardType: TextInputType.number,
                      focusNode: kilosFocusNode,
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    flex: 1,
                    child: Text(
                      'kg',
                      style: TextStyle(color: Colors.black),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              RichText(
                textAlign: TextAlign.justify,
                text: const TextSpan(
                  style: TextStyle(color: Colors.black),
                  children: [
                    TextSpan(
                      text:
                          "\n*Tenga en cuenta que la cantidad recibida puede variar ligeramente.",
                      style: TextStyle(fontStyle: FontStyle.italic),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                final kilos = double.tryParse(kilosController.text) ?? 0.0;

                if (item.objectID.isNotEmpty) {
                  cartProvider.setItem(
                    item.objectID,
                    item.nombre,
                    item.price,
                    item.imageUrl,
                    kilos,
                    isBulk: item.isBulk,
                    stock: item.stock,
                  );
                }
              },
              child: const Text('Agregar'),
            ),
          ],
        ),
      );
    },
  );
}
