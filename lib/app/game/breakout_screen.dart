import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'arcade_input_controller.dart';
import 'high_score_service.dart';

// ─── Constants ────────────────────────────────────────────────────────────────

const _kBW = 120.0, _kBH = 80.0;

// Brick grid
const _kCols = 10, _kRows = 6;
const _kBrickW = 11.0, _kBrickH = 5.0, _kBrickGapH = 1.0;
const _kBrickLeft = 5.0, _kBrickTop = 4.0;

// Paddle
const _kPaddleH = 3.0, _kPaddleY = 73.0;
const _kPaddleSpdBase = 78.0;
double _kPaddleW(int level) => (24.0 - level * 1.6).clamp(11.0, 24.0);

// Ball
const _kBallR = 1.4;
double _kBallSpd(int level) => (72.0 + level * 8.0).clamp(72.0, 135.0);

// Brick HP by row (top = hardest)
const _kBrickHp = [3, 2, 1, 1, 1, 1];

// Neon brick colours by row — vivid, saturated
const _kBrickColors = <Color>[
  Color(0xFFFF1155), // row 0 – hot pink/red    (3 hits)
  Color(0xFFFF6600), // row 1 – neon orange     (2 hits)
  Color(0xFFFFEE00), // row 2 – electric yellow
  Color(0xFF00FF66), // row 3 – neon green
  Color(0xFF00EEFF), // row 4 – cyan
  Color(0xFF8833FF), // row 5 – purple
];

// Darker shade for each row (gradient bottom)
const _kBrickColorsDark = <Color>[
  Color(0xFF880022),
  Color(0xFF883300),
  Color(0xFF887700),
  Color(0xFF007733),
  Color(0xFF006677),
  Color(0xFF440088),
];

enum _BKState { start, playing, levelClear, dead, gameOver }

// ─── Widget ───────────────────────────────────────────────────────────────────

class BreakoutScreen extends StatefulWidget {
  final String userId;
  final DocumentReference rewardsDocRef;
  final double currentSaldo;
  final ArcadeInputController controller;
  final void Function(double) onSaldoChanged;

  const BreakoutScreen({
    super.key,
    required this.userId,
    required this.rewardsDocRef,
    required this.currentSaldo,
    required this.controller,
    required this.onSaldoChanged,
  });

  @override
  State<BreakoutScreen> createState() => _BreakoutScreenState();
}

class _BreakoutScreenState extends State<BreakoutScreen> {
  // Paddle
  double _padX = (_kBW - 24) / 2; // left edge of paddle
  // Ball
  double _bx = _kBW / 2, _by = _kPaddleY - _kBallR - 1;
  double _bvx = 0, _bvy = 0;
  bool _launched = false;
  // Bricks: _bricks[row][col] = current HP (0 = gone)
  List<List<int>> _bricks = [];
  // Combo — counts consecutive brick hits without touching paddle
  int _combo = 0;
  // Ball trail — last few positions for motion blur effect
  final List<Offset> _trail = [];
  // Game state
  int _score = 0, _hiScore = 0, _lives = 3, _level = 0;
  bool _paused = false;
  late double _saldo;
  _BKState _state = _BKState.start;
  Timer? _gameTimer;
  DateTime? _lastTick;

  @override
  void initState() {
    super.initState();
    _saldo = widget.currentSaldo;
    widget.controller.addListener(_onInput);
    HighScoreService.load('breakout').then((v) {
      if (mounted) setState(() => _hiScore = v);
    });
    _resetBricks();
  }

  @override
  void dispose() {
    _gameTimer?.cancel();
    widget.controller.removeListener(_onInput);
    super.dispose();
  }

  void _resetBricks() {
    _bricks = List.generate(
        _kRows, (r) => List.generate(_kCols, (_) => _kBrickHp[r]));
  }

  void _resetBall() {
    final pw = _kPaddleW(_level);
    _bx = _padX + pw / 2;
    _by = _kPaddleY - _kBallR - 1;
    _bvx = 0;
    _bvy = 0;
    _launched = false;
    _combo = 0;
    _trail.clear();
  }

