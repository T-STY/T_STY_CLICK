import 'dart:async';
import 'dart:ui';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdv2/screens/modules/providers/search_provider.dart';
import 'package:pdv2/services/scale_service.dart';
import 'package:provider/provider.dart';
import 'package:pdv2/main.dart';
import 'dialogs/credit_scan.dart';
import 'providers/cart_provider.dart';
import 'cart/cart_item_tile.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CartPanel extends StatefulWidget {
// Make the GlobalKey static but not final
  static GlobalKey<CartPanelState> globalKey = GlobalKey<CartPanelState>();

// Use a regular const constructor
  const CartPanel({super.key});

  @override
  CartPanelState createState() => CartPanelState();
}

class CartPanelState extends State<CartPanel> {
  final List<String> _romanNumerals = const ['I', 'II', 'III'];
  final ScrollController _scrollController = ScrollController();
  int _currentCartIndex = 0;
  final FocusNode _barcodeInputFocusNode = FocusNode();
  String _scannedBarcode = '';
  Timer? _barcodeInputTimer;
  bool _processingBarcode = false;

// Track when a text field has focus to allow manual input
  bool _isEditingText = false;

// FIX: Track if a dialog is open to pause the scanner logic
  bool _isShowingDialog = false;

// Flag to ensure keyboard handler registration
  bool _keyboardHandlerRegistered = false;

  @override
  void initState() {
    super.initState();
// Listen for focus changes to know when a text field is active
    FocusManager.instance.addListener(_handleFocusChange);
    _handleFocusChange();

    ServicesBinding.instance.keyboard.addHandler(_handleKeyEvent);
    _keyboardHandlerRegistered = true;

// Schedule this to happen after the build is complete
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      Provider.of<MultiCartProvider>(context, listen: false)
          .setCurrentCartIndex(0);

// Request focus for the barcode input (for visual cues)
      _barcodeInputFocusNode.requestFocus();

      if (kDebugMode) {
        print('Setting up barcode scanner focus');
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _barcodeInputFocusNode.dispose();
    _barcodeInputTimer?.cancel();
    FocusManager.instance.removeListener(_handleFocusChange);
    if (_keyboardHandlerRegistered) {
      ServicesBinding.instance.keyboard.removeHandler(_handleKeyEvent);
      _keyboardHandlerRegistered = false;
    }
    super.dispose();
  }

  void _switchCart(int index) {
    setState(() {
      _currentCartIndex = index;
    });
// Update the current cart index in MultiCartProvider
    Provider.of<MultiCartProvider>(context, listen: false)
        .setCurrentCartIndex(index);

// Re-focus the barcode scanner when switching carts
    _barcodeInputFocusNode.requestFocus();
  }

// Calculate total unique items (counting bulk items as 1)
  int _calculateUniqueItemCount(CartProvider cart) {
    return cart.items.values.length;
  }

  void scrollToTop() {
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.minScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  void _handleFocusChange() {
    final focused = FocusManager.instance.primaryFocus;

// FIX: Do not check for EditableText.
// If the focused node is NOT our scanner node (and is not null),
// then the user is focused on a text field or another interactive widget.
    if (focused != null && focused != _barcodeInputFocusNode) {
      _isEditingText = true;
    } else {
      _isEditingText = false;
    }
  }

  void requestBarcodeFocus() {
    _isEditingText = false;
    _barcodeInputFocusNode.requestFocus();
  }

// FIX: Updated logic to match TruckScreen
  bool _handleKeyEvent(KeyEvent event) {
// 1. If we are in a dialog (like payment/rewards) or editing a text field,
// let the keys pass through normally.
    if (_isShowingDialog || _isEditingText) return false;

// 2. We only care about KeyDown
    if (event is! KeyDownEvent) return false;

    final logicalKey = event.logicalKey;

// 3. Handle ENTER. Crucial: Return TRUE to stop button clicks.
    if (logicalKey == LogicalKeyboardKey.enter ||
        logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (_scannedBarcode.isNotEmpty) {
// Cancel any pending timer and process immediately
        _barcodeInputTimer?.cancel();
        _processBarcode();
      }
      return true; // STOP PROPAGATION
    }

// 4. Handle Characters
    final character = event.character;
    if (character != null &&
        character.isNotEmpty &&
        RegExp(r'^[\w\d]$').hasMatch(character)) {
      _scannedBarcode += character;

      _barcodeInputTimer?.cancel();
      _barcodeInputTimer = Timer(const Duration(milliseconds: 300), () {
        _processBarcode();
      });

      return true; // STOP PROPAGATION
    }

// Swallow other keys to prevent unintended actions while on main screen
    return true;
  }

  Future<void> _processBarcode() async {
// Copy local to safe string and clear global immediate to prevent double firing
    String barcodeToProcess = _scannedBarcode;
    _scannedBarcode = '';

    if (barcodeToProcess.isEmpty || !mounted) return;

    final cleanBarcode = barcodeToProcess.trim();

    if (kDebugMode) {
      print('Cleaned barcode: "$cleanBarcode"');
    }

    if (cleanBarcode.isEmpty) return;

    setState(() {
      _processingBarcode = true;
    });

    try {
      final multiCartProvider =
          Provider.of<MultiCartProvider>(context, listen: false);
      final currentCart = multiCartProvider.getCart(_currentCartIndex);

      await currentCart.addProductByBarcode(cleanBarcode);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error procesando código de barras: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _processingBarcode = false;
        });
        _barcodeInputFocusNode.requestFocus();
      }
    }
  }

