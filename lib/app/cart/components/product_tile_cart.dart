import 'package:flutter/material.dart';

class ProductTileCart extends StatelessWidget {
  final String objectId;
  final String name;
  final double price;
  final String imageUrl;
  final double quantity; // Ensure this accepts fractional values
  final void Function()? increaseQuantity;
  final void Function()? decreaseQuantity;
  final bool isBulk;

  const ProductTileCart({
    Key? key,
    required this.objectId,
    required this.name,
    required this.price,
    required this.imageUrl,
    required this.quantity,
    this.increaseQuantity,
    this.decreaseQuantity,
    required this.isBulk,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final totalPrice = price * quantity; // Calculate total price

    return Container(
      // FIX 1: Removed fixed height: 120. Let content dictate height.
      // Added minimum height constraint to ensure consistency for small items.
      constraints: const BoxConstraints(minHeight: 120),
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 5.0),
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 6,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: IntrinsicHeight( // FIX 2: Ensures Row children stretch to match tallest element
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Image
            ClipRRect(
              borderRadius: BorderRadius.circular(8.0),
              child: Image.network(
                imageUrl.isNotEmpty ? imageUrl : '/images/placeholder.png',
                width: 80,
                height: 80,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    width: 80,
                    height: 80,
                    color: Colors.grey[200],
                    child: const Icon(Icons.image_not_supported, color: Colors.grey),
                  );
                },
              ),
            ),
            const SizedBox(width: 16.0),

            // Product Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4.0),
                  Text(
                    'Precio: \$${price.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 4.0),
                  Text(
                    'Total: \$${totalPrice.toStringAsFixed(2)}',
                    style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),

            // Quantity Controls
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min, // FIX 3: Ensure Row takes minimum space needed
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: decreaseQuantity,
                      color: Colors.red,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(), // Removes default padding
                      visualDensity: VisualDensity.compact, // Reduces button size
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Text(
                        quantity.toStringAsFixed(isBulk ? 2 : 0),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: increaseQuantity,
                      color: Colors.blue,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}