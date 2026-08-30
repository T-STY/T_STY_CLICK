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

    MediaQuery.of(context);
    final view = View.of(context);
    final keyboardInset = view.viewInsets.bottom / view.devicePixelRatio;

    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        final bool active = keyboardInset <= 0 &&
            h.isFinite &&
            h > (clearHeight + fadeHeight);
        final double s1 = active
            ? ((h - clearHeight - fadeHeight) / h).clamp(0.0, 1.0)
            : 1.0;
        final double s2 =
            active ? ((h - clearHeight) / h).clamp(0.0, 1.0) : 1.0;
        return ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: active
                ? const [
                    Colors.white,
                    Colors.white,
                    Colors.transparent,
                    Colors.transparent,
                  ]
                : const [
                    Colors.white,
                    Colors.white,
                    Colors.white,
                    Colors.white,
                  ],
            stops: [0.0, s1, s2, 1.0],
          ).createShader(rect),
          child: child,
        );
      },
    );
  }
}