// ... (Rewards dialog remains unchanged)
  void _showRewardsDialog(BuildContext context, CartProvider cart) async {
    // PAUSE SCANNER
    _isShowingDialog = true;

    final TextEditingController nameController = TextEditingController();
    final TextEditingController cardNumberController = TextEditingController();
    final TextEditingController cvvController = TextEditingController();
    final TextEditingController partialPointsController =
    TextEditingController();

    bool isSearching = false;
    bool userFound = false;
    bool cvvVerified = false;
    // FIX: Changed from int to double to support decimals and match provider types
    double userPoints = 0.0;
    bool useAllPoints = true;
    double pointsToUse = 0.0;
    String foundCardNumber = '';
    String foundCardHolderName = '';
    String? errorMessage;
    String? foundCvvCode;
    String? customerSince;
    DocumentReference? rewardsDocRef;

    if (cart.rewardsCardNumber != null) {
      foundCardNumber = cart.rewardsCardNumber!;
      foundCardHolderName = cart.rewardsCardHolderName!;
      // FIX: Ensure this is treated as a double
      userPoints = cart.rewardsPointsAvailable.toDouble();
      cvvVerified = cart.rewardsCvvVerified;
      userFound = true;
    }

    await showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: StatefulBuilder(
          builder: (dialogContext, setState) {
            return AlertDialog(
              title: Row(
                children: [
                  const Text(
                    'Buscar Monedero',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Carrito #${_currentCartIndex + 1}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: MediaQuery.of(dialogContext).size.width * 0.4,
                height: 450,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!userFound) ...[
                        TextField(
                          controller: nameController,
                          decoration: const InputDecoration(
                            labelText: 'Nombre de Tarjeta Habiente',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: cardNumberController,
                          decoration: const InputDecoration(
                            labelText: 'Numero de Telefono',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                      if (isSearching)
                        const Center(
                          child: CircularProgressIndicator(),
                        )
                      else if (userFound) ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Monedero Encontrado!',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Tarjeta Habiente: $foundCardHolderName',
                                style: const TextStyle(
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                'Numero de Tarjeta: $foundCardNumber',
                                style: const TextStyle(
                                  fontSize: 14,
                                ),
                              ),
                              if (customerSince != null)
                                Text(
                                  'Cliente desde: $customerSince',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey,
                                  ),
                                ),
                              const SizedBox(height: 8),
                              Text(
                                'Saldo Disponible: ${cart.rewardsRawBalance.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (!cvvVerified) ...[
                                const SizedBox(height: 16),
                                const Text(
                                  'Ingrese CVV para utilizar Monedero:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: cvvController,
                                        decoration: const InputDecoration(
                                          labelText: 'CVV',
                                          border: OutlineInputBorder(),
                                        ),
                                        keyboardType: TextInputType.number,
                                        obscureText: true,
                                        obscuringCharacter: '•',
                                        maxLength: 4,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    ElevatedButton(
                                      onPressed: () {
                                        final enteredCvv =
                                        cvvController.text.trim();
                                        final cvvIsValid =
                                            foundCvvCode == enteredCvv;

                                        setState(() {
                                          cvvVerified = cvvIsValid;
                                          errorMessage = null;

                                          if (cvvVerified) {
                                            // FIX: Use 100.0 to maintain double type in min()
                                            final maxPointsUsable = min(
                                                userPoints,
                                                (cart.totalAmount * 100.0));
                                            pointsToUse = maxPointsUsable;
                                            partialPointsController.text =
                                                pointsToUse.toStringAsFixed(2);

                                            cart.verifyCvv(true);
                                          }
                                        });
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blue,
                                        foregroundColor: Colors.white,
                                      ),
                                      child: const Text('Verificar'),
                                    ),
                                  ],
                                ),
                              ],
                              if (cvvVerified) ...[
                                const SizedBox(height: 16),
                                const Text(
                                  'Utizilar saldo en Monedero?',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: RadioListTile<bool>(
                                        title: const Text(
                                            'Utilizar saldo disponible'),
                                        value: true,
                                        groupValue: useAllPoints,
                                        onChanged: (value) {
                                          setState(() {
                                            useAllPoints = value!;
                                            if (useAllPoints) {
                                              // FIX: Ensure double math
                                              final maxPointsUsable = min(
                                                  userPoints,
                                                  (cart.totalAmount * 100.0));
                                              pointsToUse = maxPointsUsable;
                                              partialPointsController.text =
                                                  pointsToUse.toStringAsFixed(2);
                                            }
                                          });
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                Row(
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: RadioListTile<bool>(
                                        title: const Text(
                                            'Utilizar monto parcial'),
                                        value: false,
                                        groupValue: useAllPoints,
                                        onChanged: (value) {
                                          setState(() {
                                            useAllPoints = value!;
                                          });
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                if (!useAllPoints)
                                  TextField(
                                    controller: partialPointsController,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: InputDecoration(
                                      labelText:
                                      'Saldo a Utilizar (Max: ${userPoints.toStringAsFixed(2)})',
                                      border: const OutlineInputBorder(),
                                    ),
                                    onChanged: (value) {
                                      // FIX: Parse as double
                                      double? enteredPoints = double.tryParse(value);
                                      if (enteredPoints != null) {
                                        setState(() {
                                          final maxPointsUsable = min(
                                              userPoints,
                                              (cart.totalAmount * 100.0));
                                          pointsToUse = min(
                                              enteredPoints, maxPointsUsable);
                                        });
                                      }
                                    },
                                  ),
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Row(
                                    children: [
                                      Icon(Icons.info_outline,
                                          color: Colors.blue),
                                      SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Cada 100 puntos equivale a \$1. Los puntos se redondean hacia abajo para cálculos.',
                                          style: TextStyle(
                                            color: Colors.blue,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      if (errorMessage != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red),
                          ),
                          child: Text(
                            errorMessage!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Cancelar'),
                ),
                if (!userFound)
                  ElevatedButton.icon(
                    icon: const Icon(Icons.search),
                    label: const Text('Buscar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () async {
                      setState(() {
                        errorMessage = null;
                        isSearching = true;
                      });

                      try {
                        final enteredName =
                        nameController.text.trim().toUpperCase();
                        final enteredCardNumber =
                        cardNumberController.text.trim();
                        final formattedCardNumber = enteredCardNumber.isNotEmpty
                            ? "T_STY-$enteredCardNumber"
                            : "";

                        QuerySnapshot queryResults;

                        if (enteredName.isNotEmpty &&
                            formattedCardNumber.isNotEmpty) {
                          queryResults = await FirebaseFirestore.instance
                              .collection('rewards')
                              .where('cardHolderName', isEqualTo: enteredName)
                              .where('cardNumber',
                              isEqualTo: formattedCardNumber)
                              .limit(1)
                              .get();
                        } else if (enteredName.isNotEmpty) {
                          queryResults = await FirebaseFirestore.instance
                              .collection('rewards')
                              .where('cardHolderName', isEqualTo: enteredName)
                              .limit(1)
                              .get();
                        } else if (formattedCardNumber.isNotEmpty) {
                          queryResults = await FirebaseFirestore.instance
                              .collection('rewards')
                              .where('cardNumber',
                              isEqualTo: formattedCardNumber)
                              .limit(1)
                              .get();
                        } else {
                          setState(() {
                            isSearching = false;
                            errorMessage =
                            "Porfavor ingrese un numero para realizar busqueda.";
                          });
                          return;
                        }

                        if (!mounted) return;

                        if (queryResults.docs.isNotEmpty) {
                          final rewardsDoc = queryResults.docs.first;
                          final rewardsData =
                          rewardsDoc.data() as Map<String, dynamic>;

                          setState(() {
                            isSearching = false;
                            userFound = true;
                            rewardsDocRef = rewardsDoc.reference;

                            foundCardHolderName =
                                rewardsData['cardHolderName'] ?? '';
                            foundCardNumber = rewardsData['cardNumber'] ?? '';
                            customerSince = rewardsData['customerSince'] ?? '';
                            foundCvvCode = rewardsData['cvvCode'] ?? '';

                            double rawSaldo = 0.0;
                            var saldoValue = rewardsData['saldo'];
                            // FIX: Safely cast any number type from Firestore to double
                            if (saldoValue is num) {
                              rawSaldo = saldoValue.toDouble();
                              userPoints = saldoValue.toDouble();
                            } else {
                              userPoints = 0.0;
                              rawSaldo = 0.0;
                            }

                            cart.setRewardsInfo(
                                foundCardNumber,
                                foundCardHolderName,
                                userPoints, // Now passes double
                                rewardsDocRef!,
                                foundCvvCode,
                                rawSaldo);
                          });
                        } else {
                          setState(() {
                            isSearching = false;
                            errorMessage =
                            "No existe Monedero con la informacion proporcionada.";
                          });
                        }
                      } catch (e) {
                        if (mounted) {
                          setState(() {
                            isSearching = false;
                            errorMessage =
                            "Un error ocurrio durante la busqueda: $e";
                          });
                        }
                      }
                    },
                  )
                else if (cvvVerified)
                  ElevatedButton.icon(
                    icon: const Icon(Icons.redeem),
                    label: const Text('Aplicar Puntos'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () async {
                      try {
                        // FIX: Ensure pointsToApply is double
                        final double pointsToApply = useAllPoints
                            ? min(userPoints, (cart.totalAmount * 100.0))
                            : pointsToUse;

                        if (pointsToApply <= 0) {
                          setState(() {
                            errorMessage =
                            "No se puede aplicar menos de 1 punto.";
                          });
                          return;
                        }

                        // This will now pass a double to your provider
                        cart.setRewardsPointsToUse(pointsToApply);
                        final localContext = dialogContext;

                        Future.delayed(const Duration(milliseconds: 1500), () {
                          if (mounted) {
                            Navigator.of(localContext).pop();
                          }
                        });
                      } catch (e) {
                        if (mounted) {
                          setState(() {
                            errorMessage = "Un error ocurrio: $e";
                          });
                        }
                      }
                    },
                  ),
              ],
            );
          },
        ),
      ),
    );

    // RESUME SCANNER
    _isShowingDialog = false;
    _barcodeInputFocusNode.requestFocus();
  }

// --- Helper Widget for Payment Buttons ---
  Widget _buildPaymentOption({
    required String label,
    required IconData icon,
    required String value,
    required String groupValue,
    required Color color,
    required VoidCallback onTap,
  }) {
    final bool isSelected = value == groupValue;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade300,
            width: 2,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withOpacity(0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  )
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 32,
              color: isSelected ? Colors.white : color,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: isSelected ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCheckoutDialog(BuildContext context, CartProvider cart) async {
// PAUSE SCANNER
    _isShowingDialog = true;

// --- NEW: State variable to track processing status ---
    bool isProcessing = false;

    final now = DateTime.now();
    final date = "${now.day}/${now.month}/${now.year}";
    final time =
        "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
    String selectedPayment = '';
    bool showMixedPaymentInputs = false;
    final cashAmountController = TextEditingController();
    final cardAmountController = TextEditingController();

// Variables for Cash helper
    final cashReceivedController = TextEditingController();
    double changeAmount = 0.0;

    await showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (context) => StatefulBuilder(
        builder: (dialogContext, setState) => BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Container(
              width: MediaQuery.of(dialogContext).size.width * 0.7,
              height: MediaQuery.of(dialogContext).size.height * 0.85,
              padding: const EdgeInsets.all(24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
// LEFT SIDE: Receipt Summary
                  Expanded(
                    flex: 3,
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Center(
                            child: Text(
                              'T_STY',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Center(
                            child: Text(
                              '$date - $time',
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                          const Divider(height: 32),
                          const Text(
                            'Resumen de Venta',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Expanded(
                            child: SingleChildScrollView(
                              child: Column(
                                children: cart.items.values.map((item) {
                                  return Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 4),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          flex: 2,
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                item.name,
                                                style: const TextStyle(
                                                    fontSize: 14,
                                                    fontWeight:
                                                        FontWeight.w500),
                                              ),
// Display Variant and Type Specific
                                              if (item.variante != null &&
                                                  item.variante!.isNotEmpty)
                                                Text(
                                                  item.variante!,
                                                  style: const TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.grey),
                                                ),
                                              if (item.typeSpecific != null &&
                                                  item.typeSpecific!.isNotEmpty)
                                                Text(
                                                  item.typeSpecific!,
                                                  style: const TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.grey),
                                                ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '${item.quantity}x',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '\$${(item.price * item.quantity).toStringAsFixed(2)}',
                                          style: const TextStyle(fontSize: 14),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                          const Divider(height: 32),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Subtotal:'),
                              Text('\$${cart.totalAmount.toStringAsFixed(2)}'),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (cart.discountAmount > 0)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Descuento:'),
                                Text(
                                    '-\$${cart.discountAmount.toStringAsFixed(2)}',
                                    style: const TextStyle(color: Colors.red)),
                              ],
                            ),
                          if (cart.discountAmount > 0)
                            const SizedBox(height: 8),
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('IVA:'),
                              Text('\$0.00'),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Total:',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '\$${cart.totalAmountAfterDiscount.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),

// RIGHT SIDE: Payment Method
                  Expanded(
                    flex: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Eliga Metodo de Pago',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 24),

// UPDATED BUTTON GRID
                        GridView.count(
                          crossAxisCount: 2,
                          shrinkWrap: true,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 2.2,
                          physics: const NeverScrollableScrollPhysics(),
                          children: [
                            _buildPaymentOption(
                              label: 'Efectivo',
                              icon: Icons.payments_outlined,
                              value: 'cash',
                              groupValue: selectedPayment,
                              color: Colors.green,
                              onTap: () {
                                setState(() {
                                  selectedPayment = 'cash';
                                  showMixedPaymentInputs = false;
                                  changeAmount = 0.0;
                                  cashReceivedController.clear();
                                });
                              },
                            ),
                            _buildPaymentOption(
                              label: 'Tarjeta',
                              icon: Icons.credit_card,
                              value: 'card',
                              groupValue: selectedPayment,
                              color: Colors.blue,
                              onTap: () {
                                setState(() {
                                  selectedPayment = 'card';
                                  showMixedPaymentInputs = false;
                                });
                              },
                            ),
                            _buildPaymentOption(
                              label: 'Crédito',
                              icon: Icons.account_balance_wallet_outlined,
                              value: 'credit',
                              groupValue: selectedPayment,
                              color: Colors.purple,
                              onTap: () {
                                setState(() {
                                  selectedPayment = 'credit';
                                  showMixedPaymentInputs = false;
                                });

                                showDialog(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (context) => CreditScanDialog(
                                    cart: cart,
                                    onComplete: (success) {
                                      if (success) {
                                        Navigator.pop(dialogContext);
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                                'Venta a crédito completada exitosamente!'),
                                            backgroundColor: Colors.green,
                                          ),
                                        );
                                      }
                                    },
                                  ),
                                );
                              },
                            ),
                            _buildPaymentOption(
                              label: 'Mixto',
                              icon: Icons.call_split,
                              value: 'mixed',
                              groupValue: selectedPayment,
                              color: Colors.orange,
                              onTap: () {
                                setState(() {
                                  selectedPayment = 'mixed';
                                  showMixedPaymentInputs = true;
                                });
                              },
                            ),
                          ],
                        ),

// --- CASH HELPER UI ---
                        if (selectedPayment == 'cash') ...[
                          const SizedBox(height: 24),
                          const Text("Pago en Efectivo",
                              style: TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 16)),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: cashReceivedController,
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold),
                                  decoration: InputDecoration(
                                    labelText: 'Monto Recibido',
                                    prefixText: '\$',
                                    filled: true,
                                    fillColor: Colors.grey[50],
                                    border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                  ),
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  onChanged: (value) {
                                    setState(() {
                                      double received =
                                          double.tryParse(value) ?? 0.0;
                                      if (received >=
                                          cart.totalAmountAfterDiscount) {
                                        changeAmount = received -
                                            cart.totalAmountAfterDiscount;
                                      } else {
                                        changeAmount = 0.0;
                                      }
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Container(
                                  height: 60,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color: Colors.green.withOpacity(0.3)),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('CAMBIO',
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.green[800],
                                              fontWeight: FontWeight.bold)),
                                      Text(
                                        '\$${changeAmount.toStringAsFixed(2)}',
                                        style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green[800],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8.0,
                            runSpacing: 8.0,
                            children: [
                              ActionChip(
                                label: const Text('Exacto'),
                                backgroundColor: Colors.blue.withOpacity(0.1),
                                labelStyle: const TextStyle(
                                    color: Colors.blue,
                                    fontWeight: FontWeight.bold),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 8, horizontal: 4),
                                onPressed: () {
                                  setState(() {
                                    cashReceivedController.text = cart
                                        .totalAmountAfterDiscount
                                        .toStringAsFixed(2);
                                    changeAmount = 0.0;
                                  });
                                },
                              ),
                              for (var amount in [20, 50, 100, 200, 500, 1000])
                                if (amount >= cart.totalAmountAfterDiscount)
                                  ActionChip(
                                    label: Text('\$$amount'),
                                    onPressed: () {
                                      setState(() {
                                        cashReceivedController.text =
                                            amount.toString();
                                        changeAmount = amount -
                                            cart.totalAmountAfterDiscount;
                                      });
                                    },
                                  ),
                            ],
                          ),
                        ],

// --- MIXED INPUTS ---
                        if (showMixedPaymentInputs) ...[
                          const SizedBox(height: 24),
                          const Text("Pago Mixto",
                              style: TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 16)),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: cashAmountController,
                                  decoration: InputDecoration(
                                    labelText: 'Efectivo',
                                    prefixText: '\$',
                                    filled: true,
                                    fillColor: Colors.grey[50],
                                    border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                  ),
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  onChanged: (value) {
                                    final cashAmount =
                                        double.tryParse(value) ?? 0.0;
                                    final remainingAmount =
                                        cart.totalAmountAfterDiscount -
                                            cashAmount;
                                    cardAmountController.text =
                                        remainingAmount > 0
                                            ? remainingAmount.toStringAsFixed(2)
                                            : '0.00';
                                  },
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: TextField(
                                  controller: cardAmountController,
                                  decoration: InputDecoration(
                                    labelText: 'Tarjeta',
                                    prefixText: '\$',
                                    filled: true,
                                    fillColor: Colors.grey[50],
                                    border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                  ),
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  onChanged: (value) {
                                    final cardAmount =
                                        double.tryParse(value) ?? 0.0;
                                    final remainingAmount =
                                        cart.totalAmountAfterDiscount -
                                            cardAmount;
                                    cashAmountController.text =
                                        remainingAmount > 0
                                            ? remainingAmount.toStringAsFixed(2)
                                            : '0.00';
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],

                        const Spacer(),
                        const Divider(),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(dialogContext),
                                style: OutlinedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 18),
                                  foregroundColor: Colors.red,
                                  side: const BorderSide(color: Colors.red),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                                child: const Text('Cancelar',
                                    style: TextStyle(fontSize: 16)),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 2,
                              child: ElevatedButton(
// --- MODIFIED: CHECK PROCESSING STATE ---
                                onPressed: (selectedPayment.isEmpty ||
                                        isProcessing)
                                    ? null
                                    : () async {
                                        if (selectedPayment == 'credit') {
                                          Navigator.pop(dialogContext);
                                          return;
                                        }

// --- MODIFIED: SET PROCESSING TO TRUE ---
                                        setState(() {
                                          isProcessing = true;
                                        });

                                        final localContext = dialogContext;

                                  try {
                                    final ticketsRef = FirebaseFirestore.instance
                                        .collection('cortes')
                                        .doc(GlobalKeys.currentCorteId)
                                        .collection('tickets');

                                    // 1. Generate the Document Reference BEFORE the transaction
                                    final newTicketRef = ticketsRef.doc();

                                    final ticketData = {
                                      'timestamp': FieldValue.serverTimestamp(),
                                      'employeeName': GlobalKeys.currentEmployeeName,
                                      'items': cart.items.values.map((item) => {
                                        'id': item.id,
                                        'name': item.name,
                                        'price': item.price,
                                        'cost': item.cost,
                                        'quantity': item.quantity,
                                        'total': item.total,
                                        'totalCost': item.totalCost,
                                        'isBulk': item.isBulk,
                                        'variante': item.variante,
                                        'type_specific': item.typeSpecific,
                                      }).toList(),
                                      'subtotal': cart.totalAmount,
                                      'totalCost': cart.totalCost,
                                      'profit': cart.totalAmount - cart.totalCost,
                                      'profitMargin': cart.totalAmount > 0
                                          ? ((cart.totalAmount - cart.totalCost) / cart.totalAmount * 100)
                                          : 0,
                                      'discount': cart.discountAmount,
                                      'total': cart.totalAmountAfterDiscount,
                                      'profitAfterDiscount': cart.totalAmountAfterDiscount - cart.totalCost,
                                      'itemCount': cart.itemCount,

                                      'appliedPromotions': cart.appliedPromosList,
                                      'promoDiscount': cart.promoDiscount,

                                    };

                                    switch (selectedPayment) {
                                      case 'cash':
                                        ticketData['cash'] = cart.totalAmountAfterDiscount;
                                        break;
                                      case 'card':
                                        ticketData['card'] = cart.totalAmountAfterDiscount;
                                        break;
                                      case 'mixed':
                                        final cashAmount = double.tryParse(cashAmountController.text) ?? 0.0;
                                        final cardAmount = double.tryParse(cardAmountController.text) ?? 0.0;

                                        if ((cashAmount + cardAmount).toStringAsFixed(2) != cart.totalAmountAfterDiscount.toStringAsFixed(2)) {
                                          ScaffoldMessenger.of(localContext).showSnackBar(
                                            SnackBar(
                                              content: Text('Las cantidades deben sumar el total: \$${cart.totalAmountAfterDiscount.toStringAsFixed(2)}'),
                                              backgroundColor: Colors.red,
                                            ),
                                          );
                                          setState(() { isProcessing = false; });
                                          return;
                                        }
                                        ticketData['cash'] = cashAmount;
                                        ticketData['card'] = cardAmount;
                                        break;
                                    }

                                    if (cart.rewardsCardNumber != null) {
                                      ticketData['rewardsInfo'] = {
                                        'cardNumber': cart.rewardsCardNumber,
                                        'cardHolderName': cart.rewardsCardHolderName,
                                        'pointsUsed': cart.rewardsPointsToUse,
                                        'pointsEarned': cart.rewardsPointsToUse > 0
                                            ? 0
                                            : (cart.totalAmountAfterDiscount * 0.01).toInt(),
                                      };
                                    }

                                    // --- ATOMIC TRANSACTION BEGINS HERE ---
                                    await FirebaseFirestore.instance.runTransaction((transaction) async {
                                      // A. READ ALL STOCKS FIRST (Required by Firestore)
                                      Map<String, DocumentSnapshot> productDocs = {};
                                      for (final item in cart.items.values) {
                                        final productRef = FirebaseFirestore.instance.collection('products').doc(item.id);
                                        final doc = await transaction.get(productRef);
                                        if (!doc.exists) throw Exception('Producto no encontrado: ${item.name}');
                                        productDocs[item.id] = doc;
                                      }

                                      // B. VALIDATE AND DEDUCT STOCK
                                      for (final item in cart.items.values) {
                                        final doc = productDocs[item.id]!;
                                        final productData = doc.data() as Map<String, dynamic>;
                                        final dynamic rawStock = productData['stock'];
                                        final double currentStock = rawStock is int ? rawStock.toDouble() : (rawStock as double? ?? 0.0);

                                        if (currentStock < item.quantity) {
                                          throw Exception('Stock insuficiente para ${item.name}. Disponible: $currentStock');
                                        }
                                        transaction.update(doc.reference, {'stock': currentStock - item.quantity});
                                      }

                                      // C. UPDATE REWARDS (IF APPLICABLE)
                                      if (cart.rewardsDocRef != null) {
                                        if (cart.rewardsPointsToUse > 0) {
                                          transaction.update(cart.rewardsDocRef!, {'saldo': FieldValue.increment(-cart.rewardsPointsToUse)});
                                        } else {
                                          final pointsToAdd = cart.totalAmountAfterDiscount * 0.01;
                                          transaction.update(cart.rewardsDocRef!, {'saldo': FieldValue.increment(pointsToAdd)});
                                        }
                                      }

                                      // D. SAVE THE TICKET
                                      transaction.set(newTicketRef, ticketData);
                                    });
                                    // --- ATOMIC TRANSACTION ENDS HERE ---

                                    cart.clearCart();
                                    Provider.of<SearchProvider>(context, listen: false).clearSearch();

                                    if (!mounted) return;
                                    Navigator.pop(localContext);

                                  } catch (e) {
                                    setState(() {
                                      isProcessing = false;
                                    });
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(localContext).showSnackBar(
                                      SnackBar(
                                        content: Text('Error procesando venta: $e'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                      },
                                style: ElevatedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 18),
                                  backgroundColor: Colors.black,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
// --- MODIFIED: SHOW LOADING INDICATOR ---
                                child: isProcessing
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text(
                                        'FINALIZAR VENTA',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    _isShowingDialog = false;
    _barcodeInputFocusNode.requestFocus();
  }

  void _showClearCartDialog(BuildContext context, CartProvider cart) async {
    _isShowingDialog = true;
    await showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: AlertDialog(
          title: const Text('Limpiar Carrito'),
          content: const Text('Estas seguro de limpiar el carrito?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                cart.clearCart();
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Limpiar'),
            ),
          ],
        ),
      ),
    );
    _isShowingDialog = false;
    _barcodeInputFocusNode.requestFocus();
  }

  void _showBulkOrderDialog(
    BuildContext context,
    CartProvider cart,
    CartItem item,
  ) async {
    _isShowingDialog = true;

    final pesosController = TextEditingController();
    final kilosController = TextEditingController();

// FocusNodes for managing input interactions
    final FocusNode kilosFocusNode = FocusNode();
    final FocusNode pesosFocusNode = FocusNode();

// Pre-fill with current values
    kilosController.text = item.quantity.toStringAsFixed(3);
    pesosController.text = (item.quantity * item.price).toStringAsFixed(2);

// Add listeners to calculate values dynamically
    kilosFocusNode.addListener(() {
      if (!kilosFocusNode.hasFocus) {
        final kilos = double.tryParse(kilosController.text);
        if (kilos != null) {
          final pesos = kilos * item.price;
          pesosController.text = pesos.toStringAsFixed(2);
        }
      }
    });

    pesosFocusNode.addListener(() {
      if (!pesosFocusNode.hasFocus) {
        final pesos = double.tryParse(
            pesosController.text.replaceAll(RegExp(r'[^0-9.]'), ''));
        if (pesos != null && item.price > 0) {
          final kilos = pesos / item.price;
          kilosController.text = kilos.toStringAsFixed(3);
        }
      }
    });

    await showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (context) {
        final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
        final Color bgColor = isDarkMode ? Colors.grey[900]! : Colors.white;
        final Color textColor = isDarkMode ? Colors.white : Colors.black87;
        final Color mutedColor =
            isDarkMode ? Colors.grey[400]! : Colors.grey[600]!;
        final Color inputFill =
            isDarkMode ? Colors.grey[800]! : Colors.grey[50]!;

        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Dialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: Container(
              width: 400,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
// --- Header ---
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.edit_rounded,
                            color: Colors.blue, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Editar Cantidad',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

// --- Product Card ---
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDarkMode ? Colors.black26 : Colors.grey[100],
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDarkMode ? Colors.white10 : Colors.grey[300]!,
                      ),
                    ),
                    child: Row(
                      children: [
// Product Image
                        Container(
                          width: 70,
                          height: 70,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.all(8),
                          child: Image.network(
                            item.imageUrl,
                            fit: BoxFit.contain,
                            errorBuilder: (c, e, s) => Icon(
                                Icons.image_not_supported,
                                color: Colors.grey[300]),
                          ),
                        ),
                        const SizedBox(width: 16),
// Product Details
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.name,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: textColor,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '\$${item.price.toStringAsFixed(2)} / kg',
                                style: TextStyle(
                                  color: Colors.blue,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Disponible: ${item.stock.toStringAsFixed(3)} kg',
                                style: TextStyle(
                                  color: item.stock < 1
                                      ? Colors.orange
                                      : mutedColor,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

// --- Inputs Section ---
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
// Weight Input
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Peso (Kg)",
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: mutedColor)),
                            const SizedBox(height: 8),
                            TextField(
                              controller: kilosController,
                              focusNode: kilosFocusNode,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: textColor),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: inputFill,
                                suffixText: 'kg',
                                suffixIcon: _ScaleReadButton(
                                  onWeightRead: (weight) {
                                    kilosController.text = weight.toStringAsFixed(3);
                                    pesosController.text =
                                        (weight * item.price).toStringAsFixed(2);
                                  },
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 16),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                      color: Colors.blue, width: 2),
                                ),
                              ),
                              onChanged: (value) {
                                final kg = double.tryParse(value);
                                if (kg != null) {
                                  pesosController.text =
                                      (kg * item.price).toStringAsFixed(2);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
// Price Input
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Total (\$)",
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: mutedColor)),
                            const SizedBox(height: 8),
                            TextField(
                              controller: pesosController,
                              focusNode: pesosFocusNode,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: inputFill,
                                prefixText: '\$ ',
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 16),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                      color: Colors.green, width: 2),
                                ),
                              ),
                              onChanged: (value) {
                                final price = double.tryParse(value);
                                if (price != null && item.price > 0) {
                                  kilosController.text =
                                      (price / item.price).toStringAsFixed(3);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

// --- Actions ---
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            foregroundColor: mutedColor,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: () {
                            final quantity =
                                double.tryParse(kilosController.text) ?? 0;

                            if (quantity <= 0) {
                              return; // Invalid quantity
                            }

                            if (quantity > item.stock) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Stock insuficiente para esta cantidad')),
                              );
                              return;
                            }

                            cart.updateQuantity(item.id, quantity);
                            Navigator.pop(context);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Actualizar',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    _isShowingDialog = false;
    _barcodeInputFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final multiCartProvider = Provider.of<MultiCartProvider>(context);
    final currentCart = multiCartProvider.getCart(_currentCartIndex);

    return Focus(
      focusNode: _barcodeInputFocusNode,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 16.0),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                spreadRadius: 2,
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
// Cart Selection Header with Barcode Scanner Indicator
              Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
// Cart Selection tabs
                        Expanded(
                          child: Row(
                            children: List.generate(
                              3, // Always 3 carts
                              (index) => Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 12),
                                  child: GestureDetector(
                                    onTap: () => _switchCart(index),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: _currentCartIndex == index
                                            ? Colors.white
                                            : Colors.grey[800],
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: _currentCartIndex == index
                                              ? Colors.black
                                              : Colors.transparent,
                                        ),
                                      ),
                                      child: Center(
                                        child: Text(
                                          _romanNumerals[index],
                                          style: TextStyle(
                                            color: _currentCartIndex == index
                                                ? Colors.black
                                                : Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 18,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

// Barcode scanner indicator
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _barcodeInputFocusNode.hasFocus
                                ? Colors.green.withOpacity(0.1)
                                : Colors.grey.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _barcodeInputFocusNode.hasFocus
                                  ? Colors.green
                                  : Colors.grey,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.qr_code_scanner,
                                size: 16,
                                color: _barcodeInputFocusNode.hasFocus
                                    ? Colors.green
                                    : Colors.grey,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _processingBarcode
                                    ? 'Procesando...'
                                    : (_barcodeInputFocusNode.hasFocus
                                        ? 'Lector Activo'
                                        : 'Lector Inactivo'),
                                style: TextStyle(
                                  color: _barcodeInputFocusNode.hasFocus
                                      ? Colors.green
                                      : Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

// Cart Items
              Expanded(
                child: ChangeNotifierProvider.value(
                  value: currentCart,
                  child: Consumer<CartProvider>(
                    builder: (context, cart, child) {
                      if (cart.items.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.shopping_basket_outlined,
                                size: 80,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'El carrito esta vacio',
                                style: TextStyle(
                                  color: Colors.black54,
                                  fontSize: 18,
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      return ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: cart.items.length,
                        itemBuilder: (context, index) {
                          final item = cart.items.values.toList()[index];
                          return CartItemTile(
                            key: ValueKey(item.id),
                            item: item,
                            onIncrease: () {
                              if (item.isBulk) {
                                _showBulkOrderDialog(context, cart, item);
                              } else {
                                cart.updateQuantity(
                                  item.id,
                                  item.quantity + 1,
                                );
                              }
                            },
                            onDecrease: () {
                              cart.updateQuantity(
                                item.id,
                                item.quantity - 1,
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ),

// Total and Actions
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                ),
                child: ChangeNotifierProvider.value(
                  value: currentCart,
                  child: Consumer<CartProvider>(
                    builder: (context, cart, child) {
                      return Column(
                        children: [
// Item Counter
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Articulos:',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black,
                                ),
                              ),
                              Row(
                                children: [
                                  Text(
                                    '${_calculateUniqueItemCount(cart)}',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Tooltip(
                                    message: 'Monedero',
                                    child: Container(
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: Colors.orange.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(18),
                                        border:
                                            Border.all(color: Colors.orange),
                                      ),
                                      child: IconButton(
                                        icon: const Icon(Icons.card_giftcard,
                                            color: Colors.orange, size: 20),
                                        onPressed: () =>
                                            _showRewardsDialog(context, cart),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        splashRadius: 24,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

// Divider
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Divider(
                              color: Colors.grey[300],
                              thickness: 1,
                            ),
                          ),
                          const SizedBox(height: 12),

// Subtotal
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Subtotal:',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black),
                              ),
                              Text(
                                '\$${cart.totalAmount.toStringAsFixed(2)}',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),

// --- NEW: DISPLAY APPLIED PROMOTIONS ---
                          if (cart.appliedPromosList.isNotEmpty)
                            ...cart.appliedPromosList.map((promoName) => Padding(
                              padding: const EdgeInsets.only(bottom: 4.0),
                              child: Row(
                                children: [
                                  const Icon(Icons.local_offer, size: 14, color: Colors.orange),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      promoName,
                                      style: TextStyle(fontSize: 12, color: Colors.orange[700], fontWeight: FontWeight.bold),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            )),

// Discount row
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Descuento:',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black),
                              ),
                              Row(
                                children: [
                                  if (cart.rewardsCardNumber != null &&
                                      cart.rewardsPointsToUse > 0)
                                    const Icon(
                                      Icons.card_giftcard,
                                      size: 16,
                                      color: Colors.orange,
                                    ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '\$${cart.discountAmount.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Total:',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black,
                                ),
                              ),
                              Text(
                                '\$${cart.totalAmountAfterDiscount.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: ElevatedButton.icon(
                                  onPressed: cart.items.isEmpty
                                      ? null
                                      : () =>
                                          _showCheckoutDialog(context, cart),
                                  icon: const Icon(Icons.check_circle_outline),
                                  label: const Text('Finalizar'),
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                    backgroundColor: Colors.black,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: cart.items.isEmpty
                                      ? null
                                      : () {
                                          _showClearCartDialog(context, cart);
                                        },
                                  icon: const Icon(Icons.delete_outline),
                                  label: const Text('Limpiar'),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                    foregroundColor: Colors.red,
                                    side: const BorderSide(color: Colors.red),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Button to read weight from Rhino BAR-9 USB scale.
class _ScaleReadButton extends StatefulWidget {
  final ValueChanged<double> onWeightRead;

  const _ScaleReadButton({required this.onWeightRead});

  @override
  State<_ScaleReadButton> createState() => _ScaleReadButtonState();
}

class _ScaleReadButtonState extends State<_ScaleReadButton> {
  bool _isReading = false;

  Future<void> _readScale() async {
    setState(() => _isReading = true);

    try {
      final scale = ScaleService();
      final weight = await scale.readWeight();

      if (weight != null && weight > 0) {
        widget.onWeightRead(weight);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No se pudo leer el peso. Verifica la conexión USB de la báscula.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al leer báscula: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isReading = false);
    }
  }

  /// Long-press: show raw USB device diagnostics from Android UsbManager.
  Future<void> _showUsbDiagnostics() async {
    final scale = ScaleService();
    final devices = await scale.listAllUsbDevices();

    if (!mounted) return;

    final usbClassNames = {
      0: 'Per-Interface',
      2: 'CDC (Serial)',
      3: 'HID',
      7: 'Printer',
      8: 'Mass Storage',
      9: 'Hub',
      255: 'Vendor Specific',
    };

    final interfaceClassNames = {
      2: 'CDC Control',
      3: 'HID',
      7: 'Printer',
      8: 'Mass Storage',
      9: 'Hub',
      10: 'CDC Data',
      255: 'Vendor Specific',
    };

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('USB Devices (${devices.length})'),
        content: SizedBox(
          width: double.maxFinite,
          child: devices.isEmpty
              ? const Text('No USB devices detected by Android.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: devices.length,
                  itemBuilder: (_, i) {
                    final d = devices[i];
                    final interfaces = (d['interfaces'] as List?)
                        ?.map((iface) {
                          final cls = iface['class'] as int? ?? 0;
                          return '  ${interfaceClassNames[cls] ?? "Class $cls"}';
                        })
                        .join('\n') ?? '';
                    final devClass = d['deviceClass'] as int? ?? 0;
                    final vid = (d['vendorId'] as int? ?? 0).toRadixString(16).padLeft(4, '0');
                    final pid = (d['productId'] as int? ?? 0).toRadixString(16).padLeft(4, '0');

                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          '${d['productName'] ?? 'Unknown'}\n'
                          'Manufacturer: ${d['manufacturerName'] ?? 'N/A'}\n'
                          'VID:PID = $vid:$pid\n'
                          'Class: ${usbClassNames[devClass] ?? devClass}\n'
                          'Permission: ${d['hasPermission'] ?? false}\n'
                          'Interfaces:\n$interfaces',
                          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                        ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: _showUsbDiagnostics,
      child: IconButton(
        onPressed: _isReading ? null : _readScale,
        icon: _isReading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.scale, color: Colors.blue, size: 22),
        tooltip: 'Leer peso (mantener para diagnóstico USB)',
      ),
    );
  }
}
