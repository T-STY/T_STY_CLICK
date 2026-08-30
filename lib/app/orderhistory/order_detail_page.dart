import 'dart:math';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../components/bottom_fade.dart';
import '../../components/custom_loader.dart';
import '../../components/shimmer_placeholder.dart';
import '../../constants/app_colors.dart';
import '../../utils/coupon_filter.dart' as cf;
import '../verse/verse_model.dart';
import 'applied_coupon.dart';
import 'constants/address_section.dart';
import 'orders.dart';

class OrderDetailPage extends StatefulWidget {
  final UserOrder order;
  final int orderIndex;
  final VoidCallback onBack;

  const OrderDetailPage({
    super.key,
    required this.order,
    required this.orderIndex,
    required this.onBack,
  });

  @override
  State<OrderDetailPage> createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends State<OrderDetailPage> {
  Map<String, dynamic>? _addressData;
  bool _isFetchingAddress = true;
  String? _fetchError;

  Verse? _selectedVerse;

  @override
  void initState() {
    super.initState();
    _fetchAddress();
    _selectRandomVerse();
  }

  void _selectRandomVerse() {
    final random = Random();
    setState(() {
      _selectedVerse =
      motivationalVerses[random.nextInt(motivationalVerses.length)];
    });
  }

  final List<Verse> motivationalVerses = [
    Verse(
      reference: 'Romanos 1:16',
      text:
      '“Porque no me avergüenzo del evangelio, porque es poder de Dios para salvación a todo aquel que cree; al judío primeramente, y también al griego.”',
    ),
    Verse(
      reference: '1 Tesalonicenses 5:9-10',
      text:
      '“Porque no nos ha puesto Dios para ira, sino para alcanzar salvación por medio de nuestro Señor Jesucristo, quien murió por nosotros para que ya sea que velemos, o que durmamos, vivamos juntamente con él.”',
    ),
    Verse(
      reference: 'Efesios 5:6-10',
      text:
      '“No seáis partícipes con ellos; porque bien sabéis que la impiedad, ni aun seña de ello tiene quien la domine. [...] No participéis en las obras infructuosas de las tinieblas, sino más bien reprendedlas.”',
    ),
    Verse(
      reference: 'Romanos 6:12–14',
      text:
      '“No reine, pues, el pecado en vuestro cuerpo mortal, de manera que lo obedezcáis en sus deseos; ni tampoco presentéis vuestros miembros al pecado como instrumentos de iniquidad, sino presentaos vosotros mismos a Dios como vivos de entre los muertos, y vuestros miembros a Dios como instrumentos de justicia.”',
    ),
  ];

  Future<void> _fetchAddress() async {

    if (widget.order.isInstorePickup) {
      try {
        final storeDoc = await FirebaseFirestore.instance
            .collection('settings')
            .doc('address')
            .get();
        if (storeDoc.exists) {
          setState(() {
            _addressData = storeDoc.data();
            _isFetchingAddress = false;
          });
        } else {
          setState(() {
            _isFetchingAddress = false;
            _fetchError =
                'Falta la dirección de la tienda en configuración.';
          });
        }
      } catch (e) {
        setState(() {
          _isFetchingAddress = false;
          _fetchError = 'Error al obtener la dirección de la tienda: $e';
        });
      }
      return;
    }

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      setState(() {
        _isFetchingAddress = false;
        _fetchError = 'Usuario no ha iniciado sesión';
      });
      return;
    }

    if (widget.order.addressId.isEmpty || widget.order.addressId == "N/A") {
      setState(() {
        _isFetchingAddress = false;
        _fetchError = 'No hay una dirección válida asociada a este pedido.';
      });
      return;
    }

    try {
      final addressDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('addresses')
          .doc(widget.order.addressId)
          .get();

      if (addressDoc.exists) {
        setState(() {
          _addressData = addressDoc.data();
          _isFetchingAddress = false;
        });
      } else {
        setState(() {
          _isFetchingAddress = false;
          _fetchError = 'Dirección no encontrada para este pedido.';
        });
      }
    } catch (e) {
      setState(() {
        _isFetchingAddress = false;
        _fetchError = 'Error al obtener la dirección: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color cardColor = Colors.white;
    final Color textColor = Colors.grey[800]!;

    return Scaffold(
      backgroundColor: Colors.white,
      body: BottomFade(
        child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionCard(
              color: cardColor,
              child: Column(
                children: [
                  ListTile(
                    title: Text(
                      'Total: \$${widget.order.total.toStringAsFixed(2)} MXN',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: textColor,
                        fontSize: 16,
                      ),
                    ),
                    subtitle: Text(
                      widget.order.deliveryWindowLabel == null
                          ? 'Fecha: ${_formatDate(widget.order.timestamp)}'
                          : 'Fecha: ${_formatDate(widget.order.timestamp)}\n'
                              '${widget.order.isInstorePickup ? 'Recoges' : 'Entrega'}: '
                              '${widget.order.deliveryWindowLabel}',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                    trailing: _buildStatusIndicator(widget.order),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_isFetchingAddress)
              const ShimmerPlaceholder.rectangular(height: 80)
            else if (_fetchError != null)
              Text(
                _fetchError!,
                style: const TextStyle(color: Colors.red),
              )
            else ...[
              AddressDisplayTile(

                addressId: widget.order.isInstorePickup
                    ? 'store-pickup'
                    : widget.order.addressId,
                addressData: _addressData!,
              ),
            ],
            const SizedBox(height: 16),
            _buildSectionCard(
              color: cardColor,
              child: ListTile(
                leading: const Icon(Icons.payment, color: AppColors.primary),
                title: Text(
                  'Método de Pago',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                subtitle: Text(
                  widget.order.cashPaidWith > widget.order.total
                      ? '${widget.order.paymentMethod.capitalize()} · '
                          'Pagas con \$${widget.order.cashPaidWith.toStringAsFixed(0)}'
                      : widget.order.paymentMethod.capitalize(),
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),
            ),
            if (widget.order.notes.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildSectionCard(
                color: cardColor,
                child: ListTile(
                  leading: const Icon(Icons.sticky_note_2_outlined,
                      color: AppColors.primary),
                  title: Text(
                    'Notas del pedido',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: textColor),
                  ),
                  subtitle: Text(
                    widget.order.notes,
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            _buildFinancialDetailsCard(),
            const SizedBox(height: 16),
            _buildReceiptStyleOrderItems(),
            const SizedBox(height: 16),
            if (widget.order.appliedCoupon != null) ...[
              _buildAppliedCouponCard(widget.order.appliedCoupon!),
              const SizedBox(height: 16),
            ],
            _buildVerseSection(),
            const SizedBox(height: 110),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildStatusIndicator(UserOrder order) {

    final String rawStatus = order.status;

    final String rawStatusLower = rawStatus.toLowerCase();
    final bool canCancel =
        rawStatusLower == 'en revision' || rawStatusLower == 'preparando';

    return GestureDetector(
      onTap: canCancel ? _cancelOrder : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          MouseRegion(
            cursor: canCancel
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            child: Text(
              order.displayStatus.capitalize(),
              style: TextStyle(
                color: _getStatusColor(rawStatus),
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.circle,
            color: _getStatusColor(rawStatus),
            size: 12,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({required Widget child, required Color color}) {
    return Card(
      color: color,
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }

  Widget _buildFinancialDetailsCard() {
    return _buildSectionCard(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 12.0),
        child: Column(
          children: [
            _buildFinancialRow('Subtotal', widget.order.subtotal),
            const Divider(),
            _buildFinancialRow('Costo de Entrega', widget.order.deliveryFee),
            const Divider(),
            _buildFinancialRow('Descuento', widget.order.discount),
            const Divider(),
            if (widget.order.appliedCoupon != null) ...[
              _buildFinancialRow(
                'Cupón Aplicado',
                widget.order.appliedCoupon!.code,
                isCoupon: true,
              ),
              const Divider(),
            ],
            if (widget.order.appliedRewards > 0) ...[
              _buildFinancialRow(
                'Saldo de Monedero Usado',
                -widget.order.appliedRewards,
                isRewards: true,
              ),
              const Divider(),
            ],
            _buildFinancialRow(
              'Total',
              widget.order.total,
              isTotal: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFinancialRow(String label, dynamic value,
      {bool isTotal = false, bool isCoupon = false, bool isRewards = false}) {
    final TextStyle labelStyle = TextStyle(
      fontSize: isTotal ? 16 : 14,
      fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
      color: Colors.black87,
    );

    final TextStyle valueStyle = TextStyle(
      fontSize: isTotal ? 16 : 14,
      fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
      color: isCoupon || isRewards ? AppColors.primary : Colors.black87,
    );

    String displayValue;
    if (isCoupon) {
      displayValue = value as String;
    } else {
      displayValue = value is double
          ? '\$${value.toStringAsFixed(2)} MXN'
          : value.toString();
      if (value is double && value < 0) {
        displayValue = '-\$${value.abs().toStringAsFixed(2)} MXN';
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: labelStyle),
          Text(displayValue, style: valueStyle),
        ],
      ),
    );
  }

  Widget _buildReceiptStyleOrderItems() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            spreadRadius: 2,
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Productos',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: widget.order.items.length,
            separatorBuilder: (context, index) => const Divider(),
            itemBuilder: (context, index) {
              final item = widget.order.items[index];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: item.imageUrl,
                        width: 50,
                        height: 50,
                        fit: BoxFit.contain,
                        placeholder: (context, url) =>
                        const ShimmerPlaceholder(width: 50, height: 50),
                        errorWidget: (context, url, error) =>
                        const Icon(Icons.error),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          if (item.variantName != null &&
                              item.variantName!.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              item.variantName!,
                              style: TextStyle(
                                color: Colors.grey[700],
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          const SizedBox(height: 4),
                          Text(
                            'Cantidad: ${item.quantity.toStringAsFixed(2)}',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Text(
                        '\$${(item.price * item.quantity).toStringAsFixed(2)} MXN',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAppliedCouponCard(AppliedCoupon coupon) {
    return _buildSectionCard(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Cupón Aplicado',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.local_offer, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  coupon.code,
                  style: const TextStyle(
                    fontSize: 16,
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Descuento: ${coupon.percentage}% (Máximo \$${coupon.maxDiscount.toStringAsFixed(2)} MXN)',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[800],
              ),
            ),
            if (coupon.productFilterSummary.isNotEmpty) ...[
              const SizedBox(height: 10),
              _CouponScopeBlock(filter: coupon.productFilter),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildVerseSection() {
    if (_selectedVerse == null) {
      return const SizedBox.shrink();
    }

    return _buildSectionCard(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Versículo',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                )),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  colors: [Colors.grey[300]!, Colors.grey[100]!],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _selectedVerse!.reference,
                    style: const TextStyle(
                      fontStyle: FontStyle.italic,
                      color: Colors.black54,
                    ),
                    textAlign: TextAlign.justify,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _selectedVerse!.text,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.black87,
                    ),
                    textAlign: TextAlign.justify,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${_formatTime(date)}';
  }

  String _formatTime(DateTime date) {
    String hour = date.hour.toString().padLeft(2, '0');
    String minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'en revision':
        return Colors.orange;
      case 'preparando':
        return Colors.purple;
      case 'enviado':
        return Colors.blue;
      case 'entregado':
        return Colors.green;
      case 'cancelado':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Future<void> _cancelOrder() async {
    final String s = widget.order.status.toLowerCase();
    if (s != 'en revision' && s != 'preparando') {
      return;
    }

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Confirmar Cancelación'),
          content:
          const Text('¿Estás seguro de que deseas cancelar este pedido?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('No'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Sí'),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      if (!mounted) return;
      final userId = FirebaseAuth.instance.currentUser?.uid;
      final orderId = widget.order.id;

      if (userId == null) {
        return;
      }

      try {
        final userOrderRef = FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('orderHistory')
            .doc(orderId);

        final topLevelOrderRef =
        FirebaseFirestore.instance.collection('orders').doc(orderId);

        final userOrderDoc = await userOrderRef.get();
        final topLevelOrderDoc = await topLevelOrderRef.get();

        if (!userOrderDoc.exists || !topLevelOrderDoc.exists) return;

        WriteBatch batch = FirebaseFirestore.instance.batch();

        Map<String, dynamic> updateData = {
          'state': 'Cancelado',
          'cancellationTimestamp': FieldValue.serverTimestamp(),
        };

        batch.update(userOrderRef, updateData);
        batch.update(topLevelOrderRef, updateData);

        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const CustomLoader(),
        );

        await batch.commit();

        if (!mounted) return;
        Navigator.of(context).pop();

        setState(() {
          widget.order.status = 'Cancelado';
        });
      } catch (e) {
        if (kDebugMode) debugPrint('Error cancelling order: $e');
        if (!mounted) return;
        Navigator.of(context).pop();
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Error'),
            content: const Text(
                'No se pudo cancelar el pedido. Intenta de nuevo.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }
}

extension StringCasingExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}

class _CouponScopeBlock extends StatelessWidget {
  final Map<String, dynamic>? filter;

  const _CouponScopeBlock({required this.filter});

  @override
  Widget build(BuildContext context) {
    final details = cf.productFilterDetails(filter);
    if (details == null) return const SizedBox.shrink();

    final isInclude = details.isInclude;
    final headerColor =
        isInclude ? const Color(0xFF1B5E20) : const Color(0xFFB45309);
    final headerBg = isInclude
        ? const Color(0xFFDCEFDC)
        : const Color(0xFFFFF1D6);
    final headerLabel = isInclude
        ? 'Aplicó únicamente a:'
        : 'No aplicó a:';

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: headerBg.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isInclude
                    ? Icons.check_circle_outline
                    : Icons.do_not_disturb_alt_outlined,
                size: 16,
                color: headerColor,
              ),
              const SizedBox(width: 6),
              Text(
                headerLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: headerColor,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          if (!details.hasAnyChips) ...[
            const SizedBox(height: 6),
            Text(
              'Sin selección específica.',
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            ),
          ],
          if (details.subcategories.isNotEmpty) ...[
            const SizedBox(height: 8),
            const _SubLabel(text: 'Categorías'),
            const SizedBox(height: 4),
            _ChipsWrap(items: details.subcategories, color: headerColor),
          ],
          if (details.provedores.isNotEmpty) ...[
            const SizedBox(height: 8),
            const _SubLabel(text: 'Provedores'),
            const SizedBox(height: 4),
            _ChipsWrap(items: details.provedores, color: headerColor),
          ],
          if (details.productIds.isNotEmpty) ...[
            const SizedBox(height: 8),
            const _SubLabel(text: 'Productos específicos'),
            const SizedBox(height: 4),
            _ChipsWrap(
              items: [
                '${details.productIds.length} '
                    'producto${details.productIds.length == 1 ? '' : 's'}',
              ],
              color: headerColor,
            ),
          ],
        ],
      ),
    );
  }
}

class _SubLabel extends StatelessWidget {
  final String text;
  const _SubLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w800,
        color: Colors.grey[700],
        letterSpacing: 0.8,
      ),
    );
  }
}

class _ChipsWrap extends StatelessWidget {
  final List<String> items;
  final Color color;
  const _ChipsWrap({required this.items, required this.color});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 5,
      runSpacing: 5,
      children: [
        for (final t in items)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: color.withValues(alpha: 0.45)),
            ),
            child: Text(
              t,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
      ],
    );
  }
}