  void _onInput() {
    final event = widget.controller.lastEvent;
    if (event == null || !event.isDown) return;
    final btn = event.button;
    if (_state == _BKState.playing && btn == ArcadeButton.start) {
      setState(() => _paused = !_paused);
      return;
    }
    if (_paused) return;
    if (_state == _BKState.start || _state == _BKState.levelClear ||
        _state == _BKState.dead || _state == _BKState.gameOver) {
      if (btn == ArcadeButton.a || btn == ArcadeButton.start) {
        if (_state == _BKState.dead) {
          _resetBall();
          setState(() => _state = _BKState.playing);
          _startTimer();
        } else {
          _startLevel();
        }
      }
    } else if (_state == _BKState.playing && !_launched) {
      if (btn == ArcadeButton.a || btn == ArcadeButton.start) {
        _launchBall();
      }
    }
  }

  void _startLevel() {
    _resetBricks();
    _resetBall();
    _lives = 3;
    _state = _BKState.playing;
    _startTimer();
    setState(() {});
  }

  void _launchBall() {
    final spd = _kBallSpd(_level);
    final angle = (Random().nextDouble() - 0.5) * pi * 0.5; // ±45° from vertical
    _bvx = spd * sin(angle);
    _bvy = -spd * cos(angle); // always launch upward
    _launched = true;
  }

  void _startTimer() {
    _gameTimer?.cancel();
    _lastTick = null;
    _gameTimer = Timer.periodic(const Duration(milliseconds: 16), _tick);
  }

  void _tick(Timer t) {
    if (_paused) return;
    final now = DateTime.now();
    final dt = (_lastTick == null
        ? 0.016
        : now.difference(_lastTick!).inMicroseconds / 1e6)
        .clamp(0.001, 0.05) as double;
    _lastTick = now;
    if (_state != _BKState.playing) return;

    final c = widget.controller;
    final pw = _kPaddleW(_level);
    final spd = _kPaddleSpdBase * dt;

    // Paddle movement
    if (c.isHeld(ArcadeButton.left)) _padX = (_padX - spd).clamp(0, _kBW - pw);
    if (c.isHeld(ArcadeButton.right)) _padX = (_padX + spd).clamp(0, _kBW - pw);

    if (!_launched) {
      // Ball sticks to paddle before launch
      _bx = _padX + pw / 2;
      setState(() {});
      return;
    }

    // Sub-step physics to avoid tunnelling through thin bricks
    const steps = 3;
    final sdx = _bvx * dt / steps;
    final sdy = _bvy * dt / steps;

    for (int s = 0; s < steps; s++) {
      _bx += sdx;
      _by += sdy;

      // Side walls
      if (_bx - _kBallR <= 0) { _bx = _kBallR; _bvx = _bvx.abs(); }
      if (_bx + _kBallR >= _kBW) { _bx = _kBW - _kBallR; _bvx = -_bvx.abs(); }
      // Ceiling
      if (_by - _kBallR <= 0) { _by = _kBallR; _bvy = _bvy.abs(); }

      // Paddle collision (ball coming down)
      if (_bvy > 0 &&
          _by + _kBallR >= _kPaddleY &&
          _by + _kBallR <= _kPaddleY + _kPaddleH + 2 &&
          _bx >= _padX - _kBallR &&
          _bx <= _padX + pw + _kBallR) {
        _by = _kPaddleY - _kBallR;
        final relHit = (_bx - (_padX + pw / 2)) / (pw / 2); // -1 to 1
        final angle = relHit * pi * 0.38; // max ~70° from vertical
        final ballSpd = sqrt(_bvx * _bvx + _bvy * _bvy);
        _bvx = ballSpd * sin(angle);
        _bvy = -ballSpd * cos(angle).abs(); // always go up
        _combo = 0; // reset combo on paddle touch
        HapticFeedback.lightImpact();
      }

      // Ball lost below paddle
      if (_by - _kBallR > _kBH + 5) {
        _lives--;
        HapticFeedback.mediumImpact();
        if (_lives <= 0) {
          _gameTimer?.cancel();
          HighScoreService.submit('breakout', _score);
          setState(() => _state = _BKState.gameOver);
        } else {
          _gameTimer?.cancel();
          _resetBall();
          setState(() => _state = _BKState.dead);
        }
        return;
      }

      // Brick collision
      bool hitAny = false;
      for (int row = 0; row < _kRows && !hitAny; row++) {
        for (int col = 0; col < _kCols && !hitAny; col++) {
          if (_bricks[row][col] <= 0) continue;
          final bl = _kBrickLeft + col * _kBrickW;
          final bt = _kBrickTop + row * (_kBrickH + _kBrickGapH);
          final br = bl + _kBrickW, bb = bt + _kBrickH;

          if (_bx + _kBallR < bl || _bx - _kBallR > br ||
              _by + _kBallR < bt || _by - _kBallR > bb) continue;

          // Which face did we hit?
          final overlapL = _bx + _kBallR - bl;
          final overlapR = br - (_bx - _kBallR);
          final overlapT = _by + _kBallR - bt;
          final overlapB = bb - (_by - _kBallR);
          final minX = min(overlapL, overlapR);
          final minY = min(overlapT, overlapB);

          if (minX < minY) {
            _bvx = overlapL < overlapR ? -_bvx.abs() : _bvx.abs();
          } else {
            _bvy = overlapT < overlapB ? -_bvy.abs() : _bvy.abs();
          }

          _bricks[row][col]--;
          if (_bricks[row][col] <= 0) {
            // Brick destroyed — combo multiplier
            _combo++;
            final multiplier = _combo >= 5 ? 3 : _combo >= 3 ? 2 : 1;
            final pts = ((_kBrickHp[row] * 10) + _level * 5) * multiplier;
            _score += pts;
            HapticFeedback.selectionClick();
          }
          hitAny = true;
        }
      }
    }

    // Update ball trail
    _trail.add(Offset(_bx, _by));
    if (_trail.length > 8) _trail.removeAt(0);

    // Check level clear
    final remaining = _bricks.expand((r) => r).where((hp) => hp > 0).length;
    if (remaining == 0) {
      _gameTimer?.cancel();
      _level++;
      final newSaldo = _saldo + 1;
      _saldo = newSaldo;
      widget.onSaldoChanged(newSaldo);
      _updateFirestore(newSaldo);
      HighScoreService.submit('breakout', _score);
      setState(() => _state = _BKState.levelClear);
      return;
    }

    setState(() {});
  }

