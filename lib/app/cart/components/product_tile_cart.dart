import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../components/shimmer_placeholder.dart';

class ProductTileCart extends StatelessWidget {
  final String objectId;
  final String name;
  final double price;
  final String imageUrl;
  final double quantity;
  final void Function()? increaseQuantity;
  final void Function()? decreaseQuantity;
  final bool isBulk;
  // New fields
  final String? typeSpecific;
  final String? variante;

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
    this.typeSpecific,
    this.variante,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final totalPrice = price * quantity;

    return Container(
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
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8.0),
              child: CachedNetworkImage(
                imageUrl: imageUrl.isNotEmpty ? imageUrl : '',
                width: 80,
                height: 80,
                fit: BoxFit.contain,
                placeholder: (context, url) => const ShimmerPlaceholder(width: 80, height: 80),
                errorWidget: (context, url, error) => Container(
                  width: 80,
                  height: 80,
                  color: Colors.grey[200],
                  child: const Icon(Icons.image_not_supported, color: Colors.grey),
                ),
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
                  // Display Variant and Type Specific
                  if ((variante != null && variante!.isNotEmpty) || (typeSpecific != null && typeSpecific!.isNotEmpty))
                    Text(
                      "${variante ?? ''} ${typeSpecific ?? ''}".trim(),
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 4.0),
                  Text(
                    'Precio: \$${price.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 14, color: Colors.black54),
                  ),
                  const SizedBox(height: 4.0),
                  Text(
                    'Total: \$${totalPrice.toStringAsFixed(2)}',
                    style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),

            // Quantity Controls (Same as before)
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: decreaseQuantity,
                      color: Colors.red,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      visualDensity: VisualDensity.compact,
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