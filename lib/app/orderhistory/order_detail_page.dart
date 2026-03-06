import 'dart:math';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../components/custom_loader.dart';
import '../../components/shimmer_placeholder.dart';
import '../../constants/app_colors.dart';
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
      body: SingleChildScrollView(
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
                      'Fecha: ${_formatDate(widget.order.timestamp)}',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                    trailing: _buildStatusIndicator(widget.order.status),
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
            else
              AddressDisplayTile(
                addressId: widget.order.addressId,
                addressData: _addressData!,
              ),
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
                  widget.order.paymentMethod.capitalize(),
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),
            ),
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
    );
  }

  Widget _buildStatusIndicator(String status) {
    final bool canCancel = status.toLowerCase() == 'en revision';

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
              status.capitalize(),
              style: TextStyle(
                color: _getStatusColor(status),
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.circle,
            color: _getStatusColor(status),
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
            _buildFinancialRow(
              'Total',
              widget.order.total,
              isTotal: true,
            ),
            const Divider(),
            _buildFinancialRow(
              'Saldo de Monedero',
              widget.order.useRewardsBalance ? 'Sí' : 'No',
              isRewards: true,
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
      displayValue = value;
    } else if (isRewards) {
      displayValue = value;
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
                          const SizedBox(height: 4),
                          Text(
                            'Cantidad: ${item.quantity.toStringAsFixed(2)}', // Updated format
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
    if (widget.order.status.toLowerCase() != 'en revision') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
            Text('Este pedido no puede ser cancelado en su estado actual.')),
      );
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Usuario no ha iniciado sesión.')),
        );
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
        if (!mounted) return;
        Navigator.of(context).pop();
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