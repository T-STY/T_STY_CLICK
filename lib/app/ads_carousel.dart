import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'home_blocks.dart';

class AdsCarousel extends StatefulWidget {
  final String placement;
  final String? title;

  final ProductTargetTap? onProductTarget;

  final void Function(String comboId)? onCombo;

  /// Opens Apoyo Social inside the Home shell. Lets a banner be the way in,
  /// configured from the admin panel like any other ad action.
  final void Function()? onApoyo;

  final List<String>? adIds;

  const AdsCarousel({
    super.key,
    this.placement = 'home_carousel',
    this.title,
    this.onProductTarget,
    this.onCombo,
    this.onApoyo,
    this.adIds,
  });

  @override
  State<AdsCarousel> createState() => _AdsCarouselState();
}

class _AdsCarouselState extends State<AdsCarousel> {
  static const int _loopBase = 100000;
  final PageController _controller =
      PageController(viewportFraction: 1.0, initialPage: _loopBase);
  Timer? _timer;
  int _count = 0;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream =
      FirebaseFirestore.instance
          .collection('ads')
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

  bool _isLive(Map<String, dynamic> data) {
    final now = Timestamp.now();
    final start = data['startAt'];
    final end = data['endAt'];
    if (start is Timestamp && now.compareTo(start) < 0) return false;
    if (end is Timestamp && now.compareTo(end) > 0) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        final ids = widget.adIds;
        final bool useIds = ids != null && ids.isNotEmpty;
        final docs = snapshot.data!.docs.where((doc) {
          final d = doc.data();
          if (!_isLive(d)) return false;
          if (useIds) return ids.contains(doc.id);
          return (d['placement'] as String? ?? 'home_carousel') ==
              widget.placement;
        }).toList();
        if (useIds) {
          final idx = {for (int i = 0; i < ids.length; i++) ids[i]: i};
          docs.sort((a, b) =>
              (idx[a.id] ?? 1 << 30).compareTo(idx[b.id] ?? 1 << 30));
        } else {
          docs.sort((a, b) => ((a.data()['order'] as num?) ?? 0)
              .compareTo((b.data()['order'] as num?) ?? 0));
        }
        final ads = docs.map((d) => d.data()).toList();

        if (ads.isEmpty) return const SizedBox.shrink();

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _ensureAutoSlide(ads.length);
        });

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.title != null && widget.title!.isNotEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 10.0, horizontal: 8.0),
                child: Text(
                  widget.title!,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
            SizedBox(
              height: 200,
              child: PageView.builder(
                controller: _controller,
                itemBuilder: (context, index) =>
                    _buildAd(context, ads[(index - _loopBase) % ads.length]),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAd(BuildContext context, Map<String, dynamic> data) {
    final imageUrl =
        (data['imageUrl'] as String?) ?? (data['imageURL'] as String?) ?? '';
    final title = (data['title'] as String?) ?? '';
    final description = (data['description'] as String?) ?? '';
    final ctaLabel = (data['ctaLabel'] as String?) ?? '';
    final bool hasText =
        title.isNotEmpty || description.isNotEmpty || ctaLabel.isNotEmpty;
    return GestureDetector(
      onTap: () => _onAdTap(context, data),
      child: Container(
        margin: const EdgeInsets.all(8.0),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(2, 4),
            ),
          ],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.cover,
              width: double.infinity,
              placeholder: (context, url) => Container(color: Colors.grey[300]),
              errorWidget: (context, url, error) => Container(
                color: Colors.grey[300],
                child: const Icon(Icons.image_not_supported),
              ),
            ),
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
                    stops: [0.4, 0.78, 1.0],
                  ),
                ),
              ),
            if (hasText)
              Positioned(
                left: 16,
                right: 16,
                bottom: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (title.isNotEmpty)
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    if (ctaLabel.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          ctaLabel,
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _onAdTap(BuildContext context, Map<String, dynamic> data) {
    final image =
        (data['imageUrl'] as String?) ?? (data['imageURL'] as String?);
    dispatchHomeAction(
      context,
      data['action'] as Map<String, dynamic>?,
      onProductTarget: widget.onProductTarget,
      onCombo: widget.onCombo,
      onApoyo: widget.onApoyo,
      imageUrl: (image != null && image.isNotEmpty) ? image : null,
    );
  }
}
