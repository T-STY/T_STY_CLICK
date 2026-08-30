import 'package:flutter/material.dart';

import 'fraction_utils.dart';

class BulkOrderDialog extends StatefulWidget {
  final String imageUrl;
  final String nombre;
  final String variante;
  final String priceLabel;
  final double pricePerKilo;
  final double initialKilos;
  final double stock;
  final ValueChanged<double> onConfirm;
  /// Verdura y fruta que también se puede pedir por pieza ("3 manzanas").
  final bool allowByPiece;
  /// Peso promedio por pieza aprendido en el mostrador, si ya hay muestras.
  final double? avgPieceKg;
  /// Piezas pedidas; el precio queda pendiente hasta que la tienda las pese.
  final ValueChanged<int>? onConfirmPieces;

  const BulkOrderDialog({
    super.key,
    required this.imageUrl,
    required this.nombre,
    required this.variante,
    required this.priceLabel,
    required this.pricePerKilo,
    required this.initialKilos,
    required this.stock,
    required this.onConfirm,
    this.allowByPiece = false,
    this.avgPieceKg,
    this.onConfirmPieces,
  });

  @override
  State<BulkOrderDialog> createState() => BulkOrderDialogState();
}

class BulkOrderDialogState extends State<BulkOrderDialog> {
  bool _byPiece = false;
  int _pieces = 1;
  final TextEditingController pesosController = TextEditingController();
  final TextEditingController kilosController = TextEditingController();
  final FocusNode pesosFocusNode = FocusNode();
  final FocusNode kilosFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    kilosController.text = widget.initialKilos.toStringAsFixed(3);
    pesosController.text =
    '\$${(widget.initialKilos * widget.pricePerKilo).toStringAsFixed(2)}';

    pesosFocusNode.addListener(_handlePesosFocus);
    kilosFocusNode.addListener(_handleKilosFocus);
  }

  void _handlePesosFocus() {
    if (!pesosFocusNode.hasFocus) {
      final pesos =
      double.tryParse(pesosController.text.replaceAll('\$', ''));
      if (pesos != null) {
        kilosController.text =
            (pesos / widget.pricePerKilo).toStringAsFixed(3);
        pesosController.text = '\$${pesos.toStringAsFixed(2)}';
      }
    }
  }

  void _handleKilosFocus() {
    if (!kilosFocusNode.hasFocus) {
      final kilos = double.tryParse(kilosController.text);
      if (kilos != null) {
        pesosController.text =
        '\$${(kilos * widget.pricePerKilo).toStringAsFixed(2)}';
      }
    }
  }

  @override
  void dispose() {
    pesosFocusNode.removeListener(_handlePesosFocus);
    kilosFocusNode.removeListener(_handleKilosFocus);
    pesosFocusNode.dispose();
    kilosFocusNode.dispose();
    pesosController.dispose();
    kilosController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Center(child: Text("Producto a Granel")),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8.0),
                  child: Image.network(
                    widget.imageUrl,
                    fit: BoxFit.contain,
                    width: 50,
                    height: 50,
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.nombre,
                      style:
                      const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(widget.variante),
                    Text(
                      widget.priceLabel,
                      style: const TextStyle(color: Colors.green),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (widget.allowByPiece) ...[
              Row(
                children: [
                  Expanded(
                    child: ModeChip(
                      label: 'Por peso',
                      selected: !_byPiece,
                      onTap: () => setState(() => _byPiece = false),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ModeChip(
                      label: 'Por pieza',
                      selected: _byPiece,
                      onTap: () => setState(() => _byPiece = true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            if (widget.allowByPiece && _byPiece) ...[
              const Text(
                'Dinos cuántas piezas quieres. Las pesamos al prepararlas y '
                'ahí se calcula el precio, así que todavía no se puede cobrar.',
                textAlign: TextAlign.justify,
                style: TextStyle(color: Colors.black),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Piezas',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(
                    onPressed:
                        _pieces > 1 ? () => setState(() => _pieces--) : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  SizedBox(
                    width: 40,
                    child: Text('$_pieces',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w900)),
                  ),
                  IconButton(
                    onPressed: () => setState(() => _pieces++),
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (widget.avgPieceKg != null) ...[
                Text(
                  'Aproximado: '
                  '${(widget.avgPieceKg! * _pieces).toStringAsFixed(2)} kg · '
                  '\$${(widget.avgPieceKg! * _pieces * widget.pricePerKilo).toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
              ],
              Text(
                  widget.avgPieceKg != null
                      ? 'El precio final se calcula al pesarlas.'
                      : 'Se cobra al pesar',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700)),
            ] else ...[
            RichText(
              textAlign: TextAlign.justify,
              text: const TextSpan(
                style: TextStyle(color: Colors.black),
                children: [
                  TextSpan(
                    text:
                    "Este producto se vende a granel, por favor indique la cantidad que desea recibir.",
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _MoneyField(
              label: 'Valor en pesos',
              suffix: 'MXN',
              controller: pesosController,
              focusNode: pesosFocusNode,
            ),
            const SizedBox(height: 14),
            _MoneyField(
              label: 'Peso en kilo',
              suffix: 'kg',
              controller: kilosController,
              focusNode: kilosFocusNode,
            ),
            const SizedBox(height: 10),
            RichText(
              textAlign: TextAlign.justify,
              text: const TextSpan(
                style: TextStyle(color: Colors.black),
                children: [
                  TextSpan(
                    text:
                    "\n*Tenga en cuenta que la cantidad recibida puede variar ligeramente.",
                    style: TextStyle(fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
            ],
          ],
        ),
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              if (widget.allowByPiece && _byPiece) {
                widget.onConfirmPieces?.call(_pieces);
                return;
              }
              final kilos = double.tryParse(kilosController.text) ?? 0.0;
              if (kilos > widget.stock) return;
              widget.onConfirm(kilos);
            },
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
        ),
      ],
    );
  }
}

class ModeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const ModeChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? Colors.grey.shade200 : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? Colors.black87 : Colors.grey.shade300,
              width: selected ? 2 : 1),
        ),
        child: Text(label,
            style: TextStyle(
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600)),
      ),
    );
  }
}


/// Campo de captura del diálogo de granel.
///
/// Antes el campo iba a dos tercios del ancho con un "MXN" suelto flotando al
/// lado, así que se veía angosto y descentrado. Ahora ocupa todo el ancho con
/// la unidad adentro, y usa las mismas esquinas y el mismo peso de texto que
/// las fichas de fracciones.
class _MoneyField extends StatelessWidget {
  final String label;
  final String suffix;
  final TextEditingController controller;
  final FocusNode focusNode;

  const _MoneyField({
    required this.label,
    required this.suffix,
    required this.controller,
    required this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade700),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.grey.shade50,
            suffixText: suffix,
            suffixStyle: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade600),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Colors.black87, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}
