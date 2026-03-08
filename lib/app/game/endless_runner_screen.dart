import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'arcade_input_controller.dart';
import 'high_score_service.dart';

// ─── Game units: width=10, height=6 ──────────────────────────────────────────
// Player fixed at x=1.5; world scrolls right-to-left.

const _kGW = 10.0, _kGH = 6.0;
const _kGroundY = 5.0;       // top of ground stripe
const _kPlayerX = 1.5;       // fixed player x (centre)
const _kPlayerW = 0.44;      // half-width
const _kPlayerHStand = 0.95; // standing height
const _kPlayerHDuck = 0.48;  // ducking height
const _kGravity = 20.0;
const _kJumpVy = -8.6;       // upward velocity when jumping
const _kSaldoEvery = 500;    // award +1 saldo every N metres

// Obstacle types
enum _OType { wall, ceil } // wall = ground block; ceil = low ceiling bar

class _Obstacle {
  double x;
  final _OType type;
  _Obstacle({required this.x, required this.type});

  // Hitbox top/bottom y, half-width
  double get top => type == _OType.wall ? _kGroundY - 1.05 : 3.05;
  double get bot => type == _OType.wall ? _kGroundY        : 3.65;
  double get hw => 0.28;
}

// ─── Widget ───────────────────────────────────────────────────────────────────

class EndlessRunnerScreen extends StatefulWidget {
  final String userId;
  final DocumentReference rewardsDocRef;
  final double currentSaldo;
  final ArcadeInputController controller;
  final void Function(double) onSaldoChanged;

  const EndlessRunnerScreen({
    super.key,
    required this.userId,
    required this.rewardsDocRef,
    required this.currentSaldo,
    required this.controller,
    required this.onSaldoChanged,
  });

  @override
  State<EndlessRunnerScreen> createState() => _EndlessRunnerScreenState();
}

class _EndlessRunnerScreenState extends State<EndlessRunnerScreen> {
  // Player
  double _py = _kGroundY - _kPlayerHStand; // top-y of player
  double _pvy = 0;
  bool _onGround = true;
  bool _isDucking = false;
  // World
  double _dist = 0;          // metres run
  double _scrollSpd = 4.0;
  double _spawnTimer = 0;
  double _spawnInterval = 2.2;
  final List<_Obstacle> _obs = [];
  // Parallax layers: list of (x, type) where type = 0 far, 1 mid
  final List<_BgElement> _bgFar = [];
  final List<_BgElement> _bgMid = [];
  // State
  int _score = 0, _hiScore = 0;
  int _nextSaldoAt = _kSaldoEvery;
  late double _saldo;
  bool _playing = false, _dead = false;
  Timer? _gameTimer;
  DateTime? _lastTick;
  final Random _rng = Random();

  @override
  void initState() {
    super.initState();
    _saldo = widget.currentSaldo;
    widget.controller.addListener(_onInput);
    HighScoreService.load('runner').then((v) {
      if (mounted) setState(() => _hiScore = v);
    });
    _initBg();
  }

  @override
  void dispose() {
    _gameTimer?.cancel();
    widget.controller.removeListener(_onInput);
    super.dispose();
  }

  void _initBg() {
    // Seed background elements across the full width
    for (int i = 0; i < 8; i++) {
      _bgFar.add(_BgElement(x: _rng.nextDouble() * _kGW,
          h: 0.6 + _rng.nextDouble() * 1.2, w: 0.3 + _rng.nextDouble() * 0.5));
      _bgMid.add(_BgElement(x: _rng.nextDouble() * _kGW,
          h: 0.4 + _rng.nextDouble() * 0.6, w: 0.15 + _rng.nextDouble() * 0.3));
    }
  }

