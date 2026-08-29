import 'dart:async';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'category/product_display.dart';
import 'category/variant_expansion.dart';

typedef ProductTargetTap = void Function({
  String? category,
  String? brand,
  String? provedor,
  List<String>? productIds,
  String? title,
  String? imageUrl,
});

void dispatchHomeAction(
  BuildContext context,
  Map<String, dynamic>? action, {
  ProductTargetTap? onProductTarget,
  void Function(String comboId)? onCombo,
  void Function()? onApoyo,
  String? imageUrl,
}) {
  final a = action ?? const <String, dynamic>{};
  final type = (a['type'] as String?) ?? 'none';
  switch (type) {
    case 'apoyo':
      // Opens inside the Home shell, like combos do, so the bottom bar stays
      // put and Back returns to the carousel instead of unwinding the tab.
      onApoyo?.call();
      return;
    case 'url':
      final url = a['url'] as String?;
      if (url != null && url.isNotEmpty) {
        launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
      return;
    case 'combo':
      final comboId = a['comboId'] as String?;
      if (comboId != null && comboId.isNotEmpty) onCombo?.call(comboId);
      return;
    case 'category':
    case 'brand':
    case 'provedor':
    case 'products':
      final category = type == 'category' ? a['category'] as String? : null;
      final brand = type == 'brand' ? a['brand'] as String? : null;
      final provedor = type == 'provedor' ? a['provedor'] as String? : null;
      final productIds = type == 'products'
          ? (a['productIds'] as List?)?.cast<String>()
          : null;
      final title = a['title'] as String?;

      if (onProductTarget != null) {
        onProductTarget(
          category: category,
          brand: brand,
          provedor: provedor,
          productIds: productIds,
          title: title,
          imageUrl: imageUrl,
        );
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ProductDisplayPage(
            selectedCategory: category,
            brand: brand,
            distributorName: provedor,
            productIds: productIds,
            title: title,
            imageUrl: imageUrl,
          ),
        ),
      );
      return;
    case 'none':
    default:
      return;
  }
}

String _imageOf(Map<String, dynamic> d) =>
    (d['imageURL'] as String?) ?? (d['imageUrl'] as String?) ?? '';

class HeroBanner extends StatelessWidget {
  final Map<String, dynamic> data;
  final ProductTargetTap? onProductTarget;
  final void Function(String comboId)? onCombo;
  final void Function()? onApoyo;

  const HeroBanner({
    super.key,
    required this.data,
    this.onProductTarget,
    this.onCombo,
    this.onApoyo,
  });

  @override
  Widget build(BuildContext context) {
    final image = _imageOf(data);
    final title = (data['title'] as String?) ?? '';
    final description = (data['description'] as String?) ?? '';
    final action = data['action'] as Map<String, dynamic>?;
    final bool hasAction =
        action != null && (action['type'] as String? ?? 'none') != 'none';
    final bool hasText = title.isNotEmpty || description.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.all(8),
      child: GestureDetector(
        onTap: hasAction
            ? () => dispatchHomeAction(context, action,
                onProductTarget: onProductTarget,
                onCombo: onCombo,
                onApoyo: onApoyo,
                imageUrl: image.isNotEmpty ? image : null)
            : null,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
            height: 200,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (image.isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: image,
                    fit: BoxFit.cover,
                    placeholder: (c, u) => Container(color: Colors.grey[300]),
                    errorWidget: (c, u, e) =>
                        Container(color: Colors.grey[300]),
                  )
                else
                  Container(color: Colors.grey[800]),
                if (hasText)
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black54,
                          Colors.black87,
                        ],
                        stops: [0.35, 0.75, 1.0],
                      ),
                    ),
                  ),
                if (hasText)
                  Positioned(
                    left: 18,
                    right: 18,
                    bottom: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (title.isNotEmpty)
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              height: 1.1,
                            ),
                          ),
                        if (description.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ],
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

class SpotlightBlock extends StatefulWidget {
  final Map<String, dynamic> data;
  const SpotlightBlock({super.key, required this.data});

  @override
  State<SpotlightBlock> createState() => _SpotlightBlockState();
}

