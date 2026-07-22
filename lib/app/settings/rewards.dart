import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../utils/callable_retry.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../components/bottom_fade.dart';
import '../../components/cochinito_card.dart';
import '../../components/shimmer_placeholder.dart';
import '../../constants/app_images.dart';

class RewardsCardPage extends StatefulWidget {
  final VoidCallback onBack;

  /// Called when the user wants to open the "Crear monedero" flow. The
  /// settings shell hosts the create screen as its own indexed page so the
  /// bottom nav stays visible — passing the callback up keeps the nav
  /// alive instead of pushing a fresh Navigator route on top of the shell.
  final VoidCallback? onCreateCard;

  const RewardsCardPage({
    super.key,
    required this.onBack,
    this.onCreateCard,
  });

  @override
  State<RewardsCardPage> createState() => _RewardsCardPageState();
}

class _RewardsCardPageState extends State<RewardsCardPage> {
  double _saldo = 0.0;

  /// Whether the balance actually came back from the server. Until it does,
  /// `_saldo` is just its 0.0 initial value — printing that as "$0.00" is how
  /// a healthy wallet ends up looking empty to the customer.
  bool _balanceLoaded = false;
  bool _balanceFailed = false;
  String _cvv = '';
  final _phoneNumberController = TextEditingController();
  final _existingCardNumberController = TextEditingController();
  final _cvvController = TextEditingController();
  bool _isAddingExistingCard = false;

  // Linking-flow only: form key + loading + NIP-visibility toggle. The
  // controllers above are reused (the link form is mutually exclusive with
  // the update-NIP form so the shared `_cvvController` never collides).
  final GlobalKey<FormState> _linkFormKey = GlobalKey<FormState>();
  bool _isLinking = false;
  bool _linkNipVisible = false;

  // Update-phone + update-NIP tile state. These render once the wallet is
  // linked, mutually exclusive with the vincular flow. ExpansionTile
  // manages its own open/closed visual — we only keep loading + NIP
  // visibility here.
  final GlobalKey<FormState> _phoneFormKey = GlobalKey<FormState>();
  final GlobalKey<FormState> _nipFormKey = GlobalKey<FormState>();
  bool _newNipVisible = false;
  bool _isUpdatingPhone = false;
  bool _isUpdatingNip = false;

