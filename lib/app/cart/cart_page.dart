import 'dart:ui';
// Import for date and time handling
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_defaults.dart';
import '../../constants/app_images.dart';
import '../main.dart';
import '../payment/checkout_page.dart';
import '../payment/payment_done_page.dart'; // Import PaymentDonePage
import 'cart_provider.dart';
import 'components/product_tile_cart.dart';

const double shippingCost = 15.00;

class CartPage extends StatefulWidget {
  const CartPage({super.key});

  @override
  _CartPageState createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  int _index = 0; // 0 for cart view, 1 for checkout view, 2 for payment done view

  // Function to check if current time is within delivery hours (9 AM - 6 PM)
  bool _checkOrderTime() {
    final now = DateTime.now();
    // final localTimeZone = 'America/Mexico_City'; // CST (Guadalajara) - Not used directly but implies context
    final timeZoneAdjusted = now.toLocal();

    final startTime = DateTime(
        timeZoneAdjusted.year, timeZoneAdjusted.month, timeZoneAdjusted.day, 9);
    final endTime = DateTime(
        timeZoneAdjusted.year, timeZoneAdjusted.month, timeZoneAdjusted.day,
        18);

    return timeZoneAdjusted.isAfter(startTime) &&
        timeZoneAdjusted.isBefore(endTime);
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: _index,
      children: [
        // Cart content
        _buildCartContent(context),
        // Checkout content
        CheckoutPage(
          onBack: () {
            setState(() {
              _index = 0; // Switch back to cart view
            });
          },
          onOrderPlaced: () {
            setState(() {
              _index = 2; // Switch to payment done view
            });
          },
        ),
        // Payment Done Page
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

  Widget _buildCartContent(BuildContext context) {
    final bool isOrderTimeValid = _checkOrderTime();
    final String timeNotice = 'Los pedidos solo pueden realizarse entre 9 AM y 6 PM CST.';
    return Container(
      color: Theme
          .of(context)
          .brightness == Brightness.dark
          ? Colors.grey[900]
          : Colors.white,
      child: Column(children: [

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
                    // CRITICAL FIX: ValueKey ensures Flutter tracks the specific item
                    // when the list changes, preventing the "delete bottom item" bug.
                    key: ValueKey(item.objectID),
                    objectId: item.objectID,
                    name: item.nombre,
                    price: item.price,
                    imageUrl: item.imageUrl,
                    quantity: item.quantity,
                    isBulk: item.isBulk,
                    increaseQuantity: () {
                      if (item.isBulk) {
                        _showBulkOrderDialog(context, cartProvider, item);
                      } else {
                        final String productName = item.nombre;
                        final String productImage = item.imageUrl;

                        cartProvider.addItem(
                          item.objectID,
                          productName,
                          item.price,
                          productImage,
                          quantity: 1,
                          isBulk: item.isBulk,
                          stock: item.stock, // Pass stock value
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
            color: Theme
                .of(context)
                .brightness == Brightness.dark
                ? Colors.grey[850]
                : Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(AppDefaults.padding),
              child: Consumer<CartProvider>(
                builder: (context, cartProvider, child) {
                  final double subtotal = cartProvider.totalPrice;
                  final double total = subtotal + shippingCost;

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [

                      /// Shipping Cost
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Envío:',
                            style: Theme
                                .of(context)
                                .textTheme
                                .titleMedium,
                          ),
                          Text(
                            '\$${shippingCost.toStringAsFixed(2)} MXN',
                            style: Theme
                                .of(context)
                                .textTheme
                                .titleMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Divider(
                        color: Theme
                            .of(context)
                            .brightness == Brightness.dark
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
                            style: Theme
                                .of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '\$${total.toStringAsFixed(2)} MXN',
                            style: Theme
                                .of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      /// Time Restriction Notice
                      if (!isOrderTimeValid)
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
                          onPressed: cartProvider.items.isEmpty ||
                              !isOrderTimeValid
                              ? null // Disable the button if no items are in the cart or time is invalid
                              : () {
                            setState(() {
                              _index = 1; // Switch to checkout view
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: AppColors.defaultBlack,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text(
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

  // Pre-fill the dialog with the current cart quantity
  kilosController.text = item.quantity.toStringAsFixed(3);
  pesosController.text =
  '\$${(item.quantity * pricePerKilo).toStringAsFixed(2)}';

  pesosFocusNode.addListener(() {
    if (!pesosFocusNode.hasFocus) {
      final pesos = double.tryParse(
          pesosController.text.replaceAll('\$', '')) ?? 0.0;
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
                    child: Image.network(
                      item.imageUrl,
                      fit: BoxFit.cover,
                      width: 50,
                      height: 50,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.nombre,
                        style:
                        const TextStyle(fontWeight: FontWeight.bold),
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
                final kilos =
                    double.tryParse(kilosController.text) ?? 0.0;

                if (item.objectID.isNotEmpty) {
                  // Replace the quantity in the cart with the new value
                  cartProvider.setItem(
                    item.objectID,
                    item.nombre,
                    item.price,
                    item.imageUrl,
                    kilos, // Pass the quantity in kilograms
                    isBulk: item.isBulk,
                    stock: item.stock, // Pass the isBulk flag here
                  );
                }
                print('Bulk order set: $kilos kg');
              },
              child: const Text('Agregar'),
            ),
          ],
        ),
      );
    },
  );
}