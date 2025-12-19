import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_iconly/flutter_iconly.dart';
import 'package:vibration/vibration.dart';
import 'package:lottie/lottie.dart';
import '../../components/icon_with_background.dart';
import '../../constants/app_colors.dart';

class PasswordResetDialog extends StatefulWidget {
  const PasswordResetDialog({super.key});

  @override
  _PasswordResetDialogState createState() => _PasswordResetDialogState();
}

class _PasswordResetDialogState extends State<PasswordResetDialog> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final TextEditingController _resetEmailController = TextEditingController();

  bool _showErrorAnimation = false;
  bool _showSuccessAnimation = false;

  @override
  Widget build(BuildContext context) {
    double buttonWidth = MediaQuery.of(context).size.width * 0.6;

    return Stack(
      children: [
        // Blur effect layer
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: Container(
              color: Colors.transparent,
            ),
          ),
        ),

        // Actual AlertDialog without any blur
        Center(
          child: AlertDialog(
            backgroundColor: Theme.of(context).brightness == Brightness.dark
                ? AppColors.primary // Replace AppColors.darkGrey with your charcoal color for dark mode
                : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(25.0),
            ),
            titlePadding: const EdgeInsets.all(20.0),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox(width: 5.0),
                Icon(Icons.lock_open, color: Theme.of(context).iconTheme.color, size: 30.0),
                const SizedBox(width: 15.0),
                const Expanded(
                  child: Text(
                    'Restablecer Contraseña',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16.0),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  color: Theme.of(context).iconTheme.color, // Automatically uses the correct color
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  child: Text(
                    'Por favor, introduzca su dirección de correo electrónico. Se le enviara un enlace para restablecer su contraseña.',
                    textAlign: TextAlign.justify,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _resetEmailController,
                  decoration: InputDecoration(
                    fillColor: Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey[850]
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
              ],
            ),
            actionsPadding: const EdgeInsets.symmetric(vertical: 20),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              SizedBox(
                width: buttonWidth,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25.0), // Your desired border radius
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0), // Define padding explicitly
                    elevation: 2,// Define elevation explicitly if you have a preference
                  ),
                  child: const Text(
                    'Enviar Enlace',
                    style: TextStyle(
                      fontSize: 15.0,  // Example size you want
                      fontWeight: FontWeight.normal,
                      color: AppColors.defaultWhite,
                      letterSpacing: 1.0,  // If you have a specific letter spacing in mind
                      fontFamily: 'Gordita',  // Specify the font family explicitly
                      // ... any other properties you want to set
                    ),
                  ),
                  onPressed: () async {
                    if (_resetEmailController.text.isEmpty) {
                      if ((await Vibration.hasVibrator()) ?? false) {
                        Vibration.vibrate();
                      }
                      setState(() {
                        _showErrorAnimation = true;
                      });
                    } else {
                      try {
                        await _auth.sendPasswordResetEmail(email: _resetEmailController.text);
                        setState(() {
                          _showSuccessAnimation = true;
                        });
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error: $e')),
                        );
                      }
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        if (_showErrorAnimation || _showSuccessAnimation)
          Positioned.fill(
            child: Center(
              child: _showErrorAnimation
                  ? Lottie.asset('assets/animations/error.json',
                  width: 200,
                  height: 200,
                  fit: BoxFit.contain,
                  repeat: false,
                  onLoaded: (composition) {
                    Future.delayed(composition.duration, () {
                      setState(() {
                        _showErrorAnimation = false;
                      });
                    });
                  })
                  : Lottie.asset('assets/animations/check.json',
                  width: 200,
                  height: 200,
                  fit: BoxFit.contain,
                  repeat: false,
                  onLoaded: (composition) {
                    Future.delayed(composition.duration, () {
                      setState(() {
                        _showSuccessAnimation = false;
                      });
                    });
                  }),
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _resetEmailController.dispose();
    super.dispose();
  }
}