  // Weak-PIN blacklist (same as the create-monedero validator). The new NIP
  // must clear this and the all-same-digit regex below before we let it
  // through to the CF — otherwise we'd be downgrading wallet security
  // every time someone "updated" to 0000.
  static const Set<String> _weakPins = {
    '1234', '4321', '2345', '3456', '4567',
    '5678', '6789', '7890', '0123', '0987',
    '9876', '8765', '7654', '6543', '5432',
    '1212', '1004', '2000', '2580',
    '1122', '1313', '2001', '1010',
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _fetchRewardsCardData();
  }

  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _cardStream =
      FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser?.uid)
          .collection('rewardsCard')
          .doc('cardInfo')
          .snapshots();

  Future<void> _fetchRewardsCardData() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    try {
      final result = await callIdempotentCallable('getRewardsBalance');
      final data = Map<String, dynamic>.from(result.data as Map);
      if (data['hasWallet'] == true && mounted) {
        setState(() {
          _saldo = (data['saldo'] as num?)?.toDouble() ?? 0.0;
          _cvv = (data['cvvCode'] as String?) ?? '';
          _balanceLoaded = true;
          _balanceFailed = false;
        });
      } else if (mounted) {
        // Wallet link didn't resolve. Don't let the card keep printing the
        // initial 0.0 as if it were the real balance.
        setState(() => _balanceFailed = true);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error fetching balance: $e');
      // Swallowing this used to render "$0.00" over a perfectly healthy
      // wallet — the customer reads that as "my points are gone".
      if (mounted) setState(() => _balanceFailed = true);
    }
  }

  void _showAlertDialog(String title, String message) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Future<void> _addExistingCard() async {
    if (_isLinking) return;
    if (!(_linkFormKey.currentState?.validate() ?? false)) return;

    setState(() => _isLinking = true);

    final phone = _existingCardNumberController.text.trim();
    final pin = _cvvController.text.trim();

    try {
      await FirebaseFunctions.instance
          .httpsCallable('linkRewardsWallet')
          .call(<String, dynamic>{'phone': phone, 'pin': pin});

      if (!mounted) return;
      _showAlertDialog('Listo', 'Tu monedero quedó vinculado a tu cuenta.');
      setState(() {
        _isAddingExistingCard = false;
        _existingCardNumberController.clear();
        _cvvController.clear();
      });
      _fetchRewardsCardData();
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      // The CF returns a Spanish, human-readable reason for every reject
      // (wrong NIP, unknown phone, already-linked, etc.). Surface it.
      _showAlertDialog('No se pudo vincular',
          e.message ?? 'No encontramos un monedero con esos datos.');
    } catch (e) {
      if (kDebugMode) debugPrint('Error adding card: $e');
      if (!mounted) return;
      _showAlertDialog('Error',
          'No pudimos vincular tu monedero. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _isLinking = false);
    }
  }

  String? _validateLinkPhone(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Ingresa el número del monedero';
    if (!RegExp(r'^\d{10}$').hasMatch(v)) {
      return 'Debe ser un número de 10 dígitos';
    }
    return null;
  }

  String? _validateLinkNip(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Ingresa el NIP';
    if (!RegExp(r'^\d{4}$').hasMatch(v)) return 'Deben ser 4 dígitos';
    return null;
  }

  String? _validateNewPhone(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Ingresa el nuevo número';
    if (!RegExp(r'^\d{10}$').hasMatch(v)) {
      return 'Debe ser un número de 10 dígitos';
    }
    return null;
  }

  String? _validateNewNip(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Ingresa el nuevo NIP';
    if (!RegExp(r'^\d{4}$').hasMatch(v)) return 'Deben ser 4 dígitos';
    if (RegExp(r'^(\d)\1{3}$').hasMatch(v)) {
      return 'Elige un NIP menos común';
    }
    if (_weakPins.contains(v)) return 'Elige un NIP menos común';
    return null;
  }

  Future<void> _updateCVV() async {
    if (_isUpdatingNip) return;
    if (!(_nipFormKey.currentState?.validate() ?? false)) return;

    setState(() => _isUpdatingNip = true);
    final cvv = _cvvController.text.trim();

    try {
      await FirebaseFunctions.instance
          .httpsCallable('updateRewardsCard')
          .call(<String, dynamic>{'pin': cvv});
      if (!mounted) return;
      _showAlertDialog('Listo', 'Tu NIP se actualizó correctamente.');
      _cvvController.clear();
      _fetchRewardsCardData();
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      _showAlertDialog('No se pudo actualizar',
          e.message ?? 'No se pudo actualizar el NIP. Intenta de nuevo.');
    } catch (e) {
      if (kDebugMode) debugPrint('Error updating CVV: $e');
      if (!mounted) return;
      _showAlertDialog(
          'Error', 'No se pudo actualizar el NIP. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _isUpdatingNip = false);
    }
  }

  Future<void> _updatePhoneNumber() async {
    if (_isUpdatingPhone) return;
    if (!(_phoneFormKey.currentState?.validate() ?? false)) return;

    setState(() => _isUpdatingPhone = true);
    final phoneNumber = _phoneNumberController.text.trim();

    try {
      await FirebaseFunctions.instance
          .httpsCallable('updateRewardsCard')
          .call(<String, dynamic>{'phone': phoneNumber});
      if (!mounted) return;
      _showAlertDialog(
          'Listo', 'Tu número de teléfono se actualizó correctamente.');
      _phoneNumberController.clear();
      _fetchRewardsCardData();
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      _showAlertDialog('No se pudo actualizar',
          e.message ?? 'No se pudo actualizar el número. Intenta de nuevo.');
    } catch (e) {
      if (kDebugMode) debugPrint('Error updating phone: $e');
      if (!mounted) return;
      _showAlertDialog(
          'Error', 'No se pudo actualizar el número. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _isUpdatingPhone = false);
    }
  }

  void _navigateToCreateCard() {
    // Old code pushed a fresh MaterialPageRoute via the root Navigator,
    // which covered the bottom nav. The settings shell already hosts the
    // create screen at its own index — defer to it via the callback so
    // the nav bar stays visible.
    widget.onCreateCard?.call();
  }

  @override
  void dispose() {
    _phoneNumberController.dispose();
    _cvvController.dispose();
    _existingCardNumberController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final bool keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        widget.onBack();
      },
      child: Scaffold(
        appBar: AppBar(
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
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          titleTextStyle: const TextStyle(
            color: Colors.black,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        body: BottomFade(
          clearHeight: keyboardOpen ? 0 : 96,
          fadeHeight: keyboardOpen ? 0 : 48,
          child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _cardStream,
          builder: (context, userCardSnapshot) {
            if (userCardSnapshot.connectionState == ConnectionState.waiting) {
              return _buildShimmerLoading();
            }

            if (!userCardSnapshot.hasData || !userCardSnapshot.data!.exists) {
              return _buildNoCardView();
            }

            var userData = userCardSnapshot.data!.data();
            String? cardNumber = userData?['cardNumber'];

            if (cardNumber == null) {
              return _buildNoCardView();
            }

            final double saldo = _saldo;
            return SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (_balanceFailed && !_balanceLoaded)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF4E5),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: Colors.orange.withValues(alpha: 0.45)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.info_outline,
                                    size: 20, color: Colors.orange),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Text(
                                    'No pudimos consultar tu saldo en este '
                                    'momento. El monto mostrado puede no estar '
                                    'actualizado.',
                                    style: TextStyle(
                                        fontSize: 12.5,
                                        height: 1.35,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                                TextButton(
                                  onPressed: _fetchRewardsCardData,
                                  child: const Text('Reintentar'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      _buildBalanceCard(userData, cardNumber, saldo),
                      if (userData?['isVip'] != true) ...[
                        const SizedBox(height: 14),
                        _buildVipEnrollCard(),
                      ],
                      const SizedBox(height: 22),
                      // Section eyebrow + two collapsible cards. Mirrors
                      // the settings-page card pattern (white Card with
                      // elevation 4, expansion tile, expand_more chevron,
                      // small inline form) so the two screens read as one
                      // product.
                      _settingsSectionLabel('Ajustes de monedero'),
                      _ExpandingPhoneCard(
                        formKey: _phoneFormKey,
                        controller: _phoneNumberController,
                        validator: _validateNewPhone,
                        isLoading: _isUpdatingPhone,
                        onSave: _updatePhoneNumber,
                      ),
                      const SizedBox(height: 10),
                      _ExpandingNipCard(
                        formKey: _nipFormKey,
                        controller: _cvvController,
                        validator: _validateNewNip,
                        isLoading: _isUpdatingNip,
                        nipVisible: _newNipVisible,
                        onToggleVisible: () => setState(
                            () => _newNipVisible = !_newNipVisible),
                        onSave: _updateCVV,
                      ),
                      const SizedBox(height: 160),
                    ],
                  ),
                );
          },
        ),
        ),
      ),
    );
  }

  Widget _buildBalanceCard(
      Map<String, dynamic>? userData, String number, double saldo) {
    final holder = (userData?['cardHolderName'] ?? 'Titular').toString();
    final digits = number.replaceAll(RegExp(r'\D'), '');
    final qrToken = (userData?['qrToken'] as String?);
    final isVip = userData?['isVip'] == true;
    return CochinitoCard(
      saldo: saldo,
      phoneDigits: digits,
      holder: holder,
      nip: _cvv,
      showNipReveal: true,
      // The QR back face needs a real 10-digit phone to be useful; if the
      // wallet doc somehow has a malformed/short number, just disable the
      // flip (the front-only static card still works). A VIP token makes
      // the flip useful regardless of the stored phone shape.
      enableQrFlip:
          digits.length == 10 || (qrToken != null && qrToken.isNotEmpty),
      qrToken: qrToken,
      isVip: isVip,
    );
  }

  bool _isEnrollingVip = false;
  bool _vipConfirming = false;
  String? _vipError;

  /// Opt-in VIP enrollment — everything happens IN the card (no dialogs).
  /// Mints the signed QR card (the PDV verifies it server-side) and flips the
  /// persistent isVip flag that drives the +50% accrual. On success the
  /// cardInfo stream flips isVip → this card auto-hides and the gold card
  /// appears, so no confirmation popup is needed.
  Future<void> _enrollVip() async {
    if (_isEnrollingVip) return;
    setState(() {
      _isEnrollingVip = true;
      _vipError = null;
    });
    try {
      await FirebaseFunctions.instance.httpsCallable('enrollVip').call();
      // Success is signalled by the card swapping to the gold VIP card.
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        setState(() =>
            _vipError = e.message ?? 'No se pudo completar. Intenta de nuevo.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _vipError = 'No se pudo completar. Intenta de nuevo.');
      }
    } finally {
      if (mounted) setState(() => _isEnrollingVip = false);
    }
  }

  Widget _buildVipEnrollCard() {
    return Card(
      elevation: 4,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        alignment: Alignment.topCenter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: _isEnrollingVip
                  ? null
                  : () => setState(() {
                        _vipConfirming = !_vipConfirming;
                        _vipError = null;
                      }),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF6DC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFF2D67B)),
                      ),
                      child: const Icon(Icons.workspace_premium_rounded,
                          color: Color(0xFFC79A2A), size: 22),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Hazte Cliente VIP',
                              style: TextStyle(
                                  fontSize: 14.5, fontWeight: FontWeight.w800)),
                          SizedBox(height: 2),
                          Text(
                              '+50% de puntos con tu QR seguro en caja. Gratis.',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.black54,
                                  height: 1.3)),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: _vipConfirming ? 0.25 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: const Icon(Icons.chevron_right,
                          color: Colors.black38),
                    ),
                  ],
                ),
              ),
            ),
            if (_vipConfirming)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Tu cochinito se vuelve tarjeta VIP con código seguro. '
                      'Muéstralo en caja y gana +50% de puntos en cada compra.',
                      style: TextStyle(
                          fontSize: 12.5, color: Colors.black54, height: 1.35),
                    ),
                    if (_vipError != null) ...[
                      const SizedBox(height: 8),
                      Text(_vipError!,
                          style: TextStyle(
                              fontSize: 12.5,
                              color: Colors.red.shade600,
                              fontWeight: FontWeight.w600)),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _isEnrollingVip
                                ? null
                                : () => setState(() => _vipConfirming = false),
                            child: const Text('Ahora no'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                                backgroundColor: Colors.black),
                            onPressed: _isEnrollingVip ? null : _enrollVip,
                            child: _isEnrollingVip
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation(
                                            Colors.white)),
                                  )
                                : const Text('¡Ser VIP!'),
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
    );
  }

  /// Section eyebrow matching the settings page (`_sectionLabel` there):
  /// 12 px, w700, letter-spacing 0.8, grey[500], uppercased, with
  /// `(4, 0, 4, 8)` padding above the first card.
  Widget _settingsSectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: Colors.grey[500],
        ),
      ),
    );
  }

  Widget _buildShimmerLoading() {
    return const SingleChildScrollView(
      padding: EdgeInsets.all(16.0),
      child: Column(
        children: [
          ShimmerPlaceholder(
            height: 200,
            width: double.infinity,
            shapeBorder: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(16)),
            ),
          ),
          SizedBox(height: 10),
          ShimmerPlaceholder(
            height: 70,
            width: double.infinity,
            shapeBorder: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
          ),
          SizedBox(height: 20),
          ShimmerPlaceholder(
            height: 60,
            width: double.infinity,
            shapeBorder: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(16)),
            ),
          ),
          SizedBox(height: 10),
          ShimmerPlaceholder(
            height: 60,
            width: double.infinity,
            shapeBorder: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(16)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoCardView() {
    return SingleChildScrollView(
      // Bottom padding must clear the body's BottomFade region. The fade
      // wraps the entire scaffold body with clearHeight 96 + fadeHeight 48
      // (= 144px from the bottom is masked toward transparent). With less
      // padding the "Si olvidaste tu NIP..." footer landed inside the fade
      // and read as washed-out. 160 keeps it cleanly above the mask.
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 160),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Hero illustration block. Soft grey rounded panel with a piggy
          // icon tile + "Sin monedero" copy. Sets the tone before the two
          // options below — same dark gradient idea as the active card,
          // just inverted (light surface, dark accent).
          Container(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
            decoration: BoxDecoration(
              color: const Color(0xFFF6F7F9),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFFE3E5EC)),
            ),
            child: Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: const Color(0xFF141414),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.savings_rounded,
                      color: Colors.white, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Sin cochinito',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF141414),
                          letterSpacing: -0.3,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Crea uno nuevo o vincula el monedero que ya tienes en tienda para empezar a acumular saldo.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          const _ChooseLabel(label: 'ELIGE UNA OPCIÓN'),
          const SizedBox(height: 10),

          // Option 1 — Crear monedero (primary, leads to create screen).
          _OptionCard(
            icon: Icons.add_card_rounded,
            title: 'Crear monedero nuevo',
            subtitle: 'Te toma menos de un minuto.',
            primary: true,
            onTap: _navigateToCreateCard,
          ),
          const SizedBox(height: 10),

          // Option 2 — Vincular monedero existente (secondary, expands).
          _LinkExistingTile(
            expanded: _isAddingExistingCard,
            onToggle: () => setState(
                () => _isAddingExistingCard = !_isAddingExistingCard),
          ),

          // Inline form is shown when the user opens the vincular tile.
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _isAddingExistingCard
                ? Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: _LinkForm(
                      formKey: _linkFormKey,
                      phoneController: _existingCardNumberController,
                      nipController: _cvvController,
                      nipVisible: _linkNipVisible,
                      onToggleNipVisible: () => setState(
                          () => _linkNipVisible = !_linkNipVisible),
                      isLoading: _isLinking,
                      onSubmit: _addExistingCard,
                      phoneValidator: _validateLinkPhone,
                      nipValidator: _validateLinkNip,
                    ),
                  )
                : const SizedBox.shrink(),
          ),

          const SizedBox(height: 28),
          // Privacy note at the bottom — same shield-style as the create
          // screen so the two screens feel like one product.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(Icons.shield_outlined,
                    size: 15, color: Colors.grey[600]),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Si olvidaste tu NIP, acércate al PDV — un encargado puede reiniciártelo.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Colors.grey[700],
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// No-card-view atoms — option cards, vincular tile + form, primary button
// ─────────────────────────────────────────────────────────────────────────

