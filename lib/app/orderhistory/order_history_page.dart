import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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

  Stream<List<UserOrder>> _fetchOrderHistory() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Stream.value([]);
    }

    final cutoffDate = DateTime.now().subtract(const Duration(days: 30));

    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('orderHistory')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
      final orders = snapshot.docs.map((doc) {
        final order = UserOrder.fromDocument(doc);
        if (order.timestamp.isBefore(cutoffDate)) {
          FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('orderHistory')
              .doc(doc.id)
              .delete();
        }
        return order;
      }).toList();

      return orders
          .where((order) => order.timestamp.isAfter(cutoffDate))
          .toList();
    });
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
          final orders = snapshot.data!;
          return ListView.builder(
            itemCount: orders.length + 1,
            itemBuilder: (context, index) {
              if (index < orders.length) {
                final order = orders[index];
                return OrderCard(
                  order: order,
                  index: index + 1,
                  onTap: () => _navigateToOrderDetail(order, index + 1),
                );
              } else {
                return const SizedBox(height: 120);
              }
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
    return "${date.day.toString().padLeft(2, '0')}/"
        "${date.month.toString().padLeft(2, '0')}/"
        "${date.year} "
        "${date.hour.toString().padLeft(2, '0')}:"
        "${date.minute.toString().padLeft(2, '0')}";
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'en revision':
        return Colors.orange.shade400;
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
          child: Row(
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
                      'Pedido #${order.id}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
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
                          order.status,
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
        ),
      ),
    );
  }
}
