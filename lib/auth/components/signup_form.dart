import 'dart:ui';
import 'package:click/auth/components/terms_conds.dart';
import 'package:flutter/material.dart';
import 'package:flutter_iconly/flutter_iconly.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../components/icon_with_background.dart';
import '../../../constants/constants.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SignUpForm extends StatefulWidget {
  const SignUpForm({super.key});

  @override
  _SignUpFormState createState() => _SignUpFormState();
}

class _SignUpFormState extends State<SignUpForm> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _phoneNumberController = TextEditingController();
  bool _acceptTerms = false;

  Future<void> _signUpUser() async {
    try {
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: _emailController.text,
        password: _passwordController.text,
      );

      await userCredential.user!.updateDisplayName(_nameController.text);

      // Reference to the main user document
      final userDocRef = FirebaseFirestore.instance.collection('users').doc(userCredential.user!.uid);

      // Store user-specific information in Firestore
      await userDocRef.set({
        'userInfo': {
          'name': _nameController.text,
          'email': _emailController.text,
        }
      });

      // Create a placeholder document in each sub-collection to set up the structure

      // Addresses sub-collection
      await userDocRef.collection('addresses').doc('placeholder').set({
        'address': 'Placeholder'
      });


      // Order History sub-collection
      await userDocRef.collection('orderHistory').doc('placeholder').set({
        'status': 'Placeholder'
      });

      // UserInfo sub-collection
      await userDocRef.collection('userInfo').doc('userInfo').set({
        'phoneNumber': _phoneNumberController.text,
      });

      // Send email verification
      await userCredential.user!.sendEmailVerification();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El correo de verificación ha sido enviado. Por favor verifique su correo electrónico.')),
      );

      // Show success snackbar
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('¡Éxito! Usuario registrado.')),
      );

    } catch (error) {}
  }




  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppDefaults.padding),
      child: Form(
        child: Column(
          children: [
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                fillColor: Theme.of(context).brightness == Brightness.dark
                    ? Colors.grey[800]
                    : Colors.grey[100],
                filled: true,
                prefixIcon: ColorFiltered(
                  colorFilter: ColorFilter.mode(
                    Theme.of(context).iconTheme.color ?? Colors.grey,
                    BlendMode.srcIn,
                  ),
                  child: const IconWithBackground(
                    iconData: IconlyBold.profile,
                  ),
                ),
                labelText: 'Nombre',
                hintText: 'John Doe',
                contentPadding: const EdgeInsets.symmetric(vertical: 15.0, horizontal: 10.0),  // To maintain height
                border: OutlineInputBorder(
                  borderSide: BorderSide.none,
                  borderRadius: BorderRadius.circular(12.0),
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide.none,
                  borderRadius: BorderRadius.circular(12.0),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: Theme.of(context).primaryColor,
                  ),
                  borderRadius: BorderRadius.circular(12.0),
                ),
                floatingLabelBehavior: FloatingLabelBehavior.never,
                labelStyle: DefaultTextStyle.of(context).style.merge(
                  TextStyle(
                    fontSize: 15.0,  // Your desired size
                    fontWeight: FontWeight.w400,
                    color: Theme.of(context).brightness == Brightness.dark ? AppColors.defaultWhite : AppColors.defaultBlack,
                    letterSpacing: 0.8,
                    fontFamily: 'Gordita',
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppDefaults.margin),
            TextField(
              controller: _phoneNumberController, // Phone number field
              decoration: InputDecoration(
                fillColor: Theme.of(context).brightness == Brightness.dark
                    ? Colors.grey[800]
                    : Colors.grey[100],
                filled: true,
                prefixIcon: ColorFiltered(
                  colorFilter: ColorFilter.mode(
                    Theme.of(context).iconTheme.color ?? Colors.grey,
                    BlendMode.srcIn,
                  ),
                  child: const IconWithBackground(
                    iconData: IconlyBold.call,
                  ),
                ),
                labelText: 'Teléfono',
                hintText: '+521234567890',
                contentPadding: const EdgeInsets.symmetric(vertical: 15.0, horizontal: 10.0),
                border: OutlineInputBorder(
                  borderSide: BorderSide.none,
                  borderRadius: BorderRadius.circular(12.0),
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide.none,
                  borderRadius: BorderRadius.circular(12.0),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: Theme.of(context).primaryColor,
                  ),
                  borderRadius: BorderRadius.circular(12.0),
                ),
                floatingLabelBehavior: FloatingLabelBehavior.never,
                labelStyle: DefaultTextStyle.of(context).style.merge(
                  TextStyle(
                    fontSize: 15.0,
                    fontWeight: FontWeight.w400,
                    color: Theme.of(context).brightness == Brightness.dark ? AppColors.defaultWhite : AppColors.defaultBlack,
                    letterSpacing: 0.8,
                    fontFamily: 'Gordita',
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppDefaults.margin),
            TextField(
              controller: _emailController,
              decoration: InputDecoration(
                fillColor: Theme.of(context).brightness == Brightness.dark
                    ? Colors.grey[800]
                    : Colors.grey[100],
                filled: true,
                prefixIcon: ColorFiltered(
                  colorFilter: ColorFilter.mode(
                    Theme.of(context).iconTheme.color ?? Colors.grey,
                    BlendMode.srcIn,
                  ),
                  child: const IconWithBackground(
                    iconData: IconlyBold.message,
                  ),
                ),
                labelText: 'Correo',
                hintText: 'tu@email.com',
                contentPadding: const EdgeInsets.symmetric(vertical: 15.0, horizontal: 10.0),  // To maintain height
                border: OutlineInputBorder(
                  borderSide: BorderSide.none,
                  borderRadius: BorderRadius.circular(12.0),
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide.none,
                  borderRadius: BorderRadius.circular(12.0),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: Theme.of(context).primaryColor,
                  ),
                  borderRadius: BorderRadius.circular(12.0),
                ),
                floatingLabelBehavior: FloatingLabelBehavior.never,
                labelStyle: DefaultTextStyle.of(context).style.merge(
                  TextStyle(
                    fontSize: 15.0,  // Your desired size
                    fontWeight: FontWeight.w400,
                    color: Theme.of(context).brightness == Brightness.dark ? AppColors.defaultWhite : AppColors.defaultBlack,
                    letterSpacing: 0.8,
                    fontFamily: 'Gordita',
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppDefaults.margin),
            TextField(
              controller: _passwordController,
              obscureText: true,  // This line makes the password obscured
              decoration: InputDecoration(
                fillColor: Theme.of(context).brightness == Brightness.dark
                    ? Colors.grey[800]
                    : Colors.grey[100],
                filled: true,
                prefixIcon: ColorFiltered(
                  colorFilter: ColorFilter.mode(
                    Theme.of(context).iconTheme.color ?? Colors.grey,
                    BlendMode.srcIn,
                  ),
                  child: const IconWithBackground(
                    iconData: IconlyBold.lock,
                  ),
                ),
                labelText: 'Contraseña',
                hintText: '*********',
                contentPadding: const EdgeInsets.symmetric(vertical: 15.0, horizontal: 10.0),  // To maintain height
                border: OutlineInputBorder(
                  borderSide: BorderSide.none,
                  borderRadius: BorderRadius.circular(12.0),
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide.none,
                  borderRadius: BorderRadius.circular(12.0),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: Theme.of(context).primaryColor,
                  ),
                  borderRadius: BorderRadius.circular(12.0),
                ),
                floatingLabelBehavior: FloatingLabelBehavior.never,
                labelStyle: DefaultTextStyle.of(context).style.merge(
                  TextStyle(
                    fontSize: 15.0,  // Your desired size
                    fontWeight: FontWeight.w400,
                    color: Theme.of(context).brightness == Brightness.dark ? AppColors.defaultWhite : AppColors.defaultBlack,
                    letterSpacing: 0.8,
                    fontFamily: 'Gordita',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20.0),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // The TextButton
                TextButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => const TermsAndConditionsScreen(),
                    );
                  },
                  child: Text(
                      'Acepto contrato de uso',
                      style: TextStyle(
                        fontSize: 15.0,  // Example size you want
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).brightness == Brightness.dark ? AppColors.defaultWhite : AppColors.defaultBlack,
                        letterSpacing: 1.0,  // If you have a specific letter spacing in mind
                        fontFamily: 'Gordita',  // Specify the font family explicitly
                        // ... any other properties you want to set
                      )
                  ),
                ),

                // The Switch
                Switch(
                  value: _acceptTerms,
                  onChanged: (bool value) {
                    setState(() {
                      _acceptTerms = value;
                    });
                  },
                  activeColor: Colors.black,
                ),
              ],
            ),
            const SizedBox(height: 20.0),
            SizedBox(
              width: MediaQuery.of(context).size.width * 0.5,
              child: ElevatedButton(
                onPressed: () {
                  if (_acceptTerms) {
                    // Create the account normally
                    _signUpUser();
                  } else {
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (BuildContext context) {
                        return Stack(
                          children: [
                            BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                              child: Container(color: Colors.black.withOpacity(0.3)),
                            ),
                            Dialog(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(25.0),
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(25.0),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const SizedBox(height: 16),
                                      const Text(
                                        'Error',
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
                                      ),
                                      const SizedBox(height: 16),
                                      const Text('Por favor, acepte los términos y condiciones.'),
                                      const SizedBox(height: 16),
                                      TextButton(
                                        child: Text('OK',
                                            style: TextStyle(
                                              fontSize: 15.0,  // Example size you want
                                              fontWeight: FontWeight.w800,
                                              color: Theme.of(context).brightness == Brightness.dark ? AppColors.defaultWhite : AppColors.defaultBlack,
                                              letterSpacing: 1.0,  // If you have a specific letter spacing in mind
                                              fontFamily: 'Gordita',  // Specify the font family explicitly
                                              // ... any other properties you want to set
                                            )
                                        ),
                                        onPressed: () {
                                          Navigator.of(context).pop();
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25.0), // Your desired border radius
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0), // Define padding explicitly
                  elevation: 2,// Define elevation explicitly if you have a preference
                ),
                child: const Text(
                  'Crear Cuenta',
                  style: TextStyle(
                    fontSize: 15.0,  // Example size you want
                    fontWeight: FontWeight.normal,
                    color: AppColors.defaultWhite,
                    letterSpacing: 1.0,  // If you have a specific letter spacing in mind
                    fontFamily: 'Gordita',  // Specify the font family explicitly
                    // ... any other properties you want to set
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
