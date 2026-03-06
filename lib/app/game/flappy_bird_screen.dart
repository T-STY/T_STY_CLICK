import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'arcade_input_controller.dart';

// ─── Data ─────────────────────────────────────────────────────────────────────

class _Pipe {
  double x;
  double gapY; // centre of the gap
  bool scored; // has this pipe already been counted
  _Pipe(this.x, this.gapY) : scored = false;
}

class _Cloud {
  double x, y, speed, w;
  _Cloud(Random rng)
      : x = rng.nextDouble() * 10,
        y = 1 + rng.nextDouble() * 5,
        speed = 0.4 + rng.nextDouble() * 0.5,
        w = 1.2 + rng.nextDouble() * 1.2;
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class FlappyBirdScreen extends StatefulWidget {
  final String userId;
  final DocumentReference rewardsDocRef;
  final double currentSaldo;
  final ArcadeInputController controller;
  final void Function(double) onSaldoChanged;

  const FlappyBirdScreen({
    super.key,
    required this.userId,
    required this.rewardsDocRef,
    required this.currentSaldo,
    required this.controller,
    required this.onSaldoChanged,
  });

  @override
  State<FlappyBirdScreen> createState() => _FlappyBirdScreenState();
}

class _FlappyBirdScreenState extends State<FlappyBirdScreen> {
  // World: 10 wide × 16 tall
  static const double kW = 10;
  static const double kH = 16;

  // Bird
  static const double kBirdX = 2.2;
  static const double kBirdR = 0.38; // collision radius
  static const double kGravity = 18.0;
  static const double kFlapVelocity = -6.5;

  // Pipes
  static const double kPipeW = 1.3;
  static const double kPipeSpacing = 4.2; // world units between pipes
  static const double kGapHStart = 3.8; // gap height at wave 1
  // Min gap must be >= 1.5 × bird diameter (kBirdR*2=0.76 → 1.5×=1.14).
  // We keep 2.2 for comfortable playability while satisfying the constraint.
  static const double kGapHMin = 2.2; // minimum gap height (≈ 2.9× bird diameter)
  static const double kSpeedStart = 3.2;
  static const double kSpeedMax = 7.0;

  // Ground
  static const double kGroundY = 14.8;

  final _rng = Random();

  // Bird state
  double _birdY = kH / 2;
  double _birdVy = 0;

  // Pipes & world
  List<_Pipe> _pipes = [];
  List<_Cloud> _clouds = [];
  double _pipeSpeed = kSpeedStart;
  double _nextPipeX = 0;

  // Score & saldo
  int _pipesPassed = 0; // raw count
  int _displayScore = 0; // pipesPassed ~/ 10 (shown as "pts in game")
  late double _saldo;
  bool _awardingPoints = false;

  // State
  bool _isRunning = false;
  bool _isDead = false;

  // Wing flap animation
  double _flapAngle = 0;

  Timer? _ticker;
  DateTime? _lastTick;

  @override
  void initState() {
    super.initState();
    _saldo = widget.currentSaldo;
    _clouds = List.generate(5, (_) => _Cloud(_rng));
    _resetGame();
    widget.controller.addListener(_onControllerEvent);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    widget.controller.removeListener(_onControllerEvent);
    super.dispose();
  }

  void _onControllerEvent() {
    final event = widget.controller.lastEvent;
    if (event == null || !event.isDown) return;
    final btn = event.button;

    if (_isDead) {
      if (btn == ArcadeButton.a ||
          btn == ArcadeButton.b ||
          btn == ArcadeButton.start ||
          btn == ArcadeButton.up) {
        _resetGame();
        _startGame();
      }
      return;
    }

    // Any action button or up = flap
    if (btn == ArcadeButton.a ||
        btn == ArcadeButton.b ||
        btn == ArcadeButton.x ||
        btn == ArcadeButton.y ||
        btn == ArcadeButton.up ||
        btn == ArcadeButton.start) {
      _flap();
      if (!_isRunning) _startGame();
    }
  }

  void _flap() {
    _birdVy = kFlapVelocity;
    _flapAngle = -0.4; // visual upward tilt
    HapticFeedback.selectionClick();
  }

  void _startGame() {
    if (_isRunning) return;
    setState(() => _isRunning = true);
    _lastTick = DateTime.now();
    _ticker = Timer.periodic(const Duration(milliseconds: 16), _tick);
  }