class _ChooseLabel extends StatelessWidget {
  final String label;
  const _ChooseLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: Color(0xFF6B7280),
          letterSpacing: 1.6,
        ),
      ),
    );
  }
}

/// One-tap option card. The primary variant uses the dark ink fill (CTA),
/// the secondary variant the soft-grey fill. Same shape on both so the two
/// options read as siblings rather than competing buttons.
class _OptionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool primary;
  final VoidCallback onTap;

  const _OptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = primary ? const Color(0xFF141414) : const Color(0xFFF6F7F9);
    final fg = primary ? Colors.white : const Color(0xFF141414);
    final muted = primary ? Colors.white70 : Colors.grey[700];
    final border = primary
        ? Colors.transparent
        : const Color(0xFFE3E5EC);
    final iconBg = primary ? Colors.white.withValues(alpha: 0.14) : Colors.white;
    final iconFg = primary ? Colors.white : const Color(0xFF141414);

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: border),
          ),
          padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(13),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: iconFg, size: 21),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: fg,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: muted,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.arrow_forward_rounded,
                  color: fg.withValues(alpha: 0.8), size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

/// Secondary-variant tile for "Ya tengo monedero". When tapped it doesn't
/// navigate; it expands an inline form below itself.
class _LinkExistingTile extends StatelessWidget {
  final bool expanded;
  final VoidCallback onToggle;

