// components/payment_method_card.dart

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart'; // Importar Lottie

import '../../../constants/app_defaults.dart';
import '../../../constants/app_colors.dart';

class PaymentMethodCard extends StatelessWidget {
  const PaymentMethodCard({
    Key? key,
    this.methodID,
    required this.animationAsset,
    required this.isSelected,
    this.onTap,
  }) : super(key: key);

  /// Usado para reconocer el método
  final String? methodID;
  final String animationAsset; // Ruta de la animación Lottie
  final bool isSelected;
  final void Function()? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 100, // Ajusta el tamaño según tus necesidades
        height: 100, // Ajusta el tamaño según tus necesidades
        margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: AppDefaults.borderRadius,
          boxShadow: [
            BoxShadow(
                blurRadius: 9,
                offset: const Offset(4, 7),
                color: Colors.black.withOpacity(0.03))
          ],
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: Lottie.asset(
                animationAsset,
                width: 110,
                height: 70,
                fit: BoxFit.contain,
                repeat: true, // Asegura que la animación se repita
                animate: true, // Asegura que la animación se reproduzca
              ),
            ),
            if (isSelected)
              const Positioned(
                right: 4,
                top: 4,
                child: Icon(
                  Icons.check_circle_rounded,
                  color: Colors.black,
                ),
              )
          ],
        ),
      ),
    );
  }
}
