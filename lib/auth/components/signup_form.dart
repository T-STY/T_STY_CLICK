import 'dart:ui';
import 'package:click/auth/components/terms_conds.dart';
import 'package:flutter/material.dart';
import 'package:flutter_iconly/flutter_iconly.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../components/icon_with_background.dart';
import '../../../constants/constants.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../custom_page_route.dart';
import '../login_page.dart';

class SignUpForm extends StatefulWidget {
  const SignUpForm({super.key});

  @override
  State<SignUpForm> createState() => _SignUpFormState();
}

class _SignUpFormState extends State<SignUpForm> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _acceptTerms = false;

  /// Latches on the first tap so the account can only ever be created once.
  /// Without it the button stayed live during the network round-trip, and a
  /// second tap raced in as 'email-already-in-use' — which read to the
  /// customer as "registration failed" even though it had just succeeded.
  bool _submitting = false;

  static final _emailRegex = RegExp(
    r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
  );

  String? _validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Por favor, ingresa tu nombre';
    }
    if (value.trim().length > 50) {
      return 'El nombre no puede exceder 50 caracteres';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Por favor, ingresa tu correo';
    }
    if (!_emailRegex.hasMatch(value.trim())) {
      return 'Ingresa un correo electrónico válido';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Por favor, ingresa una contraseña';
    }
    if (value.length < 8) {
      return 'La contraseña debe tener al menos 8 caracteres';
    }
    if (!RegExp(r'[a-zA-Z]').hasMatch(value)) {
      return 'La contraseña debe contener al menos una letra';
    }
    if (!RegExp(r'[0-9]').hasMatch(value)) {
      return 'La contraseña debe contener al menos un número';
    }
    return null;
  }

  Future<void> _signUpUser() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _submitting = true);

    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    // Resolved before the first await. The form can be disposed mid-flight
    // (back button), but we still owe the customer the hand-off to the login
    // screen — driving it off `context` would silently swallow a successful
    // registration and leave them thinking it failed.
    final NavigatorState navigator = Navigator.of(context);

    // ── Phase 1: create the account. This is the only fatal step. ──
    try {
      await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      // Nothing was created — release the latch so they can fix and retry.
      setState(() => _submitting = false);
      String message;
      switch (e.code) {
        case 'email-already-in-use':
          message = 'Este correo ya está registrado.';
          break;
        case 'invalid-email':
          message = 'El correo electrónico no es válido.';
          break;
        case 'weak-password':
          message = 'La contraseña es muy débil.';
          break;
        case 'network-request-failed':
          message = 'Sin conexión. Revisa tu Internet e intenta de nuevo.';
          break;
        default:
          message = 'Error al crear la cuenta. Intenta de nuevo.';
      }
      _showSignUpError(message);
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _showSignUpError('Error al crear la cuenta. Intenta de nuevo.');
      return;
    }

    // ── Phase 2: the account now EXISTS. Everything below is best-effort. ──
    // A failure here must never be reported as "signup failed": the customer
    // would retry, hit 'email-already-in-use', and land right back in the
    // confusion this change removes. Each call is also bounded — a Firestore
    // set() resolves only on server ack, so an offline write would otherwise
    // hang forever with the button latched and the spinner turning.
    const Duration limit = Duration(seconds: 15);
    final User? user = _auth.currentUser;

    if (user != null) {
      final userDocRef =
          FirebaseFirestore.instance.collection('users').doc(user.uid);

      try {
        await user.updateDisplayName(name).timeout(limit);
      } catch (_) {/* cosmetic only */}

      try {
        await userDocRef.set({
          'userInfo': {
            'name': name,
            'email': email,
          }
        }, SetOptions(merge: true)).timeout(limit);
      } catch (_) {/* profile doc is recoverable later */}

      try {
        await userDocRef.collection('userInfo').doc('userInfo').set({
          'phoneNumber': '0000000000',
        }, SetOptions(merge: true)).timeout(limit);
      } catch (_) {/* profile doc is recoverable later */}

      try {
        await user.sendEmailVerification().timeout(limit);
      } catch (_) {/* they can retry from the login screen */}
    }

    // Unconditional teardown. createUserWithEmailAndPassword leaves the
    // brand-new (still unverified) user SIGNED IN, and main.dart's
    // _checkUser() admits any live session without testing emailVerified —
    // so keeping it would let an unverified account into the app on the next
    // cold launch. The login screen's gate becomes the only way in.
    try {
      await _auth.signOut().timeout(limit);
    } catch (_) {/* fall through — the login gate still guards entry */}

    // Hand off with the credentials pre-filled. We deliberately do NOT sign
    // them in: they must confirm the email first, then press "Ingresar".
    // `route.isFirst` drops the signup page (so there's no backing into a
    // stale, already-submitted form) while KEEPING the app root beneath —
    // registration is usually entered from inside the app, and clearing the
    // whole stack would leave no way back to browsing.
    navigator.pushAndRemoveUntil(
      customPageRoute(LoginPage(
        prefillEmail: email,
        prefillPassword: password,
        justRegistered: true,
      )),
      (route) => route.isFirst,
    );
  }

  void _showSignUpError(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppDefaults.padding),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            TextFormField(
              controller: _nameController,
              validator: _validateName,
              maxLength: 50,
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
            TextFormField(
              controller: _emailController,
              validator: _validateEmail,
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
            TextFormField(
              controller: _passwordController,
              validator: _validatePassword,
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
                onPressed: _submitting
                    ? null
                    : () {
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
                  disabledBackgroundColor: Colors.black54,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25.0),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
                  elevation: 2,
                ),
                child: _submitting
                    // Immediate acknowledgement of the tap — the absence of
                    // any feedback here is what drove the repeat taps.
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              AppColors.defaultWhite),
                        ),
                      )
                    : const Text(
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