  const _LinkExistingTile({
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF6F7F9),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE3E5EC)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(13),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.link_rounded,
                    color: Color(0xFF141414), size: 21),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Ya tengo un monedero',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF141414),
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Vincúlalo con tu teléfono y NIP.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[700],
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              AnimatedRotation(
                turns: expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: const Icon(Icons.expand_more_rounded,
                    color: Color(0xFF141414), size: 22),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Inline form rendered under the `_LinkExistingTile` when expanded.
class _LinkForm extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController phoneController;
  final TextEditingController nipController;
  final bool nipVisible;
  final VoidCallback onToggleNipVisible;
  final bool isLoading;
  final VoidCallback onSubmit;
  final String? Function(String?) phoneValidator;
  final String? Function(String?) nipValidator;

  const _LinkForm({
    required this.formKey,
    required this.phoneController,
    required this.nipController,
    required this.nipVisible,
    required this.onToggleNipVisible,
    required this.isLoading,
    required this.onSubmit,
    required this.phoneValidator,
    required this.nipValidator,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE3E5EC)),
      ),
      child: Form(
        key: formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          children: [
            _LinkField(
              icon: Icons.phone_iphone_rounded,
              label: 'Número del monedero',
              hint: '10 dígitos',
              controller: phoneController,
              validator: phoneValidator,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
            ),
            const SizedBox(height: 10),
            _LinkField(
              icon: Icons.lock_outline_rounded,
              label: 'NIP',
              hint: '4 dígitos',
              controller: nipController,
              validator: nipValidator,
              keyboardType: TextInputType.number,
              obscureText: !nipVisible,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              trailing: IconButton(
                onPressed: onToggleNipVisible,
                tooltip: nipVisible ? 'Ocultar NIP' : 'Mostrar NIP',
                splashRadius: 18,
                icon: Icon(
                  nipVisible
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 18,
                  color: const Color(0xFF6B7280),
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 50,
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isLoading ? null : onSubmit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF141414),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFF141414),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.4, color: Colors.white),
                      )
                    : const Text(
                        'Vincular monedero',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Single labelled field used inside `_LinkForm`. Same visual rhythm as the
/// fields on the create-monedero screen (ink icon tile + small eyebrow +
/// bold input) so the two flows feel like one product.
class _LinkField extends StatelessWidget {
  final IconData icon;
  final String label;
  final String hint;
  final TextEditingController controller;
  final String? Function(String?) validator;
  final TextInputType keyboardType;
  final bool obscureText;
  final List<TextInputFormatter>? inputFormatters;
  final Widget? trailing;

  const _LinkField({
    required this.icon,
    required this.label,
    required this.hint,
    required this.controller,
    required this.validator,
    this.keyboardType = TextInputType.text,
    this.obscureText = false,
    this.inputFormatters,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F7F9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3E5EC)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF141414),
              borderRadius: BorderRadius.circular(11),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: Colors.white, size: 17),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: Color(0xFF6B7280),
                  ),
                ),
                TextFormField(
                  controller: controller,
                  validator: validator,
                  keyboardType: keyboardType,
                  obscureText: obscureText,
                  inputFormatters: inputFormatters,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF141414),
                    letterSpacing: 0.2,
                  ),
                  cursorColor: const Color(0xFF141414),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: hint,
                    hintStyle: const TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontWeight: FontWeight.w500,
                      fontSize: 13.5,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    errorStyle: const TextStyle(
                      fontSize: 11,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 4),
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Update-section cards — these mirror `_buildExpandingInputCard` in
// settings.dart: white Material `Card` (elevation 4, 12 px radius,
// `Colors.black26` shadow), `ExpansionTile` with a black icon + 16 px w600
// title, `expand_more` chevron in `black54`, and an inline form below with
// a grey-100 filled `TextFormField` plus a small 50×50 check-icon black
// button. Same look-and-feel as the rest of the settings shell.
// ─────────────────────────────────────────────────────────────────────────

