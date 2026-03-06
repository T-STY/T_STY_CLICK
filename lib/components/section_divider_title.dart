import 'package:flutter/material.dart';
import '../constants/constants.dart';

class SectionDividerTitle extends StatelessWidget {
  const SectionDividerTitle({
    super.key,
    required this.title,
    this.buttonTitle,
    this.onTap,
  });

  final String title;
  final String? buttonTitle;
  final void Function()? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppDefaults.margin),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          TextButton(
              onPressed: onTap,
              child: Text(
                buttonTitle ?? 'Ver Mas',
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(color: Colors.grey),
              ))
        ],
      ),
    );
  }
}
