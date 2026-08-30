import 'package:flutter/material.dart';

import 'apoyo_common.dart';
import 'apoyo_cycle.dart';

class ApoyoReceipt {
  final String folio;
  final double total;
  final double subtotal;
  final double deliveryFee;
  final bool edited;
  final String cycleId;
  final String fulfillment;

  final DateTime? deliveryAt;
  final DateTime? closesAt;

  const ApoyoReceipt({
    required this.folio,
    required this.total,
    required this.subtotal,
    required this.deliveryFee,
    required this.edited,
    required this.cycleId,
    required this.fulfillment,
    required this.deliveryAt,
    required this.closesAt,
  });

  static DateTime? _ms(Object? v) => v is num
      ? DateTime.fromMillisecondsSinceEpoch(v.toInt()).toLocal()
      : null;

  factory ApoyoReceipt.fromCallable(Object? data,
      {required double fallbackTotal}) {
    final m = data is Map ? Map<String, dynamic>.from(data) : const {};
    return ApoyoReceipt(
      folio: (m['folio'] ?? '').toString(),
      total: (m['total'] as num?)?.toDouble() ?? fallbackTotal,
      subtotal: (m['subtotal'] as num?)?.toDouble() ?? 0,
      deliveryFee: (m['deliveryFee'] as num?)?.toDouble() ?? 0,
      edited: m['edited'] == true,
      cycleId: (m['cycleId'] ?? '').toString(),
      fulfillment: (m['fulfillment'] ?? 'tienda').toString() == 'domicilio'
          ? 'domicilio'
          : 'tienda',
      deliveryAt: _ms(m['deliveryAt']),
      closesAt: _ms(m['closesAt']),
    );
  }
}

class ApoyoDonePage extends StatelessWidget {
  final ApoyoConfig config;
  final ApoyoCycle cycle;
  final ApoyoReceipt receipt;

  const ApoyoDonePage({
    super.key,
    required this.config,
    required this.cycle,
    required this.receipt,
  });

  DateTime? get _delivery => receipt.deliveryAt ?? cycle.deliveryAt;

  DateTime? get _closes => receipt.closesAt ?? cycle.closesAt;

  String get _headline {
    final money = apoyoMoney(receipt.total);
    final day = _delivery == null ? '' : apoyoLongDate(_delivery!);
    if (day.isEmpty) {
      return 'Ten $money en efectivo el viernes.';
    }
    if (receipt.fulfillment == 'domicilio') {
      final clock = apoyoClock(_delivery!);
      return 'Ten $money en efectivo el $day después de las $clock.';
    }
    return 'Ten $money en efectivo y recógelo en la tienda el $day '
        '$kApoyoPickupWindow.';
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDarkMode ? Colors.grey[900] : Colors.white,
      appBar: apoyoAppBar(context, title: 'Pedido apartado'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          ApoyoCard(
            color: kApoyoGreenTint,
            borderColor: kApoyoGreenLine,
            padding: const EdgeInsets.fromLTRB(16, 22, 16, 22),
            child: Column(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: kApoyoGreenLine),
                  ),
                  child: const Icon(Icons.check_rounded,
                      size: 32, color: kApoyoGreen),
                ),
                const SizedBox(height: 14),
                Text(
                  receipt.folio.isEmpty
                      ? 'Listo'
                      : 'Listo, ${receipt.folio}.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  _headline,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    color: kApoyoInk,
                  ),
                ),
                if (receipt.edited) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'Actualizamos tu pedido anterior — es el mismo folio, no '
                    'un pedido nuevo.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: kApoyoInk,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          ApoyoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                apoyoCardTitle('Lo que sigue'),
                const SizedBox(height: 12),
                apoyoRule(
                  Icons.payments_outlined,
                  'Pagas ${apoyoMoney(receipt.total)} en EFECTIVO al recibir. '
                  'El monto debe ir completo.',
                  strong: true,
                ),
                if (receipt.fulfillment == 'domicilio' &&
                    receipt.deliveryFee > 0)
                  apoyoRule(
                    Icons.local_shipping_outlined,
                    'Incluye ${apoyoMoney(receipt.deliveryFee)} de entrega '
                    'a domicilio.',
                  )
                else
                  apoyoRule(
                    Icons.storefront_outlined,
                    'Recoges en la tienda, sin costo de entrega.',
                  ),
                if (_closes != null)
                  apoyoRule(
                    Icons.edit_calendar_outlined,
                    'Puedes cambiarlo o cancelarlo hasta el '
                    '${apoyoLongDate(_closes!)} a las ${apoyoClock(_closes!)}. '
                    'Después ya compramos la despensa.',
                  ),
                if (config.storePhone.isNotEmpty)
                  apoyoRule(
                    Icons.store_outlined,
                    '¿Algo cambió? Llama a la tienda: ${config.storePhone}',
                  ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: kApoyoInk,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text(
                'Listo',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
