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
  State<SignUpForm> createState() => _SignUpFormState();
}

class _SignUpFormState extends State<SignUpForm> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _acceptTerms = false;

  Future<void> _signUpUser() async {
    try {
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: _emailController.text,
        password: _passwordController.text,
      );

      await userCredential.user!.updateDisplayName(_nameController.text);

      final userDocRef = FirebaseFirestore.instance.collection('users').doc(userCredential.user!.uid);

      await userDocRef.set({
        'userInfo': {
          'name': _nameController.text,
          'email': _emailController.text,
        }
      });

      await userDocRef.collection('userInfo').doc('userInfo').set({
        'phoneNumber': '0000000000',
      });

      await userCredential.user!.sendEmailVerification();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El correo de verificación ha sido enviado. Por favor verifique su correo electrónico.')),
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('¡Éxito! Usuario registrado.')),
      );

    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $error')),
      );
    }
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
              controller: _passwordController,
              obscureText: true,
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
            const SizedBox(height: 20.0),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
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
                        fontSize: 15.0,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).brightness == Brightness.dark ? AppColors.defaultWhite : AppColors.defaultBlack,
                        letterSpacing: 1.0,
                        fontFamily: 'Gordita',
                      )
                  ),
                ),
                Switch(
                  value: _acceptTerms,
                  onChanged: (bool value) {
                    setState(() {
                      _acceptTerms = value;
                    });
                  },
                  activeTrackColor: Colors.black,
                ),
              ],
            ),
            const SizedBox(height: 20.0),
            SizedBox(
              width: MediaQuery.of(context).size.width * 0.5,
              child: ElevatedButton(
                onPressed: () {
                  if (_acceptTerms) {
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
                              child: Container(color: Colors.black.withValues(alpha: 0.3)),
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
                                              fontSize: 15.0,
                                              fontWeight: FontWeight.w800,
                                              color: Theme.of(context).brightness == Brightness.dark ? AppColors.defaultWhite : AppColors.defaultBlack,
                                              letterSpacing: 1.0,
                                              fontFamily: 'Gordita',
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
                    borderRadius: BorderRadius.circular(25.0),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
                  elevation: 2,
                ),
                child: const Text(
                  'Crear Cuenta',
                  style: TextStyle(
                    fontSize: 15.0,
                    fontWeight: FontWeight.normal,
                    color: AppColors.defaultWhite,
                    letterSpacing: 1.0,
                    fontFamily: 'Gordita',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}