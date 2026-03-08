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
const _kGroundY = 5.0;
const _kPlayerX = 1.5;
const _kPlayerW = 0.44;      // half-width
const _kPlayerHStand = 0.95;
const _kPlayerHDuck = 0.48;
const _kGravity = 20.0;
const _kJumpVy = -8.6;
const _kSaldoEvery = 500;

// ─── Obstacle types ───────────────────────────────────────────────────────────

enum _OType { wall, ceil, lowWall, tall }

class _Obstacle {
  double x;
  final _OType type;
  _Obstacle({required this.x, required this.type});

  double get top {
    switch (type) {
      case _OType.wall:    return _kGroundY - 1.05;
      case _OType.ceil:    return 3.05;
      case _OType.lowWall: return _kGroundY - 0.55; // short ground block
      case _OType.tall:    return _kGroundY - 1.50; // tall block, tighter timing
    }
  }
  double get bot {
    switch (type) {
      case _OType.ceil: return 3.65;
      default:          return _kGroundY;
    }
  }
  double get hw => type == _OType.tall ? 0.32 : 0.28;
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
  double _py = _kGroundY - _kPlayerHStand;
  double _pvy = 0;
  bool _onGround = true;
  bool _isDucking = false;
  double _legPhase = 0.0; // oscillates for running leg animation

  // World
  double _dist = 0;
  double _scrollSpd = 4.0;
  double _spawnTimer = 0;
  double _spawnInterval = 2.2;
  final List<_Obstacle> _obs = [];
  final List<_BgElement> _bgFar = [];
  final List<_BgElement> _bgMid = [];

  // State
  int _score = 0, _hiScore = 0;
  int _nextSaldoAt = _kSaldoEvery;
  late double _saldo;
  bool _playing = false, _dead = false;
  bool _showDeathOverlay = false;
  Timer? _gameTimer;
  DateTime? _lastTick;
  final Random _rng = Random();

  // ─── Dino intro animation (runs on start screen) ──────────────────────────
  Timer? _introTimer;
  double _introPx = 9.0;     // player display x during pan
  double _introDinoX = 6.5;  // dino display x (2.5 units BEHIND = to the LEFT of player)
  bool _introDone = false;   // pan has completed, freeze
  double _dinoLegPhase = 0.0; // oscillates for dino leg animation

  // ─── Death dino animation ─────────────────────────────────────────────────
  double _deathDinoX = -2.0;  // dino rushes from LEFT (behind player) on death
  bool _dinoChomping = false;

  @override
  void initState() {
    super.initState();
    _saldo = widget.currentSaldo;
    widget.controller.addListener(_onInput);
    HighScoreService.load('runner').then((v) {
      if (mounted) setState(() => _hiScore = v);
    });
    _initBg();
    _startIntroAnim();
  }

  @override
  void dispose() {
    _gameTimer?.cancel();
    _introTimer?.cancel();
    widget.controller.removeListener(_onInput);
    super.dispose();
  }

  void _initBg() {
    for (int i = 0; i < 8; i++) {
      _bgFar.add(_BgElement(x: _rng.nextDouble() * _kGW,
          h: 0.6 + _rng.nextDouble() * 1.2, w: 0.3 + _rng.nextDouble() * 0.5));
      _bgMid.add(_BgElement(x: _rng.nextDouble() * _kGW,
          h: 0.4 + _rng.nextDouble() * 0.6, w: 0.15 + _rng.nextDouble() * 0.3));
    }
  }