class _SpotlightBlockState extends State<SpotlightBlock> {
  static const int _loopBase = 100000;
  final PageController _controller =
      PageController(viewportFraction: 0.92, initialPage: _loopBase);
  Timer? _timer;
  int _count = 0;
  late final List<String> _ids =
      (widget.data['productIds'] as List?)?.cast<String>() ?? const [];
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream =
      FirebaseFirestore.instance
          .collection('products')
          .where(FieldPath.documentId,
              whereIn: _ids.isEmpty ? ['__none__'] : _ids.take(30).toList())
          .snapshots();

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _ensureAutoSlide(int count) {
    _count = count;
    if (count <= 1) return;
    _timer ??= Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_controller.hasClients || _count <= 1) return;
      _controller.nextPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_ids.isEmpty) return const SizedBox.shrink();
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final title = (widget.data['title'] as String?) ?? '';

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final docs = snap.data!.docs
            .where((d) => (d.data()['hide_online'] as bool?) != true)
            .toList();
        final indexById = {for (int i = 0; i < _ids.length; i++) _ids[i]: i};
        docs.sort((a, b) =>
            (indexById[a.id] ?? 1 << 30).compareTo(indexById[b.id] ?? 1 << 30));

        final entries = expandVariantEntries(docs);
        if (entries.isEmpty) return const SizedBox.shrink();

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _ensureAutoSlide(entries.length);
        });

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title.isNotEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 10.0, horizontal: 8.0),
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
              ),
            SizedBox(
              height: 236,
              child: PageView.builder(
                controller: _controller,
                itemBuilder: (context, i) =>
                    _card(entries[(i - _loopBase) % entries.length], isDark),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _card(VariantEntry entry, bool isDark) {
    final doc = entry.doc;
    final Map<String, dynamic> p = entry.parentData;
    final String parentName = (p['nombre'] as String?) ?? 'Producto';
    final String parentImage = (p['image_url'] as String?) ?? '';
    final double parentPrice = (p['price'] as num?)?.toDouble() ?? 0.0;
    final double parentStock = (p['stock'] as num?)?.toDouble() ?? 0.0;
    final String parentTypeSpecific =
        (p['type_specific'] as String?)?.trim() ?? '';

    final String name = parentName;
    final String image = entry.effectiveImageUrl(parentImage);
    final double price = entry.effectivePrice(parentPrice);
    final double stock = entry.effectiveStock(parentStock);

    final String variante = entry.isVariant
        ? (entry.variantName ?? '')
        : ((p['variante'] as String?)?.trim() ?? '');
    final String typeSpecific = parentTypeSpecific;
    final sub = [variante, typeSpecific].where((s) => s.isNotEmpty).join(' · ');
    final bool isGuest = FirebaseAuth.instance.currentUser == null;

    return Container(
      margin: const EdgeInsets.fromLTRB(6, 6, 6, 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 150,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
              child: image.isNotEmpty
                  ? CachedNetworkImage(imageUrl: image, fit: BoxFit.contain)
                  : const Icon(Icons.image, color: Colors.grey),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 84),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('DESTACADO',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            color: Colors.grey[500],
                          )),
                      const SizedBox(height: 10),
                      Text(name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                            height: 1.1,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF1A1A1A),
                          )),
                      if (sub.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(sub,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12.5, color: Colors.grey[600])),
                      ],
                    ],
                  ),
                ),
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 14,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ImageFiltered(
                        imageFilter: ImageFilter.blur(
                          sigmaX: isGuest ? 6.0 : 0.0,
                          sigmaY: isGuest ? 6.0 : 0.0,
                        ),
                        child: Text('\$${price.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                              color: Color(0xFF2E7D32),
                            )),
                      ),
                      const SizedBox(height: 8),
                      AddToCartButton(
                        key: ValueKey('spotlight-${entry.lineKey}'),
                        data: {
                          'docId': doc.id,
                          'nombre': name,
                          'price': price,
                          'image_url': image,
                          'bulk': p['bulk'] as bool? ?? false,
                          'stock': stock,
                          'type_specific': p['type_specific'] as String?,
                          'variante': entry.isVariant
                              ? variante
                              : p['variante'] as String?,
                          if (entry.isVariant) 'variantKey': entry.variantKey,
                          if (entry.isVariant) 'variantName': entry.variantName,
                        },
                        textColor: isDark ? Colors.white : Colors.black,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ComboShowcase extends StatefulWidget {
  final String title;
  final void Function(String comboId)? onCombo;

  const ComboShowcase({super.key, this.title = 'Combos', this.onCombo});

  @override
  State<ComboShowcase> createState() => _ComboShowcaseState();
}

class _ComboShowcaseState extends State<ComboShowcase> {
  static const int _loopBase = 100000;
  final PageController _controller = PageController(initialPage: _loopBase);
  Timer? _timer;
  int _count = 0;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream =
      FirebaseFirestore.instance
          .collection('promotions')
          .where('active', isEqualTo: true)
          .snapshots();

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _ensureAutoSlide(int count) {
    _count = count;
    if (count <= 1) return;
    _timer ??= Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_controller.hasClients || _count <= 1) return;
      _controller.nextPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final combos = snap.data!.docs
            .where((d) => (d.data()['type'] as String?) == 'combo')
            .toList();
        if (combos.isEmpty) return const SizedBox.shrink();

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _ensureAutoSlide(combos.length);
        });

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.title.isNotEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 10.0, horizontal: 8.0),
                child: Text(
                  widget.title,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
              ),
            if (combos.length == 1)
              _comboHero(context, combos.first, isDark)
            else
              SizedBox(
                height: 200,
                child: PageView.builder(
                  controller: _controller,
                  itemBuilder: (context, index) {
                    final doc = combos[(index - _loopBase) % combos.length];
                    return _comboHero(context, doc, isDark);
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _comboHero(BuildContext context,
      QueryDocumentSnapshot<Map<String, dynamic>> doc, bool isDark) {
    final d = doc.data();
    final name = (d['name'] as String?) ?? 'Combo';
    final image = (d['imageURL'] ?? d['imageUrl'] ?? '').toString();
    final bool isFixed = (d['pricingMode'] as String? ?? 'fixed') == 'fixed';
    final price = (d['fixedPrice'] as num?)?.toDouble();
    final Color cardColor = isDark ? Colors.grey[850]! : Colors.white;
    final Color dashColor = Colors.white.withValues(alpha: 0.75);
    final String? priceText =
        (isFixed && price != null) ? '\$${price.toStringAsFixed(2)}' : null;
    const double stubW = 104;

    return Padding(
      padding: const EdgeInsets.all(8),
      child: GestureDetector(
        onTap: () => widget.onCombo?.call(doc.id),
        child: PhysicalShape(
          clipper: const _StubClipper(stubWidth: stubW),
          clipBehavior: Clip.antiAlias,
          color: cardColor,
          elevation: 10,
          shadowColor: Colors.black.withValues(alpha: 0.45),
          child: SizedBox(
            height: 184,
            width: double.infinity,
            child: Stack(
              children: [
                Positioned.fill(
                  child: image.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: image,
                          fit: BoxFit.fill,
                          placeholder: (c, u) =>
                              Container(color: Colors.grey[300]),
                          errorWidget: (c, u, e) =>
                              Container(color: Colors.grey[300]),
                        )
                      : Container(
                          color: Colors.grey[800],
                          child: const Icon(Icons.fastfood,
                              color: Colors.white54, size: 48),
                        ),
                ),
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black26,
                          Colors.transparent,
                          Colors.black54,
                          Colors.black87,
                        ],
                        stops: [0.0, 0.42, 0.78, 1.0],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: stubW - 1,
                  top: 16,
                  bottom: 16,
                  child: CustomPaint(
                    size: const Size(2, double.infinity),
                    painter: _DashedLinePainter(dashColor),
                  ),
                ),
                const Positioned(top: 14, left: 14, child: _ComboBadge()),
                Positioned(
                  left: 16,
                  right: stubW + 10,
                  bottom: 16,
                  child: Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                      shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 14,
                  width: stubW,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Align(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.28),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            priceText ?? 'Ver combo',
                            style: TextStyle(
                              fontSize: priceText != null ? 19 : 14,
                              fontWeight: FontWeight.w800,
                              height: 1.0,
                              color: priceText != null
                                  ? const Color(0xFF2E7D32)
                                  : (isDark ? Colors.white : Colors.black),
                            ),
                          ),
                        ),
                      ),
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

class _ComboBadge extends StatelessWidget {
  const _ComboBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_offer, size: 12, color: Colors.white),
          SizedBox(width: 4),
          Text(
            'COMBO',
            style: TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

class _StubClipper extends CustomClipper<Path> {
  final double stubWidth;

  const _StubClipper({required this.stubWidth});

  @override
  Path getClip(Size size) {
    const double radius = 13;
    const double corner = 20;
    final double notchX = size.width - stubWidth;
    final rrect = Path()
      ..addRRect(RRect.fromRectAndRadius(
          Offset.zero & size, const Radius.circular(corner)));
    final notches = Path()
      ..addOval(Rect.fromCircle(center: Offset(notchX, 0), radius: radius))
      ..addOval(
          Rect.fromCircle(center: Offset(notchX, size.height), radius: radius));
    return Path.combine(PathOperation.difference, rrect, notches);
  }

  @override
  bool shouldReclip(covariant _StubClipper oldClipper) =>
      oldClipper.stubWidth != stubWidth;
}

class _DashedLinePainter extends CustomPainter {
  final Color color;

  _DashedLinePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    const double dash = 5, gap = 4;
    if (size.height >= size.width) {
      final double x = size.width / 2;
      double y = 0;
      while (y < size.height) {
        final double end = (y + dash).clamp(0, size.height).toDouble();
        canvas.drawLine(Offset(x, y), Offset(x, end), paint);
        y += dash + gap;
      }
    } else {
      final double y = size.height / 2;
      double x = 0;
      while (x < size.width) {
        final double end = (x + dash).clamp(0, size.width).toDouble();
        canvas.drawLine(Offset(x, y), Offset(end, y), paint);
        x += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter old) => old.color != color;
}
