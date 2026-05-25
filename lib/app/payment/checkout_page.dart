import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:slide_to_act_reborn/slide_to_act_reborn.dart';

import '../../components/bottom_fade.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_defaults.dart';
import '../../constants/app_images.dart';
import '../cart/cart_provider.dart';
import '../cart/components/product_tile_cart.dart';
import '../../utils/phone_format.dart';
import '../settings/addresses_section.dart';

import 'components/address_card.dart';
import 'components/payment_method_card.dart';

class CheckoutPage extends StatefulWidget {
  final VoidCallback? onBack;
  final VoidCallback onOrderPlaced;
  const CheckoutPage({
    super.key,
    required this.onBack,
    required this.onOrderPlaced,
  });

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  String _selectedPaymentMethod = 'efectivo';

  String? _selectedAddressId;

  bool _useRewardsBalance = false;

  List<Map<String, dynamic>> _assignedCoupons = [];
  String? _selectedCouponCode;
  final TextEditingController _couponController = TextEditingController();

  Map<String, dynamic> _coloniaPricing = {};

  double _subtotal = 0.0;
  double _deliveryFee = 0.0;
  double _total = 0.0;

  bool _isInstorePickup = false;

  double _rewardsBalance = 0.0;
  double _appliedRewards = 0.0;

  double _discount = 0.0;

  List<Map<String, dynamic>> _addresses = [];

  String _userName = '';
  String _userPhone = '';

  @override
  void initState() {
    super.initState();
    _fetchStorePricing();
    _fetchRewardsCardData();
    _fetchAssignedCoupons();
    _fetchAddresses();
    _fetchUserInfo();
  }

  double _toDouble(dynamic value) {
    if (value is double) {
      return value;
    } else if (value is int) {
      return value.toDouble();
    } else if (value is String) {
      return double.tryParse(value) ?? 0.0;
    } else {
      return 0.0;
    }
  }

