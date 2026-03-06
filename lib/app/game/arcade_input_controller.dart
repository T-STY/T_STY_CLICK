import 'package:flutter/material.dart';

// ─── Button vocabulary ────────────────────────────────────────────────────────

enum ArcadeButton { up, down, left, right, a, b, x, y, start, select }

// ─── Event ────────────────────────────────────────────────────────────────────

class ArcadeControllerEvent {
  final ArcadeButton button;
  final bool isDown;
  const ArcadeControllerEvent(this.button, {required this.isDown});
}

// ─── Controller ───────────────────────────────────────────────────────────────

/// Shared ChangeNotifier bridging the arcade shell's physical buttons to any
/// embedded game widget.
///
/// Games use [lastEvent] for one-shot actions (jump, fire) and [isHeld] for
/// continuous movement (walk left/right, move ship).
class ArcadeInputController extends ChangeNotifier {
  ArcadeControllerEvent? _lastEvent;
  ArcadeControllerEvent? get lastEvent => _lastEvent;

  final Set<ArcadeButton> _held = {};
  bool isHeld(ArcadeButton btn) => _held.contains(btn);

  void press(ArcadeButton button) {
    _held.add(button);
    _lastEvent = ArcadeControllerEvent(button, isDown: true);
    notifyListeners();
  }

  void release(ArcadeButton button) {
    _held.remove(button);
    _lastEvent = ArcadeControllerEvent(button, isDown: false);
    notifyListeners();
  }
}
