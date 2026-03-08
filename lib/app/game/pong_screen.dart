import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'arcade_input_controller.dart';
import 'high_score_service.dart';

// ─── Constants ────────────────────────────────────────────────────────────────

const _kPW = 120.0, _kPH = 80.0;
const _kPaddleW = 2.5, _kPaddleH = 14.0;
const _kPaddleSpd = 62.0;
const _kBallR = 1.3;
const _kBallSpdInit = 34.0;
const _kBallSpdMax = 75.0;
const _kBallSpdInc = 1.8; // speed added per paddle hit
const _kWinScore = 7;
// AI speed per round (gets faster each round)
const _kAiSpeeds = [36.0, 50.0, 62.0, 72.0];
// AI prediction error (± units at target y) — shrinks each round
const _kAiErrors = [6.0, 3.5, 1.5, 0.5];

enum _PongPhase { ready, playing, scored, gameOver }

// ─── Widget ───────────────────────────────────────────────────────────────────

class PongScreen extends StatefulWidget {
  final String userId;
  final DocumentReference rewardsDocRef;
  final double currentSaldo;
  final ArcadeInputController controller;
  final void Function(double) onSaldoChanged;

  const PongScreen({
    super.key,
    required this.userId,
    required this.rewardsDocRef,
    required this.currentSaldo,
    required this.controller,
    required this.onSaldoChanged,
  });

  @override
  State<PongScreen> createState() => _PongScreenState();
}

class _PongScreenState extends State<PongScreen> {
  double _py = (_kPH - _kPaddleH) / 2; // player paddle top-y
  double _ay = (_kPH - _kPaddleH) / 2; // AI paddle top-y
  double _bx = _kPW / 2, _by = _kPH / 2;
  double _bvx = _kBallSpdInit, _bvy = 15.0;
  double _ballSpd = _kBallSpdInit;

  int _playerScore = 0, _aiScore = 0;
  int _playerRounds = 0, _aiRounds = 0;
  int _round = 0; // increments each time a round ends

  int _hiScore = 0;
  late double _saldo;
  _PongPhase _phase = _PongPhase.ready;
  String _msg = '';

  Timer? _gameTimer;
  DateTime? _lastTick;
  final Random _rng = Random();

  @override
  void initState() {
    super.initState();
    _saldo = widget.currentSaldo;
    widget.controller.addListener(_onInput);
    HighScoreService.load('pong').then((v) {
      if (mounted) setState(() => _hiScore = v);
    });
  }

  @override
  void dispose() {
    _gameTimer?.cancel();
    widget.controller.removeListener(_onInput);
    super.dispose();
  }

  void _onInput() {
    final event = widget.controller.lastEvent;
    if (event == null || !event.isDown) return;
    if (_phase == _PongPhase.ready || _phase == _PongPhase.scored) {
      if (event.button == ArcadeButton.a || event.button == ArcadeButton.start) {
        _startRound();
      }
    }
  }

  void _startRound() {
    _ballSpd = _kBallSpdInit;
    _bx = _kPW / 2;
    _by = _kPH / 2;
    final dir = _rng.nextBool() ? 1.0 : -1.0;
    final angle = (_rng.nextDouble() - 0.5) * 0.9;
    _bvx = dir * _ballSpd * cos(angle);
    _bvy = _ballSpd * sin(angle);
    _phase = _PongPhase.playing;
    _lastTick = null;
    _gameTimer?.cancel();
    _gameTimer = Timer.periodic(const Duration(milliseconds: 16), _tick);
    setState(() {});
  }

  double get _aiSpeed => _kAiSpeeds[_round.clamp(0, _kAiSpeeds.length - 1)];
  double get _aiError => _kAiErrors[_round.clamp(0, _kAiErrors.length - 1)];