  void _onInput() {
    final event = widget.controller.lastEvent;
    if (event == null) return;
    final btn = event.button;

    if (!_playing && !_dead) {
      if (event.isDown && (btn == ArcadeButton.a || btn == ArcadeButton.up ||
          btn == ArcadeButton.start)) {
        _startGame();
      }
      return;
    }
    if (_dead) {
      if (event.isDown && (btn == ArcadeButton.a || btn == ArcadeButton.start)) {
        _startGame();
      }
      return;
    }

    // Jump
    if (event.isDown && (btn == ArcadeButton.a || btn == ArcadeButton.up) &&
        _onGround) {
      _pvy = _kJumpVy;
      _onGround = false;
      HapticFeedback.lightImpact();
    }

    // Duck
    if (btn == ArcadeButton.down) {
      _isDucking = event.isDown;
    }
  }

  void _startGame() {
    _py = _kGroundY - _kPlayerHStand;
    _pvy = 0;
    _onGround = true;
    _isDucking = false;
    _dist = 0;
    _score = 0;
    _scrollSpd = 4.0;
    _spawnInterval = 2.2;
    _spawnTimer = 1.0;
    _nextSaldoAt = _kSaldoEvery;
    _obs.clear();
    _playing = true;
    _dead = false;
    _lastTick = null;
    _gameTimer?.cancel();
    _gameTimer = Timer.periodic(const Duration(milliseconds: 16), _tick);
    setState(() {});
  }

