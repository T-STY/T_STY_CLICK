import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'apoyo_cart_provider.dart';
import 'apoyo_catalog_page.dart';
import 'apoyo_common.dart';
import 'apoyo_cycle.dart';

/// ── APOYO SOCIAL — "tu pedido", on the status screen ────────────────────────
///
/// The one place a member checks on Thursday to answer "how much do I need on
/// Friday?". It shows the week, and — while the cycle is open — the way in and
/// out of it.
///
/// It reads the LATEST cycles rather than only the open one. Requirement: a
/// member must still see their order (folio, total, items) after the Tuesday
/// cutoff, when `state` has already flipped to 'cerrado' and an
/// `abierto`-only query returns nothing — that is exactly the window where
/// they most need to know the amount. The open cycle is derived from the same
/// snapshot, so nothing is read twice.
class ApoyoOrderSection extends StatefulWidget {
  final ApoyoConfig config;
  final Map<String, dynamic> member;

  const ApoyoOrderSection({
    super.key,
    required this.config,
    required this.member,
  });

  @override
  State<ApoyoOrderSection> createState() => _ApoyoOrderSectionState();
}

class _ApoyoOrderSectionState extends State<ApoyoOrderSection> {
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _cyclesSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _orderSub;
  Timer? _ticker;

  List<ApoyoCycle> _cycles = const [];
  ApoyoOrder? _order;
  String? _orderCycleId;
  bool _loading = true;

  /// Re-entrancy latch on the cancel callable.
  bool _cancelling = false;

  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();

    // Cycle ids are 'YYYY-MM-DD', so document-id order IS chronological
    // order — no composite index, and no date parsed on the client.
    _cyclesSub = FirebaseFirestore.instance
        .collection('apoyo_cycles')
        .orderBy(FieldPath.documentId, descending: true)
        .limit(3)
        .snapshots()
        .listen((q) {
      if (!mounted) return;
      setState(() {
        _cycles = q.docs.map(ApoyoCycle.fromDoc).toList();
        _loading = false;
      });
      _syncOrderSub();
    }, onError: (_) {
      if (mounted) setState(() => _loading = false);
    });

