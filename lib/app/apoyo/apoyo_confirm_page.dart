import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'apoyo_cart_provider.dart';
import 'apoyo_common.dart';
import 'apoyo_cycle.dart';
import 'apoyo_done_page.dart';

/// ── APOYO SOCIAL — confirm ──────────────────────────────────────────────────
///
/// Its own screen, deliberately not a branch of the store's CheckoutPage:
/// nothing here is paid, nothing is a card, nothing is a coupon, and the only
/// promise being made is that a person shows up on Friday with cash. Sharing
/// checkout would drag every one of those concepts into a screen whose whole
/// job is to make ONE commitment legible.
///
/// The client never sends a price — it sends `expectedTotal`, the number the
/// member is looking at. `placeApoyoOrder` prices the order from the frozen
/// snapshot and refuses anything more than a cent away, naming both totals.
class ApoyoConfirmPage extends StatefulWidget {
  final ApoyoConfig config;
  final Map<String, dynamic> member;
  final ApoyoCycle cycle;
  final List<ApoyoDraftLine> lines;

  /// The member's existing order for this cycle, when they are editing.
  /// Re-submitting REPLACES it and keeps the same folio.
  final ApoyoOrder? existingOrder;

  const ApoyoConfirmPage({
    super.key,
    required this.config,
    required this.member,
    required this.cycle,
    required this.lines,
    this.existingOrder,
  });

  @override
  State<ApoyoConfirmPage> createState() => _ApoyoConfirmPageState();
}

class _ApoyoConfirmPageState extends State<ApoyoConfirmPage> {
  final _notesCtrl = TextEditingController();

  late String _fulfillment;
  String? _addressId;
  double? _cash;
  bool _accepted = false;

  /// Re-entrancy latch: a double tap must never place two orders. `_sent`
  /// stays true after success so the button cannot re-arm while the done
  /// screen is being pushed.
  bool _submitting = false;
  bool _sent = false;

  DateTime _now = DateTime.now();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    final prev = widget.existingOrder;
    _fulfillment = _forcePickup ? 'tienda' : (prev?.fulfillment ?? 'tienda');
    // The delivery address is NOT a choice, and must never be presented as
    // one. `placeApoyoOrder` stamps every order with the MEMBERSHIP's own
    // `addressLine`/`colonia` — the household the program approved, and the
    // one `apoyo_blocked/h_{householdKey}` is keyed on — no matter which
    // `addressId` the client sends. A picker over `users/{uid}/addresses`
    // would show the member one address, write another onto the order, and
    // send the driver to the membership one with cash to collect.
    _addressId = _membershipAddressId.isEmpty ? null : _membershipAddressId;
    if (_fulfillment == 'domicilio' && _addressId == null) {
      _fulfillment = 'tienda';
    }
    _cash = prev?.cashPaidWith;
    _notesCtrl.text = prev?.notes ?? '';

