import 'dart:async';
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
import '../../utils/callable_retry.dart';
import 'delivery_window_picker.dart';
import '../../utils/coupon_filter.dart' as cf;
import '../../utils/order_window.dart';
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

/// Whether a coupon is currently usable against the cart in view.
/// - `ok`: filter inactive OR at least one item matches.
/// - `pending`: filter active and product metadata is still loading.
///   UI shows a spinner + "Verificando elegibilidad…" so the user doesn't
///   misread a transient empty cache as "this coupon doesn't apply."
/// - `noMatch`: filter active and zero items match. UI dims the card,
///   disables the tap (except to deselect), and `_calculateDiscount`
///   auto-deselects to avoid the silent-$0 confusion.
enum _CouponEligibility { ok, pending, noMatch }

class _CheckoutPageState extends State<CheckoutPage> {
  String _selectedPaymentMethod = 'efectivo';

  String? _selectedAddressId;

  bool _useRewardsBalance = false;

  List<Map<String, dynamic>> _assignedCoupons = [];
  String? _selectedCouponCode;
  final TextEditingController _couponController = TextEditingController();
  // Re-entrancy + visible-progress guard for `_applyCoupon`. The Aplicar
  // button fires a Cloud Function call; without this flag a fast double-
  // tap would queue two `claimCoupon` calls. We flip it true on entry
  // and back to false in a finally block so the button can render a
  // spinner and be disabled while the network call is in flight.
  bool _isApplyingCoupon = false;

  Map<String, dynamic> _coloniaPricing = {};

  double _subtotal = 0.0;
  double _deliveryFee = 0.0;
  double _total = 0.0;

  bool _isInstorePickup = false;
  // Re-entrancy guard for `_placeOrder`. The SlideAction widget
  // can fire `onSubmit` repeatedly on quick taps before its own
  // dismissal animation completes; without this flag a user
  // double-tapping the slider would send two `placeOrder` CF
  // calls and post two real orders. We flip this true on entry,
  // back to false at every exit path (success, validation reject,
  // exception). Wrapped in setState so the SlideAction's enabled
  // state can be driven off it.
  bool _isPlacingOrder = false;

  double _rewardsBalance = 0.0;
  double _appliedRewards = 0.0;

  double _discount = 0.0;

  List<Map<String, dynamic>> _addresses = [];

  String _userName = '';
  String _userPhone = '';

  /// Resolved store/delivery state, refreshed from a live `settings/store`
  /// stream. The submit handler reads this; the order options panel uses
  /// it to disable the delivery toggle outside the window.
  OrderWindow _window = OrderWindow.openPlaceholder;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _storeSub;
  CartProvider? _cartProviderRef;

  /// Chosen 30-min slot start, or null = "Lo antes posible".
  TimeOfDay? _deliverySlot;

  /// Free-text order note for the store (referencias, "sin cebolla",
  /// "plátanos maduros"…). Optional; capped and trimmed server-side.
  final TextEditingController _notesController = TextEditingController();

  /// Cash "pago con" — how much the customer will hand over so the driver
  /// brings change. null | 'exacto' | '100' | '200' | '500' | '1000' | 'otro'.
  /// Only relevant when the payment method is efectivo.
  String? _cashOption;
  final TextEditingController _cashOtherController = TextEditingController();

  /// The amount the customer will pay with (bill/exact/custom), or null when
  /// unspecified. 'exacto' tracks the live total so it stays correct if a
  /// coupon/saldo changes it.
  double? get _cashGiven {
    switch (_cashOption) {
      case 'exacto':
        return _total;
      case 'otro':
        return double.tryParse(_cashOtherController.text.trim());
      case null:
        return null;
      default:
        return double.tryParse(_cashOption!);
    }
  }

  /// Device-clock skew vs the server (server - device). Slot generation adds
  /// this to DateTime.now() so a wrong device clock can't offer stale slots;
  /// placeOrder re-validates with real server time regardless.
  Duration _clockSkew = Duration.zero;

  DateTime get _networkNow => DateTime.now().add(_clockSkew);

