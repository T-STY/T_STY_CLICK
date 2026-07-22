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
    // Soft keyboard up → the viewport shrinks (resizeToAvoidBottomInset),
    // which would slide the fade band UP into the content the user is
    // actually looking at (typically the focused TextField). Skip the
    // shader entirely while the keyboard is open — the bottom nav it's
    // designed to fade content behind is hidden anyway.
    //
    // Two-step read:
    //   1. Touch MediaQuery.of(context) so this widget SUBSCRIBES to
    //      keyboard-insets changes and rebuilds when the platform reports
    //      the keyboard appearing/disappearing. View.of(context) alone
    //      does NOT trigger rebuilds — without this subscription the
    //      BottomFade never re-evaluates after the keyboard opens.
    //   2. Read the inset directly from FlutterView, because the Scaffold
    //      above us (resizeToAvoidBottomInset: true) consumes the bottom
    //      inset in its body's MediaQuery — so MediaQuery.viewInsetsOf
    //      would always report 0 here. View.viewInsets is the raw,
    //      unconsumed platform value (in physical px → divide by ratio).
    MediaQuery.of(context);
    final view = View.of(context);
    final keyboardInset = view.viewInsets.bottom / view.devicePixelRatio;
    // SHAPE-STABLE tree: this build must ALWAYS return the same widget
    // structure (LayoutBuilder → ShaderMask → child). An earlier version
    // returned the bare child while the keyboard was open — that runtimeType
    // change at this slot made Flutter DISPOSE the whole subtree, which
    // killed the focused TextField the instant the keyboard started to
    // appear (tap a field → keyboard opens → subtree replaced → field
    // unfocused → keyboard closes). Instead, when the fade should be off we
    // keep the ShaderMask and render an identity (all-opaque) mask.
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
