import 'package:flutter/material.dart';
import 'package:flutter_iconly/flutter_iconly.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../components/icon_with_background.dart';
import '../../../constants/constants.dart';
import '../../../custom_page_route.dart';
import '../../app/main.dart';
import '../pass_reset.dart';
import 'dart:ui';

class LoginForm extends StatefulWidget {
  const LoginForm({super.key});

  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppDefaults.padding),
      child: SingleChildScrollView(
        child: Form(
          child: Column(
            children: [
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
                  contentPadding: const EdgeInsets.symmetric(
                      vertical: 15.0, horizontal: 10.0),
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
                      color: Theme.of(context).brightness == Brightness.dark
                          ? AppColors.defaultWhite
                          : AppColors.defaultBlack,
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
                  contentPadding: const EdgeInsets.symmetric(
                      vertical: 15.0, horizontal: 10.0),
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
                      color: Theme.of(context).brightness == Brightness.dark
                          ? AppColors.defaultWhite
                          : AppColors.defaultBlack,
                      letterSpacing: 0.8,
                      fontFamily: 'Gordita',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => const PasswordResetDialog(),
                    );
                  },
                  child: Text('¿Olvidaste la contraseña?',
                      style: TextStyle(
                        fontSize: 15.0,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? AppColors.defaultWhite
                            : AppColors.defaultBlack,
                        letterSpacing: 1.0,
                        fontFamily: 'Gordita',
                      )),
                ),
              ),
              const SizedBox(height: 40.0),
              SizedBox(
                width: MediaQuery.of(context).size.width * 0.5,
                child: ElevatedButton(
                  onPressed: () async {
                    try {
                      UserCredential userCredential =
                      await _auth.signInWithEmailAndPassword(
                        email: _emailController.text,
                        password: _passwordController.text,
                      );

                      if (!context.mounted) return;

                      if (userCredential.user!.emailVerified) {
                        Navigator.pushAndRemoveUntil(
                          context,
                          customPageRoute(const MainMenuScreen()),
                              (route) => false,
                        );
                      } else {
                        _showEmailVerificationDialog(context);
                      }
                    } catch (e) {
                      if (!context.mounted) return;

                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (BuildContext context) {
                          return Stack(
                            children: [
                              BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                                child: Container(
                                    color: Colors.black.withValues(alpha: 0.3)),
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
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 24),
                                        ),
                                        const SizedBox(height: 16),
                                        const Text(
                                            'Verifique sus credenciales'),
                                        const SizedBox(height: 16),
                                        TextButton(
                                          child: Text('OK',
                                              style: TextStyle(
                                                fontSize: 15.0,
                                                fontWeight: FontWeight.w800,
                                                color: Theme.of(context)
                                                    .brightness ==
                                                    Brightness.dark
                                                    ? AppColors.defaultWhite
                                                    : AppColors.defaultBlack,
                                                letterSpacing: 1.0,
                                                fontFamily: 'Gordita',
                                              )),
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 16.0),
                    elevation: 2,
                  ),
                  child: const Text(
                    'Ingresar',
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
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}

void _showEmailVerificationDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      double buttonWidth = MediaQuery.of(context).size.width * 0.4;
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? AppColors.primary
                  : Colors.white,
              borderRadius: BorderRadius.circular(25.0),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 16.0),
                  const Center(
                    child: Text(
                      'Verificación de Correo',
                      style:
                      TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 16.0),
                  const Center(
                    child: Text(
                      'Por favor verifique su correo electrónico antes de iniciar sesión.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 16.0),
                  SizedBox(
                    width: buttonWidth,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      child: const Text(
                        'OK',
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
          ),
        ),
      );
    },
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.5),
  );
}