  Future<void> _fetchStorePricing() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('store')
          .get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        if (data.containsKey('pricing')) {
          setState(() {
            _coloniaPricing = data['pricing'];
          });
          _calculateDeliveryFee();
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint("Error loading shipping settings: $e");
    }
  }

  void _calculateDeliveryFee() {
    if (_isInstorePickup) {
      setState(() {
        _deliveryFee = 0.0;
      });
      _calculateTotal();
      return;
    }

    if (_selectedAddressId == null || _addresses.isEmpty) {
      setState(() {
        _deliveryFee = 0.0;
      });
      _calculateTotal();
      return;
    }

    final selectedAddress = _addresses.firstWhere(
          (addr) => addr['id'] == _selectedAddressId,
      orElse: () => {},
    );

    if (selectedAddress.isEmpty || !selectedAddress.containsKey('colonia')) {
      setState(() {
        _deliveryFee = 0.0;
      });
      _calculateTotal();
      return;
    }

    String colonia = selectedAddress['colonia'];

    if (_coloniaPricing.containsKey(colonia)) {
      var priceVal = _coloniaPricing[colonia];
      double fee = 0.0;
      if (priceVal is String) {
        fee = double.tryParse(priceVal) ?? 0.0;
      } else if (priceVal is num) {
        fee = priceVal.toDouble();
      }

      setState(() {
        _deliveryFee = fee;
      });
    } else {
      setState(() {
        _deliveryFee = 20.0;
      });
    }
    _calculateTotal();
  }

  Future<void> _fetchRewardsCardData() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    final userCardDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('rewardsCard')
        .doc('cardInfo')
        .get();

    if (userCardDoc.exists) {
      try {
        final result = await FirebaseFunctions.instance
            .httpsCallable('getRewardsBalance')
            .call();
        final data = Map<String, dynamic>.from(result.data as Map);
        if (data['hasWallet'] == true) {
          setState(() {
            _rewardsBalance = _toDouble(data['saldo']);
          });
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Error fetching rewards balance: $e');
      }
    }
  }

  Future<void> _fetchAssignedCoupons() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    final Timestamp now = Timestamp.now();

    try {
      final couponsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('coupons')
          .where('used', isEqualTo: false)
          .where('expiry_date', isGreaterThanOrEqualTo: now)
          .get();

      final validCoupons = couponsSnapshot.docs
          .where((doc) {
        final data = doc.data();
        return data.containsKey('expiry_date') &&
            data['expiry_date'] is Timestamp;
      })
          .map((doc) => {...doc.data(), 'code': doc.id})
          .toList();

      setState(() {
        _assignedCoupons = validCoupons;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('Error fetching coupons: $e');
      if (!mounted) return;
      _showAlertDialog('Error', 'No se pudieron cargar los cupones. Intenta de nuevo.');
    }
  }

  Future<void> _fetchAddresses() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    final addressesSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('addresses')
        .get();

    setState(() {
      _addresses = addressesSnapshot.docs
          .map((doc) => {'id': doc.id, ...doc.data()})
          .toList();

      if (_addresses.isNotEmpty && _selectedAddressId == null) {
        _selectedAddressId = _addresses[0]['id'];
        _calculateDeliveryFee();
      }
    });
  }

  Future<void> _fetchUserInfo() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    final userDoc =
    await FirebaseFirestore.instance.collection('users').doc(userId).get();

    if (userDoc.exists) {
      final userData = userDoc.data();
      setState(() {
        _userName = userData?['userInfo']['name'] ?? 'Usuario';
      });
    }

    final userInfoDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('userInfo')
        .doc('userInfo')
        .get();

    if (userInfoDoc.exists) {
      final userInfo = userInfoDoc.data();
      setState(() {
        _userPhone = userInfo?['phoneNumber'] ?? '';
      });
    }
  }

  bool _isValidPhoneNumber(String input) {
    final cleanPhone = input.trim().replaceAll(RegExp(r'\D'), '');

    if (cleanPhone.length != 10) return false;

    if (RegExp(r'^(\d)\1+$').hasMatch(cleanPhone)) return false;

    if (cleanPhone == '1234567890') return false;
    if (cleanPhone == '0123456789') return false;
    if (cleanPhone == '9876543210') return false;

    return true;
  }

  Future<void> _showPhoneUpdateDialog() async {
    final phoneController = TextEditingController();
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: AlertDialog(
          title: const Text('Agregar Número de Teléfono'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                  'Necesitamos un número de contacto en caso de que no encontremos tu dirección o haya cambios en el pedido. Por favor, agrega un número de teléfono válido para continuar.'),
              const SizedBox(height: 10),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                inputFormatters: [MxPhoneFormatter()],
                decoration: InputDecoration(
                  labelText: 'Número de Teléfono',
                  hintText: '(xxx) xxx - xxxx',
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () async {
                String newPhone =
                    phoneController.text.replaceAll(RegExp(r'\D'), '');

                if (_isValidPhoneNumber(newPhone)) {
                  final userId = FirebaseAuth.instance.currentUser?.uid;
                  if (userId != null) {
                    try {
                      await FirebaseFirestore.instance
                          .collection('users')
                          .doc(userId)
                          .collection('userInfo')
                          .doc('userInfo')
                          .update({'phoneNumber': newPhone});

                      if (!context.mounted) return;
                      setState(() {
                        _userPhone = newPhone;
                      });
                      Navigator.pop(context);
                      _showAlertDialog('Éxito', 'Teléfono actualizado.');
                    } catch (e) {
                      if (!context.mounted) return;
                      Navigator.pop(context);
                      if (kDebugMode) debugPrint('Error updating phone: $e');
                      _showAlertDialog('Error', 'No se pudo actualizar. Intenta de nuevo.');
                    }
                  }
                }
              },
              child:
              const Text('Guardar', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToAddresses() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddressesSection(
          onBack: () => Navigator.pop(context),
        ),
      ),
    ).then((_) {
      _fetchAddresses();
    });
  }

  void _showAlertDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                child: const Text('Aceptar'),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _applyCoupon(String code) async {
    final upper = code.toUpperCase();
    try {
      await FirebaseFunctions.instance
          .httpsCallable('claimCoupon')
          .call(<String, dynamic>{'code': upper});

      await _fetchAssignedCoupons();
      if (!mounted) return;
      setState(() {
        _selectedCouponCode = upper;
        _calculateDiscount();
      });

      _showAlertDialog('Éxito', 'Cupón aplicado exitosamente.');
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      _showAlertDialog('Error', e.message ?? 'No se pudo aplicar el cupón.');
    } catch (_) {
      if (!mounted) return;
      _showAlertDialog('Error', 'No se pudo aplicar el cupón.');
    }
  }

  void _calculateDiscount() {
    if (_selectedCouponCode != null) {
      final couponData = _assignedCoupons.firstWhere(
            (coupon) => coupon['code'] == _selectedCouponCode,
        orElse: () => {},
      );

      if (couponData.isNotEmpty) {
        double percentage = _toDouble(couponData['percentage']);
        double maxDiscount = _toDouble(couponData['max_discount']);
        double discountAmount =
        (_subtotal * percentage / 100).clamp(0, maxDiscount);
        setState(() {
          _discount = discountAmount;
        });
      }
    } else {
      setState(() {
        _discount = 0.0;
      });
    }
  }

  void _calculateTotal() {
    final cartProvider = Provider.of<CartProvider>(context, listen: false);
    double subtotal = cartProvider.totalPriceAfterDiscount;

    _calculateDiscount();

    double total = subtotal - _discount + _deliveryFee;

    double appliedRewards = 0.0;
    if (_useRewardsBalance && _rewardsBalance > 0) {
      if (_rewardsBalance >= total) {
        appliedRewards = total;
        total = 0.0;
      } else {
        appliedRewards = _rewardsBalance;
        total -= _rewardsBalance;
      }
    }

    setState(() {
      _subtotal = subtotal;
      _total = total;
      _appliedRewards = appliedRewards;
    });
  }

  void _placeOrder() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;
    final cartProvider = Provider.of<CartProvider>(context, listen: false);

    if (!_isInstorePickup && _selectedAddressId == null) {
      _showAlertDialog(
          'Error', 'Por favor, selecciona una dirección de entrega.');
      return;
    }

    try {
      await FirebaseFunctions.instance
          .httpsCallable('placeOrder')
          .call(<String, dynamic>{
        'items':
            cartProvider.items.values.map((item) => item.toMap()).toList(),
        'subtotal': _subtotal,
        'addressId': _isInstorePickup ? null : _selectedAddressId,
        'paymentMethod': _selectedPaymentMethod,
        'useRewardsBalance': _useRewardsBalance,
        'isInstorePickup': _isInstorePickup,
        'couponCode': _selectedCouponCode,
      });

      cartProvider.clearCart();
      widget.onOrderPlaced();
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      _showAlertDialog('Error',
          e.message ?? 'No se pudo completar el pedido. Intenta de nuevo.');
    } catch (e) {
      if (!mounted) return;
      if (kDebugMode) debugPrint('Error placing order: $e');
      _showAlertDialog('Error', 'No se pudo completar el pedido. Intenta de nuevo.');
    }
  }

  @override
  void dispose() {
    _couponController.dispose();
    super.dispose();
  }

  Widget _buildOrderReview() {
    final cartProvider = Provider.of<CartProvider>(context);
    if (cartProvider.items.isEmpty) return const SizedBox.shrink();

    final children = <Widget>[
      const Padding(
        padding: EdgeInsets.fromLTRB(16.0, 0, 16.0, 4.0),
        child: Text(
          'Tu Pedido',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
    ];

    Widget tile(String pid, double qty) {
      final item = cartProvider.getItem(pid);
      if (item == null) return const SizedBox.shrink();
      return ProductTileCart(
        objectId: pid,
        name: item.nombre,
        price: item.price,
        imageUrl: item.imageUrl,
        quantity: qty,
        isBulk: item.isBulk,
        typeSpecific: item.typeSpecific,
        variante: item.variante,
        readOnly: true,
      );
    }

    for (final g in cartProvider.groups) {
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 2),
        child: Row(
          children: [
            const Icon(Icons.local_offer, size: 16, color: Colors.orange),
            const SizedBox(width: 6),
            Expanded(
              child: Text(g.name,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.orange[800]),
                  overflow: TextOverflow.ellipsis),
            ),
            if (g.savings > 0)
              Text('-\$${g.savings.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Color(0xFF2E7D32))),
          ],
        ),
      ));
      g.claimed.forEach((pid, qty) {
        if (qty > 0) children.add(tile(pid, qty));
      });
    }

    final ungrouped = cartProvider.items.values
        .where((it) => cartProvider.ungroupedQuantity(it.objectID) > 0)
        .toList();
    if (cartProvider.groups.isNotEmpty && ungrouped.isNotEmpty) {
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 2),
        child: Text('Otros productos',
            style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: Colors.grey[600])),
      ));
    }
    for (final item in ungrouped) {
      children.add(tile(item.objectID, cartProvider.ungroupedQuantity(item.objectID)));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }

  Widget _buildRewardsSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Container(
          padding: const EdgeInsets.all(AppDefaults.padding),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Usar saldo de monedero (\$${_rewardsBalance.toStringAsFixed(2)})',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Switch(
                value: _useRewardsBalance,
                onChanged: (bool value) {
                  setState(() {
                    _useRewardsBalance = value;
                    _calculateTotal();
                  });
                },
                activeThumbColor: AppColors.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _calculateTotal();
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        scrolledUnderElevation: 0,
        backgroundColor: Colors.white,
        automaticallyImplyLeading: false,
        title: Padding(
          padding: const EdgeInsets.all(0),
          child: SizedBox(
            height: 180,
            width: 300,
            child: AspectRatio(
              aspectRatio: 1 / 1,
              child: Image.asset(
                isDarkMode ? AppImages.logowhite : AppImages.logo,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: BottomFade(
          clearHeight: 90,
          fadeHeight: 45,
          child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 16.0),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: AddressCardWidget(
                  addresses: _addresses,
                  selectedAddressId: _selectedAddressId,
                  onAddressSelected: (String? value) {
                    setState(() {
                      _selectedAddressId = value;
                    });
                    _calculateDeliveryFee();
                  },
                  userName: _userName,
                  userPhone: _userPhone,
                  isInstorePickup: _isInstorePickup,
                  onPickupToggled: (bool value) {
                    setState(() {
                      _isInstorePickup = value;
                    });
                    _calculateDeliveryFee();
                  },
                ),
              ),
              const SizedBox(height: 16.0),
              _buildOrderReview(),
              const SizedBox(height: 16.0),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: const Text(
                  'Información de Facturación',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 8.0),
              if (_rewardsBalance > 0) _buildRewardsSection(),
              const SizedBox(height: 8.0),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: CheckoutBillingInformation(
                    rawSubtotal:
                        Provider.of<CartProvider>(context, listen: false)
                            .totalPrice,
                    comboDiscount:
                        Provider.of<CartProvider>(context, listen: false)
                            .discountAmount,
                    comboNames:
                        Provider.of<CartProvider>(context, listen: false)
                            .appliedPromosList,
                    discount: _discount,
                    couponCode: _selectedCouponCode,
                    deliveryFee: _deliveryFee,
                    appliedRewards: _appliedRewards,
                    total: _total,
                    isInstorePickup: _isInstorePickup,
                  ),
                ),
              ),
              const SizedBox(height: 16.0),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: PaymentMethods(
                  selectedPaymentMethod: _selectedPaymentMethod,
                  onPaymentMethodSelected: (String? value) {
                    setState(() {
                      _selectedPaymentMethod = value!;
                    });
                  },
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: _buildCouponSection(),
              ),
              const SizedBox(height: 16),
              if (_userPhone == '0000000000' ||
                  _userPhone.isEmpty ||
                  !_isValidPhoneNumber(_userPhone))
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _showPhoneUpdateDialog,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        "Agregar Teléfono para Continuar",
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16),
                      ),
                    ),
                  ),
                )
              else if (_addresses.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _navigateToAddresses,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        "Agregar Dirección para Continuar",
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16),
                      ),
                    ),
                  ),
                )
              else
                SizedBox(
                  width: MediaQuery.of(context).size.width * 0.8,
                  child: SlideAction(
                    text: 'Desliza para pagar',
                    textStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.white,
                    ),
                    outerColor: AppColors.primary,
                    innerColor: Colors.white,
                    onSubmit: _placeOrder,
                  ),
                ),
              const SizedBox(height: 10),
              Text(
                'Efesios 1:7-9',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 120),
            ],
          ),
        ),
        ),
      ),
    );
  }

  Widget _buildCouponSection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
        child: ExpansionTile(
          leading: const Icon(Icons.local_offer_outlined, color: Colors.black),
          title: const Text(
            'Cupones',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            if (_assignedCoupons.isNotEmpty) ...[
              ..._assignedCoupons.map(_buildSelectableCoupon),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(child: Divider(color: Colors.grey.shade300)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text('o ingresa un código',
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[500])),
                  ),
                  Expanded(child: Divider(color: Colors.grey.shade300)),
                ],
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _couponController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      hintText: 'Código de cupón',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14),
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 48,
                  width: 96,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.black,
                      elevation: 0,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      String code = _couponController.text.trim();
                      if (code.isNotEmpty) {
                        _applyCoupon(code).then((_) {
                          _couponController.clear();
                        });
                      } else {
                        _showAlertDialog('Error',
                            'Por favor, ingresa un código de cupón.');
                      }
                    },
                    child: const Text('Aplicar',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectableCoupon(Map<String, dynamic> coupon) {
    final bool isSelected = _selectedCouponCode == coupon['code'];
    final code = (coupon['code'] ?? '').toString();
    final pct = (coupon['percentage'] as num?)?.toDouble() ?? 0;
    final exp = coupon['expiry_date'];
    final String expText = exp is Timestamp ? _fmtCheckoutDate(exp) : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() {
            _selectedCouponCode = isSelected ? null : code;
            _calculateTotal();
          });
        },
        child: Container(
          height: 62,
          decoration: BoxDecoration(
            color: isSelected ? Colors.black.withValues(alpha: 0.04) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? Colors.black : Colors.grey.shade300,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 58,
                alignment: Alignment.center,
                color: isSelected ? Colors.black : Colors.grey.shade400,
                child: Text(
                  '${pct.toStringAsFixed(0)}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      code,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        letterSpacing: 0.5,
                        color: isSelected ? Colors.black : Colors.black87,
                      ),
                    ),
                    if (expText.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text('Vence $expText',
                          style:
                              TextStyle(fontSize: 11.5, color: Colors.grey[600])),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Icon(
                  isSelected ? Icons.check_circle : Icons.circle_outlined,
                  color: isSelected ? Colors.black : Colors.grey[400],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtCheckoutDate(Timestamp ts) {
    final d = ts.toDate().toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }
}

class CircularCheckbox extends StatelessWidget {
  final bool value;
  final Color activeColor;
  final Color checkColor;

  const CircularCheckbox({
    super.key,
    required this.value,
    this.activeColor = Colors.black,
    this.checkColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: activeColor,
          width: 2.0,
        ),
        color: value ? activeColor : Colors.transparent,
      ),
      width: 24.0,
      height: 24.0,
      child: value
          ? Icon(
        Icons.check,
        size: 16.0,
        color: checkColor,
      )
          : null,
    );
  }
}

