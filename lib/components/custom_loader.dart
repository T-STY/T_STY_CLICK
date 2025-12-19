import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class CustomLoader extends StatelessWidget {
  const CustomLoader({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 150,
        height: 150,
        // Ensure this file exists in your assets/animations folder
        child: Lottie.asset('assets/animations/animation.json'),
      ),
    );
  }
}