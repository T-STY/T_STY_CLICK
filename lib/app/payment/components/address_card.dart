import 'package:flutter/material.dart';
import 'package:flutter_iconly/flutter_iconly.dart';

import '../../../constants/constants.dart';

class AddressCard extends StatelessWidget {
  const AddressCard({
    Key? key,
    required this.label,
    required this.number,
    required this.address,
    required this.isSelected,
  }) : super(key: key);

  final String label;
  final String number;
  final String address;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppDefaults.margin,
        vertical: AppDefaults.margin / 2,
      ),
      padding: const EdgeInsets.all(AppDefaults.padding),
      decoration: BoxDecoration(
        color: isSelected ? Colors.white : Colors.transparent,
        border: isSelected ? null : Border.all(width: 0.1),
        borderRadius: AppDefaults.borderRadius,
        boxShadow: [
          BoxShadow(
            blurRadius: 8,
            offset: const Offset(4, 7),
            color: Colors.black.withOpacity(.05),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start, // Alineación superior
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: isSelected
                ? const Icon(
              Icons.check_circle_rounded,
              color: AppColors.primary,
            )
                : const Icon(
              Icons.circle_outlined,
              color: Colors.black12,
            ),
          ),
          const SizedBox(width: AppDefaults.margin),
          // Detalles
          Expanded( // Permite que la columna ocupe el espacio restante
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 2.0), // Espaciado entre textos
                Text(
                  number,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 2.0), // Espaciado entre textos
                Text(
                  address,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