  // Start intro: player pans in from the right, dino chases from behind (left)
  void _startIntroAnim() {
    _introPx = 9.0;
    _introDinoX = 6.5; // dino starts 2.5 units LEFT of player (behind)
    _introDone = false;
    _dinoLegPhase = 0.0;
    _legPhase = 0.0;
    _introTimer?.cancel();
    _introTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!mounted) return;
      if (_introDone) return; // pan complete, hold position
      setState(() {
        _introPx = (_introPx - 0.042).clamp(1.5, 9.0);
        // Dino always 2.5 units to the LEFT of the player (chasing from behind)
        _introDinoX = _introPx - 2.5;
        // Animate both sets of legs
        _legPhase += 0.30;
        _dinoLegPhase += 0.28;
        if (_introPx <= 1.5) _introDone = true;
      });
    });
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
      if (event.isDown && (btn == ArcadeButton.a || btn == ArcadeButton.start) &&
          _showDeathOverlay) {
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
    _introTimer?.cancel();
    _introDone = true;
    _introPx = _kPlayerX;
    _introDinoX = _kPlayerX + 2.5;

    _py = _kGroundY - _kPlayerHStand;
    _pvy = 0;
    _onGround = true;
    _isDucking = false;
    _legPhase = 0.0;
    _dist = 0;
    _score = 0;
    _scrollSpd = 4.0;
    _spawnInterval = 2.2;
    _spawnTimer = 1.0;
    _nextSaldoAt = _kSaldoEvery;
    _obs.clear();
    _playing = true;
    _dead = false;
    _showDeathOverlay = false;
    _dinoChomping = false;
    _deathDinoX = -2.0;    // will enter from left on next death
    _lastTick = null;
    _gameTimer?.cancel();
    _gameTimer = Timer.periodic(const Duration(milliseconds: 16), _tick);
    setState(() {});
  }

  // Determine obstacle type for a spawn, based on current distance
  _OType _pickObstacleType({bool forCombo = false}) {
    // Ceiling chance rises from 30% → 65% with distance
    final ceilChance = (0.30 + _dist / 1200).clamp(0.30, 0.65);
    if (_rng.nextDouble() < ceilChance) return _OType.ceil;
    // Ground obstacle variety: lowWall early, tall later
    if (_dist < 80) return _OType.lowWall;
    final tallChance = (_dist / 600).clamp(0.0, 0.35);
    if (_rng.nextDouble() < tallChance) return _OType.tall;
    return _OType.wall;
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

    // Leg animation phase (speed-proportional)
    if (_onGround) _legPhase += _scrollSpd * dt * 7.0;

    // Scroll obstacles
    for (final o in _obs) { o.x -= _scrollSpd * dt; }
    _obs.removeWhere((o) => o.x < -1.0);

    // Spawn obstacles
    _spawnTimer -= dt;
    if (_spawnTimer <= 0) {
      _spawnTimer = _spawnInterval * (0.8 + _rng.nextDouble() * 0.4);
      final type = _pickObstacleType();
      _obs.add(_Obstacle(x: _kGW + 0.5, type: type));

      // Combo: spawn a second obstacle close behind at higher distances (20→40%)
      if (_dist > 120) {
        final comboChance = ((_dist - 120) / 900).clamp(0.0, 0.40);
        if (_rng.nextDouble() < comboChance) {
          final spacing = 1.5 + _rng.nextDouble() * 0.6;
          // Second type is intentionally different for variety
          final t2 = type == _OType.ceil ? _OType.wall : _OType.ceil;
          _obs.add(_Obstacle(x: _kGW + 0.5 + spacing, type: t2));
        }
      }
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
      if (pRight <= oLeft || pLeft >= oRight ||
          pBot <= o.top || pTop >= o.bot) continue;
      // Hit — trigger death dino animation
      _gameTimer?.cancel();
      _playing = false;
      _dead = true;
      _showDeathOverlay = false;
      _dinoChomping = false;
      _deathDinoX = -2.0;    // enters from left (behind the player)
      HapticFeedback.heavyImpact();
      HighScoreService.submit('runner', _score);
      HighScoreService.load('runner').then((v) {
        if (mounted) setState(() => _hiScore = v);
      });
      _startDeathAnim();
      setState(() {});
      return;
    }

    setState(() {});
  }

  void _startDeathAnim() {
    _introTimer?.cancel();
    _introTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!mounted) { _introTimer?.cancel(); return; }
      const dt = 0.016;
      setState(() {
        // Dino rushes RIGHTWARD from behind (left side) toward player
        _deathDinoX += 7.0 * dt;
        _dinoLegPhase += 0.32; // animate dino legs while running
        if (_deathDinoX >= _kPlayerX - 0.3 && !_dinoChomping) {
          _dinoChomping = true;
          _introTimer?.cancel();
          Future.delayed(const Duration(milliseconds: 600), () {
            if (mounted) setState(() => _showDeathOverlay = true);
          });
        }
      });
    });
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
    // Dino x to pass to painter: hidden during gameplay
    final dinoX = _playing
        ? double.infinity
        : (_dead ? _deathDinoX : _introDinoX);

    // Player display x: fixed during play, panning during intro
    final playerDisplayX = _playing ? _kPlayerX : _introPx;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        SizedBox.expand(
          child: CustomPaint(
            painter: _RunnerPainter(
              py: _py, isDucking: _isDucking, onGround: _onGround,
              legPhase: _legPhase,
              playerDisplayX: playerDisplayX,
              obstacles: List.unmodifiable(_obs),
              bgFar: List.unmodifiable(_bgFar),
              bgMid: List.unmodifiable(_bgMid),
              score: _score, hiScore: _hiScore,
              dinoX: dinoX,
              dinoChomping: _dinoChomping,
              dinoLegPhase: _dinoLegPhase,
            ),
          ),
        ),
        if (!_playing && !_dead)
          _buildOverlay('CORREDOR INFINITO',
              'Arriba / A = Saltar\nAbajo = Agacharse\nPulsa A para correr'),
        if (_dead && _showDeathOverlay)
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
  final double py, playerDisplayX, dinoX, legPhase, dinoLegPhase;
  final bool isDucking, onGround, dinoChomping;
  final List<_Obstacle> obstacles;
  final List<_BgElement> bgFar, bgMid;
  final int score, hiScore;

  const _RunnerPainter({
    required this.py, required this.isDucking, required this.onGround,
    required this.legPhase,
    required this.playerDisplayX,
    required this.obstacles, required this.bgFar, required this.bgMid,
    required this.score, required this.hiScore,
    required this.dinoX,
    required this.dinoChomping,
    required this.dinoLegPhase,
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
    // Windows
    p.color = const Color(0xFF1A2A55).withOpacity(0.6);
    for (final b in bgFar) {
      for (double wy = _kGroundY - b.h + 0.15; wy < _kGroundY - 0.2; wy += 0.25) {
        for (double wx = b.x + 0.05; wx < b.x + b.w - 0.05; wx += 0.12) {
          canvas.drawRect(Rect.fromLTWH(wx * ux, wy * uy, 0.07 * ux, 0.14 * uy), p);
        }
      }
    }

    // Mid background
    p.color = const Color(0xFF0D1530);
    for (final b in bgMid) {
      canvas.drawRect(
          Rect.fromLTWH(b.x * ux, (_kGroundY - b.h) * uy, b.w * ux, b.h * uy), p);
    }

    // Ground
    p..color = const Color(0xFF0C1208)..maskFilter = null;
    canvas.drawRect(Rect.fromLTWH(0, _kGroundY * uy, size.width,
        size.height - _kGroundY * uy), p);
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

      final oColor = switch (o.type) {
        _OType.wall    => const Color(0xFFFF4422),
        _OType.ceil    => const Color(0xFFFF8800),
        _OType.lowWall => const Color(0xFFDDCC00),
        _OType.tall    => const Color(0xFFFF1155),
      };

      // Glow
      p..color = oColor.withOpacity(0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
      canvas.drawRect(Rect.fromLTWH(ox - 2, ot - 2, ow + 4, oh + 4), p);
      p.maskFilter = null;

      // Body
      p.color = oColor.withOpacity(0.75);
      canvas.drawRect(Rect.fromLTWH(ox, ot, ow, oh), p);

      // Border
      p..color = oColor..style = PaintingStyle.stroke..strokeWidth = 1;
      canvas.drawRect(Rect.fromLTWH(ox, ot, ow, oh), p);
      p.style = PaintingStyle.fill;

      // Ceiling bar connector
      if (o.type == _OType.ceil) {
        p.color = oColor.withOpacity(0.4);
        canvas.drawRect(Rect.fromLTWH(o.x * ux - 1, 0, 2, ot), p);
      }
    }

    // ── Dinosaur ─────────────────────────────────────────────────────────────
    if (dinoX > -3.0 && dinoX < _kGW + 4.5) {
      _drawDino(canvas, dinoX, ux, uy,
          chomping: dinoChomping, legPhase: dinoLegPhase);
    }

    // ── Player ───────────────────────────────────────────────────────────────
    final pLeft = (playerDisplayX - _kPlayerW) * ux;
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

    if (!isDucking) {
      // Eye (right side of face, front of runner)
      p.color = Colors.black;
      canvas.drawCircle(
          Offset((playerDisplayX + _kPlayerW * 0.45) * ux, (py + 0.17) * uy),
          2.5, p);
      p.color = playerColor.withOpacity(0.9);
      canvas.drawCircle(
          Offset((playerDisplayX + _kPlayerW * 0.45) * ux, (py + 0.17) * uy),
          1.2, p);

      // Legs — left and right, clearly separated, no overlap
      // Left leg center: playerDisplayX - _kPlayerW*0.5
      // Right leg center: playerDisplayX + _kPlayerW*0.5
      final legW = _kPlayerW * 0.55 * ux; // leg width
      final legH = pH * 0.28;
      final legBaseY = pTop + pH * 0.70;
      final sinV = sin(legPhase); // -1..1
      final legSwing = uy * 0.08; // max swing in pixels

      p.color = playerColor.withOpacity(0.7);
      // Left leg
      final llX = (playerDisplayX - _kPlayerW * 0.55) * ux;
      canvas.drawRect(Rect.fromLTWH(
          llX, legBaseY + sinV * legSwing, legW, legH), p);
      // Right leg (opposite phase)
      final rlX = (playerDisplayX + _kPlayerW * 0.05) * ux;
      canvas.drawRect(Rect.fromLTWH(
          rlX, legBaseY - sinV * legSwing, legW, legH), p);
    }

    // ── HUD ──────────────────────────────────────────────────────────────────
    final hfs = size.height / 26;
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

  // ── Dinosaur painter ───────────────────────────────────────────────────────
  static void _drawDino(Canvas canvas, double dx, double ux, double uy,
      {bool chomping = false, double legPhase = 0.0}) {
    final p = Paint()..isAntiAlias = true;
    const clr = Color(0xFF1DAA55); // dino green
    const clrDark = Color(0xFF0E6633);

    // Glow
    p..color = clr.withOpacity(0.20)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(dx * ux, (_kGroundY - 0.55) * uy),
            width: 1.5 * ux, height: 1.1 * uy),
        p);
    p.maskFilter = null;

    // Tail (triangle pointing left)
    p.color = clrDark;
    final tailPath = Path()
      ..moveTo((dx - 0.38) * ux, (_kGroundY - 0.55) * uy)
      ..lineTo((dx - 0.85) * ux, (_kGroundY - 0.32) * uy)
      ..lineTo((dx - 0.42) * ux, (_kGroundY - 0.90) * uy)
      ..close();
    canvas.drawPath(tailPath, p);

    // Body
    p.color = clr;
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(
                (dx - 0.38) * ux, (_kGroundY - 1.10) * uy,
                0.75 * ux, 0.78 * uy),
            const Radius.circular(4)),
        p);

    // Head
    final mouthDrop = chomping ? 0.18 : 0.0;
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(
                (dx + 0.10) * ux, (_kGroundY - 1.58 - mouthDrop) * uy,
                0.52 * ux, (0.44 + mouthDrop) * uy),
            const Radius.circular(3)),
        p);

    // Upper jaw tip (snout)
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(
                (dx + 0.46) * ux, (_kGroundY - 1.42) * uy,
                0.22 * ux, 0.20 * uy),
            const Radius.circular(2)),
        p);

    // Teeth when chomping
    if (chomping) {
      p.color = Colors.white.withOpacity(0.9);
      for (int i = 0; i < 3; i++) {
        canvas.drawRect(Rect.fromLTWH(
            (dx + 0.48 + i * 0.065) * ux,
            (_kGroundY - 1.42 + 0.18) * uy,
            0.04 * ux, 0.10 * uy), p);
      }
      p.color = clr;
    }

    // Eye
    p.color = Colors.white;
    canvas.drawCircle(
        Offset((dx + 0.44) * ux, (_kGroundY - 1.52) * uy), 3.0, p);
    p.color = Colors.black;
    canvas.drawCircle(
        Offset((dx + 0.46) * ux, (_kGroundY - 1.52) * uy), 1.5, p);

    // Tiny arm
    p.color = clrDark;
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(
                (dx + 0.24) * ux, (_kGroundY - 0.88) * uy,
                0.18 * ux, 0.16 * uy),
            const Radius.circular(2)),
        p);

    // Legs — sinusoidal alternating run animation
    p.color = clr;
    final legSin = chomping ? 0.0 : sin(legPhase);
    final legSwingPx = legSin * 0.09; // game-unit swing amplitude
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(
                (dx - 0.25) * ux, (_kGroundY - 0.32 + legSwingPx) * uy,
                0.18 * ux, 0.32 * uy),
            const Radius.circular(2)),
        p);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(
                (dx + 0.07) * ux, (_kGroundY - 0.32 - legSwingPx) * uy,
                0.18 * ux, 0.32 * uy),
            const Radius.circular(2)),
        p);
  }
}