  void _tick(Timer t) {
    final now = DateTime.now();
    final dt = (_lastTick == null
        ? 0.016
        : now.difference(_lastTick!).inMicroseconds / 1e6)
        .clamp(0.001, 0.05) as double;
    _lastTick = now;
    if (_phase != _PongPhase.playing) return;

    // Player paddle movement
    final c = widget.controller;
    if (c.isHeld(ArcadeButton.up))
      _py = (_py - _kPaddleSpd * dt).clamp(0, _kPH - _kPaddleH);
    if (c.isHeld(ArcadeButton.down))
      _py = (_py + _kPaddleSpd * dt).clamp(0, _kPH - _kPaddleH);

    // AI paddle — tracks ball y with speed cap + error
    final aiTarget = _by - _kPaddleH / 2 +
        (_rng.nextDouble() - 0.5) * _aiError * 2;
    final aiDiff = aiTarget - _ay;
    if (aiDiff.abs() > 0.3) {
      final aiMove = aiDiff.sign * _aiSpeed * dt;
      _ay = (_ay + aiMove).clamp(0, _kPH - _kPaddleH);
    }

    // Ball movement
    _bx += _bvx * dt;
    _by += _bvy * dt;

    // Top/bottom wall bounce
    if (_by - _kBallR <= 0) {
      _by = _kBallR;
      _bvy = _bvy.abs();
    }
    if (_by + _kBallR >= _kPH) {
      _by = _kPH - _kBallR;
      _bvy = -_bvy.abs();
    }

    // Player paddle collision (left, x=5 to 5+kPaddleW)
    const plx = 5.0;
    if (_bvx < 0 &&
        _bx - _kBallR <= plx + _kPaddleW &&
        _bx - _kBallR >= plx - 2 &&
        _by >= _py &&
        _by <= _py + _kPaddleH) {
      _bx = plx + _kPaddleW + _kBallR;
      final hit = ((_by - _py) / _kPaddleH).clamp(0.0, 1.0);
      final angle = (hit - 0.5) * pi * 0.72;
      _ballSpd = (_ballSpd + _kBallSpdInc).clamp(0, _kBallSpdMax);
      _bvx = _ballSpd * cos(angle).abs();
      _bvy = _ballSpd * sin(angle);
      HapticFeedback.lightImpact();
    }

    // AI paddle collision (right, x=kPW-5-kPaddleW to kPW-5)
    final aix = _kPW - 5 - _kPaddleW;
    if (_bvx > 0 &&
        _bx + _kBallR >= aix &&
        _bx + _kBallR <= aix + _kPaddleW + 2 &&
        _by >= _ay &&
        _by <= _ay + _kPaddleH) {
      _bx = aix - _kBallR;
      final hit = ((_by - _ay) / _kPaddleH).clamp(0.0, 1.0);
      final angle = (hit - 0.5) * pi * 0.65;
      _ballSpd = (_ballSpd + _kBallSpdInc).clamp(0, _kBallSpdMax);
      _bvx = -_ballSpd * cos(angle).abs();
      _bvy = _ballSpd * sin(angle);
    }

    // Out of bounds — point scored
    if (_bx < -3) {
      _aiScore++;
      _onPoint(false);
    } else if (_bx > _kPW + 3) {
      _playerScore++;
      _onPoint(true);
    }

    setState(() {});
  }

  void _onPoint(bool playerScored) {
    _gameTimer?.cancel();
    HapticFeedback.mediumImpact();
    if (_playerScore >= _kWinScore || _aiScore >= _kWinScore) {
      if (_playerScore >= _kWinScore) {
        _playerRounds++;
        _msg = '¡GANASTE LA RONDA!';
        final newSaldo = _saldo + 1;
        _saldo = newSaldo;
        widget.onSaldoChanged(newSaldo);
        _updateFirestore(newSaldo);
      } else {
        _aiRounds++;
        _msg = 'IA GANA LA RONDA';
      }
      _round++;
      _playerScore = 0;
      _aiScore = 0;
      HighScoreService.submit('pong', _playerRounds);
    } else {
      _msg = playerScored ? '¡PUNTO!' : 'IA ANOTA';
    }
    _phase = _PongPhase.scored;
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
    } catch (e) { debugPrint('Pong Firestore: $e'); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        SizedBox.expand(
          child: CustomPaint(
            painter: _PongPainter(
              py: _py, ay: _ay, bx: _bx, by: _by,
              playerScore: _playerScore, aiScore: _aiScore,
              playerRounds: _playerRounds, aiRounds: _aiRounds,
              hiScore: _hiScore, round: _round,
            ),
          ),
        ),
        if (_phase == _PongPhase.ready)
          _buildOverlay('CONTRAGOLPE', 'Sube/Baja con el D-Pad\n¡Pulsa A para jugar!'),
        if (_phase == _PongPhase.scored)
          _buildOverlay(_msg, 'Pulsa A para continuar'),
      ]),
    );
  }

  Widget _buildOverlay(String title, String sub) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.85),
          border: Border.all(color: const Color(0xFF00DDFF), width: 1.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Color(0xFF00DDFF),
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace')),
          const SizedBox(height: 8),
          Text(sub,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 12, fontFamily: 'monospace')),
          if (_playerRounds > 0 || _aiRounds > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                  'Rondas  TÚ $_playerRounds  —  IA $_aiRounds',
                  style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 10,
                      fontFamily: 'monospace')),
            ),
        ]),
      ),
    );
  }
}

