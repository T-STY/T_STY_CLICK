import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../components/bottom_fade.dart';
import '../../components/shimmer_placeholder.dart';
import '../../constants/app_images.dart';

import 'create_new_card.dart';

class RewardsCardPage extends StatefulWidget {
  final VoidCallback onBack;
  const RewardsCardPage({super.key, required this.onBack});

  @override
  State<RewardsCardPage> createState() => _RewardsCardPageState();
}

class _RewardsCardPageState extends State<RewardsCardPage> {
  double _saldo = 0.0;
  String _cvv = '';
  final _phoneNumberController = TextEditingController();
  final _existingCardNumberController = TextEditingController();
  final _cvvController = TextEditingController();
  bool _isAddingExistingCard = false;
  bool _showNip = false;

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
      final result = await FirebaseFunctions.instance
          .httpsCallable('getRewardsBalance')
          .call();
      final data = Map<String, dynamic>.from(result.data as Map);
      if (data['hasWallet'] == true && mounted) {
        setState(() {
          _saldo = (data['saldo'] as num?)?.toDouble() ?? 0.0;
          _cvv = (data['cvvCode'] as String?) ?? '';
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error fetching balance: $e');
    }
  }

  void _showAlertDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
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
        );
      },
    );
  }

  Future<void> _addExistingCard() async {
    String cardNumber = _existingCardNumberController.text.trim();
    String cvv = _cvvController.text.trim();

    if (cardNumber.isEmpty || cvv.isEmpty) {
      _showAlertDialog('Error', 'Por favor, ingrese número de tarjeta y NIP');
      return;
    }

    try {
      await FirebaseFunctions.instance
          .httpsCallable('linkRewardsWallet')
          .call(<String, dynamic>{'phone': cardNumber, 'pin': cvv});

      if (!mounted) return;
      _showAlertDialog('Éxito', 'Monedero agregado a tu cuenta');
      setState(() {
        _isAddingExistingCard = false;
        _existingCardNumberController.clear();
        _cvvController.clear();
      });
      _fetchRewardsCardData();
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      _showAlertDialog('Error',
          e.message ?? 'No se encontró un monedero con esos datos.');
    } catch (e) {
      if (kDebugMode) debugPrint('Error adding card: $e');
      _showAlertDialog('Error', 'Error al agregar el monedero. Intenta de nuevo.');
    }
  }

  Future<void> _updateCVV() async {
    String cvv = _cvvController.text.trim();

    if (cvv.length != 4) {
      _showAlertDialog('Error', 'El NIP debe tener exactamente 4 dígitos');
      return;
    }

    try {
      await FirebaseFunctions.instance
          .httpsCallable('updateRewardsCard')
          .call(<String, dynamic>{'pin': cvv});
      if (!mounted) return;
      _showAlertDialog('Éxito', 'NIP actualizado con éxito');
      _fetchRewardsCardData();
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      _showAlertDialog('Error',
          e.message ?? 'No se pudo actualizar el NIP. Intenta de nuevo.');
    } catch (e) {
      if (kDebugMode) debugPrint('Error updating CVV: $e');
      _showAlertDialog('Error', 'No se pudo actualizar el NIP. Intenta de nuevo.');
    }
  }

  Future<void> _updatePhoneNumber() async {
    String phoneNumber = _phoneNumberController.text.trim();

    if (phoneNumber.length != 10) {
      _showAlertDialog(
          'Error', 'El número de teléfono debe tener exactamente 10 dígitos');
      return;
    }

    try {
      await FirebaseFunctions.instance
          .httpsCallable('updateRewardsCard')
          .call(<String, dynamic>{'phone': phoneNumber});
      if (!mounted) return;
      _showAlertDialog('Éxito', 'Número de teléfono actualizado');
      _fetchRewardsCardData();
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      _showAlertDialog('Error',
          e.message ?? 'No se pudo actualizar el número. Intenta de nuevo.');
    } catch (e) {
      if (kDebugMode) debugPrint('Error updating phone: $e');
      _showAlertDialog(
          'Error', 'No se pudo actualizar el número de teléfono. Intenta de nuevo.');
    }
  }

  void _navigateToCreateCard() {
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (_) => CreateNewCard(onBack: () {
          Navigator.of(context).pop();
          _fetchRewardsCardData();
        }),
      ),
    )
        .then((_) {
      _fetchRewardsCardData();
    });
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
                      _buildBalanceCard(userData, cardNumber, saldo),
                      const SizedBox(height: 24),
                      CustomExpansionTile(
                        title: 'Actualizar teléfono',
                        leading: const Icon(Icons.phone_android,
                            color: Colors.black),
                        children: [_buildPhoneNumberUpdateSection()],
                      ),
                      const SizedBox(height: 12),
                      CustomExpansionTile(
                        title: 'Actualizar NIP',
                        leading: const Icon(Icons.lock_outline,
                            color: Colors.black),
                        children: [_buildCVVUpdateSection()],
                      ),
                      const SizedBox(height: 120),
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
    return Container(
      width: double.infinity,
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF141414), Color(0xFF3A3A3A)],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(top: -34, right: -24, child: _decorCircle(130, 0.06)),
          Positioned(bottom: -56, right: 48, child: _decorCircle(150, 0.05)),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.savings,
                              color: Colors.white, size: 18),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Cochinito',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    const Text(
                      'T_STY',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.5,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                const Text(
                  'Saldo disponible',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  '\$${saldo.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _formatNumber(number),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            holder.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () => setState(() => _showNip = !_showNip),
                      behavior: HitTestBehavior.opaque,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'NIP ${_showNip && _cvv.isNotEmpty ? _cvv : '••••'}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Icon(
                            _showNip
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: Colors.white54,
                            size: 16,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _decorCircle(double size, double alpha) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: alpha),
        ),
      );

  String _formatNumber(String number) {
    final d = number.replaceAll(RegExp(r'\D'), '');
    if (d.length == 10) {
      return '${d.substring(0, 3)} ${d.substring(3, 6)} ${d.substring(6)}';
    }
    return d.isEmpty ? number : d;
  }

  Widget _buildPhoneNumberUpdateSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        children: [
          TextFormField(
            controller: _phoneNumberController,
            keyboardType: TextInputType.number,
            maxLength: 10,
            decoration: InputDecoration(
              hintText: 'Nuevo número (10 dígitos)',
              counterText: '',
              prefixIcon: const Icon(Icons.phone_android, size: 20),
              filled: true,
              fillColor: Colors.grey[100],
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            style: const TextStyle(color: Colors.black),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _updatePhoneNumber,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Actualizar teléfono',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCVVUpdateSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        children: [
          TextFormField(
            controller: _cvvController,
            keyboardType: TextInputType.number,
            maxLength: 4,
            obscureText: true,
            decoration: InputDecoration(
              hintText: 'Nuevo NIP (4 dígitos)',
              counterText: '',
              prefixIcon: const Icon(Icons.lock_outline, size: 20),
              filled: true,
              fillColor: Colors.grey[100],
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            style: const TextStyle(color: Colors.black),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _updateCVV,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Actualizar NIP',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
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
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDarkMode ? Colors.white70 : Colors.black87;
    final backgroundColor = isDarkMode ? Colors.grey[800] : Colors.white;
    final cardColor = isDarkMode ? Colors.grey[900] : Colors.white;
    final shadowColor =
    isDarkMode ? Colors.black54 : Colors.grey.withValues(alpha: 0.5);

    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16.0, 0.0, 16.0, 16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.card_membership,
              size: 80,
              color: Colors.black,
            ),
            const SizedBox(height: 20),
            Text(
              'No tienes un monedero asignado a tu cuenta.',
              style: TextStyle(
                fontSize: 16,
                color: textColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _navigateToCreateCard,
              style: ElevatedButton.styleFrom(
                padding:
                const EdgeInsets.symmetric(vertical: 16, horizontal: 100),
                backgroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                shadowColor: shadowColor,
                elevation: 8,
              ),
              child: const Text(
                'Crear Monedero',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _isAddingExistingCard = !_isAddingExistingCard;
                });
              },
              style: ElevatedButton.styleFrom(
                padding:
                const EdgeInsets.symmetric(vertical: 16, horizontal: 100),
                backgroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                shadowColor: shadowColor,
                elevation: 8,
              ),
              child: Text(
                _isAddingExistingCard ? 'Cancelar' : 'Vincular Monedero',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
            ),
            if (_isAddingExistingCard) ...[
              const SizedBox(height: 20),
              Card(
                color: cardColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 4,
                shadowColor: shadowColor,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: TextFormField(
                    controller: _existingCardNumberController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Número de Telefono',
                      labelStyle: TextStyle(color: textColor),
                      filled: true,
                      fillColor: backgroundColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.black),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Card(
                color: cardColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 4,
                shadowColor: shadowColor,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: TextFormField(
                    controller: _cvvController,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'NIP',
                      labelStyle: TextStyle(color: textColor),
                      filled: true,
                      fillColor: backgroundColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.black),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _addExistingCard,
                style: ElevatedButton.styleFrom(
                  padding:
                  const EdgeInsets.symmetric(vertical: 16, horizontal: 25),
                  backgroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  shadowColor: shadowColor,
                  elevation: 8,
                ),
                child: const Text(
                  'Agregar Monedero',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }
}

class CustomExpansionTile extends StatefulWidget {
  final String title;
  final Widget? leading;
  final List<Widget> children;

  const CustomExpansionTile({
    super.key,
    required this.title,
    this.leading,
    this.children = const <Widget>[],
  });

  @override
  State<CustomExpansionTile> createState() => _CustomExpansionTileState();
}

class _CustomExpansionTileState extends State<CustomExpansionTile>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  late final AnimationController _controller;
  late final Animation<double> _iconTurns;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _iconTurns = _controller.drive(Tween<double>(
      begin: 0.0,
      end: 0.5,
    ));
  }

  void _handleTap() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
      elevation: 4,
      child: Column(
        children: [
          Theme(
            data: Theme.of(context).copyWith(
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
            ),
            child: ListTile(
              onTap: _handleTap,
              leading: widget.leading,
              title: Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              trailing: RotationTransition(
                turns: _iconTurns,
                child: const Icon(Icons.expand_more),
              ),
            ),
          ),
          ClipRect(
            child: AnimatedAlign(
              alignment: Alignment.center,
              heightFactor: _isExpanded ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 250),
              child: Column(children: widget.children),
            ),
          ),
        ],
      ),
    );
  }
}
