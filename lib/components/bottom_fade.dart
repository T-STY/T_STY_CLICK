import 'package:flutter/material.dart';

class BottomFade extends StatelessWidget {
  final Widget child;
  final double clearHeight;
  final double fadeHeight;

  const BottomFade({
    super.key,
    required this.child,
    this.clearHeight = 100,
    this.fadeHeight = 90,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        if (!h.isFinite || h <= (clearHeight + fadeHeight)) return child;
        final double s1 = ((h - clearHeight - fadeHeight) / h).clamp(0.0, 1.0);
        final double s2 = ((h - clearHeight) / h).clamp(0.0, 1.0);
        return ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: const [
              Colors.white,
              Colors.white,
              Colors.transparent,
              Colors.transparent,
            ],
            stops: [0.0, s1, s2, 1.0],
          ).createShader(rect),
          child: child,
        );
      },
    );
  }
}