class AddressCardWidget extends StatelessWidget {
  final List<Map<String, dynamic>> addresses;
  final String? selectedAddressId;
  final ValueChanged<String?> onAddressSelected;
  final String userName;
  final String userPhone;
  final bool isInstorePickup;
  final ValueChanged<bool> onPickupToggled;

  const AddressCardWidget({
    super.key,
    required this.addresses,
    required this.selectedAddressId,
    required this.onAddressSelected,
    required this.userName,
    required this.userPhone,
    required this.isInstorePickup,
    required this.onPickupToggled,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 20.0),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Dirección de Entrega',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              GestureDetector(
                onTap: () => onPickupToggled(!isInstorePickup),
                behavior: HitTestBehavior.opaque,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.storefront,
                      size: 18,
                      color: isInstorePickup
                          ? AppColors.primary
                          : Colors.grey[700],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Pick-Up',
                      style: TextStyle(
                        color: isInstorePickup
                            ? AppColors.primary
                            : Colors.grey[700],
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8.0),
        if (isInstorePickup)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.storefront,
                  size: 56,
                  color: AppColors.primary,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Recoger en tienda',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Pasa por tu pedido sin costo de envío.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          )
        else if (addresses.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('No tienes direcciones guardadas.'),
          )
        else
          Column(
            children: addresses.map((address) {
              return GestureDetector(
                onTap: () {
                  onAddressSelected(address['id']);
                },
                child: AddressCard(
                  label: userName,
                  number: formatMxPhone(userPhone),
                  address:
                  '${address['street']} ${address['streetNumber']}, ${address['colonia']}, ${address['city']}, ${address['state']}',
                  isSelected: selectedAddressId == address['id'],
                ),
              );
            }).toList(),
          ),
      ],
    );
  }
}