// ─── Painter ──────────────────────────────────────────────────────────────────

class _PongPainter extends CustomPainter {
  final double py, ay, bx, by;
  final int playerScore, aiScore, playerRounds, aiRounds, hiScore, round;

  const _PongPainter({
    required this.py, required this.ay,
    required this.bx, required this.by,
    required this.playerScore, required this.aiScore,
    required this.playerRounds, required this.aiRounds,
    required this.hiScore, required this.round,
  });

  @override bool shouldRepaint(_PongPainter o) => true;

  @override
  void paint(Canvas canvas, Size size) {
    final pw = size.width / _kPW, ph = size.height / _kPH;
    final p = Paint()..isAntiAlias = false;

    // Background
    p.color = const Color(0xFF050510);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), p);

    // Centre dashed line
    p.color = Colors.white.withOpacity(0.12);
    final dashH = size.height / 22;
    for (int i = 0; i < 22; i++) {
      if (i.isEven) {
        canvas.drawRect(
            Rect.fromLTWH(size.width / 2 - 1, i * dashH, 2, dashH * 0.65), p);
      }
    }

    // Scores
    final tp = TextPainter(textDirection: TextDirection.ltr);
    void txt(String s, double x, double y, Color c, double fs) {
      tp.text = TextSpan(
          text: s,
          style: TextStyle(
              color: c,
              fontSize: fs,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold));
      tp.layout();
      tp.paint(canvas, Offset(x, y));
    }

    txt('$playerScore', size.width * 0.28, size.height * 0.03,
        Colors.white, 26 * ph);
    txt('$aiScore', size.width * 0.64, size.height * 0.03,
        Colors.white.withOpacity(0.55), 26 * ph);

    // Round indicators (up to 4)
    const cyan = Color(0xFF00DDFF);
    for (int i = 0; i < 4; i++) {
      p.color = i < playerRounds ? cyan : Colors.white12;
      canvas.drawCircle(
          Offset(size.width * 0.37 + i * 9 * pw, size.height * 0.06),
          3.5 * ph, p);
      p.color = i < aiRounds ? Colors.redAccent : Colors.white12;
      canvas.drawCircle(
          Offset(size.width * 0.58 + i * 9 * pw, size.height * 0.06),
          3.5 * ph, p);
    }

    // Player paddle
    p..color = cyan
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawRect(
        Rect.fromLTWH(5 * pw - 2, py * ph - 1,
            _kPaddleW * pw + 4, _kPaddleH * ph + 2), p);
    p..color = cyan..maskFilter = null;
    canvas.drawRect(
        Rect.fromLTWH(5 * pw, py * ph, _kPaddleW * pw, _kPaddleH * ph), p);

    // AI paddle
    final aix = (_kPW - 5 - _kPaddleW) * pw;
    p..color = Colors.redAccent.withOpacity(0.5)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawRect(
        Rect.fromLTWH(aix - 2, ay * ph - 1,
            _kPaddleW * pw + 4, _kPaddleH * ph + 2), p);
    p..color = Colors.redAccent..maskFilter = null;
    canvas.drawRect(
        Rect.fromLTWH(aix, ay * ph, _kPaddleW * pw, _kPaddleH * ph), p);

    // Ball glow + core
    final bscr = Offset(bx * pw, by * ph);
    final br = _kBallR * min(pw, ph);
    p..color = Colors.white.withOpacity(0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(bscr, br * 2.2, p);
    p..color = Colors.white..maskFilter = null;
    canvas.drawCircle(bscr, br, p);

    // Hi-score
    txt('RÉCORD: $hiScore rondas', size.width * 0.25, size.height * 0.93,
        Colors.white24, 8 * ph);

    // Round label
    if (round > 0) {
      txt('RONDA $round', size.width * 0.42, size.height * 0.89,
          Colors.white38, 8 * ph);
    }
  }
}
