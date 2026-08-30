import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../components/network_image.dart';
import 'apoyo_cart_provider.dart';
import 'apoyo_common.dart';
import 'apoyo_confirm_page.dart';
import 'apoyo_cycle.dart';

class ApoyoCatalogPage extends StatefulWidget {
  final ApoyoConfig config;
  final Map<String, dynamic> member;
  final String cycleId;

  const ApoyoCatalogPage({
    super.key,
    required this.config,
    required this.member,
    required this.cycleId,
  });

  @override
  State<ApoyoCatalogPage> createState() => _ApoyoCatalogPageState();
}

class _ApoyoCatalogPageState extends State<ApoyoCatalogPage> {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _cycleSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _itemsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _commitSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _orderSub;
  Timer? _ticker;

  ApoyoCycle? _cycle;
  List<ApoyoCatalogItem> _items = const [];
  Map<String, double> _committed = const {};
  ApoyoOrder? _order;

  bool _loadingItems = true;

  final Completer<void> _cycleLoaded = Completer<void>();
  bool _cycleReady = false;

  DateTime _now = DateTime.now();

  String _countdownLabel = '';

  bool _cartResolved = false;

  bool _seeded = false;

  String get _cyclePath => 'apoyo_cycles/${widget.cycleId}';

  @override
  void initState() {
    super.initState();
    final db = FirebaseFirestore.instance;
    final uid = FirebaseAuth.instance.currentUser?.uid;

    _cycleSub = db.doc(_cyclePath).snapshots().listen((doc) {
      if (!mounted) return;
      setState(() {
        _cycle = doc.exists ? ApoyoCycle.fromDoc(doc) : null;
        _cycleReady = true;
      });
      if (!_cycleLoaded.isCompleted) _cycleLoaded.complete();
    }, onError: (_) {
      if (mounted) setState(() => _cycleReady = true);
      if (!_cycleLoaded.isCompleted) _cycleLoaded.complete();
    });

    _itemsSub =
        db.collection('$_cyclePath/catalog_snapshot').snapshots().listen((q) {
      if (!mounted) return;
      final list = q.docs.map(ApoyoCatalogItem.fromDoc).toList()
        ..sort((a, b) {
          final byOrden = a.orden.compareTo(b.orden);
          return byOrden != 0 ? byOrden : a.nombre.compareTo(b.nombre);
        });
      setState(() {
        _items = list;
        _loadingItems = false;
      });
      _pruneMissing();
    }, onError: (_) {
      if (mounted) setState(() => _loadingItems = false);
    });

    _commitSub =
        db.collection('$_cyclePath/commitments').snapshots().listen((q) {
      if (!mounted) return;
      setState(() {
        _committed = {
          for (final d in q.docs)
            d.id: (d.data()['qty'] as num?)?.toDouble() ?? 0,
        };
      });
    }, onError: (_) {});

    if (uid != null) {
      _orderSub = db
          .doc('apoyo_orders/${widget.cycleId}_$uid')
          .snapshots()
          .listen((doc) {
        if (!mounted) return;
        setState(() => _order = doc.exists ? ApoyoOrder.fromDoc(doc) : null);
        _seedFromOrder();
      }, onError: (_) {});
    }

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final now = DateTime.now();
      final cycle = _cycle;
      final label = cycle?.closesAt == null
          ? ''
          : apoyoCountdown(cycle!.timeLeftAt(now));
      final open = cycle?.isOpenAt(now) ?? false;
      if (label == _countdownLabel && open == _isOpen) return;
      setState(() {
        _now = now;
        _countdownLabel = label;
      });
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_resolveCart());
    });
  }

  @override
  void dispose() {
    _cycleSub?.cancel();
    _itemsSub?.cancel();
    _commitSub?.cancel();
    _orderSub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _resolveCart() async {
    final cart = context.read<ApoyoCartProvider>();
    await cart.ready;
    await _cycleLoaded.future;
    if (!mounted || _cartResolved) return;

    if (cart.cycleId == widget.cycleId) {
      _cartResolved = true;
      _seedFromOrder();
      _pruneMissing();
      return;
    }
    if (cart.isEmpty) {
      cart.startFresh(widget.cycleId);
      _cartResolved = true;
      _seedFromOrder();
      _pruneMissing();
      return;
    }

    final friday = _cycle?.deliveryLabel ?? '';
    final move = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Tu selección es del ciclo pasado'),
        content: Text(
          friday.isEmpty
              ? '¿La paso a la lista de esta semana?'
              : '¿La paso al $friday?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Empezar de nuevo'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sí, pásala'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (move == true) {
      cart.adoptCycle(widget.cycleId);
    } else {
      cart.startFresh(widget.cycleId);
    }
    _cartResolved = true;
    _seedFromOrder();
    _pruneMissing();
  }

  void _seedFromOrder() {
    if (!_cartResolved || _seeded) return;
    final order = _order;
    if (order == null || order.isCancelled) return;
    final cart = context.read<ApoyoCartProvider>();
    _seeded = true;
    if (cart.isNotEmpty) return;
    cart.replaceAll(widget.cycleId, order.quantities);
  }

  Future<void> _pruneMissing() async {
    if (!_cartResolved || _loadingItems || _items.isEmpty) return;
    final cart = context.read<ApoyoCartProvider>();
    if (cart.cycleId != widget.cycleId) return;
    final gone = cart.pruneTo(_items.map((i) => i.id).toSet());
    if (gone.isEmpty || !mounted) return;
    await apoyoAlert(
      context,
      title: 'Cambió la lista',
      message: gone.length == 1
          ? 'Quitamos 1 producto de tu selección porque ya no está en la '
              'lista de esta semana.'
          : 'Quitamos ${gone.length} productos de tu selección porque ya no '
              'están en la lista de esta semana.',
    );
  }

  bool get _isFirstOrder => widget.member['firstOrderDone'] != true;

  double get _orderCap {
    if (_isFirstOrder) return widget.config.firstOrderMaxTotal.toDouble();
    final custom = widget.member['maxOrderTotal'];
    if (custom is num && custom > 0) return custom.toDouble();
    return widget.config.defaultMaxOrderTotal.toDouble();
  }

  double? _remainingFor(ApoyoCatalogItem item) {
    if (item.cycleCap <= 0) return null;
    final committed = _committed[item.id] ?? 0;
    final mine = _order?.quantities[item.id] ?? 0;
    return math.max(0, item.cycleCap - (committed - mine));
  }

  double _maxFor(ApoyoCatalogItem item) {
    var cap = double.infinity;
    if (item.maxPerMember > 0) cap = item.maxPerMember;
    final left = _remainingFor(item);
    if (left != null) cap = math.min(cap, left);
    return cap;
  }

  List<ApoyoDraftLine> _draftLines(ApoyoCartProvider cart) {
    final out = <ApoyoDraftLine>[];
    for (final item in _items) {
      final qty = cart.qtyOf(item.id);
      if (qty > 0) out.add(ApoyoDraftLine(item, qty));
    }
    return out;
  }

  bool get _isOpen => _cycle?.isOpenAt(_now) ?? false;

  void _bump(ApoyoCatalogItem item, double delta) {
    final cart = context.read<ApoyoCartProvider>();
    final next = cart.qtyOf(item.id) + delta;
    final max = _maxFor(item);
    cart.setQty(
      cycleId: widget.cycleId,
      catalogItemId: item.id,
      quantity: next > max ? max : next,
    );
  }

  Future<void> _continue() async {
    final cart = context.read<ApoyoCartProvider>();
    final lines = _draftLines(cart);
    final cycle = _cycle;
    if (lines.isEmpty || cycle == null) return;

    final placed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ApoyoConfirmPage(
          config: widget.config,
          member: widget.member,
          cycle: cycle,
          lines: lines,
          existingOrder: _order,
        ),
      ),
    );
    if (placed == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final cart = context.watch<ApoyoCartProvider>();

    return Scaffold(
      backgroundColor: isDarkMode ? Colors.grey[900] : Colors.white,
      appBar: apoyoAppBar(context,
          onBack: () => Navigator.of(context).pop(),
          title: 'Despensa de la semana'),
      body: _loadingItems
          ? const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                _headerCard(),
                if (_order != null && !_order!.isCancelled) ...[
                  const SizedBox(height: 14),
                  _editingCard(_order!),
                ],
                const SizedBox(height: 22),
                apoyoSectionLabel('La lista de esta semana'),
                if (_items.isEmpty)
                  _emptyCatalogCard()
                else
                  for (final item in _items) ...[
                    _itemCard(item, cart.qtyOf(item.id)),
                    const SizedBox(height: 10),
                  ],
              ],
            ),
      bottomNavigationBar: _loadingItems ? null : _bottomBar(cart),
    );
  }

  Widget _headerCard() {
    final cycle = _cycle;
    final left = cycle?.timeLeftAt(_now) ?? Duration.zero;
    final open = _isOpen;

    return ApoyoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ApoyoIconTile(
                icon: open
                    ? Icons.shopping_basket_outlined
                    : Icons.lock_clock_outlined,
                tint: open ? kApoyoGreenTint : kApoyoAmberTint,
                line: open ? kApoyoGreenLine : kApoyoAmberLine,
                color: open ? kApoyoGreen : kApoyoAmber,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Pedido de la semana',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      cycle == null
                          ? 'Elige lo que necesitas.'
                          : 'Entrega ${cycle.elDeliveryLabel}.',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.3,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_cycleReady) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: open ? kApoyoGreenTint : kApoyoAmberTint,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: open ? kApoyoGreenLine : kApoyoAmberLine),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    open ? Icons.timer_outlined : Icons.event_busy_outlined,
                    size: 18,
                    color: open ? kApoyoGreen : kApoyoAmber,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          !open
                              ? 'Los pedidos de esta semana ya cerraron'
                              : cycle?.closesAt == null
                                  ? 'Abierto — puedes pedir hasta el martes'
                                  : 'Cierra en ${apoyoCountdown(left)}',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: open
                                ? kApoyoInk
                                : kApoyoInk,
                          ),
                        ),
                        if (cycle?.closesAt != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Cierra el ${apoyoLongDate(cycle!.closesAt!)} '
                            'a las ${apoyoClock(cycle.closesAt!)}.',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.3,
                              color: open
                                  ? kApoyoInk
                                  : kApoyoInk,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (cycle?.deliveryAt != null) ...[
            const SizedBox(height: 10),
            apoyoRule(
              Icons.local_shipping_outlined,
              'A domicilio el ${cycle!.deliveryLabel} después de las '
              '${cycle.deliveryClock} por '
              '${apoyoMoney(widget.config.deliveryFee)}.',
            ),
            apoyoRule(
              Icons.storefront_outlined,
              'O gratis en la tienda ese mismo día $kApoyoPickupWindow.',
            ),
            apoyoRule(
              Icons.payments_outlined,
              'Pagas en efectivo al recibir, con el monto completo.',
              strong: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _editingCard(ApoyoOrder order) {
    return ApoyoCard(
      color: kApoyoAmberTint,
      borderColor: kApoyoAmberLine,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.edit_note_outlined, size: 20, color: kApoyoAmber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Ya tienes el pedido ${order.folio} por '
              '${apoyoMoney(order.total)}. Si confirmas otra vez, reemplazas '
              'ese pedido con lo que elijas aquí — no se suma.',
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: kApoyoInk,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyCatalogCard() {
    return ApoyoCard(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      child: Column(
        children: [
          Icon(Icons.inventory_2_outlined, size: 26, color: Colors.grey[500]),
          const SizedBox(height: 10),
          const Text(
            'Todavía no hay productos',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'La tienda aún no publica la lista de esta semana. Vuelve a '
            'entrar en un rato.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12.5, height: 1.35, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _itemCard(ApoyoCatalogItem item, double qty) {
    final max = _maxFor(item);
    final remaining = _remainingFor(item);
    final soldOut = remaining != null && remaining <= 0 && qty <= 0;
    final perMember = apoyoQtyUnit(item.maxPerMember, item.unidad);
    final canAdd = _isOpen && !soldOut && qty + item.step <= max + 0.001;
    final lineTotal = apoyoRound2(item.memberPrice * qty);

    return ApoyoCard(
      padding: const EdgeInsets.all(12),
      borderColor: qty > 0 ? kApoyoGreenLine : null,
      color: qty > 0 ? kApoyoGreenTint : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _itemImage(item),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.nombre.isEmpty ? 'Producto' : item.nombre,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      apoyoMoney(item.memberPrice),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: kApoyoGreen,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      item.priceLabel,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
                if (item.components.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    _componentsLabel(item),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12, height: 1.3, color: Colors.grey[700]),
                  ),
                ],
                if (soldOut || remaining != null || item.maxPerMember > 0) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (soldOut)
                        _tag('Agotado esta semana', kApoyoRed, kApoyoRedTint,
                            kApoyoRedLine)
                      else if (remaining != null)
                        _tag('Quedan ${apoyoQtyUnit(remaining, item.unidad)}',
                            kApoyoAmber, kApoyoAmberTint, kApoyoAmberLine),
                      if (item.maxPerMember > 0)
                        _tag(
                          'Máx. $perMember por persona',
                          Colors.grey.shade700,
                          Colors.grey.shade100,
                          Colors.grey.shade300,
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: qty > 0
                          ? Text(
                              '${apoyoQtyUnit(qty, item.unidad)} · '
                              '${apoyoMoney(lineTotal)}',
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: kApoyoGreen,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    _stepper(item, qty, canAdd),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _componentsLabel(ApoyoCatalogItem item) {
    final parts = item.components
        .map((c) => '${apoyoQty(c.quantity)} × ${c.nombre}')
        .join(' · ');
    return 'Incluye: $parts';
  }

  Widget _itemImage(ApoyoCatalogItem item) {
    if (item.imageUrl.isEmpty) {
      return Container(
        width: 62,
        height: 62,
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Icon(
          item.isBundle
              ? Icons.card_giftcard_outlined
              : Icons.shopping_basket_outlined,
          size: 24,
          color: Colors.grey[500],
        ),
      );
    }
    return SizedBox(
      width: 62,
      height: 62,
      child: NetworkImageWithLoader(item.imageUrl, radius: 12),
    );
  }

  Widget _tag(String text, Color color, Color tint, Color line) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: line),
      ),
      child: Text(
        text,
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }

  Widget _stepper(ApoyoCatalogItem item, double qty, bool canAdd) {
    final canRemove = _isOpen && qty > 0;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _stepButton(
            Icons.remove,
            canRemove ? () => _bump(item, -item.step) : null,
          ),
          Container(
            constraints: const BoxConstraints(minWidth: 42),
            alignment: Alignment.center,
            child: Text(
              apoyoQty(qty),
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800),
            ),
          ),
          _stepButton(
            Icons.add,
            canAdd ? () => _bump(item, item.step) : null,
          ),
        ],
      ),
    );
  }

  Widget _stepButton(IconData icon, VoidCallback? onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(
            icon,
            size: 18,
            color: onTap == null ? Colors.grey.shade400 : kApoyoInk,
          ),
        ),
      ),
    );
  }

  Widget _bottomBar(ApoyoCartProvider cart) {
    final lines = _draftLines(cart);
    final subtotal = apoyoDraftSubtotal(lines);
    final overCap = subtotal > _orderCap;
    final open = _isOpen;
    final canContinue = _cycleReady && open && lines.isNotEmpty && !overCap;

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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!_cycleReady)
                const SizedBox.shrink()
              else if (!open)
                _barNote(
                  'Los pedidos de esta semana ya cerraron. La próxima lista '
                  'abre el sábado.',
                  kApoyoAmber,
                )
              else if (overCap)
                _barNote(
                  _isFirstOrder
                      ? 'Tu primer pedido puede ser de hasta '
                          '${apoyoMoney(_orderCap)}. Este suma '
                          '${apoyoMoney(subtotal)}.'
                      : 'Tu límite por pedido es ${apoyoMoney(_orderCap)}. '
                          'Este suma ${apoyoMoney(subtotal)}.',
                  kApoyoRed,
                )
              else if (lines.isEmpty)
                _barNote(
                  'Elige lo que necesitas para el viernes.',
                  Colors.grey.shade600,
                ),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          lines.length == 1
                              ? '1 producto'
                              : '${lines.length} productos',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[600]),
                        ),
                        Text(
                          apoyoMoney(subtotal),
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: canContinue ? _continue : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kApoyoInk,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey.shade300,
                        disabledForegroundColor: Colors.grey.shade600,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text(
                        'Continuar',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _barNote(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
            fontSize: 12, height: 1.3, fontWeight: FontWeight.w600,
            color: color),
      ),
    );
  }
}