  Future<void> _updateFirestore(double newSaldo) async {
    try {
      final ref = FirebaseFirestore.instance
          .collection('users').doc(widget.userId)
          .collection('rewardsCard').doc('cardInfo');
      final batch = FirebaseFirestore.instance.batch();
      batch.update(ref, {'saldo': newSaldo});
      batch.update(widget.rewardsDocRef, {'saldo': newSaldo});
      await batch.commit();
    } catch (e) { debugPrint('Breakout Firestore: $e'); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        SizedBox.expand(
          child: CustomPaint(
            painter: _BreakoutPainter(
              padX: _padX,
              bx: _bx, by: _by,
              bricks: _bricks,
              score: _score, hiScore: _hiScore,
              lives: _lives, level: _level,
              combo: _combo,
              trail: List.unmodifiable(_trail),
            ),
          ),
        ),
        if (_state == _BKState.start)
          _buildOverlay(
            title: 'NEON BREAK',
            subtitle: 'Izq/Der para mover',
            actionLabel: 'PULSA A PARA LANZAR',
            accentColor: const Color(0xFF00EEFF),
            titleColor: const Color(0xFF00EEFF),
          ),
        if (_state == _BKState.levelClear)
          _buildOverlay(
            title: '¡NIVEL ${_level}!',
            subtitle: 'Siguiente nivel desbloqueado',
            actionLabel: 'SIGUIENTE NIVEL',
            accentColor: const Color(0xFF00FF66),
            titleColor: const Color(0xFFFFEE00),
          ),
        if (_state == _BKState.dead)
          _buildOverlay(
            title: '${_lives} ${_lives == 1 ? "VIDA" : "VIDAS"}',
            subtitle: 'Sigue intentándolo',
            actionLabel: 'CONTINUAR',
            accentColor: const Color(0xFFFF6600),
            titleColor: const Color(0xFFFF6600),
          ),
        if (_state == _BKState.gameOver)
          _buildOverlay(
            title: 'GAME OVER',
            subtitle: 'Puntuación: $_score',
            actionLabel: 'NUEVA PARTIDA',
            accentColor: const Color(0xFFFF1155),
            titleColor: const Color(0xFFFF1155),
          ),
        if (_paused && _state == _BKState.playing)
          _buildOverlay(
            title: 'PAUSA',
            subtitle: 'El juego está pausado',
            actionLabel: 'START PARA CONTINUAR',
            accentColor: Colors.white54,
            titleColor: Colors.white,
          ),
      ]),
    );
  }

  Widget _buildOverlay({
    required String title,
    required String subtitle,
    required String actionLabel,
    required Color accentColor,
    required Color titleColor,
  }) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF0A0015).withOpacity(0.97),
              const Color(0xFF000008).withOpacity(0.97),
            ],
          ),
          border: Border.all(color: accentColor.withOpacity(0.8), width: 1.5),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: accentColor.withOpacity(0.35),
              blurRadius: 24,
              spreadRadius: 2,
            ),
            BoxShadow(
              color: accentColor.withOpacity(0.12),
              blurRadius: 48,
              spreadRadius: 8,
            ),
          ],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Decorative top line
          Container(
            width: 48,
            height: 2,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                Colors.transparent,
                accentColor,
                Colors.transparent,
              ]),
            ),
          ),
          const SizedBox(height: 12),
          // Title with glow
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: titleColor,
              fontSize: 26,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              letterSpacing: 3,
              shadows: [
                Shadow(color: titleColor.withOpacity(0.9), blurRadius: 12),
                Shadow(color: titleColor.withOpacity(0.5), blurRadius: 24),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Subtitle
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 12,
              fontFamily: 'monospace',
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 16),
          // Action button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accentColor.withOpacity(0.25),
                  accentColor.withOpacity(0.10),
                ],
              ),
              border: Border.all(color: accentColor.withOpacity(0.7), width: 1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              actionLabel,
              style: TextStyle(
                color: accentColor,
                fontSize: 11,
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
                shadows: [
                  Shadow(color: accentColor.withOpacity(0.8), blurRadius: 8),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Decorative bottom line
          Container(
            width: 48,
            height: 2,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                Colors.transparent,
                accentColor,
                Colors.transparent,
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

// ─── Painter ──────────────────────────────────────────────────────────────────

class _BreakoutPainter extends CustomPainter {
  final double padX, bx, by;
  final List<List<int>> bricks;
  final int score, hiScore, lives, level, combo;
  final List<Offset> trail;

  const _BreakoutPainter({
    required this.padX, required this.bx, required this.by,
    required this.bricks,
    required this.score, required this.hiScore,
    required this.lives, required this.level,
    required this.combo,
    required this.trail,
  });

  @override bool shouldRepaint(_BreakoutPainter o) => true;

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / _kBW;
    final scaleY = size.height / _kBH;
    final p = Paint()..isAntiAlias = true;

    // ── Background ────────────────────────────────────────────────────────────
    _drawBackground(canvas, size, p);

    // ── Bricks ────────────────────────────────────────────────────────────────
    _drawBricks(canvas, size, scaleX, scaleY, p);

    // ── Paddle ────────────────────────────────────────────────────────────────
    _drawPaddle(canvas, size, scaleX, scaleY, p);

    // ── Ball trail ────────────────────────────────────────────────────────────
    _drawTrail(canvas, scaleX, scaleY, p);

    // ── Ball ──────────────────────────────────────────────────────────────────
    _drawBall(canvas, scaleX, scaleY, p);

    // ── HUD ───────────────────────────────────────────────────────────────────
    _drawHud(canvas, size);
  }

  void _drawBackground(Canvas canvas, Size size, Paint p) {
    // Deep dark base
    final bgRect = Rect.fromLTWH(0, 0, size.width, size.height);
    p.color = const Color(0xFF04000C);
    canvas.drawRect(bgRect, p);

    // Subtle grid lines (low opacity)
    p
      ..color = const Color(0xFF00EEFF).withOpacity(0.035)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;
    const gridSpacing = 18.0;
    for (double x = 0; x < size.width; x += gridSpacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += gridSpacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
    p.style = PaintingStyle.fill;

    // Faint diagonal accent lines for depth
    p
      ..color = const Color(0xFF8833FF).withOpacity(0.018)
      ..strokeWidth = 0.4
      ..style = PaintingStyle.stroke;
    for (double d = -size.height; d < size.width + size.height; d += 36.0) {
      canvas.drawLine(Offset(d, 0), Offset(d + size.height, size.height), p);
    }
    p.style = PaintingStyle.fill;

    // Edge vignette (radial dark overlay)
    final vignetteShader = RadialGradient(
      center: Alignment.center,
      radius: 0.8,
      colors: [
        Colors.transparent,
        Colors.black.withOpacity(0.55),
      ],
    ).createShader(bgRect);
    p.shader = vignetteShader;
    canvas.drawRect(bgRect, p);
    p.shader = null;
  }

  void _drawBricks(Canvas canvas, Size size, double scaleX, double scaleY, Paint p) {
    for (int row = 0; row < _kRows; row++) {
      for (int col = 0; col < _kCols; col++) {
        final hp = bricks.length > row && bricks[row].length > col
            ? bricks[row][col]
            : 0;
        if (hp <= 0) continue;

        final bl = (_kBrickLeft + col * _kBrickW) * scaleX;
        final bt = (_kBrickTop + row * (_kBrickH + _kBrickGapH)) * scaleY;
        final bw = _kBrickW * scaleX - 1.5;
        final bh = _kBrickH * scaleY - 1.5;
        const rr = Radius.circular(3.5);
        final brickRect = RRect.fromLTRBR(bl, bt, bl + bw, bt + bh, rr);

        final baseColor = _kBrickColors[row];
        final darkColor = _kBrickColorsDark[row];
        final maxHp = _kBrickHp[row];
        final hpFrac = maxHp > 1 ? hp / maxHp : 1.0;

        // Fade colour toward dark when damaged
        final topColor = Color.lerp(darkColor.withOpacity(0.55), baseColor, hpFrac)!;
        final botColor = Color.lerp(darkColor.withOpacity(0.3), darkColor, hpFrac)!;

        // Outer neon glow (blurred, wide)
        p
          ..color = baseColor.withOpacity(0.18 * hpFrac)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
        canvas.drawRRect(
            RRect.fromLTRBR(bl - 3, bt - 3, bl + bw + 3, bt + bh + 3, rr), p);

        // Inner tighter glow
        p
          ..color = baseColor.withOpacity(0.30 * hpFrac)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
        canvas.drawRRect(
            RRect.fromLTRBR(bl - 1, bt - 1, bl + bw + 1, bt + bh + 1, rr), p);
        p.maskFilter = null;

        // Gradient fill (lighter top → darker bottom)
        final gradShader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [topColor, botColor],
        ).createShader(Rect.fromLTWH(bl, bt, bw, bh));
        p.shader = gradShader;
        canvas.drawRRect(brickRect, p);
        p.shader = null;

        // Bright neon border stroke
        p
          ..color = baseColor.withOpacity(0.85 * hpFrac)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8;
        canvas.drawRRect(brickRect, p);
        p.style = PaintingStyle.fill;

        // Top-left highlight streak
        final hlRect = RRect.fromLTRBR(
            bl + 2, bt + 1.5, bl + bw * 0.55, bt + bh * 0.32,
            const Radius.circular(2));
        final hlShader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.white.withOpacity(0.45 * hpFrac),
            Colors.white.withOpacity(0.0),
          ],
        ).createShader(Rect.fromLTWH(bl + 2, bt + 1.5, bw * 0.55, bh * 0.32));
        p.shader = hlShader;
        canvas.drawRRect(hlRect, p);
        p.shader = null;

        // HP crack marks for multi-hit bricks (show damage)
        if (maxHp > 1 && hp < maxHp) {
          final damageFrac = 1.0 - hpFrac;
          p
            ..color = Colors.black.withOpacity(0.6 * damageFrac)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.7;
          // Draw a diagonal crack line scaled to damage
          final crackX1 = bl + bw * 0.3;
          final crackY1 = bt + bh * 0.2;
          final crackX2 = bl + bw * (0.3 + 0.4 * damageFrac);
          final crackY2 = bt + bh * (0.2 + 0.6 * damageFrac);
          final crackPath = Path()
            ..moveTo(crackX1, crackY1)
            ..lineTo(crackX2, crackY2)
            ..moveTo(crackX1 + bw * 0.1, crackY1 + bh * 0.1)
            ..lineTo(crackX2 - bw * 0.1, crackY2);
          canvas.drawPath(crackPath, p);
          p.style = PaintingStyle.fill;
        }
      }
    }
  }

  void _drawPaddle(Canvas canvas, Size size, double scaleX, double scaleY, Paint p) {
    final pw = _kPaddleW(level) * scaleX;
    final padLeft = padX * scaleX;
    final padTop = _kPaddleY * scaleY;
    final padH = _kPaddleH * scaleY;
    const paddleRadius = Radius.circular(4.0);
    final paddleRRect = RRect.fromLTRBR(
        padLeft, padTop, padLeft + pw, padTop + padH, paddleRadius);

    // Wide outer glow
    p
      ..color = const Color(0xFF00EEFF).withOpacity(0.20)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawRRect(
        RRect.fromLTRBR(padLeft - 4, padTop - 3, padLeft + pw + 4,
            padTop + padH + 3, paddleRadius),
        p);

    // Tighter inner glow
    p
      ..color = const Color(0xFF00EEFF).withOpacity(0.40)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawRRect(
        RRect.fromLTRBR(padLeft - 1, padTop - 1, padLeft + pw + 1,
            padTop + padH + 1, paddleRadius),
        p);
    p.maskFilter = null;

    // Metallic body gradient (silver-blue top → darker blue bottom)
    final bodyShader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: const [
        Color(0xFFB0E8FF), // light silver-blue top
        Color(0xFF1AACDD), // mid cyan
        Color(0xFF006688), // dark teal bottom
      ],
      stops: const [0.0, 0.45, 1.0],
    ).createShader(Rect.fromLTWH(padLeft, padTop, pw, padH));
    p.shader = bodyShader;
    canvas.drawRRect(paddleRRect, p);
    p.shader = null;

    // Neon cyan border
    p
      ..color = const Color(0xFF00EEFF).withOpacity(0.90)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;
    canvas.drawRRect(paddleRRect, p);
    p.style = PaintingStyle.fill;

    // Top highlight shine
    final shinePath = RRect.fromLTRBR(
        padLeft + 3, padTop + 0.5, padLeft + pw - 3, padTop + padH * 0.42,
        const Radius.circular(2));
    final shineShader = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        Colors.white.withOpacity(0.0),
        Colors.white.withOpacity(0.55),
        Colors.white.withOpacity(0.0),
      ],
    ).createShader(Rect.fromLTWH(padLeft + 3, padTop, pw - 6, padH * 0.42));
    p.shader = shineShader;
    canvas.drawRRect(shinePath, p);
    p.shader = null;
  }

  void _drawTrail(Canvas canvas, double scaleX, double scaleY, Paint p) {
    final br = _kBallR * min(scaleX, scaleY) * 1.6;
    for (int i = 0; i < trail.length; i++) {
      final t = (i + 1) / trail.length;
      final alpha = t * 0.35;
      final radius = br * (0.3 + t * 0.6);
      final cx = trail[i].dx * scaleX;
      final cy = trail[i].dy * scaleY;

      // Each ghost ball: cyan with radial fade
      final trailShader = RadialGradient(
        colors: [
          const Color(0xFF00EEFF).withOpacity(alpha),
          const Color(0xFF0088AA).withOpacity(alpha * 0.3),
          Colors.transparent,
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: radius));
      p.shader = trailShader;
      canvas.drawCircle(Offset(cx, cy), radius, p);
      p.shader = null;
    }
  }

  void _drawBall(Canvas canvas, double scaleX, double scaleY, Paint p) {
    final br = _kBallR * min(scaleX, scaleY) * 1.6;
    final bscr = Offset(bx * scaleX, by * scaleY);

    // Large outer glow (wide, very soft)
    p
      ..color = const Color(0xFF00EEFF).withOpacity(0.15)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(bscr, br * 2.8, p);

    // Medium glow ring
    p
      ..color = const Color(0xFF00EEFF).withOpacity(0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(bscr, br * 1.7, p);
    p.maskFilter = null;

    // Radial gradient core: white centre → cyan → transparent
    final ballShader = RadialGradient(
      colors: const [
        Colors.white,
        Color(0xFF88FFFF),
        Color(0xFF00CCEE),
        Colors.transparent,
      ],
      stops: const [0.0, 0.35, 0.65, 1.0],
    ).createShader(Rect.fromCircle(center: bscr, radius: br * 1.2));
    p.shader = ballShader;
    canvas.drawCircle(bscr, br * 1.2, p);
    p.shader = null;

    // Tiny specular highlight
    p.color = Colors.white.withOpacity(0.9);
    canvas.drawCircle(
        Offset(bscr.dx - br * 0.25, bscr.dy - br * 0.25), br * 0.22, p);
  }

  void _drawHud(Canvas canvas, Size size) {
    final hfs = size.height / 28;
    final tp = TextPainter(textDirection: TextDirection.ltr);

    void glowText(String s, double x, double y, Color col, double fs,
        {double glowRadius = 6.0}) {
      // Glow pass
      tp.text = TextSpan(
          text: s,
          style: TextStyle(
              color: col.withOpacity(0.7),
              fontSize: fs,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
              shadows: [
                Shadow(color: col.withOpacity(0.8), blurRadius: glowRadius),
                Shadow(color: col.withOpacity(0.4), blurRadius: glowRadius * 2),
              ]));
      tp.layout();
      tp.paint(canvas, Offset(x, y));
    }

    // Score — cyan glow
    glowText(
      '$score',
      size.width * 0.04,
      size.height * 0.012,
      const Color(0xFF00EEFF),
      hfs,
      glowRadius: 8,
    );

    // Level — yellow
    glowText(
      'NIV ${level + 1}',
      size.width * 0.42,
      size.height * 0.012,
      const Color(0xFFFFEE00),
      hfs * 0.85,
      glowRadius: 6,
    );

    // Hi-score — dim purple
    glowText(
      'REC $hiScore',
      size.width * 0.66,
      size.height * 0.012,
      const Color(0xFFAA66FF),
      hfs * 0.85,
      glowRadius: 5,
    );

    // Combo indicator — shown when combo >= 2
    if (combo >= 2) {
      final comboColor = combo >= 5
          ? const Color(0xFFFFEE00)
          : const Color(0xFFFF6600);
      final comboFs = hfs * (combo >= 5 ? 1.1 : 0.95);
      glowText(
        'x$combo COMBO!',
        size.width * 0.34,
        size.height * 0.89,
        comboColor,
        comboFs,
        glowRadius: combo >= 5 ? 10 : 7,
      );
    }

    // Lives as glowing orb icons
    final orbR = hfs * 0.45;
    final orbY = size.height - orbR * 2.5;
    final orbCount = lives.clamp(0, 5);
    for (int i = 0; i < orbCount; i++) {
      final cx = size.width * 0.04 + i * (orbR * 2.6);
      final center = Offset(cx, orbY);

      // Orb outer glow
      final orbP = Paint()
        ..color = const Color(0xFFFF1155).withOpacity(0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawCircle(center, orbR * 1.6, orbP);
      orbP.maskFilter = null;

      // Orb fill gradient
      final orbShader = RadialGradient(
        colors: const [
          Color(0xFFFF88AA),
          Color(0xFFFF1155),
          Color(0xFF880022),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: orbR));
      orbP.shader = orbShader;
      canvas.drawCircle(center, orbR, orbP);
      orbP.shader = null;

      // Orb specular
      orbP.color = Colors.white.withOpacity(0.6);
      canvas.drawCircle(
          Offset(cx - orbR * 0.28, orbY - orbR * 0.28), orbR * 0.22, orbP);
    }
  }
}
