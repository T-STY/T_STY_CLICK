import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:slide_to_act_reborn/slide_to_act_reborn.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_defaults.dart';
import '../../constants/app_images.dart';
import '../cart/cart_provider.dart';
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

  Map<String, dynamic>? _rewardsCardData;
  bool _useRewardsBalance = false;

  List<Map<String, dynamic>> _assignedCoupons = [];
  String? _selectedCouponCode;
  final TextEditingController _couponController = TextEditingController();

  Map<String, dynamic> _coloniaPricing = {};

  double _subtotal = 0.0;
  double _deliveryFee = 0.0;
  double _total = 0.0;

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
        _deliveryFee = 0.0;
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
      _rewardsCardData = userCardDoc.data();
      String? cardNumber = _rewardsCardData?['cardNumber'];

      if (cardNumber != null) {
        final querySnapshot = await FirebaseFirestore.instance
            .collection('rewards')
            .where('cardNumber', isEqualTo: cardNumber)
            .get();

        if (querySnapshot.docs.isNotEmpty) {
          var rewardsData = querySnapshot.docs.first.data();
          double? saldo = _toDouble(rewardsData['saldo']);

          setState(() {
            _rewardsBalance = saldo;
          });
        }
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
          .map((doc) => {'code': doc.id, ...doc.data()})
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
                decoration: InputDecoration(
                  labelText: 'Número de Teléfono',
                  hintText: '10 dígitos',
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
                String newPhone = phoneController.text.trim();

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
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text(
                            'Por favor ingresa un número de 10 dígitos válido (no consecutivos ni repetidos).')),
                  );
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
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;
    final firestore = FirebaseFirestore.instance;

    try {
      await firestore.runTransaction((transaction) async {
        final couponDocRef =
        firestore.collection('coupons').doc(code.toUpperCase());
        final couponSnapshot = await transaction.get(couponDocRef);

        if (!couponSnapshot.exists) {
          throw Exception('Cupón no válido.');
        }

        final couponData = couponSnapshot.data()!;
        int remainingUses = couponData['remaining_uses'] ?? 0;

        if (remainingUses < 1) {
          throw Exception('Este cupón ya no está disponible.');
        }

        final expiryTimestamp = couponData['expiry_date'];
        if (expiryTimestamp != null) {
          final expiryDate = expiryTimestamp.toDate();
          if (expiryDate.isBefore(DateTime.now())) {
            throw Exception('Este cupón ha expirado.');
          }
        }

        final userCouponRef = firestore
            .collection('users')
            .doc(userId)
            .collection('coupons')
            .doc(code.toUpperCase());

        final userCouponSnapshot = await transaction.get(userCouponRef);

        if (userCouponSnapshot.exists) {
          final existingCoupon = userCouponSnapshot.data()!;
          if (!(existingCoupon['used'] ?? true)) {
            throw Exception('Ya has aplicado este cupón.');
          } else {
            throw Exception('Este cupón ya ha sido utilizado.');
          }
        }

        transaction.set(userCouponRef, {
          'code': couponData['code'],
          'max_discount': couponData['max_discount'],
          'percentage': couponData['percentage'],
          'expiry_date': couponData['expiry_date'],
          'used': false,
        });

        transaction.update(couponDocRef, {
          'remaining_uses': remainingUses - 1,
        });
      });

      await _fetchAssignedCoupons();
      if (!mounted) return;
      setState(() {
        _selectedCouponCode = code.toUpperCase();
        _calculateDiscount();
      });

      _showAlertDialog('Éxito', 'Cupón aplicado exitosamente.');
    } catch (e) {
      if (!mounted) return;
      _showAlertDialog('Error', e.toString().replaceFirst('Exception: ', ''));
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
    double subtotal = cartProvider.totalPrice;

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

    if (_selectedAddressId == null) {
      _showAlertDialog(
          'Error', 'Por favor, selecciona una dirección de entrega.');
      return;
    }

    Map<String, dynamic>? selectedCouponData;
    if (_selectedCouponCode != null) {
      try {
        selectedCouponData = _assignedCoupons.firstWhere(
              (coupon) => coupon['code'] == _selectedCouponCode,
        );
      } catch (e) {
        selectedCouponData = null;
      }
    }

    Map<String, dynamic> orderData = {
      'userId': userId,
      'addressId': _selectedAddressId,
      'paymentMethod': _selectedPaymentMethod,
      'items': cartProvider.items.values.map((item) => item.toMap()).toList(),
      'subtotal': _subtotal,
      'deliveryFee': _deliveryFee,
      'discount': _discount,
      'total': _total,
      'useRewardsBalance': _useRewardsBalance,
      'timestamp': FieldValue.serverTimestamp(),
      'appliedCoupon': selectedCouponData != null
          ? {
        'code': selectedCouponData['code'],
        'percentage': selectedCouponData['percentage'],
        'max_discount': selectedCouponData['max_discount'],
      }
          : null,
      'state': 'En Revision',
    };

    try {
      final firestore = FirebaseFirestore.instance;

      await firestore.runTransaction((transaction) async {
        // If using rewards, read current saldo inside transaction for atomicity
        double verifiedSaldo = 0.0;
        DocumentReference? rewardsDocRef;
        DocumentReference? userRewardsSaldoRef;

        if (_useRewardsBalance && _appliedRewards > 0) {
          userRewardsSaldoRef = firestore
              .collection('users')
              .doc(userId)
              .collection('rewardsCard')
              .doc('cardInfo');

          final userRewardsSnap = await transaction.get(userRewardsSaldoRef);
          if (!userRewardsSnap.exists) {
            throw Exception('No se encontró información de monedero.');
          }

          final rewardsQuery = await firestore
              .collection('rewards')
              .where('cardNumber', isEqualTo: _rewardsCardData?['cardNumber'])
              .limit(1)
              .get();

          if (rewardsQuery.docs.isNotEmpty) {
            rewardsDocRef = rewardsQuery.docs.first.reference;
            final rewardsSnap = await transaction.get(rewardsDocRef);
            verifiedSaldo = _toDouble(rewardsSnap.data()?['saldo'] ?? 0);
          }

          if (verifiedSaldo < _appliedRewards) {
            throw Exception('Saldo insuficiente en el monedero.');
          }
        }

        // Create order
        DocumentReference orderRef = firestore.collection('orders').doc();
        transaction.set(orderRef, orderData);

        // User order history
        DocumentReference userOrderHistoryRef = firestore
            .collection('users')
            .doc(userId)
            .collection('orderHistory')
            .doc(orderRef.id);
        transaction.set(userOrderHistoryRef, orderData);

        // Deduct rewards atomically
        if (_useRewardsBalance && _appliedRewards > 0 && rewardsDocRef != null && userRewardsSaldoRef != null) {
          double newRewardsSaldo = (verifiedSaldo - _appliedRewards).clamp(0.0, double.infinity);
          double newUserSaldo = (_rewardsBalance - _appliedRewards).clamp(0.0, double.infinity);

          transaction.update(userRewardsSaldoRef, {'saldo': newUserSaldo});
          transaction.update(rewardsDocRef, {'saldo': newRewardsSaldo});
        }

        // Mark coupon as used
        if (_selectedCouponCode != null) {
          DocumentReference userCouponRef = firestore
              .collection('users')
              .doc(userId)
              .collection('coupons')
              .doc(_selectedCouponCode);
          transaction.update(userCouponRef, {'used': true});
        }
      });

      cartProvider.clearCart();
      widget.onOrderPlaced();
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
        automaticallyImplyLeading: true,
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
                ),
              ),
              const SizedBox(height: 16.0),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(
                  'Información de Facturación',
                  style: Theme.of(context).textTheme.titleLarge,
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
                    subtotal: _subtotal,
                    deliveryFee: _deliveryFee,
                    discount: _discount,
                    appliedRewards: _appliedRewards,
                    total: _total,
                    useRewardsBalance: _useRewardsBalance,
                    rewardsBalance: _rewardsBalance,
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
          title: const Text(
            'Aplicar Cupón',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          children: [
            if (_assignedCoupons.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: ListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: _assignedCoupons.map((coupon) {
                    bool isSelected = _selectedCouponCode == coupon['code'];
                    return ListTile(
                      leading: CircularCheckbox(
                        value: isSelected,
                        activeColor: Colors.black,
                        checkColor: Colors.white,
                      ),
                      title: Text(
                        '${coupon['code']} - ${coupon['percentage']}% de descuento',
                        style: TextStyle(
                          color: isSelected ? Colors.black : Colors.grey,
                        ),
                      ),
                      subtitle: Text(
                        'Expira: ${coupon['expiry_date'].toDate().toLocal().toString().split(' ')[0]}',
                        style: TextStyle(
                          color: isSelected ? Colors.black : Colors.grey,
                        ),
                      ),
                      onTap: () {
                        setState(() {
                          if (isSelected) {
                            _selectedCouponCode = null;
                          } else {
                            _selectedCouponCode = coupon['code'];
                          }
                          _calculateTotal();
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.all(AppDefaults.padding),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _couponController,
                      decoration: const InputDecoration(
                        hintText: 'Código de Cupón',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  SizedBox(
                    width: 100,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 16.0),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.0),
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
                      child: const Text(
                        'Aplicar',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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

  const AddressCardWidget({
    super.key,
    required this.addresses,
    required this.selectedAddressId,
    required this.onAddressSelected,
    required this.userName,
    required this.userPhone,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Dirección de Entrega',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8.0),
        addresses.isEmpty
            ? const Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('No tienes direcciones guardadas.'),
        )
            : Column(
          children: addresses.map((address) {
            return GestureDetector(
              onTap: () {
                onAddressSelected(address['id']);
              },
              child: AddressCard(
                label: userName,
                number: userPhone,
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
  final double subtotal;
  final double deliveryFee;
  final double discount;
  final double appliedRewards;
  final double total;
  final bool useRewardsBalance;
  final double rewardsBalance;

  const CheckoutBillingInformation({
    super.key,
    required this.subtotal,
    required this.deliveryFee,
    required this.discount,
    required this.appliedRewards,
    required this.total,
    required this.useRewardsBalance,
    required this.rewardsBalance,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppDefaults.padding),
      child: Column(
        children: [
          Row(
            children: [
              const Text(
                'Subtotal',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              Text(
                '\$${subtotal.toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (discount > 0)
            Row(
              children: [
                const Text(
                  'Descuento',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                const Spacer(),
                Text(
                  '-\$${discount.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            ),
          const SizedBox(height: 10),
          if (appliedRewards > 0)
            Row(
              children: [
                const Text(
                  'Saldo de Recompensas Aplicado',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                const Spacer(),
                Text(
                  '-\$${appliedRewards.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text(
                'Tarifa de Envío',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              Text(
                '\$${deliveryFee.toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(),
          Row(
            children: [
              const Text(
                'Total',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                '\$${total.toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
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