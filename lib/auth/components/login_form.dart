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
  /// Credentials carried over from a just-completed registration so the
  /// customer doesn't retype them. They are only seeded into the fields —
  /// sign-in still requires an explicit tap, because the account's email
  /// has to be verified first.
  final String? prefillEmail;
  final String? prefillPassword;

  const LoginForm({super.key, this.prefillEmail, this.prefillPassword});

  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  late final TextEditingController _emailController;
  late final TextEditingController _passwordController;

  /// Same latch as the signup button: this screen is where every new user is
  /// sent right after registering, so it inherits the repeat-tap habit.
  bool _signingIn = false;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.prefillEmail ?? '');
    _passwordController =
        TextEditingController(text: widget.prefillPassword ?? '');
  }

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
                  onPressed: _signingIn ? null : () async {
                    if (_signingIn) return;
                    setState(() => _signingIn = true);
                    try {
                      UserCredential userCredential =
                      await _auth.signInWithEmailAndPassword(
                        email: _emailController.text.trim(),
                        password: _passwordController.text,
                      );

                      // Resolve the verification state and tear down an
                      // unverified session BEFORE any mounted check. A
                      // `mounted` bail-out here used to return while the
                      // session was still live and unverified, which
                      // main.dart's _checkUser() would then admit on the
                      // next cold launch.
                      try {
                        await userCredential.user!.reload();
                      } catch (_) {/* fall back to the cached claim */}
                      final refreshed = _auth.currentUser;
                      final bool verified =
                          refreshed != null && refreshed.emailVerified;
                      if (!verified) {
                        await _auth.signOut();
                      }

                      if (!context.mounted) return;

                      if (verified) {
                        Navigator.pushAndRemoveUntil(
                          context,
                          customPageRoute(const MainMenuScreen()),
                              (route) => false,
                        );
                      } else {
                        setState(() => _signingIn = false);
                        _showEmailVerificationDialog(
                          context,
                          email: _emailController.text.trim(),
                          password: _passwordController.text,
                        );
                      }
                    } on FirebaseAuthException catch (e) {
                      if (!context.mounted) return;
                      setState(() => _signingIn = false);

                      final String errorMessage;
                      switch (e.code) {
                        case 'user-not-found':
                          errorMessage =
                              'No existe una cuenta con ese correo.';
                          break;
                        case 'wrong-password':
                          errorMessage =
                              'Contraseña incorrecta. Intenta de nuevo.';
                          break;
                        case 'invalid-email':
                          errorMessage = 'El correo no es válido.';
                          break;
                        case 'user-disabled':
                          errorMessage =
                              'Esta cuenta está deshabilitada. Contáctanos.';
                          break;
                        case 'too-many-requests':
                          errorMessage =
                              'Demasiados intentos. Espera unos minutos.';
                          break;
                        case 'network-request-failed':
                          errorMessage =
                              'Sin conexión. Revisa tu Internet e intenta de nuevo.';
                          break;
                        case 'invalid-credential':
                          errorMessage =
                              'Credenciales inválidas. Verifica correo y contraseña.';
                          break;
                        default:
                          errorMessage =
                              'No pudimos iniciar sesión. Intenta de nuevo.';
                      }

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
                                        Text(errorMessage),
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
                    } catch (e) {
                      if (!context.mounted) return;
                      setState(() => _signingIn = false);

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
                    disabledBackgroundColor: Colors.black54,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25.0),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 16.0),
                    elevation: 2,
                  ),
                  child: _signingIn
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

/// Shown when a sign-in succeeds but the address is still unverified. The
/// session has already been torn down by the caller, so [email]/[password]
/// are needed to re-authenticate for the duration of a resend — before this
/// existed, a single failed send at registration left the customer with no
/// way to ever get another verification mail.
void _showEmailVerificationDialog(
  BuildContext context, {
  required String email,
  required String password,
}) {
  bool sending = false;
  String? status;
  bool statusIsError = false;

  showDialog(
    context: context,
    builder: (BuildContext context) {
      double buttonWidth = MediaQuery.of(context).size.width * 0.4;
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter setLocal) {
      Future<void> resend() async {
        if (sending) return;
        setLocal(() {
          sending = true;
          status = null;
        });

        final auth = FirebaseAuth.instance;
        String message;
        bool isError;
        try {
          // Re-authenticate only long enough to send, then sign back out so
          // no unverified session is left alive behind the dialog.
          final cred = await auth.signInWithEmailAndPassword(
            email: email,
            password: password,
          );
          await cred.user!.sendEmailVerification();
          message = 'Te reenviamos el correo. Revisa tu bandeja y la '
              'carpeta de spam.';
          isError = false;
        } on FirebaseAuthException catch (e) {
          message = e.code == 'too-many-requests'
              ? 'Demasiados intentos. Espera unos minutos e intenta de nuevo.'
              : 'No pudimos reenviar el correo. Intenta más tarde.';
          isError = true;
        } catch (_) {
          message = 'No pudimos reenviar el correo. Intenta más tarde.';
          isError = true;
        } finally {
          try {
            await auth.signOut();
          } catch (_) {/* the login gate still guards entry */}
        }

        setLocal(() {
          sending = false;
          status = message;
          statusIsError = isError;
        });
      }

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
                  if (status != null) ...[
                    const SizedBox(height: 12.0),
                    Text(
                      status!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: statusIsError
                            ? Colors.red.shade600
                            : Colors.green.shade700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16.0),
                  TextButton(
                    onPressed: sending ? null : resend,
                    child: sending
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            'Reenviar correo de verificación',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14.0,
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? AppColors.defaultWhite
                                  : AppColors.defaultBlack,
                              fontFamily: 'Gordita',
                            ),
                          ),
                  ),
                  const SizedBox(height: 8.0),
                  SizedBox(
                    width: buttonWidth,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
                      ),
                      onPressed: sending
                          ? null
                          : () {
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
      );
    },
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.5),
  );
}
