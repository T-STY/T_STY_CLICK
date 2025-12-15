import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart'; // Import Lottie package
import '../../constants/constants.dart';
import '../main.dart';

class PaymentDonePage extends StatelessWidget {
  final VoidCallback onBackToHome; // Callback to navigate back to home

  const PaymentDonePage({
    Key? key,
    required this.onBackToHome,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Optionally, remove AppBar if not needed
      body: SafeArea(
        child: SingleChildScrollView( // Added to handle overflow on smaller screens
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Small Text at the Top
              Padding(
                padding: const EdgeInsets.only(top: 16.0), // Adjust top padding as needed
                child: Text(
                  'Gálatas 6:7-10', // Your desired text
                  style: TextStyle(
                    fontSize: 14, // Smaller font size
                    color: Colors.grey[600], // Subtle color
                    fontStyle: FontStyle.italic, // Optional: Italic style
                  ),
                ),
              ),
              const SizedBox(
                height: AppDefaults.margin * 8,
              ),

              // Replace CheckBoxIcon with Lottie Animation
              SizedBox(
                width: 250, // Width of the animation
                height: 250, // Height adjusted for better visibility
                child: Lottie.asset(
                  'assets/animations/success.json', // Path to your Lottie file
                  repeat: true,
                  animate: true// Play the animation only once
                  // animate: true, // 'animate' is true by default
                ),
              ),
              /// Info
              Padding(
                padding: const EdgeInsets.all(AppDefaults.margin),
                child: Column(
                  children: [
                    Text(
                      '¡Felicidades!',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8.0),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        'El pedido se ha realizado exitosamente y está siendo procesado.',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: Colors.black45),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              /// Actions
              SizedBox(
                width: MediaQuery.of(context).size.width * 0.6,
                child: ElevatedButton(
                  onPressed: onBackToHome, // Use the callback
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary.withOpacity(0.15),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Volver al Inicio',
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold),
                  ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}