    // The cutoff can pass while this screen is open. When it does, the
    // commitment stops being one the member can make, and the button says so
    // instead of sending them into a server rejection.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    _ticker?.cancel();
    super.dispose();
  }

  // ── the rules, mirrored from placeApoyoOrder ──────────────────────────────

  bool get _isFirstOrder => widget.member['firstOrderDone'] != true;

  /// Same expression the callable evaluates: the first order obeys the
  /// program-wide pickup-only switch, later ones obey the member's own flag.
  bool get _forcePickup => _isFirstOrder
      ? widget.config.firstOrderPickupOnly
      : widget.member['forcePickup'] == true;

  /// The address the membership was approved on. Registration required a
  /// street, number and colonia, and froze them onto `apoyo_members/{uid}`;
  /// these are the exact fields the owner's Friday delivery list prints.
  String get _membershipAddressId =>
      (widget.member['addressId'] ?? '').toString().trim();

  String get _membershipAddressLine =>
      (widget.member['addressLine'] ?? '').toString().trim();

  String get _membershipColonia =>
      (widget.member['colonia'] ?? '').toString().trim();

  bool get _hasMembershipAddress => _membershipAddressId.isNotEmpty;

  /// What the driver will actually read off the order.
  String get _deliveryAddressText {
    final parts = [_membershipAddressLine, _membershipColonia]
        .where((s) => s.isNotEmpty)
        .toList();
    return parts.isEmpty ? 'Tu dirección registrada' : parts.join(', ');
  }

  double get _orderCap {
    if (_isFirstOrder) return widget.config.firstOrderMaxTotal.toDouble();
    final custom = widget.member['maxOrderTotal'];
    if (custom is num && custom > 0) return custom.toDouble();
    return widget.config.defaultMaxOrderTotal.toDouble();
  }

  double get _subtotal => apoyoDraftSubtotal(widget.lines);

  double get _fee =>
      _fulfillment == 'domicilio' ? widget.config.deliveryFee.toDouble() : 0;

  double get _total => apoyoRound2(_subtotal + _fee);

  bool get _isOpen => widget.cycle.isOpenAt(_now);

  bool get _needsAddress =>
      _fulfillment == 'domicilio' && !_hasMembershipAddress;

  /// The first thing standing between the member and a confirmed order. Shown
  /// inline above the button — a disabled control with no reason is a dead
  /// end.
  String? get _blockReason {
    if (!_isOpen) {
      return 'Los pedidos de esta semana ya cerraron. La próxima lista abre '
          'el sábado.';
    }
    if (widget.lines.isEmpty) return 'Tu pedido está vacío.';
    if (_total > _orderCap) {
      return _isFirstOrder
          ? 'Tu primer pedido puede ser de hasta ${apoyoMoney(_orderCap)}. '
              'Este suma ${apoyoMoney(_total)}.'
          : 'Tu límite por pedido es ${apoyoMoney(_orderCap)}. Este suma '
              '${apoyoMoney(_total)}.';
    }
    if (_needsAddress) {
      return 'Tu membresía no tiene una dirección registrada, así que no '
          'podemos llevártelo. Recoge en la tienda o habla con nosotros para '
          'actualizarla.';
    }
    if (_cash == null) return 'Dinos con cuánto vas a pagar.';
    if (!_accepted) return 'Marca la casilla para confirmar tu compromiso.';
    return null;
  }

  bool get _canSubmit => _blockReason == null && !_submitting && !_sent;

  // ── cash chips ────────────────────────────────────────────────────────────

  /// The exact amount first, then the bills a neighbour actually carries.
  /// This is the only way the owner knows what change to bring on Friday.
  List<double> _cashOptions() {
    final total = _total;
    final out = <double>[total];
    for (final step in const [50, 100, 200, 500]) {
      final v = (total / step).ceil() * step.toDouble();
      if (v > total + 0.001 && !out.contains(v)) out.add(v);
    }
    out.sort();
    return out.take(4).toList();
  }

  void _setFulfillment(String next) {
    if (_fulfillment == next) return;
    final oldTotal = _total;
    setState(() {
      _fulfillment = next;
      final newTotal = _total;
      // "Exacto" must follow the total when the delivery fee joins or leaves;
      // anything now below the total is no longer an answer to the question.
      if (_cash != null) {
        if ((_cash! - oldTotal).abs() < 0.001) {
          _cash = newTotal;
        } else if (_cash! < newTotal - 0.001) {
          _cash = null;
        }
      }
    });
  }

  // ── submit ────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _submitting = true);
    FocusScope.of(context).unfocus();

    final total = _total;
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('placeApoyoOrder')
          .call(<String, dynamic>{
        'cycleId': widget.cycle.id,
        'expectedTotal': total,
        'fulfillment': _fulfillment,
        'addressId': _fulfillment == 'domicilio' ? (_addressId ?? '') : '',
        'cashPaidWith': _cash,
        'notes': _notesCtrl.text.trim(),
        'items': [
          for (final l in widget.lines)
            {'catalogItemId': l.item.id, 'quantity': l.quantity},
        ],
      });
      if (!mounted) return;

      final receipt = ApoyoReceipt.fromCallable(res.data, fallbackTotal: total);
      setState(() => _sent = true);

      // The order document is the source of truth from here on; a leftover
      // selection would show the member the same basket twice.
      context.read<ApoyoCartProvider>().clear();

      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ApoyoDonePage(
            config: widget.config,
            cycle: widget.cycle,
            receipt: receipt,
          ),
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      await apoyoAlert(
        context,
        title: 'No pudimos guardar tu pedido',
        message: apoyoCallableMessage(
          e,
          'No se pudo guardar tu pedido. Revisa tu conexión e intenta de '
          'nuevo.',
        ),
      );
    } catch (_) {
      if (!mounted) return;
      await apoyoAlert(
        context,
        title: 'No pudimos guardar tu pedido',
        message: 'No se pudo guardar tu pedido. Revisa tu conexión e intenta '
            'de nuevo.',
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDarkMode ? Colors.grey[900] : Colors.white,
      resizeToAvoidBottomInset: true,
      appBar: apoyoAppBar(context,
          onBack: () => Navigator.of(context).pop(),
          title: 'Confirmar pedido'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _summaryCard(),
          const SizedBox(height: 22),
          apoyoSectionLabel('¿Cómo lo recibes?'),
          _fulfillmentCard(),
          if (_fulfillment == 'domicilio') ...[
            const SizedBox(height: 14),
            _addressCard(),
          ],
          const SizedBox(height: 22),
          apoyoSectionLabel('El viernes'),
          _cashCard(),
          const SizedBox(height: 14),
          _notesCard(),
          const SizedBox(height: 22),
          apoyoSectionLabel('Tu compromiso'),
          _commitmentCard(),
        ],
      ),
      bottomNavigationBar: _bottomBar(),
    );
  }

  // ── what they are ordering ────────────────────────────────────────────────

  Widget _summaryCard() {
    return ApoyoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: apoyoCardTitle('Tu pedido')),
              Text(
                widget.cycle.deliveryLabel,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700,
                    color: Colors.grey[600]),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final l in widget.lines) _summaryLine(l),
          const Divider(height: 22),
          _totalRow('Productos', apoyoMoney(_subtotal)),
          const SizedBox(height: 6),
          _totalRow(
            _fulfillment == 'domicilio' ? 'Entrega a domicilio' : 'Recoges',
            _fee > 0 ? apoyoMoney(_fee) : 'Gratis',
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: kApoyoGreenTint,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kApoyoGreenLine),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Total a pagar',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  apoyoMoney(_total),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: kApoyoGreen,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Pagas en efectivo el viernes al recibir. Nada se cobra ahora.',
            style: TextStyle(
                fontSize: 13, height: 1.35, fontWeight: FontWeight.w600,
                color: Colors.black87),
          ),
        ],
      ),
    );
  }

  Widget _summaryLine(ApoyoDraftLine l) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Text(
              apoyoQtyUnit(l.quantity, l.item.unidad),
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l.item.nombre.isEmpty ? 'Producto' : l.item.nombre,
              style: const TextStyle(fontSize: 13, height: 1.3),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            apoyoMoney(l.total),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _totalRow(String label, String value) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 13, color: Colors.grey[700]),
          ),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  // ── pickup / delivery ─────────────────────────────────────────────────────

  Widget _fulfillmentCard() {
    return ApoyoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fulfillmentOption(
            value: 'tienda',
            icon: Icons.storefront_outlined,
            title: 'Recojo en la tienda',
            subtitle: 'Gratis · ${widget.cycle.elDeliveryLabel} '
                '$kApoyoPickupWindow.',
            enabled: true,
          ),
          const SizedBox(height: 10),
          _fulfillmentOption(
            value: 'domicilio',
            icon: Icons.home_outlined,
            title: 'A mi casa',
            subtitle: '${apoyoMoney(widget.config.deliveryFee)} · '
                '${widget.cycle.elDeliveryLabel} después de las '
                '${widget.cycle.deliveryClock}.',
            enabled: !_forcePickup && _hasMembershipAddress,
          ),
          if (!_forcePickup && !_hasMembershipAddress) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: kApoyoAmberTint,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kApoyoAmberLine),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 18, color: kApoyoAmber),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tu membresía no tiene una dirección registrada, así '
                      'que por ahora sólo puedes recoger en la tienda. Habla '
                      'con nosotros para actualizarla.',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: kApoyoInk,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_forcePickup) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: kApoyoAmberTint,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kApoyoAmberLine),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, size: 18, color: kApoyoAmber),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _isFirstOrder
                          ? 'Tu PRIMER pedido es sólo para recoger en la '
                              'tienda. A partir del segundo puedes pedir '
                              'entrega a domicilio por '
                              '${apoyoMoney(widget.config.deliveryFee)}.'
                          : 'Tu membresía está marcada como sólo para recoger '
                              'en la tienda. Si crees que es un error, habla '
                              'con la tienda.',
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: kApoyoInk,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _fulfillmentOption({
    required String value,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool enabled,
  }) {
    final selected = _fulfillment == value;
    return Material(
      color: selected ? kApoyoGreenTint : Colors.grey[50],
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled ? () => _setFulfillment(value) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? kApoyoGreen : Colors.grey.shade300,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 20,
                color: !enabled
                    ? Colors.grey.shade400
                    : selected
                        ? kApoyoGreen
                        : Colors.grey.shade500,
              ),
              const SizedBox(width: 10),
              Icon(icon,
                  size: 18,
                  color: enabled ? Colors.grey[700] : Colors.grey.shade400),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color:
                            enabled ? Colors.black87 : Colors.grey.shade500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.3,
                        color:
                            enabled ? Colors.grey[600] : Colors.grey.shade400,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── address ───────────────────────────────────────────────────────────────

  /// A statement of fact, not a choice.
  ///
  /// `placeApoyoOrder` writes `addressLine`/`colonia` from the MEMBERSHIP doc
  /// and ignores the `addressId` for anything but a presence check, so the
  /// only address that can ever receive an Apoyo delivery is this one. It is
  /// shown, never picked: a radio list over `users/{uid}/addresses` would let
  /// a member select a second home, read it back on the receipt, and then
  /// have the driver arrive at the first one expecting cash.
  Widget _addressCard() {
    return ApoyoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          apoyoCardTitle('¿A dónde te lo llevamos?'),
          const SizedBox(height: 10),
          if (!_hasMembershipAddress)
            Text(
              'Tu membresía no tiene una dirección registrada. Recoge en la '
              'tienda, o habla con nosotros para actualizarla.',
              style: TextStyle(
                  fontSize: 12.5, height: 1.35, color: Colors.grey[700]),
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.home_outlined, size: 20, color: kApoyoGreen),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _deliveryAddressText,
                    style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Es la dirección con la que te registraste en el Apoyo Social. '
              'Si te mudaste, habla con la tienda para actualizarla.',
              style: TextStyle(
                  fontSize: 12, height: 1.35, color: Colors.grey[600]),
            ),
          ],
        ],
      ),
    );
  }

  // ── cash ──────────────────────────────────────────────────────────────────

  Widget _cashCard() {
    final options = _cashOptions();
    return ApoyoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          apoyoCardTitle('¿Con cuánto vas a pagar?'),
          const SizedBox(height: 4),
          apoyoBody(
              'Así la tienda lleva tu cambio el viernes. El monto debe ir '
              'completo.'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final v in options)
                _cashChip(
                  v,
                  (v - _total).abs() < 0.001
                      ? 'Exacto · ${apoyoMoney(v)}'
                      : apoyoMoney(v),
                ),
            ],
          ),
          if (_cash != null && _cash! > _total + 0.001) ...[
            const SizedBox(height: 10),
            Text(
              'Tu cambio sería ${apoyoMoney(apoyoRound2(_cash! - _total))}.',
              style: TextStyle(
                  fontSize: 12.5, color: Colors.grey[700]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _cashChip(double value, String label) {
    final selected = _cash != null && (_cash! - value).abs() < 0.001;
    return Material(
      color: selected ? kApoyoGreen : Colors.grey[50],
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _cash = value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? kApoyoGreen : Colors.grey.shade300,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: selected ? Colors.white : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }

  // ── notes ─────────────────────────────────────────────────────────────────

  Widget _notesCard() {
    return ApoyoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          apoyoCardTitle('Notas (opcional)'),
          const SizedBox(height: 4),
          apoyoBody(
              'Por ejemplo: una referencia de tu casa, o a qué hora te '
              'encuentran.'),
          const SizedBox(height: 10),
          TextField(
            controller: _notesCtrl,
            maxLines: 3,
            maxLength: 300,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Escribe aquí…',
              filled: true,
              fillColor: Colors.grey[50],
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: kApoyoInk),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── the commitment ────────────────────────────────────────────────────────

  Widget _commitmentCard() {
    final day = widget.cycle.elDeliveryLabel;
    final verb = _fulfillment == 'domicilio' ? 'recibir' : 'recoger';
    return ApoyoCard(
      color: kApoyoAmberTint,
      borderColor: kApoyoAmberLine,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'La comida se compra el miércoles con tu pedido adentro. Si no la '
            '$verb, se pierde — por eso esta casilla.',
            style: const TextStyle(
                fontSize: 12.5, height: 1.35, color: kApoyoInk),
          ),
          const SizedBox(height: 10),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _accepted = !_accepted),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 26,
                    height: 26,
                    child: Checkbox(
                      value: _accepted,
                      activeColor: kApoyoGreen,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onChanged: (v) => setState(() => _accepted = v ?? false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        'Me comprometo a $verb y pagar ${apoyoMoney(_total)} '
                        'en efectivo $day.',
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── bottom bar ────────────────────────────────────────────────────────────

  Widget _bottomBar() {
    final reason = _blockReason;
    final editing = widget.existingOrder != null &&
        !widget.existingOrder!.isCancelled;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (reason != null && !_sent) ...[
                Text(
                  reason,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                    color: _isOpen ? Colors.grey[700] : kApoyoAmber,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _canSubmit ? _submit : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kApoyoInk,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade300,
                    disabledForegroundColor: Colors.grey.shade600,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          editing
                              ? 'Guardar mi pedido · ${apoyoMoney(_total)}'
                              : 'Confirmar mi pedido · ${apoyoMoney(_total)}',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