const Color _kSettingsAccent = Colors.black;
const Color _kSettingsCard = Colors.white;

class _ExpandingPhoneCard extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController controller;
  final String? Function(String?) validator;
  final bool isLoading;
  final VoidCallback onSave;

  const _ExpandingPhoneCard({
    required this.formKey,
    required this.controller,
    required this.validator,
    required this.isLoading,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return _SettingsExpandingCard(
      title: 'Actualizar teléfono',
      icon: Icons.phone_android,
      body: Form(
        key: formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: _InlineFieldRow(
          controller: controller,
          validator: validator,
          hintText: 'Nuevo número (10 dígitos)',
          obscureText: false,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ],
          isLoading: isLoading,
          onSave: onSave,
        ),
      ),
    );
  }
}

class _ExpandingNipCard extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController controller;
  final String? Function(String?) validator;
  final bool isLoading;
  final bool nipVisible;
  final VoidCallback onToggleVisible;
  final VoidCallback onSave;

  const _ExpandingNipCard({
    required this.formKey,
    required this.controller,
    required this.validator,
    required this.isLoading,
    required this.nipVisible,
    required this.onToggleVisible,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return _SettingsExpandingCard(
      title: 'Actualizar NIP',
      icon: Icons.lock_outline,
      body: Form(
        key: formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: _InlineFieldRow(
          controller: controller,
          validator: validator,
          hintText: 'Nuevo NIP (4 dígitos)',
          obscureText: !nipVisible,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(4),
          ],
          isLoading: isLoading,
          onSave: onSave,
          // Eye toggle sits inside the field as a suffixIcon — matches
          // how the password field on the settings page renders its
          // show/hide affordance.
          suffixIcon: IconButton(
            onPressed: onToggleVisible,
            tooltip: nipVisible ? 'Ocultar NIP' : 'Mostrar NIP',
            splashRadius: 18,
            icon: Icon(
              nipVisible
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: 18,
              color: Colors.black54,
            ),
          ),
        ),
      ),
    );
  }
}

