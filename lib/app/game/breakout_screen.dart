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
// Brick colours by row
const _kBrickColors = <Color>[
  Color(0xFFFF2222), // row 0 – red    (3 hits)
  Color(0xFFFF8800), // row 1 – orange (2 hits)
  Color(0xFFFFDD00), // row 2 – yellow
  Color(0xFF44FF44), // row 3 – green
  Color(0xFF00DDFF), // row 4 – cyan
  Color(0xFF4466FF), // row 5 – blue
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
          _buildOverlay('MURO DE NEÓN',
              'Izq/Der para mover\nA para lanzar la pelota', null),
        if (_state == _BKState.levelClear)
          _buildOverlay('¡NIVEL ${_level}!',
              'Pulsa A para continuar', Colors.amber),
        if (_state == _BKState.dead)
          _buildOverlay('${_lives} VIDAS RESTANTES',
              'Pulsa A para continuar', Colors.orange),
        if (_state == _BKState.gameOver)
          _buildOverlay('GAME OVER',
              'Puntuación: $_score\nPulsa A para reintentar',
              Colors.redAccent),
        if (_paused && _state == _BKState.playing)
          _buildOverlay('⏸ PAUSA', 'Start para continuar', Colors.white54),
      ]),
    );
  }

  Widget _buildOverlay(String title, String sub, Color? accent) {
    final col = accent ?? const Color(0xFF00DDFF);
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.88),
          border: Border.all(color: col, width: 1.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(title,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: col,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace')),
          const SizedBox(height: 8),
          Text(sub,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 12, fontFamily: 'monospace')),
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
    final pw = size.width / _kBW, ph = size.height / _kBH;
    final p = Paint()..isAntiAlias = false;

    // Background
    p.color = const Color(0xFF04000C);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), p);

    // Bricks — rounded 3D look
    for (int row = 0; row < _kRows; row++) {
      for (int col = 0; col < _kCols; col++) {
        final hp = bricks.length > row && bricks[row].length > col
            ? bricks[row][col]
            : 0;
        if (hp <= 0) continue;
        final bl = (_kBrickLeft + col * _kBrickW) * pw;
        final bt = (_kBrickTop + row * (_kBrickH + _kBrickGapH)) * ph;
        final bw = _kBrickW * pw - 1.5;
        final bh = _kBrickH * ph - 1.5;
        final rr = const Radius.circular(3);
        final rect = RRect.fromLTRBR(bl, bt, bl + bw, bt + bh, rr);

        final baseColor = _kBrickColors[row];
        final maxHp = _kBrickHp[row];
        final fade = maxHp > 1 ? hp / maxHp : 1.0;
        final c = Color.lerp(baseColor.withOpacity(0.25), baseColor, fade)!;

        // Outer glow
        p..color = c.withOpacity(0.22)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
        canvas.drawRRect(
            RRect.fromLTRBR(bl - 2, bt - 2, bl + bw + 2, bt + bh + 2, rr), p);
        p.maskFilter = null;

        // Dark shadow (bottom-right) for depth
        p.color = Colors.black.withOpacity(0.45);
        canvas.drawRRect(
            RRect.fromLTRBR(bl + 2, bt + 2, bl + bw + 2, bt + bh + 2, rr), p);

        // Main fill — slightly darker
        p.color = c.withOpacity(0.62);
        canvas.drawRRect(rect, p);

        // Lighter face top-left (3D raised look)
        p.color = c.withOpacity(0.85);
        canvas.drawRRect(
            RRect.fromLTRBR(bl, bt, bl + bw - 2, bt + bh - 2, rr), p);

        // Top highlight shine
        p.color = Colors.white.withOpacity(0.28);
        canvas.drawRRect(
            RRect.fromLTRBR(bl + 2, bt + 1, bl + bw - 4, bt + bh * 0.35,
                const Radius.circular(2)),
            p);

        // Neon border
        p..color = c..style = PaintingStyle.stroke..strokeWidth = 0.9;
        canvas.drawRRect(rect, p);
        p.style = PaintingStyle.fill;
      }
    }

    // Paddle
    final pw2 = _kPaddleW(level) * pw;
    final padLeft = padX * pw;
    const paddleColor = Color(0xFF00DDFF);
    p..color = paddleColor.withOpacity(0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(padLeft - 2, _kPaddleY * ph - 1, pw2 + 4,
                _kPaddleH * ph + 2),
            const Radius.circular(3)),
        p);
    p..color = paddleColor..maskFilter = null;
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(padLeft, _kPaddleY * ph, pw2, _kPaddleH * ph),
            const Radius.circular(2)),
        p);

    // Ball trail
    final br = _kBallR * min(pw, ph) * 1.5;
    for (int i = 0; i < trail.length; i++) {
      final t = (i + 1) / trail.length;
      p..color = Colors.white.withOpacity(t * 0.18)..maskFilter = null;
      canvas.drawCircle(Offset(trail[i].dx * pw, trail[i].dy * ph),
          br * t * 0.9, p);
    }

    // Ball
    final bscr = Offset(bx * pw, by * ph);
    p..color = Colors.white.withOpacity(0.28)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(bscr, br * 2.0, p);
    p..color = Colors.white..maskFilter = null;
    canvas.drawCircle(bscr, br, p);

    // HUD — fixed-pixel font, no scaling by ph/pw
    final hfs = size.height / 30; // ≈ 13 px on typical canvas
    final tp = TextPainter(textDirection: TextDirection.ltr);
    void txt(String s, double x, double y, Color c, double fs) {
      tp.text = TextSpan(
          text: s,
          style: TextStyle(
              color: c, fontSize: fs, fontFamily: 'monospace',
              fontWeight: FontWeight.bold));
      tp.layout();
      tp.paint(canvas, Offset(x, y));
    }

    txt('$score', size.width * 0.04, size.height * 0.015 - 5, paddleColor, hfs);
    txt('NIV ${level + 1}', size.width * 0.44, size.height * 0.015 - 5,
        Colors.white54, hfs * 0.9);
    txt('RÉC $hiScore', size.width * 0.68, size.height * 0.015 - 5,
        Colors.white24, hfs * 0.9);

    // Combo indicator — shown when combo >= 2
    if (combo >= 2) {
      final comboColor = combo >= 5 ? Colors.amber : Colors.orange;
      txt('×$combo COMBO!', size.width * 0.36, size.height * 0.90,
          comboColor, hfs * 0.95);
    }

    // Lives — small hearts so they read clearly as life indicators
    txt(List.filled(lives.clamp(0, 5), '♥').join(' '),
        size.width * 0.04, size.height - hfs - 11,
        Colors.redAccent.withOpacity(0.85), hfs);
  }
}