  void _tick(Timer t) {
    if (!mounted) return;
    final now = DateTime.now();
    final dt =
        (now.difference(_lastTick!).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _lastTick = now;
    if (_isDead) return;
    _update(dt);
    if (mounted) setState(() {});
  }

  void _update(double dt) {
    // ── Bird physics ────────────────────────────────────────────────────────
    _birdVy += kGravity * dt;
    _birdY += _birdVy * dt;

    // Wing tilt: nose up when moving up, nose down when falling
    _flapAngle = (_birdVy * 0.05).clamp(-0.5, 0.8);

    // ── Ground / ceiling collision ──────────────────────────────────────────
    if (_birdY + kBirdR >= kGroundY || _birdY - kBirdR <= 0) {
      _triggerDeath();
      return;
    }

    // ── Pipe speed scales gently with score ────────────────────────────────
    _pipeSpeed = (kSpeedStart + _pipesPassed * 0.015).clamp(kSpeedStart, kSpeedMax);

    // ── Clouds ─────────────────────────────────────────────────────────────
    for (final c in _clouds) {
      c.x -= c.speed * dt;
      if (c.x + c.w < 0) {
        c.x = kW + c.w;
        c.y = 1 + _rng.nextDouble() * 5;
      }
    }

    // ── Move pipes ─────────────────────────────────────────────────────────
    for (final p in _pipes) {
      p.x -= _pipeSpeed * dt;
    }
    _pipes.removeWhere((p) => p.x + kPipeW < 0);

    // ── Spawn new pipe ──────────────────────────────────────────────────────
    _nextPipeX -= _pipeSpeed * dt;
    if (_nextPipeX <= 0) {
      _nextPipeX = kPipeSpacing;
      // Ensure gap never drops below 1.5× bird diameter regardless of score
      const minSafeGap = kBirdR * 2 * 1.5; // = 1.14 world units
      final gapH = (kGapHStart - _pipesPassed * 0.008)
          .clamp(kGapHMin.clamp(minSafeGap, kGapHStart), kGapHStart);
      final gapCentre = (gapH / 2 + 1.5) +
          _rng.nextDouble() * (kGroundY - gapH - 2.5 - (gapH / 2 + 1.5));
      _pipes.add(_Pipe(kW + 0.5, gapCentre));
    }

    // ── Score: count pipes passed ──────────────────────────────────────────
    for (final p in _pipes) {
      if (!p.scored && p.x + kPipeW < kBirdX) {
        p.scored = true;
        _pipesPassed++;
        _displayScore = _pipesPassed ~/ 10;

        // Award 1 saldo every 10 pipes
        if (_pipesPassed % 10 == 0) {
          _awardSaldo();
        }
      }
    }

    // ── Pipe collision ─────────────────────────────────────────────────────
    for (final p in _pipes) {
      final pLeft = p.x;
      final pRight = p.x + kPipeW;
      final gapTop = p.gapY - _currentGapH / 2;
      final gapBot = p.gapY + _currentGapH / 2;

      if (kBirdX + kBirdR > pLeft && kBirdX - kBirdR < pRight) {
        // Bird is horizontally inside this pipe column
        if (_birdY - kBirdR < gapTop || _birdY + kBirdR > gapBot) {
          _triggerDeath();
          return;
        }
      }
    }
  }

  double get _currentGapH =>
      (kGapHStart - _pipesPassed * 0.008).clamp(kGapHMin, kGapHStart);

  void _triggerDeath() {
    _ticker?.cancel();
    HapticFeedback.heavyImpact();
    if (mounted) setState(() { _isDead = true; _isRunning = false; });
  }

  void _resetGame() {
    _birdY = kH / 2 - 1;
    _birdVy = 0;
    _flapAngle = 0;
    _pipes = [];
    _pipesPassed = 0;
    _displayScore = 0;
    _pipeSpeed = kSpeedStart;
    _nextPipeX = kPipeSpacing * 0.6; // first pipe appears sooner
    _isDead = false;
    _isRunning = false;
  }

  Future<void> _awardSaldo() async {
    if (_awardingPoints) return;
    _awardingPoints = true;
    final newSaldo = _saldo + 1.0;
    try {
      final userCardRef = FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .collection('rewardsCard')
          .doc('cardInfo');
      final batch = FirebaseFirestore.instance.batch();
      batch.update(userCardRef, {'saldo': newSaldo});
      batch.update(widget.rewardsDocRef, {'saldo': newSaldo});
      await batch.commit();
      if (mounted) {
        setState(() => _saldo = newSaldo);
        widget.onSaldoChanged(newSaldo);
      }
    } catch (e) {
      debugPrint('Flappy Firestore error: $e');
    }
    _awardingPoints = false;
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, cons) {
      return Stack(children: [
        CustomPaint(
          painter: _FlappyPainter(
            birdY: _birdY,
            flapAngle: _flapAngle,
            pipes: _pipes,
            clouds: _clouds,
            pipesPassed: _pipesPassed,
            currentGapH: _currentGapH,
          ),
          child: SizedBox(width: cons.maxWidth, height: cons.maxHeight),
        ),
        // HUD
        Positioned(
          top: 4, left: 4, right: 4,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _chip('🪈 $_pipesPassed'),
              _chip('⭐ $_displayScore pts'),
              _chip('💰 ${_saldo.toStringAsFixed(0)}'),
            ],
          ),
        ),
        if (!_isRunning && !_isDead) _buildStartOverlay(),
        if (_isDead) _buildDeathOverlay(),
      ]);
    });
  }

  Widget _chip(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
            color: Colors.black38, borderRadius: BorderRadius.circular(8)),
        child: Text(t,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold)),
      );

  Widget _buildStartOverlay() => Positioned.fill(
        child: Container(
          color: Colors.black.withOpacity(0.55),
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('🐦', style: TextStyle(fontSize: 56)),
                const SizedBox(height: 10),
                const Text('PÁJARO VELOZ',
                    style: TextStyle(
                        color: Colors.yellow,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 3)),
                const SizedBox(height: 18),
                const Text('Pulsa A, B o ↑ para volar',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 4),
                const Text('Pasa entre los tubos sin chocar',
                    style: TextStyle(color: Colors.white54, fontSize: 11)),
                const SizedBox(height: 6),
                const Text('+1 pto real cada 10 tubos',
                    style: TextStyle(color: Colors.white38, fontSize: 10)),
                const SizedBox(height: 2),
                const Text('SELECT para volver al menú',
                    style: TextStyle(color: Colors.white38, fontSize: 10)),
              ]),
        ),
      );

  Widget _buildDeathOverlay() => Positioned.fill(
        child: Container(
          color: Colors.black.withOpacity(0.80),
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('💥', style: TextStyle(fontSize: 52)),
                const Text('¡CHOCASTE!',
                    style: TextStyle(
                        color: Colors.orangeAccent,
                        fontSize: 24,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Text('Tubos pasados: $_pipesPassed',
                    style: const TextStyle(color: Colors.white, fontSize: 15)),
                Text('Puntos reales: $_displayScore',
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    _resetGame();
                    _startGame();
                  },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade700,
                      foregroundColor: Colors.white,
                      shape: const StadiumBorder()),
                  child: const Text('Intentar de nuevo'),
                ),
                const SizedBox(height: 8),
                const Text('SELECT para volver al menú',
                    style: TextStyle(color: Colors.white38, fontSize: 10)),
              ]),
        ),
      );
}

