import 'package:flutter/material.dart';
import 'package:flutter_credit_card/flutter_credit_card.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../../constants/app_images.dart'; // For date formatting

class CreateNewCard extends StatefulWidget {
  final VoidCallback onBack; // Add the onBack callback
  const CreateNewCard({super.key, required this.onBack});


  @override
  _CreateNewCardState createState() => _CreateNewCardState();
}

class _CreateNewCardState extends State<CreateNewCard> {
  final GlobalKey<FormState> _createCardFormKey = GlobalKey<FormState>(); // Reintroduced

  String cardNumber = '';
  String expiryDate = '';
  String cardHolderName = '';
  String cvvCode = '';
  bool isCvvFocused = false;

  // Customer Since
  late String customerSince;

  // Loading state
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Initialize customerSince to current date in MM/yyyy format
    customerSince = DateFormat('MM/yyyy').format(DateTime.now());
  }

  void _onCreditCardModelChange(CreditCardModel data) {
    setState(() {
      // Remove 'T_STY-' prefix if user includes it
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

  // Validator for card holder name: only letters and spaces
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

  // Validator for card number: starts with T_STY- followed by exactly 10 digits
  String? _validateCardNumber(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter card number';
    }
    if (!value.startsWith('T_STY-')) {
      return 'Card number must start with T_STY-';
    }
    final numberPart = value.substring(6); // Extract the 10 digits
    final regex = RegExp(r'^\d{10}$'); // Exactly 10 digits
    if (!regex.hasMatch(numberPart)) {
      return 'Please enter a valid 10-digit phone number after T_STY-';
    }
    return null;
  }

  // Method to show AlertDialog
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
                Navigator.of(context).pop(); // Close the dialog
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
        _showAlertDialog('Error', 'Usuario no autenticado');
        setState(() {
          _isLoading = false;
        });
        return;
      }

      try {
        // Convert card holder name to uppercase
        String upperCaseName = cardHolderName.toUpperCase();

        // Save card info in the user's collection (without saldo)
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('rewardsCard')
            .doc('cardInfo')
            .set({
          'cardNumber': 'T_STY$cardNumber', // Include the prefix
          'customerSince': customerSince,
          'cardHolderName': upperCaseName, // Upload in all caps
          'cvvCode': cvvCode,
          // Do not include saldo here
        });

        // Save card info in the rewards collection (with saldo)
        await FirebaseFirestore.instance.collection('rewards').doc(userId).set({
          'cardNumber': 'T_STY$cardNumber', // Include the prefix
          'customerSince': customerSince,
          'cardHolderName': upperCaseName, // Upload in all caps
          'cvvCode': cvvCode,
          'saldo': 0, // Include saldo in this collection
        });

        // Show success dialog
        _showAlertDialog('Éxito', 'Nuevo monedero creado');
        // Navigate back after a slight delay to ensure the dialog is seen
        Future.delayed(const Duration(seconds: 1), () {
          Navigator.of(context).pop(); // Return to previous screen
        });
      } catch (e) {
        // Handle Firestore errors
        _showAlertDialog('Error', 'No se pudo crear el monedero: $e');
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    } else {
      // If validation fails, show an alert dialog
      _showAlertDialog('Error', 'Por favor, corrige los errores en el formulario');
    }
  }





  // Function to build the CreditCardWidget with custom labels and icons
  Widget _buildCustomCreditCardWidget() {
    return Stack(
      children: [
        CreditCardWidget(
          cardNumber: 'T_STY$cardNumber',
          expiryDate: customerSince, // Display "Cliente Desde" here
          cardHolderName: cardHolderName,
          cvvCode: cvvCode,
          showBackView: isCvvFocused,
          isHolderNameVisible: true,
          obscureCardNumber: false,
          obscureCardCvv: false,
          onCreditCardWidgetChange: (brand) {},
          backgroundImage: 'assets/images/card_bg.png',
          bankName: 'T_STY', // Set your custom bank name here
          customCardTypeIcons: <CustomCardTypeIcon>[
            CustomCardTypeIcon(
              cardType: CardType.t_sty, // Your custom card type
              cardImage: Image.asset(
                'assets/images/visa.png', // Ensure this asset exists
                height: 48,
                width: 48,
              ),
            ),
            // You can add more custom card type icons if needed
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return WillPopScope(
        onWillPop: () async {
      // Intercept the back button and gesture to go to index 0 instead of exiting the app
      widget.onBack(); // Navigate to index 0
      return false; // Prevent default back behavior
    },
    child:  Scaffold(
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
            // Custom CreditCardWidget with "Cliente Desde" label and custom icon
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: _buildCustomCreditCardWidget(),
            ),
            // Expanded widget to make the form scrollable
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Form( // Ensure there's only one Form widget
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Instructional Text for Card Number
                      const Text(
                        'Ingrese su numero de telefono despues del prefijo T_STY-',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 10),
                      // CreditCardForm handles the input fields and validation
                      CreditCardForm(
                        formKey: _createCardFormKey, // Pass the formKey
                        cardNumber: '$cardNumber',
                        expiryDate: expiryDate, // Not used but set for UI
                        cardHolderName: cardHolderName,
                        cvvCode: cvvCode,
                        onCreditCardModelChange: _onCreditCardModelChange,
                        obscureCvv: false,
                        obscureNumber: false,
                        isHolderNameVisible: true,
                        isCardNumberVisible: true,
                        isExpiryDateVisible: false, // Hide expiry date field
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
                      // Cliente Desde as a read-only field in the form
                      TextFormField(
                        initialValue: customerSince,
                        decoration: InputDecoration(
                          labelText: 'Cliente Desde',
                          border: OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.calendar_today),
                        ),
                        readOnly: true,
                        enabled: false,
                      ),
                      const SizedBox(height: 20),
                      // ElevatedButton to submit the form
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
                            ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            strokeWidth: 2,
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
    )
    );
  }
}