class CheckoutBillingInformation extends StatelessWidget {
  final double rawSubtotal;
  final double comboDiscount;
  final List<String> comboNames;
  final double discount;
  final String? couponCode;
  final double deliveryFee;
  final double appliedRewards;
  final double total;
  final bool isInstorePickup;

  const CheckoutBillingInformation({
    super.key,
    required this.rawSubtotal,
    required this.comboDiscount,
    required this.comboNames,
    required this.discount,
    required this.couponCode,
    required this.deliveryFee,
    required this.appliedRewards,
    required this.total,
    this.isInstorePickup = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppDefaults.padding),
      child: Column(
        children: [
          _row(context, 'Subtotal', '\$${rawSubtotal.toStringAsFixed(2)}'),
          if (comboDiscount > 0) ...[
            const SizedBox(height: 10),
            _row(
              context,
              comboNames.length == 1
                  ? 'Descuento de combo: ${comboNames.first}'
                  : 'Descuento de combo',
              '-\$${comboDiscount.toStringAsFixed(2)}',
              valueColor: Colors.red,
            ),
            if (comboNames.length > 1)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(top: 2.0, left: 4.0),
                  child: Text(
                    comboNames.join(', '),
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ),
              ),
          ],
          if (discount > 0) ...[
            const SizedBox(height: 10),
            _row(
              context,
              (couponCode != null && couponCode!.isNotEmpty)
                  ? 'Descuento de cupón: $couponCode'
                  : 'Descuento',
              '-\$${discount.toStringAsFixed(2)}',
              valueColor: Colors.red,
            ),
          ],
          if (!isInstorePickup) ...[
            const SizedBox(height: 10),
            _row(context, 'Tarifa de Envío',
                '\$${deliveryFee.toStringAsFixed(2)}'),
          ],
          const SizedBox(height: 10),
          const Divider(),
          if (appliedRewards > 0) ...[
            _row(
              context,
              'Saldo de monedero aplicado',
              '-\$${appliedRewards.toStringAsFixed(2)}',
              valueColor: Colors.red,
            ),
            const Divider(),
          ],
          Row(
            children: [
              const Text('Total', style: TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(
                '\$${total.toStringAsFixed(2)}',
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value,
      {Color? valueColor}) {
    return Row(
      children: [
        Expanded(
          child:
              Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style:
              Theme.of(context).textTheme.bodyLarge?.copyWith(color: valueColor),
        ),
      ],
    );
  }
}

class PaymentMethods extends StatelessWidget {
  final String selectedPaymentMethod;
  final ValueChanged<String?> onPaymentMethodSelected;

  const PaymentMethods({
    super.key,
    required this.selectedPaymentMethod,
    required this.onPaymentMethodSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Método de Pago',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            PaymentMethodCard(
              methodID: 'efectivo',
              animationAsset: 'assets/animations/cash.json',
              isSelected: selectedPaymentMethod == 'efectivo',
              onTap: () {
                onPaymentMethodSelected('efectivo');
              },
            ),
            PaymentMethodCard(
              methodID: 'tarjeta',
              animationAsset: 'assets/animations/card.json',
              isSelected: selectedPaymentMethod == 'tarjeta',
              onTap: () {
                onPaymentMethodSelected('tarjeta');
              },
            ),
          ],
        ),
      ],
    );
  }
}
