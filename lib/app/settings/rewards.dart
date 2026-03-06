import 'package:flutter/material.dart';
import 'package:flutter_credit_card/flutter_credit_card.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  Map<String, dynamic>? _rewardsCardData;
  final _phoneNumberController = TextEditingController();
  final _existingCardNumberController = TextEditingController();
  final _cvvController = TextEditingController();
  bool _isAddingExistingCard = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _fetchRewardsCardData();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> _userCardStream() {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('rewardsCard')
        .doc('cardInfo')
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _rewardsCardStream(
      String cardNumber) {
    return FirebaseFirestore.instance
        .collection('rewards')
        .where('cardNumber', isEqualTo: cardNumber)
        .snapshots();
  }

  Future<void> _fetchRewardsCardData() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    try {
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
            double? saldo = rewardsData['saldo'] is String
                ? double.tryParse(rewardsData['saldo'])
                : (rewardsData['saldo'] is int)
                ? (rewardsData['saldo'] as int).toDouble()
                : rewardsData['saldo'];

            if (mounted) {
              setState(() {
                _rewardsCardData = {
                  ..._rewardsCardData!,
                  'saldo': saldo ?? 0.0,
                };
              });
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching card data: $e');
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

    String prefixedCardNumber = 'T_STY-$cardNumber';

    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('rewards')
          .where('cardNumber', isEqualTo: prefixedCardNumber)
          .where('cvvCode', isEqualTo: cvv)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        var rewardsData = querySnapshot.docs.first.data();
        final userId = FirebaseAuth.instance.currentUser?.uid;

        if (userId != null) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .collection('rewardsCard')
              .doc('cardInfo')
              .set(rewardsData);

          if (!mounted) return;
          _showAlertDialog('Éxito', 'Monedero agregado a tu cuenta');

          setState(() {
            _isAddingExistingCard = false;
            _existingCardNumberController.clear();
            _cvvController.clear();
          });
        }
      } else {
        _showAlertDialog('Error',
            'No se encontró un monedero con esos datos. Verifica tu número y NIP.');
      }
    } catch (e) {
      _showAlertDialog('Error', 'Error al agregar el monedero: $e');
    }
  }

  Future<void> _updateCVV() async {
    String cvv = _cvvController.text.trim();

    if (cvv.length != 4) {
      _showAlertDialog('Error', 'El NIP debe tener exactamente 4 dígitos');
      return;
    }

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      _showAlertDialog('Error', 'Usuario no autenticado');
      return;
    }

    try {
      final userDocRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('rewardsCard')
          .doc('cardInfo');

      await userDocRef.update({
        'cvvCode': cvv,
      });

      final querySnapshot = await FirebaseFirestore.instance
          .collection('rewards')
          .where('cardNumber', isEqualTo: _rewardsCardData?['cardNumber'])
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final rewardsDocRef = querySnapshot.docs.first.reference;

        await rewardsDocRef.update({
          'cvvCode': cvv,
        });

        if (!mounted) return;
        _showAlertDialog('Éxito', 'NIP actualizado con éxito');
      } else {
        _showAlertDialog('Error', 'No se encontró ningún monedero');
      }
    } catch (e) {
      _showAlertDialog('Error', 'No se pudo actualizar el NIP: $e');
    }
  }

  Future<void> _updatePhoneNumber() async {
    String phoneNumber = _phoneNumberController.text.trim();

    if (phoneNumber.length != 10) {
      _showAlertDialog(
          'Error', 'El número de teléfono debe tener exactamente 10 dígitos');
      return;
    }

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      _showAlertDialog('Error', 'Usuario no autenticado');
      return;
    }

    String updatedPhoneNumber = "T_STY-$phoneNumber";

    try {
      final userDocRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('rewardsCard')
          .doc('cardInfo');

      await userDocRef.update({
        'cardNumber': updatedPhoneNumber,
      });

      final querySnapshot = await FirebaseFirestore.instance
          .collection('rewards')
          .where('cardNumber', isEqualTo: _rewardsCardData?['cardNumber'])
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final rewardsDocRef = querySnapshot.docs.first.reference;

        await rewardsDocRef.update({
          'cardNumber': updatedPhoneNumber,
        });

        if (mounted) {
          setState(() {
            _rewardsCardData?['cardNumber'] = updatedPhoneNumber;
          });
        }

        _showAlertDialog('Éxito', 'Número de teléfono actualizado');
      } else {
        _showAlertDialog('Error', 'No se encontró ningún monedero');
      }
    } catch (e) {
      _showAlertDialog(
          'Error', 'No se pudo actualizar el número de teléfono: $e');
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        widget.onBack();
      },
      child: Scaffold(
        appBar: AppBar(
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
        body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _userCardStream(),
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

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _rewardsCardStream(cardNumber),
              builder: (context, rewardsSnapshot) {
                if (rewardsSnapshot.connectionState ==
                    ConnectionState.waiting) {
                  return _buildShimmerLoading();
                }

                if (!rewardsSnapshot.hasData ||
                    rewardsSnapshot.data!.docs.isEmpty) {
                  return _buildNoCardView();
                }

                var rewardsData = rewardsSnapshot.data!.docs.first.data();
                double? saldo = (rewardsData['saldo'] is int)
                    ? (rewardsData['saldo'] as int).toDouble()
                    : rewardsData['saldo'];

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      CreditCardWidget(
                        cardNumber: cardNumber,
                        obscureCardNumber: false,
                        expiryDate: userData?['customerSince'] ?? 'MM/YY',
                        cardHolderName:
                        userData?['cardHolderName'] ?? 'Card Holder',
                        cvvCode: userData?['cvvCode'] ?? '',
                        obscureCardCvv: false,
                        showBackView: false,
                        isHolderNameVisible: true,
                        cardType: CardType.t_sty,
                        bankName: 'T_STY',
                        backgroundImage: 'assets/images/card_bg.png',
                        customCardTypeIcons: <CustomCardTypeIcon>[
                          CustomCardTypeIcon(
                            cardType: CardType.t_sty,
                            cardImage: Image.asset(
                              'assets/images/visa.png',
                              height: 48,
                              width: 48,
                            ),
                          ),
                        ],
                        onCreditCardWidgetChange: (creditCardBrand) {},
                      ),
                      const SizedBox(height: 10),
                      Card(
                        color: Colors.black87,
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        margin: const EdgeInsets.symmetric(
                            vertical: 4, horizontal: 16),
                        child: ListTile(
                          leading: const Icon(Icons.account_balance_wallet,
                              color: Colors.white),
                          title: const Text(
                            'Monedero',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          trailing: Text(
                            '\$${saldo?.toStringAsFixed(2) ?? '0.00'}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.lightGreenAccent,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      CustomExpansionTile(
                        title: 'Actualizar Teléfono',
                        children: [_buildPhoneNumberUpdateSection()],
                      ),
                      const SizedBox(height: 20),
                      CustomExpansionTile(
                        title: 'Actualizar NIP',
                        children: [_buildCVVUpdateSection()],
                      ),
                      const SizedBox(height: 120),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildPhoneNumberUpdateSection() {
    final accentColor = Colors.grey[700]!;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: TextFormField(
                controller: _phoneNumberController,
                keyboardType: TextInputType.number,
                maxLength: 10,
                decoration: InputDecoration(
                  hintText: 'Número de Teléfono (10 dígitos)',
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
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 50,
              child: ElevatedButton(
                onPressed: _updatePhoneNumber,
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: EdgeInsets.zero,
                ),
                child: const Icon(
                  Icons.check_circle,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCVVUpdateSection() {
    final accentColor = Colors.grey[700]!;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: TextFormField(
                controller: _cvvController,
                keyboardType: TextInputType.number,
                maxLength: 4,
                obscureText: true,
                decoration: InputDecoration(
                  hintText: 'NIP (4 dígitos)',
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
                onEditingComplete: () {
                  String cvv = _cvvController.text.trim();
                  if (cvv.length != 4) {
                    _showAlertDialog(
                        'Error', 'El NIP debe tener exactamente 4 dígitos');
                  }
                },
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 50,
              child: ElevatedButton(
                onPressed: _updateCVV,
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Icon(
                  Icons.check_circle,
                  color: Colors.white,
                ),
              ),
            ),
          ],
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