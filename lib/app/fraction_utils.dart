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

String fractionUnit(Map<String, dynamic>? data) =>
    (data?['fraccion_unidad'] as String?) == 'kilo' ? 'kilo' : 'pieza';

String _plainFraction(double f) {
  if (f == 1) return '1';
  if (f == 0.5) return '½';
  if (f == 0.25) return '¼';
  if (f == 0.75) return '¾';
  final s = f.toStringAsFixed(3);
  return s.replaceFirst(RegExp(r'\.?0+$'), '');
}

String fractionLabel(double f, {String unit = 'pieza'}) {
  if (unit == 'kilo') return '${_plainFraction(f)} kg';
  if (f == 1) return 'Entera';
  if (f == 2) return 'Doble';
  return _plainFraction(f);
}

String qtyLabel(double q) {
  if (q == q.roundToDouble()) return q.toStringAsFixed(0);
  return q.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');
}

String fractionIntro(String unit) => unit == 'kilo'
    ? 'Este producto se vende por kilo. Elige cuánto quieres llevar.'
    : 'Este producto se vende por piezas completas o partidas. Elige cuánto '
        'quieres llevar.';

class FractionTile extends StatelessWidget {
  final String label;
  final String price;
  final bool enabled;
  final bool isDark;
  final bool selected;
  final VoidCallback onTap;

  const FractionTile({
    super.key,
    required this.label,
    required this.price,
    required this.enabled,
    required this.onTap,
    this.isDark = false,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color fill = selected
        ? (isDark ? Colors.white10 : Colors.grey[200]!)
        : (isDark ? Colors.black26 : Colors.grey[50]!);
    final Color line = selected
        ? (isDark ? Colors.white : Colors.black87)
        : (isDark ? Colors.white10 : Colors.grey[300]!);
    final Color ink = isDark ? Colors.white : Colors.black87;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: line, width: selected ? 2 : 1),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    price,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700, color: ink),
                  ),
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

class FractionChooser extends StatefulWidget {
  final List<double> fractions;
  final String unit;
  final double unitPrice;
  final double stock;
  final bool isDark;
  final ValueChanged<double> onConfirm;

  const FractionChooser({
    super.key,
    required this.fractions,
    required this.unit,
    required this.unitPrice,
    required this.stock,
    required this.onConfirm,
    this.isDark = false,
  });

  @override
  State<FractionChooser> createState() => _FractionChooserState();
}

class _FractionChooserState extends State<FractionChooser> {
  late double _size = widget.fractions.firstWhere(
      (f) => f <= widget.stock + 1e-9,
      orElse: () => widget.fractions.last);
  int _count = 1;

  double get _total => _size * _count;
  bool get _fits => _total <= widget.stock + 1e-9;
  bool get _canAddMore => _size * (_count + 1) <= widget.stock + 1e-9;

  String _money(double v) => '\$${v.toStringAsFixed(2)}';

  String _stockText() {
    final s = widget.stock % 1 == 0
        ? widget.stock.toStringAsFixed(0)
        : widget.stock.toStringAsFixed(2);
    return widget.unit == 'kilo' ? 'Disponible: $s kg' : 'Disponible: $s';
  }

  @override
  Widget build(BuildContext context) {
    final Color ink = widget.isDark ? Colors.white : Colors.black87;
    final Color muted =
        widget.isDark ? Colors.grey[400]! : Colors.grey[600]!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (int i = 0; i < widget.fractions.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: FractionTile(
                  label: fractionLabel(widget.fractions[i], unit: widget.unit),
                  price: _money(widget.unitPrice * widget.fractions[i]),
                  enabled: widget.fractions[i] <= widget.stock + 1e-9,
                  selected: widget.fractions[i] == _size,
                  isDark: widget.isDark,
                  onTap: () => setState(() {
                    _size = widget.fractions[i];
                    _count = 1;
                  }),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Text('Cantidad',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, color: muted)),
            const Spacer(),
            _StepBtn(
              icon: Icons.remove,
              enabled: _count > 1,
              isDark: widget.isDark,
              onTap: () => setState(() => _count--),
            ),
            SizedBox(
              width: 46,
              child: Text('$_count',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: ink)),
            ),
            _StepBtn(
              icon: Icons.add,
              enabled: _canAddMore,
              isDark: widget.isDark,
              onTap: () => setState(() => _count++),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Text(
                '${fractionLabel(_size, unit: widget.unit)} x $_count',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: muted),
              ),
            ),
            Text(
              _money(widget.unitPrice * _total),
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w900, color: ink),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          _fits ? _stockText() : 'No alcanza el inventario.',
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _fits ? muted : Colors.red.shade700),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _fits ? () => widget.onConfirm(_total) : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
          child: const Text('Agregar',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w800, height: 1.2)),
        ),
      ],
    );
  }
}

class _StepBtn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final bool isDark;
  final VoidCallback onTap;

  const _StepBtn({
    required this.icon,
    required this.enabled,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color line = isDark ? Colors.white24 : Colors.grey.shade400;
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: line),
            ),
            child: Icon(icon,
                size: 20, color: isDark ? Colors.white : Colors.black87),
          ),
        ),
      ),
    );
  }
}

double? avgPieceWeight(Map<String, dynamic>? data) {
  final kg = (data?['peso_muestra_total'] as num?)?.toDouble() ?? 0;
  final pz = (data?['piezas_muestra_total'] as num?)?.toDouble() ?? 0;
  if (kg <= 0 || pz <= 0) return null;
  return kg / pz;
}

int pieceSampleCount(Map<String, dynamic>? data) =>
    ((data?['muestras_pieza'] as num?)?.toInt()) ?? 0;

Future<double?> pickFraction({
  required BuildContext context,
  required String productName,
  required String? variante,
  required String imageUrl,
  required List<double> fractions,
  required double unitPrice,
  required double stock,
  String unit = 'pieza',
}) {
  return showDialog<double>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Center(child: Text('Producto por Fracción')),
      contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
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
                        unit == 'kilo'
                            ? '\$${unitPrice.toStringAsFixed(2)} / kg'
                            : '\$${unitPrice.toStringAsFixed(2)} c/u',
                        style: const TextStyle(color: Colors.green),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              fractionIntro(unit),
              textAlign: TextAlign.justify,
              style: const TextStyle(color: Colors.black),
            ),
            const SizedBox(height: 14),
            FractionChooser(
              fractions: fractions,
              unit: unit,
              unitPrice: unitPrice,
              stock: stock,
              onConfirm: (total) => Navigator.pop(ctx, total),
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
