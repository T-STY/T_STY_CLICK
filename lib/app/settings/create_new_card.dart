import 'package:flutter/material.dart';
import 'package:flutter_credit_card/flutter_credit_card.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';
import '../../constants/app_images.dart';
import '../../utils/crypto_utils.dart';

class CreateNewCard extends StatefulWidget {
  final VoidCallback onBack;
  const CreateNewCard({super.key, required this.onBack});

  @override
  State<CreateNewCard> createState() => _CreateNewCardState();
}

class _CreateNewCardState extends State<CreateNewCard> {
  final GlobalKey<FormState> _createCardFormKey = GlobalKey<FormState>();

  String cardNumber = '';
  String expiryDate = '';
  String cardHolderName = '';
  String cvvCode = '';
  bool isCvvFocused = false;
  late String customerSince;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    customerSince = DateFormat('MM/yyyy').format(DateTime.now());
  }

  void _onCreditCardModelChange(CreditCardModel data) {
    setState(() {
      if (data.cardNumber.startsWith('T_STY-')) {
        cardNumber = data.cardNumber.substring(5);
      } else {
        cardNumber = data.cardNumber;
      }
      cardHolderName = data.cardHolderName;
      cvvCode = data.cvvCode;
      isCvvFocused = data.isCvvFocused;
    });
  }

  String? _validateCardHolderName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter card holder name';
    }
    final regex = RegExp(r'^[a-zA-Z\s]+$');
    if (!regex.hasMatch(value)) {
      return 'Name can only contain letters and spaces';
    }
    return null;
  }

  String? _validateCardNumber(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter card number';
    }
    if (!value.startsWith('T_STY-')) {
      return 'Card number must start with T_STY-';
    }
    final numberPart = value.substring(6);
    final regex = RegExp(r'^\d{10}$');
    if (!regex.hasMatch(numberPart)) {
      return 'Please enter a valid 10-digit phone number after T_STY-';
    }
    return null;
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

  Future<void> _saveCard() async {
    if (_createCardFormKey.currentState?.validate() ?? false) {
      setState(() {
        _isLoading = true;
      });

      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) {
        if (!mounted) return;
        _showAlertDialog('Error', 'Usuario no autenticado');
        setState(() {
          _isLoading = false;
        });
        return;
      }

      try {
        String upperCaseName = cardHolderName.toUpperCase();

        final hashedCvv = hashPin(cvvCode);

        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('rewardsCard')
            .doc('cardInfo')
            .set({
          'cardNumber': 'T_STY$cardNumber',
          'customerSince': customerSince,
          'cardHolderName': upperCaseName,
          'cvvCode': hashedCvv,
        });

        await FirebaseFirestore.instance.collection('rewards').doc(userId).set({
          'cardNumber': 'T_STY$cardNumber',
          'customerSince': customerSince,
          'cardHolderName': upperCaseName,
          'cvvCode': hashedCvv,
          'saldo': 0,
        });

        if (!mounted) return;
        _showAlertDialog('Éxito', 'Nuevo monedero creado');
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) Navigator.of(context).pop();
        });
      } catch (e) {
        if (!mounted) return;
        debugPrint('Error creating card: $e');
        _showAlertDialog('Error', 'No se pudo crear el monedero. Intenta de nuevo.');
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } else {
      _showAlertDialog(
          'Error', 'Por favor, corrige los errores en el formulario');
    }
  }

  Widget _buildCustomCreditCardWidget() {
    return Stack(
      children: [
        CreditCardWidget(
          cardNumber: 'T_STY$cardNumber',
          expiryDate: customerSince,
          cardHolderName: cardHolderName,
          cvvCode: cvvCode,
          showBackView: isCvvFocused,
          isHolderNameVisible: true,
          obscureCardNumber: false,
          obscureCardCvv: false,
          onCreditCardWidgetChange: (brand) {},
          backgroundImage: 'assets/images/card_bg.png',
          bankName: 'T_STY',
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
        ),
      ],
    );
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
          automaticallyImplyLeading: false,
          backgroundColor: Colors.white,
          scrolledUnderElevation: 0,
          elevation: 0,
        ),
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: _buildCustomCreditCardWidget(),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Form(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Ingrese su numero de telefono despues del prefijo T_STY-',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 10),
                        CreditCardForm(
                          formKey: _createCardFormKey,
                          cardNumber: cardNumber,
                          expiryDate: expiryDate,
                          cardHolderName: cardHolderName,
                          cvvCode: cvvCode,
                          onCreditCardModelChange: _onCreditCardModelChange,
                          obscureCvv: false,
                          obscureNumber: false,
                          isHolderNameVisible: true,
                          isCardNumberVisible: true,
                          isExpiryDateVisible: false,
                          cardNumberValidator: _validateCardNumber,
                          cardHolderValidator: _validateCardHolderName,
                          cvvValidator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Ingrese su NIP';
                            }
                            if (value.length < 3 || value.length > 4) {
                              return 'El NIP debe ser de 4 digitos';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),
                        TextFormField(
                          initialValue: customerSince,
                          decoration: const InputDecoration(
                            labelText: 'Cliente Desde',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.calendar_today),
                          ),
                          readOnly: true,
                          enabled: false,
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: _isLoading ? null : _saveCard,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                vertical: 16, horizontal: 100),
                            backgroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: _isLoading
                              ? SizedBox(
                            height: 35,
                            width: 35,
                            child: Lottie.asset(
                              'assets/animations/animation.json',
                              fit: BoxFit.contain,
                            ),
                          )
                              : const Text(
                            'Crear Monedero',
                            style: TextStyle(
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
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