  Widget _buildCashPaySection() {
    // Bills that actually cover the order; "Otro" handles anything else.
    final bills =
        [100.0, 200.0, 500.0, 1000.0].where((b) => b >= _total).toList();
    final given = _cashGiven;
    final change = (_cashOption != null &&
            _cashOption != 'exacto' &&
            given != null &&
            given >= _total)
        ? given - _total
        : null;
    final bool otherTooLow = _cashOption == 'otro' &&
        given != null &&
        given < _total;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.payments_outlined,
                  size: 20, color: Colors.grey.shade800),
              const SizedBox(width: 8),
              const Text('¿Con cuánto pagas?',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 2),
          Text('Para llevarte tu cambio exacto.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 10),
          _cashChipGrid([
            _cashChip('Pago justo', 'exacto'),
            for (final b in bills)
              _cashChip('\$${b.toInt()}', b.toInt().toString()),
            _cashChip('Otro', 'otro'),
          ]),
          if (_cashOption == 'otro') ...[
            const SizedBox(height: 10),
            TextField(
              controller: _cashOtherController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixText: '\$ ',
                hintText: 'Monto en efectivo',
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.black, width: 1.4),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ],
          if (_cashOption == 'exacto') ...[
            const SizedBox(height: 8),
            Text('Pagas justo, sin cambio.',
                style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600)),
          ] else if (change != null) ...[
            const SizedBox(height: 8),
            Text('Tu cambio: \$${change.toStringAsFixed(2)}',
                style: const TextStyle(
                    fontSize: 13,
                    color: Colors.green,
                    fontWeight: FontWeight.w800)),
          ] else if (otherTooLow) ...[
            const SizedBox(height: 8),
            Text('El monto debe ser al menos \$${_total.toStringAsFixed(2)}.',
                style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.red.shade600,
                    fontWeight: FontWeight.w600)),
          ],
        ],
      ),
    );
  }

  /// Lays the cash chips out three per row, every chip the same width with
  /// even gaps. Short final rows are padded with empty slots so the leftover
  /// chips keep the standard width instead of stretching across the row.
  Widget _cashChipGrid(List<Widget> chips) {
    const double gap = 8;
    final List<Widget> rows = [];
    for (int i = 0; i < chips.length; i += 3) {
      final int end = (i + 3 <= chips.length) ? i + 3 : chips.length;
      final List<Widget> slice = chips.sublist(i, end);
      rows.add(Row(
        children: [
          for (int j = 0; j < 3; j++) ...[
            if (j > 0) const SizedBox(width: gap),
            Expanded(
              child: j < slice.length ? slice[j] : const SizedBox.shrink(),
            ),
          ],
        ],
      ));
      if (end < chips.length) rows.add(const SizedBox(height: gap));
    }
    return Column(children: rows);
  }

  Widget _cashChip(String label, String value) {
    final selected = _cashOption == value;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _cashOption = selected ? null : value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? Colors.black : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
              color: selected ? Colors.black : Colors.grey.shade300),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : Colors.grey.shade800,
          ),
        ),
      ),
    );
  }

  Widget _buildNotesSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.edit_note, size: 20, color: Colors.grey.shade800),
              const SizedBox(width: 8),
              const Text(
                'Notas del pedido (opcional)',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _notesController,
            maxLines: 3,
            maxLength: 300,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(
              hintText:
                  'Ej: casa azul, tocar timbre, plátanos maduros, sin popote…',
              hintStyle:
                  TextStyle(color: Colors.grey.shade400, fontSize: 13),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.black, width: 1.4),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }

  Map<String, String> _buildDeliveryWindowPayload(TimeOfDay slot) {
    String two(int n) => n.toString().padLeft(2, '0');
    final n = _networkNow;
    final endMin = slot.hour * 60 + slot.minute + 30;
    return {
      'date': '${n.year}-${two(n.month)}-${two(n.day)}',
      'start': '${two(slot.hour)}:${two(slot.minute)}',
      'end': '${two(endMin ~/ 60 % 24)}:${two(endMin % 60)}',
    };
  }

  Future<void> _fetchServerTimeSkew() async {
    try {
      final res = await callIdempotentCallable('getServerTime');
      final epochMs = (res.data?['epochMs'] as num?)?.toInt();
      if (epochMs != null && mounted) {
        setState(() {
          _clockSkew = DateTime.fromMillisecondsSinceEpoch(epochMs)
              .difference(DateTime.now());
        });
      }
    } catch (_) {
      // Device time is the graceful fallback; the CF stays authoritative.
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchStorePricing();
    _fetchRewardsCardData();
    _fetchAssignedCoupons();
    _fetchAddresses();
    _fetchUserInfo();
    _subscribeOrderWindow();
    _fetchServerTimeSkew();
    // Listen to the SCOPED product-meta channel so the coupon row can flip
    // from "Verificando elegibilidad…" to its real label without forcing
    // every CartProvider Consumer (notably home/search) to rebuild on
    // every product fetch. The broader Consumer<CartProvider>(context)
    // path below already covers actual cart mutations.
    _cartProviderRef =
        Provider.of<CartProvider>(context, listen: false);
    _cartProviderRef!.productMetaVersion.addListener(_onProductMetaChanged);
  }

  void _onProductMetaChanged() {
    if (!mounted) return;
    // Trigger a rebuild so `_buildSelectableCoupon` re-evaluates
    // eligibility now that one more item's category/provedor is known.
    setState(_calculateTotal);
  }

  /// Stream `settings/store` so the delivery/pickup state stays live while
  /// the user is on this screen. When the user crosses the delivery cutoff
  /// mid-checkout, the toggle auto-flips to pickup and the delivery option
  /// disables itself in the next rebuild.
  void _subscribeOrderWindow() {
    _storeSub = FirebaseFirestore.instance
        .collection('settings')
        .doc('store')
        .snapshots()
        .listen((snap) {
      if (!mounted || !snap.exists) return;
      final win =
          OrderWindow.evaluate(doc: snap.data() ?? const {}, now: DateTime.now());
      var pickupFlip = _isInstorePickup;
      if (win.status == OrderingStatus.pickupOnly && !pickupFlip) {
        pickupFlip = true;
      }
      // Second mounted check — the listener fires asynchronously
      // and any future addition between the top-of-listener check
      // and the setState could introduce an await window where the
      // user navigates away. Cheap defense against drift.
      if (!mounted) return;
      setState(() {
        _window = win;
        _isInstorePickup = pickupFlip;
      });
      _calculateDeliveryFee();
    });
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

  /// Colonia strings reach us from two different writers: the curated
  /// dropdown, and free text — which includes the raw geocoder `subLocality`
  /// whenever GPS reverse-geocoding doesn't match the curated list. So the
  /// same place arrives as "Centro", "centro", "Céntro" or " Centro ".
  /// Matching the pricing map by exact key meant identical addresses were
  /// billed differently depending on how the address happened to be created.
  static String normalizeColonia(String s) {
    var out = s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    const accented = 'áàäâãéèëêíìïîóòöôõúùüûñç';
    const plain = 'aaaaaeeeeiiiiooooouuuunc';
    for (var i = 0; i < accented.length; i++) {
      out = out.replaceAll(accented[i], plain[i]);
    }
    return out;
  }

  /// Fee for [colonia], or null when the pricing map genuinely has no entry.
  ///
  /// When several pricing keys collapse to the same normalized colonia (the
  /// classic case being one entry typed with accents and one without) the
  /// LOWEST fee wins, so a duplicate or typo'd row can never overcharge a
  /// customer — it can only ever undercharge, which is the safe direction.
  double? _feeForColonia(String colonia) {
    final target = normalizeColonia(colonia);
    double? best;
    _coloniaPricing.forEach((key, value) {
      if (normalizeColonia(key) != target) return;
      final v = value is num
          ? value.toDouble()
          : double.tryParse(value.toString());
      if (v == null) return;
      if (best == null || v < best!) best = v;
    });
    return best;
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

    final matched = _feeForColonia(colonia);
    setState(() {
      _deliveryFee = matched ?? 20.0;
    });
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
        final result = await callIdempotentCallable('getRewardsBalance');
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
      // The user can pop the addresses screen via system back at
      // any time; if the checkout itself was disposed in between
      // (deep-nav pop, timeout dialog, etc.) we'd setState in
      // `_fetchAddresses` on a defunct State.
      if (!mounted) return;
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
    if (_isApplyingCoupon) return;
    final upper = code.toUpperCase();
    setState(() {
      _isApplyingCoupon = true;
    });
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
    } finally {
      if (mounted) {
        setState(() {
          _isApplyingCoupon = false;
        });
      }
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
        // Honor the coupon's product-filter when present. eligibleSubtotalFor
        // returns the full subtotal for inactive filters (back-compat with
        // pre-feature coupons), so the legacy code path is preserved.
        // Returns null IFF an active filter needs product meta and it's
        // still loading — we treat that as "0 discount for now" but DON'T
        // auto-deselect (the eligibility check below distinguishes
        // unresolved from genuinely-zero).
        final cartProvider =
            Provider.of<CartProvider>(context, listen: false);
        final filter = couponData['productFilter'];
        final filterMap =
            filter is Map ? Map<String, dynamic>.from(filter) : null;
        final eligibleRaw = cartProvider.eligibleSubtotalFor(filterMap);
        final hasActiveFilter = filterMap != null &&
            ((filterMap['mode'] ?? 'all') == 'include' ||
                (filterMap['mode'] ?? 'all') == 'exclude');

        // Auto-deselect when the cart mutates and the eligible amount
        // genuinely drops to 0 (meta loaded, no matches). Skip when meta
        // is still loading (eligibleRaw == null) — that's a transient
        // "verifying" state, not a final answer.
        if (hasActiveFilter && eligibleRaw != null && eligibleRaw <= 0) {
          _selectedCouponCode = null;
          _discount = 0.0;
          return;
        }

        final effectiveEligible = eligibleRaw ?? 0.0;
        // Clamp to the post-combo subtotal so coupon + combo discount never
        // overshoot the cart's actual value. Mirrors the server's Math.min
        // guard against an inflated items[] payload.
        final base = effectiveEligible > _subtotal ? _subtotal : effectiveEligible;
        // Defensive clamp upper bound — admin form already validates
        // max_discount >= 0, but Dart's num.clamp throws ArgumentError if
        // upperLimit < lowerLimit, so guard against a malformed master doc.
        final maxClamp = maxDiscount < 0 ? 0.0 : maxDiscount;
        double discountAmount =
            (base * percentage / 100).clamp(0, maxClamp).toDouble();
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

  /// Eligibility status of a coupon against the current cart, used by
  /// `_buildSelectableCoupon` to render badges.
  /// - `pending`: filter is active and product meta hasn't loaded yet.
  /// - `noMatch`: filter is active and ZERO items qualify.
  /// - `ok`: filter inactive, or at least one item qualifies.
  _CouponEligibility _couponEligibility(Map<String, dynamic> coupon) {
    final filter = coupon['productFilter'];
    if (filter is! Map) return _CouponEligibility.ok;
    final mode = (filter['mode'] ?? 'all').toString();
    if (mode != 'include' && mode != 'exclude') return _CouponEligibility.ok;
    final cartProvider = Provider.of<CartProvider>(context, listen: false);
    final eligible = cartProvider
        .eligibleSubtotalFor(Map<String, dynamic>.from(filter));
    if (eligible == null) return _CouponEligibility.pending;
    if (eligible <= 0) return _CouponEligibility.noMatch;
    return _CouponEligibility.ok;
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
    // Re-entrancy guard. A SlideAction `onSubmit` could fire twice
    // on a rapid double-tap and post two orders. The flag also
    // disables the slider in the UI while in flight.
    if (_isPlacingOrder) return;

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;
    final cartProvider = Provider.of<CartProvider>(context, listen: false);

    // Re-check the window at submit time. Belt-and-braces against the user
    // sitting on the page long enough to cross either the delivery cutoff
    // or the global quiet-hours window. The CF will reject too, but doing
    // it here gives a clearer message instead of a generic CF error.
    if (_window.status == OrderingStatus.closed) {
      _showAlertDialog('Estamos cerrados',
          'No estamos tomando pedidos entre '
              '${formatHourMinute(_window.quietStart)} y '
              '${formatHourMinute(_window.quietEnd)}. '
              'Vuelve más tarde.');
      return;
    }
    if (!_isInstorePickup &&
        _window.status == OrderingStatus.pickupOnly) {
      _showAlertDialog(
          'Solo entrega en tienda',
          _window.deliveryRestToday
              ? 'Hoy no estamos haciendo entregas a domicilio. Puedes recoger en tienda.'
              : 'Las entregas a domicilio se reanudan a las '
                  '${formatHourMinute(_window.todayOpen!)}. '
                  'Mientras tanto puedes recoger en tienda.');
      return;
    }

    if (!_isInstorePickup && _selectedAddressId == null) {
      _showAlertDialog(
          'Error', 'Por favor, selecciona una dirección de entrega.');
      return;
    }

    setState(() => _isPlacingOrder = true);
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
        if (_deliverySlot != null)
          'deliveryWindow': _buildDeliveryWindowPayload(_deliverySlot!),
        if (_notesController.text.trim().isNotEmpty)
          'notes': _notesController.text.trim(),
        if (_selectedPaymentMethod == 'efectivo' &&
            _cashGiven != null &&
            _cashGiven! >= _total)
          'cashPaidWith': _cashGiven,
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
    } finally {
      // Re-enable the slider on every exit — success, validation,
      // exception. If the widget was disposed mid-flight (rare),
      // setState would throw; the mounted guard suppresses that.
      if (mounted) setState(() => _isPlacingOrder = false);
    }
  }

  @override
  void dispose() {
    _storeSub?.cancel();
    _cartProviderRef?.productMetaVersion.removeListener(_onProductMetaChanged);
    _couponController.dispose();
    _notesController.dispose();
    _cashOtherController.dispose();
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
              // ── 1. WHAT you're buying ─────────────────────────────
              const SizedBox(height: 16.0),
              _buildOrderReview(),

              // ── 2. WHERE + WHEN ───────────────────────────────────
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
                      // Slots differ between delivery and pickup hours —
                      // reset to "Lo antes posible" on mode change.
                      _deliverySlot = null;
                    });
                    _calculateDeliveryFee();
                  },
                  deliveryLockedReason:
                      _window.status == OrderingStatus.pickupOnly
                          ? (_window.deliveryRestToday
                              ? 'Hoy no hacemos entregas a domicilio.'
                              : 'Entregas a domicilio: '
                                  '${formatHourMinute(_window.todayOpen!)} – '
                                  '${formatHourMinute(_window.todayClose!)}.')
                          : null,
                ),
              ),
              DeliveryWindowPicker(
                window: _window,
                isPickup: _isInstorePickup,
                now: _networkNow,
                selected: _deliverySlot,
                onChanged: (slot) => setState(() => _deliverySlot = slot),
              ),

              // ── 3. HOW you pay + discounts ────────────────────────
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: PaymentMethods(
                  selectedPaymentMethod: _selectedPaymentMethod,
                  onPaymentMethodSelected: (String? value) {
                    setState(() {
                      _selectedPaymentMethod = value!;
                      // The "pago con" question only applies to cash.
                      if (value != 'efectivo') _cashOption = null;
                    });
                  },
                ),
              ),
              if (_selectedPaymentMethod == 'efectivo') _buildCashPaySection(),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: _buildCouponSection(),
              ),
              if (_rewardsBalance > 0) ...[
                const SizedBox(height: 8.0),
                _buildRewardsSection(),
              ],

              // ── 4. SUMMARY (reflects every choice above) ──────────
              const SizedBox(height: 16.0),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Resumen de pago',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
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

              // ── 5. NOTE + CONFIRM ─────────────────────────────────
              const SizedBox(height: 8),
              _buildNotesSection(),
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
                    text: _isPlacingOrder
                        ? 'Procesando…'
                        : 'Desliza para pagar',
                    textStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.white,
                    ),
                    outerColor: AppColors.primary,
                    innerColor: Colors.white,
                    // Suppress the submit handler while in flight —
                    // SlideAction will visually slide back but
                    // won't re-fire `_placeOrder` because the no-op
                    // returns immediately and `onSubmit` returning
                    // null aborts the slide animation gracefully.
                    onSubmit: _isPlacingOrder ? null : _placeOrder,
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
                    onPressed: _isApplyingCoupon
                        ? null
                        : () {
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
                    child: _isApplyingCoupon
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text('Aplicar',
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

    final filter = coupon['productFilter'];
    final filterMode =
        filter is Map ? (filter['mode'] ?? 'all').toString() : 'all';
    final hasFilter = filterMode == 'include' || filterMode == 'exclude';
    final filterLabel = hasFilter ? _filterLabel(filter as Map) : '';
    final eligibility =
        hasFilter ? _couponEligibility(coupon) : _CouponEligibility.ok;
    final notApplicable = eligibility == _CouponEligibility.noMatch;
    final pending = eligibility == _CouponEligibility.pending;

    // Long-press / hover tooltip explaining WHY the tap was ignored when
    // the coupon is greyed out. Without this, users tap repeatedly thinking
    // it's a misfire. Empty when not disabled so Tooltip renders nothing.
    final disabledHint = (notApplicable && !isSelected)
        ? (hasFilter
            ? 'Este cupón aplica $filterLabel. Agrega un producto elegible para usarlo.'
            : 'Este cupón no aplica a tu carrito actual.')
        : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Tooltip(
        message: disabledHint,
        triggerMode: TooltipTriggerMode.tap,
        showDuration: const Duration(seconds: 3),
        preferBelow: false,
        textStyle: const TextStyle(color: Colors.white, fontSize: 12.5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.86),
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Selecting a non-applicable coupon is blocked, but if the user was
        // already on it when the cart shifted out of eligibility we still
        // allow them to tap to deselect — otherwise they'd be stuck on a
        // greyed-out card showing $0 discount.
        onTap: (notApplicable && !isSelected)
            ? null
            : () {
                setState(() {
                  _selectedCouponCode = isSelected ? null : code;
                  _calculateTotal();
                });
              },
        child: Opacity(
          opacity: notApplicable ? 0.55 : 1.0,
          child: Container(
            constraints: const BoxConstraints(minHeight: 62),
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.black.withValues(alpha: 0.04)
                  : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? Colors.black : Colors.grey.shade300,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: IntrinsicHeight(
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
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
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
                                style: TextStyle(
                                    fontSize: 11.5, color: Colors.grey[600])),
                          ],
                          if (hasFilter) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                if (pending)
                                  SizedBox(
                                    width: 11,
                                    height: 11,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.6,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.grey[700]!,
                                      ),
                                    ),
                                  )
                                else
                                  Icon(
                                    filterMode == 'include'
                                        ? Icons.check_circle_outline
                                        : Icons.do_not_disturb_alt_outlined,
                                    size: 12,
                                    color: notApplicable
                                        ? Colors.redAccent
                                        : Colors.grey[700],
                                  ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    pending
                                        ? 'Verificando elegibilidad…'
                                        : notApplicable
                                            ? 'No aplica a tu carrito actual'
                                            : filterLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: notApplicable
                                          ? Colors.redAccent
                                          : Colors.grey[700],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
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
        ),
      ),
      ),
    );
  }

  /// Renders the productFilter as a short label for the coupon card.
  /// Thin wrapper over [cf.productFilterSummary] so checkout, the receipt
  /// view, and the settings card all stay in lockstep.
  String _filterLabel(Map filter) => cf.productFilterSummary(filter);

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
  // When non-null, the delivery option is unavailable right now and the
  // pickup toggle is locked on. Used outside the configured delivery
  // window so the user can't switch back to "Entrega a domicilio" only to
  // bounce off submit. The string is rendered as a small caption.
  final String? deliveryLockedReason;

  const AddressCardWidget({
    super.key,
    required this.addresses,
    required this.selectedAddressId,
    required this.onAddressSelected,
    required this.userName,
    required this.userPhone,
    required this.isInstorePickup,
    required this.onPickupToggled,
    this.deliveryLockedReason,
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
                // Locked outside delivery hours — tap is a no-op and the
                // chip stays in the active (pickup) state.
                onTap: deliveryLockedReason != null
                    ? null
                    : () => onPickupToggled(!isInstorePickup),
                behavior: HitTestBehavior.opaque,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      deliveryLockedReason != null
                          ? Icons.lock_outline
                          : Icons.storefront,
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
        if (deliveryLockedReason != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 20),
            child: Text(
              deliveryLockedReason!,
              style: TextStyle(
                fontSize: 12,
                color: Colors.orange[800],
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
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
                const Icon(
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