  void _tick(Timer t) {
    final now = DateTime.now();
    final dt = (_lastTick == null
        ? 0.016
        : now.difference(_lastTick!).inMicroseconds / 1e6)
        .clamp(0.001, 0.05) as double;
    _lastTick = now;

    // Scroll speed ramps up with distance (4 → 8.5 over 500 m)
    _scrollSpd = 4.0 + (_dist / 500).clamp(0.0, 4.5);
    // Spawn interval tightens (2.2 → 0.7 s over 700 m)
    _spawnInterval = (2.2 - _dist / 700).clamp(0.7, 2.2);

    // Distance / score
    _dist += _scrollSpd * dt;
    _score = _dist.floor();

    // Saldo milestone
    if (_score >= _nextSaldoAt) {
      _nextSaldoAt += _kSaldoEvery;
      final newSaldo = _saldo + 1;
      _saldo = newSaldo;
      widget.onSaldoChanged(newSaldo);
      _updateFirestore(newSaldo);
    }

    // Player physics
    _pvy += _kGravity * dt;
    _py += _pvy * dt;
    final groundTop = _kGroundY - (_isDucking ? _kPlayerHDuck : _kPlayerHStand);
    if (_py >= groundTop) {
      _py = groundTop;
      _pvy = 0;
      _onGround = true;
    } else {
      _onGround = false;
    }

    // Scroll obstacles
    for (final o in _obs) { o.x -= _scrollSpd * dt; }
    _obs.removeWhere((o) => o.x < -1.0);

    // Spawn obstacles
    _spawnTimer -= dt;
    if (_spawnTimer <= 0) {
      _spawnTimer = _spawnInterval * (0.8 + _rng.nextDouble() * 0.4);
      // Ceiling obstacles become more frequent at higher distances (30 % → 65 %)
      final ceilChance = (0.30 + _dist / 1200).clamp(0.30, 0.65);
      final type = _rng.nextDouble() < ceilChance ? _OType.ceil : _OType.wall;
      _obs.add(_Obstacle(x: _kGW + 0.5, type: type));
    }

    // Scroll background
    for (final b in _bgFar) {
      b.x -= _scrollSpd * 0.18 * dt;
      if (b.x + b.w < 0) b.x = _kGW + _rng.nextDouble() * 2;
    }
    for (final b in _bgMid) {
      b.x -= _scrollSpd * 0.42 * dt;
      if (b.x + b.w < 0) b.x = _kGW + _rng.nextDouble() * 1.5;
    }

    // Collision detection — AABB
    final ph = _isDucking ? _kPlayerHDuck : _kPlayerHStand;
    final pTop = _py, pBot = _py + ph;
    final pLeft = _kPlayerX - _kPlayerW, pRight = _kPlayerX + _kPlayerW;

    for (final o in _obs) {
      final oLeft = o.x - o.hw, oRight = o.x + o.hw;
      final oTop = o.top, oBot = o.bot;
      if (pRight <= oLeft || pLeft >= oRight ||
          pBot <= oTop || pTop >= oBot) continue;
      // Hit!
      _gameTimer?.cancel();
      _playing = false;
      _dead = true;
      HapticFeedback.heavyImpact();
      HighScoreService.submit('runner', _score);
      HighScoreService.load('runner').then((v) {
        if (mounted) setState(() => _hiScore = v);
      });
      setState(() {});
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
    } catch (e) { debugPrint('Runner Firestore: $e'); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        SizedBox.expand(
          child: CustomPaint(
            painter: _RunnerPainter(
              py: _py, isDucking: _isDucking, onGround: _onGround,
              obstacles: List.unmodifiable(_obs),
              bgFar: List.unmodifiable(_bgFar),
              bgMid: List.unmodifiable(_bgMid),
              score: _score, hiScore: _hiScore,
            ),
          ),
        ),
        if (!_playing && !_dead)
          _buildOverlay('CORREDOR INFINITO',
              'Arriba / A = Saltar\nAbajo = Agacharse\nPulsa A para correr'),
        if (_dead)
          _buildOverlay('¡APLASTADO!',
              'Distancia: ${_score}m\nPulsa A para reintentar'),
      ]),
    );
  }

  Widget _buildOverlay(String title, String sub) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.88),
          border: Border.all(color: const Color(0xFF88FF44), width: 1.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Color(0xFF88FF44),
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace')),
          const SizedBox(height: 8),
          Text(sub,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 12, fontFamily: 'monospace')),
          if (_hiScore > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('RÉCORD: ${_hiScore}m',
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

class _BgElement {
  double x;
  final double h, w;
  _BgElement({required this.x, required this.h, required this.w});
}

// ─── Painter ──────────────────────────────────────────────────────────────────

class _RunnerPainter extends CustomPainter {
  final double py;
  final bool isDucking, onGround;
  final List<_Obstacle> obstacles;
  final List<_BgElement> bgFar, bgMid;
  final int score, hiScore;

  const _RunnerPainter({
    required this.py, required this.isDucking, required this.onGround,
    required this.obstacles, required this.bgFar, required this.bgMid,
    required this.score, required this.hiScore,
  });

  @override bool shouldRepaint(_RunnerPainter o) => true;

  @override
  void paint(Canvas canvas, Size size) {
    final ux = size.width / _kGW;
    final uy = size.height / _kGH;
    final p = Paint()..isAntiAlias = false;

    // Sky gradient
    final skyPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Color(0xFF02040C), Color(0xFF050A18)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), skyPaint);

    // Stars (static seed-based)
    p.color = Colors.white.withOpacity(0.3);
    for (int i = 0; i < 40; i++) {
      final sx = (i * 237.3) % _kGW;
      final sy = (i * 133.7) % (_kGroundY * 0.8);
      canvas.drawCircle(Offset(sx * ux, sy * uy), 1, p);
    }

    // Far background buildings
    p.color = const Color(0xFF0A0F22);
    for (final b in bgFar) {
      canvas.drawRect(
          Rect.fromLTWH(b.x * ux, (_kGroundY - b.h) * uy, b.w * ux, b.h * uy), p);
    }
    // Windows in far buildings
    p.color = const Color(0xFF1A2A55).withOpacity(0.6);
    for (final b in bgFar) {
      for (double wy = _kGroundY - b.h + 0.15; wy < _kGroundY - 0.2; wy += 0.25) {
        for (double wx = b.x + 0.05; wx < b.x + b.w - 0.05; wx += 0.12) {
          canvas.drawRect(Rect.fromLTWH(wx * ux, wy * uy, 0.07 * ux, 0.14 * uy), p);
        }
      }
    }

    // Mid background elements
    p.color = const Color(0xFF0D1530);
    for (final b in bgMid) {
      canvas.drawRect(
          Rect.fromLTWH(b.x * ux, (_kGroundY - b.h) * uy, b.w * ux, b.h * uy), p);
    }

    // Ground
    p..color = const Color(0xFF0C1208)..maskFilter = null;
    canvas.drawRect(Rect.fromLTWH(0, _kGroundY * uy, size.width,
        size.height - _kGroundY * uy), p);
    // Neon ground line
    p..color = const Color(0xFF44FF44).withOpacity(0.7)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawRect(Rect.fromLTWH(0, _kGroundY * uy - 1, size.width, 2), p);
    p..color = const Color(0xFF44FF44)..maskFilter = null;
    canvas.drawRect(Rect.fromLTWH(0, _kGroundY * uy - 1, size.width, 1), p);

    // Obstacles
    for (final o in obstacles) {
      final ox = (o.x - o.hw) * ux;
      final ow = o.hw * 2 * ux;
      final ot = o.top * uy;
      final oh = (o.bot - o.top) * uy;
      final oColor = o.type == _OType.wall
          ? const Color(0xFFFF4422)
          : const Color(0xFFFF8800);

      // Glow
      p..color = oColor.withOpacity(0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
      canvas.drawRect(Rect.fromLTWH(ox - 2, ot - 2, ow + 4, oh + 4), p);
      p.maskFilter = null;

      // Body
      p.color = oColor.withOpacity(0.75);
      canvas.drawRect(Rect.fromLTWH(ox, ot, ow, oh), p);

      // Neon border
      p..color = oColor..style = PaintingStyle.stroke..strokeWidth = 1;
      canvas.drawRect(Rect.fromLTWH(ox, ot, ow, oh), p);
      p.style = PaintingStyle.fill;

      // Ceiling bar has a connector to the top
      if (o.type == _OType.ceil) {
        p.color = oColor.withOpacity(0.4);
        canvas.drawRect(Rect.fromLTWH(o.x * ux - 1, 0, 2, ot), p);
      }
    }

    // Player
    final pLeft = (_kPlayerX - _kPlayerW) * ux;
    final pW = _kPlayerW * 2 * ux;
    final pH = (isDucking ? _kPlayerHDuck : _kPlayerHStand) * uy;
    final pTop = py * uy;

    const playerColor = Color(0xFFFFAA00);
    // Body glow
    p..color = playerColor.withOpacity(0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(pLeft - 2, pTop - 2, pW + 4, pH + 4),
            const Radius.circular(4)),
        p);
    p.maskFilter = null;

    // Body
    p.color = playerColor.withOpacity(0.85);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(pLeft, pTop, pW, pH),
            const Radius.circular(3)),
        p);

    // Face
    if (!isDucking) {
      // Eyes
      p.color = Colors.black;
      canvas.drawCircle(
          Offset((_kPlayerX + _kPlayerW * 0.2) * ux, (py + 0.15) * uy),
          2.5, p);
      p.color = playerColor.withOpacity(0.9);
      canvas.drawCircle(
          Offset((_kPlayerX + _kPlayerW * 0.2) * ux, (py + 0.15) * uy),
          1.2, p);
      // Legs (animation)
      p.color = playerColor.withOpacity(0.6);
      final legOff = onGround ? 0.0 : 0.15;
      canvas.drawRect(
          Rect.fromLTWH(
              (_kPlayerX - _kPlayerW * 0.3) * ux,
              (py + _kPlayerHStand * 0.6 + legOff) * uy,
              pW * 0.3, pH * 0.3),
          p);
      canvas.drawRect(
          Rect.fromLTWH(
              (_kPlayerX + _kPlayerW * 0.1) * ux,
              (py + _kPlayerHStand * 0.6 - legOff) * uy,
              pW * 0.3, pH * 0.3),
          p);
    }

    // HUD — fixed-pixel font so it doesn't scale with game units
    final hfs = size.height / 26; // ≈ 15 px on typical canvas
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
    txt('${score}m', size.width * 0.04, size.height * 0.02,
        const Color(0xFF88FF44), hfs);
    if (hiScore > 0) {
      txt('RÉC: ${hiScore}m', size.width * 0.58, size.height * 0.02,
          Colors.white38, hfs * 0.82);
    }
  }
}
