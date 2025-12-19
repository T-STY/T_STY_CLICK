// lib/pages/order_history/order_history_page.dart

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../constants/app_colors.dart';
import '../../components/shimmer_placeholder.dart';
import '../../constants/app_images.dart';
import 'OrderDetailPage.dart';
import 'orders.dart';


class OrderHistoryPage extends StatefulWidget {
  const OrderHistoryPage({Key? key}) : super(key: key);

  @override
  _OrderHistoryPageState createState() => _OrderHistoryPageState();
}

class _OrderHistoryPageState extends State<OrderHistoryPage> {
  // Index to track the current view: 0 - Order List, 1 - Order Detail
  int _currentIndex = 0;

  // Selected order and its index
  UserOrder? _selectedOrder;
  int? _selectedOrderIndex;

  /// Fetches the current user's order history from Firestore and deletes orders older than 30 days
  Stream<List<UserOrder>> _fetchOrderHistory() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      // Handle unauthenticated state if necessary
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
        // Check if the order is older than 30 days
        if (order.timestamp.isBefore(cutoffDate)) {
          // If the order is older than 30 days, delete it
          FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('orderHistory')
              .doc(doc.id)
              .delete();
        }
        return order;
      }).toList();

      // Return only the orders that are not older than 30 days
      return orders
          .where((order) => order.timestamp.isAfter(cutoffDate))
          .toList();
    });
  }


  /// Navigates to the Order Detail view by updating the index and selected order
  void _navigateToOrderDetail(UserOrder order, int index) {
    setState(() {
      _selectedOrder = order;
      _selectedOrderIndex = index;
      _currentIndex = 1;
    });
  }

  /// Navigates back to the Order List view
  void _navigateBackToList() {
    setState(() {
      _currentIndex = 0;
      _selectedOrder = null;
      _selectedOrderIndex = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme
        .of(context)
        .brightness == Brightness.dark;

    return WillPopScope(
      onWillPop: () async {
        if (_currentIndex != 0) {
          _navigateBackToList();
          return false; // Prevent default back behavior
        }
        return true; // Allow default back behavior
      },
      child: Scaffold(
        appBar: AppBar(
          scrolledUnderElevation: 0,
          backgroundColor: Colors.transparent,
          title: Padding(
            padding: const EdgeInsets.all(0),
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
            ? _buildOrderList()
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
        // NEW: Shimmer List Loading State
        if (snapshot.connectionState == ConnectionState.waiting) {
          return ListView.builder(
            itemCount: 6, // Show 6 dummy items
            itemBuilder: (context, index) {
              return Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      // Image Placeholder
                      const ShimmerPlaceholder(width: 80, height: 80),
                      const SizedBox(width: 16),
                      // Text Details Placeholders
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            ShimmerPlaceholder(width: 120, height: 16),
                            // Order ID
                            SizedBox(height: 8),
                            ShimmerPlaceholder(width: 150, height: 14),
                            // Date
                            SizedBox(height: 4),
                            ShimmerPlaceholder(width: 80, height: 14),
                            // Price
                            SizedBox(height: 4),
                            ShimmerPlaceholder(width: 100, height: 14),
                            // Status
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
    Key? key,
    required this.order,
    required this.index,
    required this.onTap,
  }) : super(key: key);

  /// Formats the date to a readable string
  String _formatDate(DateTime date) {
    return "${date.day.toString().padLeft(2, '0')}/"
        "${date.month.toString().padLeft(2, '0')}/"
        "${date.year} "
        "${date.hour.toString().padLeft(2, '0')}:"
        "${date.minute.toString().padLeft(2, '0')}";
  }

  /// Returns a color based on the order status
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
              // Order Image
              // Inside OrderCard:
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl: order.items.isNotEmpty ? order.items[0].imageUrl : '',
                  width: 80,
                  height: 80,
                  fit: BoxFit.contain,
                  // NEW: Shimmer Placeholder
                  placeholder: (context, url) => const ShimmerPlaceholder(width: 80, height: 80),
                  errorWidget: (context, url, error) => Container(
                    width: 80,
                    height: 80,
                    color: Colors.grey.shade200,
                    child: const Icon(Icons.broken_image, color: Colors.grey),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Order Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Order ID
                    Text(
                      'Pedido #${order.id}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Order Date
                    Row(
                      children: [
                        const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                          _formatDate(order.timestamp),
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Order Total
                    Row(
                      children: [
                        const Icon(Icons.attach_money, size: 16, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                          '${order.total.toStringAsFixed(2)} MXN',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Order Status
                    Row(
                      children: [
                        const Icon(Icons.info_outline, size: 16, color: Colors.grey),
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
                  ],
                ),
              ),
              // Arrow Icon
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
