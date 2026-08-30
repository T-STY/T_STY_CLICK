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

Future<double?> pickFraction({
  required BuildContext context,
  required String productName,
  required List<double> fractions,
  required double unitPrice,
  required double stock,
}) {
  return showDialog<double>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.3),
    builder: (_) => _FractionPickerDialog(
      productName: productName,
      fractions: fractions,
      unitPrice: unitPrice,
      stock: stock,
    ),
  );
}

class _FractionPickerDialog extends StatelessWidget {
  final String productName;
  final List<double> fractions;
  final double unitPrice;
  final double stock;

  const _FractionPickerDialog({
    required this.productName,
    required this.fractions,
    required this.unitPrice,
    required this.stock,
  });

  String _money(double v) => '\$${v.toStringAsFixed(2)}';

  String _stockText() {
    final s = stock % 1 == 0
        ? stock.toStringAsFixed(0)
        : stock.toStringAsFixed(2);
    return 'Quedan $s';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '¿Cuánto se lleva?',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.6,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          productName,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    tooltip: 'Cancelar',
                  ),
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, color: Colors.grey.shade200),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  for (int i = 0; i < fractions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(
                      child: _FractionTile(
                        label: fractionLabel(fractions[i]),
                        price: _money(unitPrice * fractions[i]),
                        enabled: fractions[i] <= stock + 1e-9,
                        onTap: () =>
                            Navigator.of(context).pop(fractions[i]),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Text(
                _stockText(),
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FractionTile extends StatelessWidget {
  final String label;
  final String price;
  final bool enabled;
  final VoidCallback onTap;

  const _FractionTile({
    required this.label,
    required this.price,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Un glifo corto como ½ y una palabra como "Entera" no caben
                // igual: se escala hacia abajo para que ninguna se pegue a los
                // bordes y las dos se lean con el mismo peso.
                SizedBox(
                  height: 38,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: const TextStyle(
                          fontSize: 32,
                          height: 1.05,
                          fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  price,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700),
                ),
                if (!enabled)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text('sin stock',
                        style: TextStyle(fontSize: 11, height: 1)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
