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
  String money(double v) => '\$${v.toStringAsFixed(2)}';
  return showDialog<double>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(productName,
          style: const TextStyle(fontWeight: FontWeight.w800)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Disponible: ${stock.toStringAsFixed(stock % 1 == 0 ? 0 : 2)}',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5)),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final f in fractions)
                _FractionChip(
                  label: fractionLabel(f),
                  price: money(unitPrice * f),
                  enabled: f <= stock + 1e-9,
                  onTap: () => Navigator.pop(ctx, f),
                ),
            ],
          ),
        ],
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

class _FractionChip extends StatelessWidget {
  final String label;
  final String price;
  final bool enabled;
  final VoidCallback onTap;

  const _FractionChip({
    required this.label,
    required this.price,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 104,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade400),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(price,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.green.shade700)),
              if (!enabled)
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Text('sin stock', style: TextStyle(fontSize: 10)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