/// Generic settings-style expanding card. Takes a title, leading icon and
/// the body to render under the header. Settings page uses this exact
/// surface treatment (elevation 4, 12 px radius, ExpansionTile with the
/// `expand_more` chevron) for every editable field.
class _SettingsExpandingCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget body;

  const _SettingsExpandingCard({
    required this.title,
    required this.icon,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: _kSettingsCard,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 4,
      shadowColor: Colors.black26,
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
        child: ExpansionTile(
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: EdgeInsets.zero,
          title: Row(
            children: [
              Icon(icon, color: _kSettingsAccent),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: _kSettingsAccent,
                ),
              ),
            ],
          ),
          trailing:
              const Icon(Icons.expand_more, color: Colors.black54),
          children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: body,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Inline `TextFormField` + 50×50 black check button — same layout as
/// settings' `_buildExpandingInputCard` body, with a spinner swapped in
/// while the CF call is in flight.
class _InlineFieldRow extends StatelessWidget {
  final TextEditingController controller;
  final String? Function(String?) validator;
  final String hintText;
  final bool obscureText;
  final TextInputType keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final bool isLoading;
  final VoidCallback onSave;
  final Widget? suffixIcon;

  const _InlineFieldRow({
    required this.controller,
    required this.validator,
    required this.hintText,
    required this.obscureText,
    required this.keyboardType,
    required this.inputFormatters,
    required this.isLoading,
    required this.onSave,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: TextFormField(
              controller: controller,
              obscureText: obscureText,
              keyboardType: keyboardType,
              inputFormatters: inputFormatters,
              validator: validator,
              decoration: InputDecoration(
                hintText: hintText,
                filled: true,
                fillColor: Colors.grey[100],
                contentPadding: const EdgeInsets.symmetric(
                    vertical: 14, horizontal: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: suffixIcon,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 50,
            child: ElevatedButton(
              onPressed: isLoading ? null : onSave,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kSettingsAccent,
                disabledBackgroundColor: _kSettingsAccent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: EdgeInsets.zero,
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(
                      Icons.check_circle,
                      color: Colors.white,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