    // Coarse: this widget lives inside SettingsPage's IndexedStack, which
    // builds it whether or not it is the visible section. Half a minute is
    // enough to flip the screen to "cerrado" the moment the cutoff passes
    // without spending a rebuild every second on a page nobody is looking at.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      // The cutoff passing can move the focus from an open cycle to a newer
      // one, which is a different order document.
      _syncOrderSub();
    });
  }

  @override
  void dispose() {
    _cyclesSub?.cancel();
    _orderSub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  /// The cycle this screen is about: the open one while ordering is possible,
  /// otherwise the most recent one — the week whose delivery is still coming.
  ApoyoCycle? get _focusCycle {
    for (final c in _cycles) {
      if (c.isOpenAt(_now)) return c;
    }
    return _cycles.isEmpty ? null : _cycles.first;
  }

  bool get _isOpen => _focusCycle?.isOpenAt(_now) ?? false;

  void _syncOrderSub() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final cycleId = _focusCycle?.id;
    if (uid == null || cycleId == null) return;
    if (_orderCycleId == cycleId) return;

    _orderCycleId = cycleId;
    _orderSub?.cancel();
    // Never show one week's order under another week's header while the new
    // subscription is still in flight.
    if (_order != null) setState(() => _order = null);
    _orderSub = FirebaseFirestore.instance
        .doc('apoyo_orders/${cycleId}_$uid')
        .snapshots()
        .listen((doc) {
      if (!mounted) return;
      setState(() => _order = doc.exists ? ApoyoOrder.fromDoc(doc) : null);
    }, onError: (_) {});
  }

  /// Why Editar and Cancelar are dead after the cutoff — the server's own
  /// reason ("Ya compramos tu pedido…"), shown inline instead of letting the
  /// member tap into a rejection they could have read first.
  String get _lockedReason {
    final phone = widget.config.storePhone;
    return 'Ya no puedes editar ni cancelar: ya compramos tu pedido. '
        '${phone.isEmpty ? 'Habla con la tienda' : 'Llámanos al $phone'} si '
        'algo cambió.';
  }

  // ── actions ───────────────────────────────────────────────────────────────

  Future<void> _openCatalog() async {
    final cycle = _focusCycle;
    if (cycle == null || !cycle.isOpenAt(DateTime.now())) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ApoyoCatalogPage(
          config: widget.config,
          member: widget.member,
          cycleId: cycle.id,
        ),
      ),
    );
  }

  Future<void> _cancel() async {
    final cycle = _focusCycle;
    final order = _order;
    if (cycle == null || order == null || _cancelling) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('¿Cancelar tu pedido?'),
        content: Text(
          'Se libera lo que apartaste y no tendrás que pagar nada '
          '${cycle.elDeliveryLabel}. Puedes volver a pedir mientras el ciclo '
          'siga abierto.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('No, dejarlo'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sí, cancelar'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _cancelling = true);
    try {
      await FirebaseFunctions.instance
          .httpsCallable('cancelApoyoOrder')
          .call(<String, dynamic>{'cycleId': cycle.id});
      if (!mounted) return;
      // The selection is rebuilt from the catalog next time; leaving the old
      // lines behind would re-offer a basket they just cancelled.
      context.read<ApoyoCartProvider>().clear();
      await apoyoAlert(
        context,
        title: 'Pedido cancelado',
        message: 'Listo, cancelamos tu pedido ${order.folio}. No tienes nada '
            'que pagar ${cycle.elDeliveryLabel}.',
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      await apoyoAlert(
        context,
        title: 'No pudimos cancelar',
        message: apoyoCallableMessage(
          e,
          'No se pudo cancelar tu pedido. Revisa tu conexión e intenta de '
          'nuevo.',
        ),
      );
    } catch (_) {
      if (!mounted) return;
      await apoyoAlert(
        context,
        title: 'No pudimos cancelar',
        message: 'No se pudo cancelar tu pedido. Revisa tu conexión e intenta '
            'de nuevo.',
      );
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ApoyoCard(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    final cycle = _focusCycle;
    final order = _order;

    if (cycle == null) return _noCycleCard();
    if (order == null) {
      return _isOpen ? _openNoOrderCard(cycle) : _closedNoOrderCard(cycle);
    }
    return _orderCard(cycle, order);
  }

  /// No cycle document at all — the week has not been opened yet.
  Widget _noCycleCard() {
    return ApoyoCard(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      child: Column(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Icon(Icons.shopping_basket_outlined,
                size: 26, color: Colors.grey[500]),
          ),
          const SizedBox(height: 12),
          const Text(
            'El catálogo abre el sábado',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Aquí verás la lista de esta semana con sus precios. Puedes pedir '
            'de sábado a martes; el pedido cierra el martes a las 11:59 PM y '
            'lo recibes el viernes.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12.5, height: 1.35, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _openNoOrderCard(ApoyoCycle cycle) {
    return ApoyoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ApoyoIconTile(icon: Icons.shopping_basket_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'La lista de esta semana ya está',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Arma tu pedido para ${cycle.elDeliveryLabel}.',
                      style: TextStyle(
                          fontSize: 12.5, height: 1.3, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _cutoffStrip(cycle),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _openCatalog,
              style: ElevatedButton.styleFrom(
                backgroundColor: kApoyoInk,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text(
                'Ver el catálogo',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _closedNoOrderCard(ApoyoCycle cycle) {
    return ApoyoCard(
      color: kApoyoAmberTint,
      borderColor: kApoyoAmberLine,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.event_busy_outlined,
                  size: 20, color: kApoyoAmber),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Esta semana ya cerró',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.brown.shade900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'No hiciste pedido para ${cycle.elDeliveryLabel}. La próxima '
            'lista abre el sábado y se entrega el viernes siguiente.',
            style: TextStyle(
                fontSize: 13, height: 1.4, color: Colors.brown.shade900),
          ),
        ],
      ),
    );
  }

  // ── the order itself ──────────────────────────────────────────────────────

  Widget _orderCard(ApoyoCycle cycle, ApoyoOrder order) {
    if (order.isCancelled) return _cancelledCard(cycle, order);

    final open = _isOpen;
    final pickup = order.fulfillment != 'domicilio';

    return ApoyoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ApoyoIconTile(
                icon: pickup
                    ? Icons.storefront_outlined
                    : Icons.local_shipping_outlined,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            order.folio.isEmpty ? 'Tu pedido' : order.folio,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w800),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: (open ? kApoyoGreen : kApoyoAmber)
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            order.state.isEmpty ? 'Apartado' : order.state,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: open ? kApoyoGreen : kApoyoAmber,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      cycle.handoffLine(order.fulfillment),
                      style: TextStyle(
                          fontSize: 12.5, height: 1.3, color: Colors.grey[700]),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: kApoyoGreenTint,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kApoyoGreenLine),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Ten en efectivo',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.green.shade900,
                    ),
                  ),
                ),
                Text(
                  apoyoMoney(order.total),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: kApoyoGreen,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          for (final it in order.items) _orderLine(it),
          if (order.deliveryFee > 0) ...[
            const SizedBox(height: 2),
            _feeLine(order.deliveryFee),
          ],
          if (order.cashPaidWith != null) ...[
            const SizedBox(height: 10),
            apoyoBody(
                'Dijiste que pagas con ${apoyoMoney(order.cashPaidWith!)}.'),
          ],
          if (order.notes.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            apoyoBody('Notas: ${order.notes.trim()}'),
          ],
          const SizedBox(height: 14),
          if (open) ...[
            _cutoffStrip(cycle),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: OutlinedButton(
                      onPressed: _cancelling ? null : _cancel,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kApoyoRed,
                        side: BorderSide(
                          color: _cancelling
                              ? Colors.grey.shade300
                              : kApoyoRedLine,
                        ),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _cancelling
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text(
                              'Cancelar',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: ElevatedButton(
                      onPressed: _cancelling ? null : _openCatalog,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kApoyoInk,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey.shade300,
                        disabledForegroundColor: Colors.grey.shade600,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text(
                        'Editar',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
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
                  const Icon(Icons.lock_outline, size: 18, color: kApoyoAmber),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _lockedReason,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: Colors.brown.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: OutlinedButton(
                      onPressed: null,
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Cancelar'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: ElevatedButton(
                      onPressed: null,
                      style: ElevatedButton.styleFrom(
                        disabledBackgroundColor: Colors.grey.shade300,
                        disabledForegroundColor: Colors.grey.shade600,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Editar'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _orderLine(ApoyoOrderItem it) {
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
              apoyoQtyUnit(it.quantity, it.unidad),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              it.nombre.isEmpty ? 'Producto' : it.nombre,
              style: const TextStyle(fontSize: 13, height: 1.3),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            apoyoMoney(it.total),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _feeLine(double fee) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Entrega a domicilio',
            style: TextStyle(fontSize: 13, color: Colors.grey[700]),
          ),
        ),
        Text(
          apoyoMoney(fee),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  /// The server cancels an order at close when the membership is no longer
  /// active. The member must find out here, not on Friday at the door.
  Widget _cancelledCard(ApoyoCycle cycle, ApoyoOrder order) {
    return ApoyoCard(
      color: kApoyoRedTint,
      borderColor: kApoyoRedLine,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.cancel_outlined, size: 20, color: kApoyoRed),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Tu pedido ${order.folio} fue cancelado',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            order.cancelReason.trim().isEmpty
                ? 'No tienes nada que pagar ${cycle.elDeliveryLabel}.'
                : '${order.cancelReason.trim()}. No tienes nada que pagar '
                    '${cycle.elDeliveryLabel}.',
            style: const TextStyle(
                fontSize: 13, height: 1.4, color: Colors.black87),
          ),
          if (widget.config.storePhone.isNotEmpty) ...[
            const SizedBox(height: 8),
            apoyoBody('¿Dudas? Llama a la tienda: '
                '${widget.config.storePhone}'),
          ],
        ],
      ),
    );
  }

  /// Countdown + the exact instant, both formatted from the server Timestamp.
  Widget _cutoffStrip(ApoyoCycle cycle) {
    final left = cycle.timeLeftAt(_now);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.timer_outlined, size: 18, color: Colors.grey[700]),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cycle.closesAt == null
                      ? 'Abierto — puedes pedir hasta el martes'
                      : 'Cierra en ${apoyoCountdown(left)}',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800),
                ),
                if (cycle.closesAt != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'El ${apoyoLongDate(cycle.closesAt!)} a las '
                    '${apoyoClock(cycle.closesAt!)}.',
                    style: TextStyle(
                        fontSize: 12, height: 1.3, color: Colors.grey[600]),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
