import 'package:flutter/material.dart';

List<double> productFractions(Map<String, dynamic>? data) {
  final raw = data?['fracciones'];
  if (raw is! List) return const [];
  final out = <double>[];
  for (final v in raw) {
    final d = v is num ? v.toDouble() : double.tryParse('$v');
    if (d != null && d > 0 && d <= 100 && !out.contains(d)) out.add(d);
  }
  out.sort((a, b) => b.compareTo(a));
  return out;
}

bool sellsByFraction(Map<String, dynamic>? data) =>
    productFractions(data).isNotEmpty;

String fractionLabel(double f) {
  if (f == 1) return 'Entera';
  if (f == 0.5) return '½';
  if (f == 0.25) return '¼';
  if (f == 0.75) return '¾';
  if (f == 2) return 'Doble';
  final s = f.toStringAsFixed(3);
  return s.replaceFirst(RegExp(r'\.?0+$'), '');
}

class FractionTile extends StatelessWidget {
  final String label;
  final String price;
  final bool enabled;
  final bool isDark;
  final VoidCallback onTap;

  const FractionTile({
    super.key,
    required this.label,
    required this.price,
    required this.enabled,
    required this.onTap,
    this.isDark = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color fill = isDark ? Colors.black26 : Colors.grey[50]!;
    final Color line = isDark ? Colors.white10 : Colors.grey[300]!;
    final Color ink = isDark ? Colors.white : Colors.black87;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: line),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Una palabra como "Entera" y un glifo como ½ no ocupan igual;
                // se escala hacia abajo para que las dos se lean parejas.
                SizedBox(
                  height: 34,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: TextStyle(
                          fontSize: 28,
                          height: 1.05,
                          fontWeight: FontWeight.w900,
                          color: ink),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  price,
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700, color: ink),
                ),
                if (!enabled)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text('sin stock',
                        style: TextStyle(
                            fontSize: 11,
                            height: 1,
                            color: isDark ? Colors.white54 : Colors.black54)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// El diálogo de fracciones de la app del cliente: mismo formato que el de
/// granel de esta app —AlertDialog, título centrado, la fila con imagen,
/// nombre, variante y precio en verde— pero ofreciendo las fracciones.
Future<double?> pickFraction({
  required BuildContext context,
  required String productName,
  required String? variante,
  required String imageUrl,
  required List<double> fractions,
  required double unitPrice,
  required double stock,
}) {
  return showDialog<double>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Center(child: Text('Producto por Fracción')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8.0),
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    width: 50,
                    height: 50,
                    errorBuilder: (c, e, st) =>
                        const Icon(Icons.image_not_supported_outlined),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(productName,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      if ((variante ?? '').isNotEmpty) Text(variante!),
                      Text(
                        '\$${unitPrice.toStringAsFixed(2)} c/u',
                        style: const TextStyle(color: Colors.green),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'Este producto se vende por piezas completas o partidas. '
              'Elige cuánto quieres llevar.',
              textAlign: TextAlign.justify,
              style: TextStyle(color: Colors.black),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                for (int i = 0; i < fractions.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(
                    child: FractionTile(
                      label: fractionLabel(fractions[i]),
                      price:
                          '\$${(unitPrice * fractions[i]).toStringAsFixed(2)}',
                      enabled: fractions[i] <= stock + 1e-9,
                      onTap: () => Navigator.pop(ctx, fractions[i]),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancelar'),
        ),
      ],
    ),
  );
}
