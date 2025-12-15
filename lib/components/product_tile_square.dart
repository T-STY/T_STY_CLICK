import 'package:flutter/material.dart';
import 'package:flutter_iconly/flutter_iconly.dart';
import 'package:intl/intl.dart';
import '../constants/constants.dart';
import 'network_image.dart';

class ProductTileSquare extends StatelessWidget {
  const ProductTileSquare({
    super.key,
    required this.title,
    required this.price,
    required this.model,
    required this.variante,
    required this.imageLink,
    this.onTap,
    this.hasFavourite = false,
    this.isFavourite = false,
    this.onFavouriteClicked,
  });

  final String title;
  final String model;
  final String variante;
  final double price;
  final String imageLink;
  final void Function()? onTap;
  final bool hasFavourite;
  final bool isFavourite;
  final void Function()? onFavouriteClicked;

  @override
  Widget build(BuildContext context) {
    // Determine if we're currently in dark mode
    bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    // Adjust colors based on the theme mode
    Color currentBackgroundColor = isDarkMode ? Colors.grey[850]! : Colors.white;
    Color currentBorderColor = isDarkMode ? Colors.grey[800]! : Colors.grey[100]!;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
      child: Material(
        color: currentBackgroundColor,
        borderRadius: AppDefaults.borderRadius,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: currentBorderColor, width: 5.0),
            borderRadius: AppDefaults.borderRadius,
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: AppDefaults.borderRadius,
            child: Container(
              width: MediaQuery.of(context).size.width * 0.45,
              padding: const EdgeInsets.all(AppDefaults.padding),
              child: Center(
                child: Stack(
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          height: 180,
                          child: AspectRatio(
                            aspectRatio: 1 / 1,
                            child: Hero(
                              tag: imageLink,
                              child: NetworkImageWithLoader(
                                imageLink,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              title,
                              style: Theme.of(context).textTheme.titleMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 5),
                            Text(
                              variante,
                              style: Theme.of(context).textTheme.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 5),
                                Text(
                                  '\$${NumberFormat("#,##0").format(price.toInt())} MXN',
                                  style: Theme.of(context).textTheme.bodyLarge,
                                  maxLines: 1,
                                ),
                            const SizedBox(height: 5),
                                Text(
                                  model,
                                  style: Theme.of(context).textTheme.bodySmall,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          ],
                        )
                      ],
                    ),
                    if (hasFavourite)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: GestureDetector(
                          onTap: onFavouriteClicked,
                          child: Container(
                            padding: const EdgeInsets.all(8.0),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: currentBackgroundColor,
                            ),
                            child: Icon(
                              isFavourite ? IconlyBold.heart : IconlyLight.heart,
                              color: Colors.red,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

