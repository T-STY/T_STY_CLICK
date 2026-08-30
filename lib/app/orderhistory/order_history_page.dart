import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../../constants/app_colors.dart';
import '../../components/bottom_fade.dart';
import '../../components/shimmer_placeholder.dart';
import '../../constants/app_images.dart';
import 'order_detail_page.dart';
import 'orders.dart';

class OrderHistoryPage extends StatefulWidget {
  const OrderHistoryPage({super.key});

  @override
  State<OrderHistoryPage> createState() => _OrderHistoryPageState();
}

class _OrderHistoryPageState extends State<OrderHistoryPage> {
  int _currentIndex = 0;
  UserOrder? _selectedOrder;
  int? _selectedOrderIndex;

  bool _showAllOrders = false;

  Stream<List<UserOrder>> _fetchOrderHistory() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value([]);

    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('orderHistory')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => UserOrder.fromDocument(doc))
            .toList());
  }

  void _navigateToOrderDetail(UserOrder order, int index) {
    setState(() {
      _selectedOrder = order;
      _selectedOrderIndex = index;
      _currentIndex = 1;
    });
  }

  void _navigateBackToList() {
    setState(() {
      _currentIndex = 0;
      _selectedOrder = null;
      _selectedOrderIndex = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: _currentIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _navigateBackToList();
      },
      child: Scaffold(
        appBar: AppBar(
          scrolledUnderElevation: 0,
          backgroundColor: Colors.transparent,
          title: Padding(
            padding: EdgeInsets.zero,
            child: SizedBox(
              height: 180,
              width: 300,
              child: AspectRatio(
                aspectRatio: 1 / 1,
                child: Image.asset(
                  isDarkMode ? AppImages.logowhite : AppImages.logo,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          automaticallyImplyLeading: false,
          centerTitle: true,
        ),
        body: _currentIndex == 0
            ? BottomFade(child: _buildOrderList())
            : _selectedOrder != null && _selectedOrderIndex != null
            ? OrderDetailPage(
          order: _selectedOrder!,
          orderIndex: _selectedOrderIndex!,
          onBack: _navigateBackToList,
        )
            : const Center(child: Text('Pedido no encontrado.')),
      ),
    );
  }

  Widget _buildOrderList() {
    return StreamBuilder<List<UserOrder>>(
      stream: _fetchOrderHistory(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return ListView.builder(
            itemCount: 6,
            itemBuilder: (context, index) {
              return Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                child: const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      ShimmerPlaceholder(width: 80, height: 80),
                      SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ShimmerPlaceholder(width: 120, height: 16),
                            SizedBox(height: 8),
                            ShimmerPlaceholder(width: 150, height: 14),
                            SizedBox(height: 4),
                            ShimmerPlaceholder(width: 80, height: 14),
                            SizedBox(height: 4),
                            ShimmerPlaceholder(width: 100, height: 14),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        } else if (snapshot.hasError) {
          return Center(
            child: Text('Error al cargar los pedidos: ${snapshot.error}'),
          );
        } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(
            child: Text('No tienes pedidos en tu historial.'),
          );
        } else {
          final allOrders = snapshot.data!;

          final cutoff = DateTime.now().subtract(const Duration(days: 30));
          final recent = allOrders
              .where((o) => o.timestamp.isAfter(cutoff))
              .toList();
          final older = allOrders
              .where((o) => !o.timestamp.isAfter(cutoff))
              .toList();

          final visible = _showAllOrders ? allOrders : recent;
          final hasOlder = older.isNotEmpty;

          final extras = (hasOlder ? 1 : 0) + 1;

          return ListView.builder(
            itemCount: visible.length + extras,
            itemBuilder: (context, index) {
              if (index < visible.length) {
                final order = visible[index];
                return OrderCard(
                  order: order,
                  index: index + 1,
                  onTap: () => _navigateToOrderDetail(order, index + 1),
                );
              }

              if (hasOlder && index == visible.length) {
                return _OlderHistoryToggle(
                  expanded: _showAllOrders,
                  olderCount: older.length,
                  onTap: () => setState(
                      () => _showAllOrders = !_showAllOrders),
                );
              }

              return const SizedBox(height: 120);
            },
          );
        }
      },
    );
  }
}

class OrderCard extends StatelessWidget {
  final UserOrder order;
  final int index;
  final VoidCallback onTap;

  const OrderCard({
    super.key,
    required this.order,
    required this.index,
    required this.onTap,
  });

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateDay = DateTime(date.year, date.month, date.day);
    final diffDays = today.difference(dateDay).inDays;
    final time = DateFormat('HH:mm').format(date);

    if (diffDays == 0) return 'Hoy · $time';
    if (diffDays == 1) return 'Ayer · $time';
    final pattern = date.year == now.year ? 'd MMM' : 'd MMM yyyy';

    final formatted = DateFormat(pattern, 'es').format(date);
    final capped = formatted.replaceFirstMapped(
      RegExp(r'[a-záéíóúñ]'),
      (m) => m[0]!.toUpperCase(),
    );
    return '$capped · $time';
  }

  static String _shortId(String id) {
    final clean = id.trim();
    if (clean.length <= 6) return clean.toUpperCase();
    return clean.substring(clean.length - 6).toUpperCase();
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'en revision':
        return Colors.orange.shade400;
      case 'preparando':
        return Colors.purple.shade400;
      case 'enviado':
        return Colors.blue.shade400;
      case 'entregado':
        return Colors.green.shade400;
      case 'cancelado':
        return Colors.red.shade400;
      default:
        return Colors.grey.shade400;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Stack(
            children: [
              Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl:
                  order.items.isNotEmpty ? order.items[0].imageUrl : '',
                  width: 80,
                  height: 80,
                  fit: BoxFit.contain,
                  placeholder: (context, url) =>
                  const ShimmerPlaceholder(width: 80, height: 80),
                  errorWidget: (context, url, error) => Container(
                    width: 80,
                    height: 80,
                    color: Colors.grey.shade200,
                    child: const Icon(Icons.broken_image, color: Colors.grey),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(

                      'Pedido #${_shortId(order.id)}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.calendar_today,
                            size: 16, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                          _formatDate(order.timestamp),
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.attach_money,
                            size: 16, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                          '${order.total.toStringAsFixed(2)} MXN',
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.info_outline,
                            size: 16, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(

                          order.displayStatus,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _getStatusColor(order.status),
                          ),
                        ),
                      ],
                    ),
                    if (order.appliedRewards > 0) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.account_balance_wallet,
                              size: 16, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(
                            'Saldo usado: \$${order.appliedRewards.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios,
                color: AppColors.primary,
                size: 16,
              ),
            ],
          ),

              Positioned(
                top: 0,
                right: 0,
                child: _FulfillmentMark(isPickup: order.isInstorePickup),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OlderHistoryToggle extends StatelessWidget {
  final bool expanded;
  final int olderCount;
  final VoidCallback onTap;

  const _OlderHistoryToggle({
    required this.expanded,
    required this.olderCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            decoration: BoxDecoration(
              color: const Color(0xFFF6F7F9),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE3E5EC)),
            ),
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Icon(
                  expanded ? Icons.unfold_less : Icons.unfold_more,
                  size: 18,
                  color: const Color(0xFF141414),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    expanded
                        ? 'Mostrar solo los últimos 30 días'
                        : 'Ver pedidos anteriores ($olderCount)',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF141414),
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FulfillmentMark extends StatelessWidget {
  final bool isPickup;
  const _FulfillmentMark({required this.isPickup});

  @override
  Widget build(BuildContext context) {
    final color = isPickup ? AppColors.primary : Colors.orange.shade800;
    return Tooltip(
      message: isPickup ? 'Recoger en tienda' : 'Entrega a domicilio',
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: (isPickup ? AppColors.primary : Colors.orange)
              .withValues(alpha: 0.10),
          shape: BoxShape.circle,
        ),
        child: Icon(
          isPickup ? Icons.storefront : Icons.delivery_dining,
          size: 16,
          color: color,
        ),
      ),
    );
  }
}
