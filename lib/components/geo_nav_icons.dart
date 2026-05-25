import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

enum GeoIconKind { recipe, orders, home, cart, settings }

const Map<GeoIconKind, String> _assetByKind = {
  GeoIconKind.recipe: 'assets/icons/recipe.svg',
  GeoIconKind.orders: 'assets/icons/orders.svg',
  GeoIconKind.home: 'assets/icons/home.svg',
  GeoIconKind.cart: 'assets/icons/cart.svg',
  GeoIconKind.settings: 'assets/icons/settings.svg',
};

/// Brand nav icon backed by an SVG asset in `assets/icons/`.
///
/// The SVG is tinted to [color] via a srcIn colour filter, so the source
/// artwork can be a single solid colour and still pick up the selected /
/// unselected nav colours. Swap the files in `assets/icons/` to rebrand.
class GeoNavIcon extends StatelessWidget {
  const GeoNavIcon({
    super.key,
    required this.kind,
    required this.color,
    this.size = 26,
  });

  final GeoIconKind kind;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      _assetByKind[kind]!,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}
