import 'package:flutter/material.dart';

// ─── Button vocabulary ────────────────────────────────────────────────────────

enum ArcadeButton { up, down, left, right, a, b, start, select }

// ─── Controller ───────────────────────────────────────────────────────────────

/// Shared ChangeNotifier that bridges the arcade shell's physical buttons
/// to any embedded game widget. Games call [addListener] in initState and
/// [removeListener] in dispose; the shell calls [press] on every tap.
class ArcadeInputController extends ChangeNotifier {
  ArcadeButton? _lastEvent;
  ArcadeButton? get lastEvent => _lastEvent;

  void press(ArcadeButton button) {
    _lastEvent = button;
    notifyListeners();
  }
}