// ─── Painter ─────────────────────────────────────────────────────────────────

class _FlappyPainter extends CustomPainter {
  final double birdY;
  final double flapAngle;
  final List<_Pipe> pipes;
  final List<_Cloud> clouds;
  final int pipesPassed;
  final double currentGapH;

  static const double kW = 10;
  static const double kH = 16;
  static const double kBirdX = 2.2;
  static const double kBirdR = 0.38;
  static const double kPipeW = 1.3;
  static const double kGroundY = 14.8;

  const _FlappyPainter({
    required this.birdY,
    required this.flapAngle,
    required this.pipes,
    required this.clouds,
    required this.pipesPassed,
    required this.currentGapH,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cs = size.width / kW;

    double wx(double x) => x * cs;
    double wy(double y) => y * cs;

    // ── Sky gradient ──────────────────────────────────────────────────────────
    final skyPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF4FC3F7), Color(0xFF81D4FA)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), skyPaint);

    // ── Clouds ───────────────────────────────────────────────────────────────
    final cloudPaint = Paint()..color = Colors.white.withOpacity(0.85);
    for (final c in clouds) {
      final cx = wx(c.x);
      final cy = wy(c.y);
      final cw = c.w * cs;
      canvas.drawOval(Rect.fromLTWH(cx, cy, cw, cw * 0.45), cloudPaint);
      canvas.drawOval(
          Rect.fromLTWH(cx + cw * 0.15, cy - cw * 0.15, cw * 0.5, cw * 0.45),
          cloudPaint);
      canvas.drawOval(
          Rect.fromLTWH(cx + cw * 0.5, cy - cw * 0.05, cw * 0.45, cw * 0.4),
          cloudPaint);
    }

    // ── Pipes ─────────────────────────────────────────────────────────────────
    final pipeBodyPaint = Paint()..color = const Color(0xFF388E3C);
    final pipeLightPaint = Paint()..color = const Color(0xFF66BB6A);
    final pipeDarkPaint = Paint()..color = const Color(0xFF1B5E20);
    final pipeCapPaint = Paint()..color = const Color(0xFF2E7D32);
    const capH = 0.25; // cap height in world units
    const capExtra = 0.12; // cap is wider than body by this amount each side

    for (final p in pipes) {
      final px = wx(p.x);
      final pw = kPipeW * cs;
      final gapTop = wy(p.gapY - currentGapH / 2);
      final gapBot = wy(p.gapY + currentGapH / 2);
      final capHpx = capH * cs;
      final capExPx = capExtra * cs;

      // Top pipe body
      canvas.drawRect(
          Rect.fromLTWH(px, 0, pw, gapTop), pipeBodyPaint);
      // Top pipe highlight
      canvas.drawRect(
          Rect.fromLTWH(px, 0, pw * 0.18, gapTop), pipeLightPaint);
      canvas.drawRect(
          Rect.fromLTWH(px + pw - pw * 0.12, 0, pw * 0.12, gapTop),
          pipeDarkPaint);
      // Top pipe cap
      canvas.drawRect(
          Rect.fromLTWH(px - capExPx, gapTop - capHpx, pw + capExPx * 2, capHpx),
          pipeCapPaint);

      // Bottom pipe body
      canvas.drawRect(
          Rect.fromLTWH(px, gapBot, pw, size.height - gapBot), pipeBodyPaint);
      // Bottom pipe highlight
      canvas.drawRect(
          Rect.fromLTWH(px, gapBot, pw * 0.18, size.height - gapBot),
          pipeLightPaint);
      canvas.drawRect(
          Rect.fromLTWH(
              px + pw - pw * 0.12, gapBot, pw * 0.12, size.height - gapBot),
          pipeDarkPaint);
      // Bottom pipe cap
      canvas.drawRect(
          Rect.fromLTWH(px - capExPx, gapBot, pw + capExPx * 2, capHpx),
          pipeCapPaint);
    }

    // ── Ground ────────────────────────────────────────────────────────────────
    canvas.drawRect(
      Rect.fromLTWH(0, wy(kGroundY), size.width, size.height - wy(kGroundY)),
      Paint()..color = const Color(0xFF8D6E63),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, wy(kGroundY), size.width, cs * 0.25),
      Paint()..color = const Color(0xFF558B2F),
    );

    // ── Bird ──────────────────────────────────────────────────────────────────
    final bx = wx(kBirdX);
    final by = wy(birdY);
    final br = kBirdR * cs;

    canvas.save();
    canvas.translate(bx, by);
    canvas.rotate(flapAngle);

    // Body
    canvas.drawCircle(Offset.zero, br, Paint()..color = const Color(0xFFFFD600));
    // Belly
    canvas.drawCircle(Offset(br * 0.15, br * 0.2), br * 0.6,
        Paint()..color = const Color(0xFFFFF9C4));
    // Eye
    canvas.drawCircle(Offset(br * 0.45, -br * 0.25), br * 0.22,
        Paint()..color = Colors.white);
    canvas.drawCircle(Offset(br * 0.52, -br * 0.22), br * 0.13,
        Paint()..color = Colors.black87);
    // Beak
    final beak = Path()
      ..moveTo(br * 0.7, br * 0.05)
      ..lineTo(br * 1.25, br * 0.0)
      ..lineTo(br * 0.75, br * 0.28)
      ..close();
    canvas.drawPath(beak, Paint()..color = const Color(0xFFFF6F00));
    // Wing (flaps based on angle)
    final wingY = -br * 0.1 + sin(DateTime.now().millisecondsSinceEpoch / 80) * br * 0.15;
    canvas.drawOval(
        Rect.fromLTWH(-br * 0.3, wingY, br * 0.8, br * 0.35),
        Paint()..color = const Color(0xFFF57F17));

    canvas.restore();
  }

  @override
  bool shouldRepaint(_FlappyPainter old) => true;
}
