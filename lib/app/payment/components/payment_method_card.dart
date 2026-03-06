import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../../../constants/app_defaults.dart';
import '../../../constants/app_colors.dart';

class PaymentMethodCard extends StatelessWidget {
  const PaymentMethodCard({
    super.key,
    this.methodID,
    required this.animationAsset,
    required this.isSelected,
    this.onTap,
  });

  final String? methodID;
  final String animationAsset;
  final bool isSelected;
  final void Function()? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 100,
        height: 100,
        margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: AppDefaults.borderRadius,
          boxShadow: [
            BoxShadow(
              blurRadius: 9,
              offset: const Offset(4, 7),
              color: Colors.black.withValues(alpha: 0.03),
            )
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
                repeat: true,
                animate: true,
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