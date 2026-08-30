import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'arcade_center_screen.dart' show AppLanguage;
import 'arcade_input_controller.dart';
import 'game_saldo.dart';
import 'high_score_service.dart';

const _kGW = 10.0, _kGH = 6.0;
const _kGroundY = 5.0;
const _kPlayerX = 1.5;
const _kPlayerW = 0.44;
const _kPlayerHStand = 0.95;
const _kPlayerHDuck = 0.48;
const _kGravity = 20.0;
const _kJumpVy = -8.6;
const _kSaldoEvery = 500;

enum _OType {
  log,
  stump,
  boulder,
  pterodactyl,
}

class _Obstacle {
  double x;
  final _OType type;
  _Obstacle({required this.x, required this.type});

  double get top {
    switch (type) {
      case _OType.log:         return _kGroundY - 0.55;
      case _OType.stump:       return _kGroundY - 1.05;
      case _OType.boulder:     return _kGroundY - 1.50;
      case _OType.pterodactyl: return 3.95;
    }
  }
  double get bot {
    switch (type) {
      case _OType.pterodactyl: return 4.40;
      default:                 return _kGroundY;
    }
  }
  double get hw => type == _OType.boulder ? 0.38 : 0.30;
}

class EndlessRunnerScreen extends StatefulWidget {
  final String userId;
  final DocumentReference rewardsDocRef;
  final double currentSaldo;
  final ArcadeInputController controller;
  final void Function(double) onSaldoChanged;
  final AppLanguage language;

  const EndlessRunnerScreen({
    super.key,
    required this.userId,
    required this.rewardsDocRef,
    required this.currentSaldo,
    required this.controller,
    required this.onSaldoChanged,
    this.language = AppLanguage.spanish,
  });

  @override
  State<EndlessRunnerScreen> createState() => _EndlessRunnerScreenState();
}

class _EndlessRunnerScreenState extends State<EndlessRunnerScreen> {
  double _py = _kGroundY - _kPlayerHStand;
  double _pvy = 0;
  bool _onGround = true;
  bool _isDucking = false;
  double _legPhase = 0.0;

  double _dist = 0;
  double _scrollSpd = 5.0;
  double _spawnTimer = 0;
  double _spawnInterval = 1.8;
  final List<_Obstacle> _obs = [];
  final List<_BgElement> _bgFar = [];
  final List<_BgElement> _bgMid = [];

  int _score = 0, _hiScore = 0;
  int _nextSaldoAt = _kSaldoEvery;
  late double _saldo;
  late double _lastCommitted;
  bool _playing = false, _dead = false;
  bool _showDeathOverlay = false;
  Timer? _gameTimer;
  DateTime? _lastTick;
  final Random _rng = Random();

  Timer? _introTimer;
  double _introPx = 9.0;
  double _introDinoX = 6.5;
  bool _introDone = false;
  double _dinoLegPhase = 0.0;

  double _deathDinoX = -2.0;
  bool _dinoChomping = false;
  bool _fallingDead = false;
  double _fallDeadVy = 0.0;
  bool _mauling = false;
  double _maulPhase = 0.0;
  bool _playerMauled = false;
  final List<_BloodParticle> _bloodParticles = [];

  bool _paused = false;

  String _t(String es, String en) =>
      widget.language == AppLanguage.spanish ? es : en;

  @override
  void initState() {
    super.initState();
    _saldo = widget.currentSaldo;
    _lastCommitted = widget.currentSaldo;
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

  void _startIntroAnim() {
    _introPx = 9.0;
    _introDinoX = 6.5;
    _introDone = false;
    _dinoLegPhase = 0.0;
    _legPhase = 0.0;
    _introTimer?.cancel();
    _introTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!mounted) return;
      if (_introDone) return;
      setState(() {
        _introPx = (_introPx - 0.042).clamp(1.5, 9.0);
        _introDinoX = _introPx - 2.5;
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
        _payAndReplay();
      }
      return;
    }

    if (event.isDown && btn == ArcadeButton.start) {
      setState(() => _paused = !_paused);
      return;
    }
    if (_paused) return;

    if (event.isDown && (btn == ArcadeButton.a || btn == ArcadeButton.up) &&
        _onGround) {
      _pvy = _kJumpVy;
      _onGround = false;
      HapticFeedback.lightImpact();
    }

    if (btn == ArcadeButton.down) {
      _isDucking = event.isDown;
    }
  }

  Future<void> _payAndReplay() async {
    final ns = await chargeForReplay(
        userId: widget.userId,
        rewardsDocRef: widget.rewardsDocRef,
        currentSaldo: _saldo);
    if (ns == null) return;
    if (!mounted) return;

    _lastCommitted = ns;
    setState(() => _saldo = ns);
    widget.onSaldoChanged(ns);
    _startGame();
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
    _scrollSpd = 5.0;
    _spawnInterval = 1.8;
    _spawnTimer = 1.0;
    _nextSaldoAt = _kSaldoEvery;
    _obs.clear();
    _playing = true;
    _dead = false;
    _paused = false;
    _showDeathOverlay = false;
    _dinoChomping = false;
    _fallingDead = false;
    _fallDeadVy = 0.0;
    _mauling = false;
    _maulPhase = 0.0;
    _playerMauled = false;
    _bloodParticles.clear();
    _deathDinoX = -2.0;
    _lastTick = null;
    _gameTimer?.cancel();
    _gameTimer = Timer.periodic(const Duration(milliseconds: 16), _tick);
    setState(() {});
  }

  _OType _pickObstacleType({bool forCombo = false}) {
    final pteroChance = (0.30 + _dist / 1200).clamp(0.30, 0.65);
    if (_rng.nextDouble() < pteroChance) return _OType.pterodactyl;
    if (_dist < 80) return _OType.log;
    final boulderChance = (_dist / 600).clamp(0.0, 0.35);
    if (_rng.nextDouble() < boulderChance) return _OType.boulder;
    return _OType.stump;
  }

  void _tick(Timer t) {
    if (_paused) return;
    final now = DateTime.now();
    final dt = (_lastTick == null
        ? 0.016
        : now.difference(_lastTick!).inMicroseconds / 1e6)
        .clamp(0.001, 0.05) as double;
    _lastTick = now;

    _scrollSpd = 5.0 + (_dist / 400).clamp(0.0, 5.0);
    _spawnInterval = (1.8 - _dist / 600).clamp(0.6, 1.8);

    _dist += _scrollSpd * dt;
    _score = _dist.floor();

    if (_score >= _nextSaldoAt) {
      _nextSaldoAt += _kSaldoEvery;
      final newSaldo = _saldo + 1;
      _saldo = newSaldo;
      widget.onSaldoChanged(newSaldo);
      _updateFirestore(newSaldo);
    }

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

    if (_onGround) _legPhase += _scrollSpd * dt * 7.0;

    for (final o in _obs) { o.x -= _scrollSpd * dt; }
    _obs.removeWhere((o) => o.x < -1.0);

    _spawnTimer -= dt;
    if (_spawnTimer <= 0) {
      _spawnTimer = _spawnInterval * (0.8 + _rng.nextDouble() * 0.4);
      final type = _pickObstacleType();
      _obs.add(_Obstacle(x: _kGW + 0.5, type: type));

      if (_dist > 120) {
        final comboChance = ((_dist - 120) / 900).clamp(0.0, 0.40);
        if (_rng.nextDouble() < comboChance) {
          final t2 = type == _OType.pterodactyl ? _OType.stump : _OType.pterodactyl;
          final comboGap =
              (_scrollSpd * 0.62).clamp(3.2, 6.0) + _rng.nextDouble() * 0.8;
          _obs.add(_Obstacle(x: _kGW + 0.5 + comboGap, type: t2));
          _spawnTimer += comboGap / _scrollSpd + 0.3;
        }
      }
    }

    for (final b in _bgFar) {
      b.x -= _scrollSpd * 0.18 * dt;
      if (b.x + b.w < 0) b.x = _kGW + _rng.nextDouble() * 2;
    }
    for (final b in _bgMid) {
      b.x -= _scrollSpd * 0.42 * dt;
      if (b.x + b.w < 0) b.x = _kGW + _rng.nextDouble() * 1.5;
    }

    final ph = _isDucking ? _kPlayerHDuck : _kPlayerHStand;
    final pTop = _py, pBot = _py + ph;
    final pLeft = _kPlayerX - _kPlayerW, pRight = _kPlayerX + _kPlayerW;

    for (final o in _obs) {
      final oLeft = o.x - o.hw, oRight = o.x + o.hw;
      if (pRight <= oLeft || pLeft >= oRight ||
          pBot <= o.top || pTop >= o.bot) continue;
      _gameTimer?.cancel();
      _playing = false;
      _dead = true;
      _fallingDead = true;
      _fallDeadVy = 0.0;
      _showDeathOverlay = false;
      _dinoChomping = false;
      _deathDinoX = -2.0;
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
        if (_fallingDead) {
          _fallDeadVy += _kGravity * dt;
          _py += _fallDeadVy * dt;
          final groundTop = _kGroundY - _kPlayerHStand;
          if (_py >= groundTop) {
            _py = groundTop;
            _fallDeadVy = 0;
            _fallingDead = false;
            _onGround = true;
          }
          return;
        }

        if (!_dinoChomping) {
          _deathDinoX += 7.0 * dt;
          _dinoLegPhase += 0.32;
          if (_deathDinoX >= _kPlayerX - 0.3) {
            _dinoChomping = true;
            _mauling = true;
          }
        } else if (_mauling) {
          _maulPhase += 0.40;
          if (_rng.nextDouble() < 0.35) {
            _bloodParticles.add(_BloodParticle(
              x: _kPlayerX + (_rng.nextDouble() - 0.5) * 0.6,
              y: _kGroundY - 0.6 - _rng.nextDouble() * 0.5,
              vx: (_rng.nextDouble() - 0.5) * 3.0,
              vy: -2.0 - _rng.nextDouble() * 3.0,
            ));
          }
          for (final bp in _bloodParticles) { bp.update(dt); }
          _bloodParticles.removeWhere((bp) => bp.opacity <= 0);
          if (_maulPhase > 30 && !_playerMauled) _playerMauled = true;
          if (_maulPhase > 60) {
            _mauling = false;
            _introTimer?.cancel();
            Future.delayed(const Duration(milliseconds: 400), () {
              if (mounted) setState(() => _showDeathOverlay = true);
            });
          }
        }
      });
    });
  }

  Future<void> _updateFirestore(double newSaldo) async {

    final delta = newSaldo - _lastCommitted;
    if (delta == 0) return;
    final result = await applyArcadeDelta(
      delta: delta,
      reason: 'endless_runner',
    );
    if (result != null) {
      _lastCommitted = result;
      if (mounted && _saldo != result) {
        setState(() => _saldo = result);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dinoX = _playing
        ? double.infinity
        : (_dead ? _deathDinoX : _introDinoX);

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
              maulPhase: _maulPhase,
              playerMauled: _playerMauled,
              bloodParticles: List.unmodifiable(_bloodParticles),
              hiLabel: _t('RÉC', 'BEST'),
            ),
          ),
        ),
        if (!_playing && !_dead)
          _buildOverlay(_t('🦕 DINO ESCAPE', '🦕 DINO DASH'),
              _t('Arriba / A = Saltar\nAbajo = Agacharse\nStart = Pausa',
                 'Up / A = Jump\nDown = Duck\nStart = Pause')),
        if (_dead && _showDeathOverlay)
          _buildOverlay(_t('😱 ¡DEVORADO!', '😱 DEVOURED!'),
              _t('Distancia: ${_score}m\nPulsa A para reintentar',
                 'Distance: ${_score}m\nPress A to retry')),
        if (_playing && _paused)
          _buildOverlay(_t('⏸ PAUSA', '⏸ PAUSED'),
              _t('Start para continuar', 'Start to continue')),
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
              child: Text(_t('RÉCORD: ${_hiScore}m', 'BEST: ${_hiScore}m'),
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

class _BloodParticle {
  double x, y, vx, vy;
  double opacity = 1.0;
  _BloodParticle({required this.x, required this.y, required this.vx, required this.vy});
  void update(double dt) {
    x += vx * dt;
    y += vy * dt;
    vy += 12.0 * dt;
    opacity -= dt * 1.8;
  }
}

class _RunnerPainter extends CustomPainter {
  final double py, playerDisplayX, dinoX, legPhase, dinoLegPhase;
  final double maulPhase;
  final bool isDucking, onGround, dinoChomping, playerMauled;
  final List<_Obstacle> obstacles;
  final List<_BgElement> bgFar, bgMid;
  final List<_BloodParticle> bloodParticles;
  final int score, hiScore;
  final String hiLabel;

  const _RunnerPainter({
    required this.py, required this.isDucking, required this.onGround,
    required this.legPhase,
    required this.playerDisplayX,
    required this.obstacles, required this.bgFar, required this.bgMid,
    required this.score, required this.hiScore,
    required this.dinoX,
    required this.dinoChomping,
    required this.dinoLegPhase,
    required this.maulPhase,
    required this.playerMauled,
    required this.bloodParticles,
    required this.hiLabel,
  });

  @override bool shouldRepaint(_RunnerPainter o) => true;

  @override
  void paint(Canvas canvas, Size size) {
    final ux = size.width / _kGW;
    final uy = size.height / _kGH;
    final p = Paint()..isAntiAlias = false;

    final skyPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Color(0xFFD96820), Color(0xFFE8A840), Color(0xFFF5C860)],
        stops: [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), skyPaint);

    p.isAntiAlias = true;
    p.color = const Color(0xFF8B3010).withOpacity(0.50);
    for (final b in bgFar) {
      final vx = b.x * ux;
      final vw = b.w * ux * 1.8;
      final vh = b.h * uy * 1.5;
      final vy = (_kGroundY - b.h * 1.5) * uy;
      final volPath = Path()
        ..moveTo(vx - vw / 2, _kGroundY * uy)
        ..lineTo(vx, vy)
        ..lineTo(vx + vw / 2, _kGroundY * uy)
        ..close();
      canvas.drawPath(volPath, p);
      p.color = const Color(0xFFFF4400).withOpacity(0.25);
      canvas.drawCircle(Offset(vx, vy), 8, p);
      p.color = const Color(0xFF8B3010).withOpacity(0.50);
    }

    p.color = const Color(0xFF2A5A10).withOpacity(0.55);
    for (final b in bgMid) {
      canvas.drawRect(Rect.fromLTWH(
          b.x * ux - 2, (_kGroundY - b.h) * uy, 4, b.h * uy), p);
      p.color = const Color(0xFF3A7A18).withOpacity(0.65);
      for (int fi = -2; fi <= 2; fi++) {
        final fPath = Path()
          ..moveTo(b.x * ux, (_kGroundY - b.h) * uy)
          ..quadraticBezierTo(
              (b.x + fi * 0.25) * ux, (_kGroundY - b.h - 0.45) * uy,
              (b.x + fi * 0.45) * ux, (_kGroundY - b.h - 0.30) * uy);
        p..style = PaintingStyle.stroke..strokeWidth = 3;
        canvas.drawPath(fPath, p);
        p.style = PaintingStyle.fill;
      }
      p.color = const Color(0xFF2A5A10).withOpacity(0.55);
    }

    p..color = const Color(0xFF7A4A1A)..maskFilter = null..isAntiAlias = false;
    canvas.drawRect(Rect.fromLTWH(0, _kGroundY * uy, size.width,
        size.height - _kGroundY * uy), p);
    p.color = const Color(0xFF4A8A20);
    canvas.drawRect(Rect.fromLTWH(0, _kGroundY * uy - 1, size.width, 5 * (uy / 10)), p);
    p.color = const Color(0xFF5A3410).withOpacity(0.35);
    for (int i = 0; i < 20; i++) {
      final gx = (i * 0.53) % _kGW;
      final gy = _kGroundY + 0.12 + (i * 0.37) % 0.25;
      canvas.drawCircle(Offset(gx * ux, gy * uy), 2, p);
    }

    p.isAntiAlias = true;
    for (final o in obstacles) {
      final cx = o.x * ux;
      final ox = (o.x - o.hw) * ux;
      final ow = o.hw * 2 * ux;
      final ot = o.top * uy;
      final oh = (o.bot - o.top) * uy;

      switch (o.type) {
        case _OType.log:
          p.color = const Color(0xFF5A3010);
          canvas.drawRRect(RRect.fromRectAndRadius(
              Rect.fromLTWH(ox, ot, ow, oh), const Radius.circular(6)), p);
          p..color = const Color(0xFF3A1A08)..style = PaintingStyle.stroke..strokeWidth = 1.5;
          canvas.drawRRect(RRect.fromRectAndRadius(
              Rect.fromLTWH(ox + 2, ot + 2, ow - 4, oh - 4), const Radius.circular(4)), p);
          p.style = PaintingStyle.fill;
          p.color = const Color(0xFF3A7A20);
          canvas.drawRRect(RRect.fromRectAndRadius(
              Rect.fromLTWH(ox + 2, ot, ow - 4, oh * 0.28), const Radius.circular(4)), p);

        case _OType.stump:
          p.color = const Color(0xFF6A3818);
          canvas.drawRRect(RRect.fromRectAndRadius(
              Rect.fromLTWH(ox, ot, ow, oh), const Radius.circular(4)), p);
          p.color = const Color(0xFF4A2A0A);
          canvas.drawOval(Rect.fromLTWH(ox + 2, ot, ow - 4, oh * 0.22), p);
          p..color = const Color(0xFF7A4A22)..style = PaintingStyle.stroke..strokeWidth = 1;
          canvas.drawOval(Rect.fromLTWH(ox + 5, ot + 2, ow - 10, oh * 0.12), p);
          p..style = PaintingStyle.fill;
          p.color = const Color(0xFF3A2010).withOpacity(0.4);
          for (double ly = ot + oh * 0.28; ly < ot + oh - 3; ly += oh * 0.18) {
            canvas.drawRect(Rect.fromLTWH(ox, ly, ow, 2), p);
          }
          p.color = const Color(0xFF4A8A20);
          canvas.drawRRect(RRect.fromRectAndRadius(
              Rect.fromLTWH(ox - 3, _kGroundY * uy - 4, ow + 6, 5), const Radius.circular(2)), p);

        case _OType.boulder:
          p.color = const Color(0xFF888880);
          canvas.drawRRect(RRect.fromRectAndRadius(
              Rect.fromLTWH(ox, ot, ow, oh), const Radius.circular(10)), p);
          p.color = const Color(0xFFBBBBB5).withOpacity(0.5);
          canvas.drawOval(Rect.fromLTWH(ox + 4, ot + 4, ow * 0.45, oh * 0.30), p);
          p..color = const Color(0xFF555550)..style = PaintingStyle.stroke..strokeWidth = 1.2;
          canvas.drawLine(Offset(cx + 4, ot + oh * 0.2),
              Offset(cx - 2, ot + oh * 0.65), p);
          canvas.drawLine(Offset(cx - 6, ot + oh * 0.3),
              Offset(cx + 2, ot + oh * 0.5), p);
          p.style = PaintingStyle.fill;
          p.color = const Color(0xFF7A8A40).withOpacity(0.55);
          canvas.drawCircle(Offset(ox + ow * 0.7, ot + oh * 0.25), 5, p);
          canvas.drawCircle(Offset(ox + ow * 0.25, ot + oh * 0.55), 4, p);

        case _OType.pterodactyl:
          final wingFlap = sin(DateTime.now().millisecondsSinceEpoch / 220.0);
          final flapOffset = wingFlap * oh * 0.45;
          final bodyW = ow * 0.55;
          final bodyH = oh * 0.65;
          final bodyCX = cx - ow * 0.05;
          final bodyCY = ot + oh * 0.42;

          p.style = PaintingStyle.fill;

          p.color = const Color(0xFF7A3818);
          final lwPath = Path()
            ..moveTo(bodyCX - bodyW * 0.35, bodyCY)
            ..quadraticBezierTo(
                bodyCX - ow * 0.85, bodyCY - oh * 0.25 - flapOffset * 0.6,
                bodyCX - ow * 1.2, bodyCY + flapOffset * 0.3)
            ..quadraticBezierTo(
                bodyCX - ow * 0.75, bodyCY + oh * 0.22,
                bodyCX - bodyW * 0.35, bodyCY + oh * 0.20);
          canvas.drawPath(lwPath, p);
          final rwPath = Path()
            ..moveTo(bodyCX + bodyW * 0.35, bodyCY)
            ..quadraticBezierTo(
                bodyCX + ow * 0.60, bodyCY - oh * 0.30 - flapOffset * 0.8,
                bodyCX + ow * 0.90, bodyCY + flapOffset * 0.4)
            ..quadraticBezierTo(
                bodyCX + ow * 0.50, bodyCY + oh * 0.18,
                bodyCX + bodyW * 0.35, bodyCY + oh * 0.20);
          canvas.drawPath(rwPath, p);

          p..color = const Color(0xFF4A1A08).withOpacity(0.40)
            ..style = PaintingStyle.stroke..strokeWidth = 1;
          canvas.drawLine(Offset(bodyCX - bodyW * 0.2, bodyCY + 3),
              Offset(bodyCX - ow * 0.9, bodyCY + flapOffset * 0.2 + 5), p);
          canvas.drawLine(Offset(bodyCX + bodyW * 0.2, bodyCY + 3),
              Offset(bodyCX + ow * 0.65, bodyCY + flapOffset * 0.3 + 5), p);
          p.style = PaintingStyle.fill;

          p.color = const Color(0xFF9A4A20);
          canvas.drawOval(Rect.fromLTWH(
              bodyCX - bodyW * 0.50, bodyCY - bodyH * 0.45,
              bodyW, bodyH), p);

          final headR = oh * 0.28;
          p.color = const Color(0xFF9A4A20);
          canvas.drawOval(Rect.fromLTWH(
              bodyCX - bodyW * 0.50 - headR * 1.6, bodyCY - bodyH * 0.40,
              headR * 1.7, headR * 1.4), p);

          p.color = const Color(0xFFCC9040);
          final beakPath = Path()
            ..moveTo(bodyCX - bodyW * 0.50 - headR * 1.5, bodyCY - bodyH * 0.20)
            ..lineTo(bodyCX - bodyW * 0.50 - headR * 2.6, bodyCY - bodyH * 0.05)
            ..lineTo(bodyCX - bodyW * 0.50 - headR * 1.5, bodyCY + bodyH * 0.08)
            ..close();
          canvas.drawPath(beakPath, p);
          p..color = const Color(0xFF996820)..style = PaintingStyle.stroke..strokeWidth = 1;
          canvas.drawLine(
              Offset(bodyCX - bodyW * 0.50 - headR * 1.5, bodyCY - bodyH * 0.06),
              Offset(bodyCX - bodyW * 0.50 - headR * 2.6, bodyCY - bodyH * 0.05), p);
          p.style = PaintingStyle.fill;

          p.color = Colors.red.withOpacity(0.90);
          canvas.drawCircle(
              Offset(bodyCX - bodyW * 0.50 - headR * 0.8, bodyCY - bodyH * 0.25), 4, p);
          p.color = Colors.black;
          canvas.drawCircle(
              Offset(bodyCX - bodyW * 0.50 - headR * 0.75, bodyCY - bodyH * 0.24), 2, p);

          p..color = const Color(0xFF5A2A08)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2
            ..strokeCap = StrokeCap.round;
          final hipY = bodyCY + bodyH * 0.40;
          for (int t = 0; t < 2; t++) {
            final hipX = bodyCX + (t == 0 ? -bodyW * 0.05 : bodyW * 0.22);
            final footX = hipX + ow * 0.14;
            final footY = hipY + oh * 0.20;
            canvas.drawLine(Offset(hipX, hipY), Offset(footX, footY), p);
            p.strokeWidth = 1.5;
            for (int c = 0; c < 3; c++) {
              final ca = -0.7 + c * 0.7;
              canvas.drawLine(
                  Offset(footX, footY),
                  Offset(footX + sin(ca) * 5.0, footY + cos(ca) * 5.0), p);
            }
            p.strokeWidth = 2.2;
          }
          p..style = PaintingStyle.fill..strokeCap = StrokeCap.butt;
      }
    }

    if (dinoX > -3.0 && dinoX < _kGW + 4.5) {
      final shakeX = _mauling ? sin(maulPhase * 18.0) * 0.18 : 0.0;
      _drawDino(canvas, dinoX + shakeX, ux, uy,
          chomping: dinoChomping, legPhase: dinoLegPhase, mauling: _mauling);
    }

    for (final bp in bloodParticles) {
      p.color = const Color(0xFFCC0010).withOpacity(bp.opacity.clamp(0, 1));
      canvas.drawCircle(Offset(bp.x * ux, bp.y * uy), 3.5, p);
    }

    if (playerMauled) {
      _drawPorkLeg(canvas, playerDisplayX, py, ux, uy, isDucking);
    } else {
      _drawCaveman(canvas, playerDisplayX, py, ux, uy, isDucking, legPhase, onGround);
    }

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
        const Color(0xFFFFDD44), hfs);
    if (hiScore > 0) {
      txt('$hiLabel: ${hiScore}m', size.width * 0.58, size.height * 0.02,
          Colors.white54, hfs * 0.82);
    }
  }

  static void _drawCaveman(Canvas canvas, double px, double py, double ux, double uy,
      bool isDucking, double legPhase, bool onGround) {
    final p = Paint()..isAntiAlias = true;
    final pH = (isDucking ? _kPlayerHDuck : _kPlayerHStand);
    final bodyH = pH * 0.52;
    const skinColor = Color(0xFFD4925A);
    const leatherColor = Color(0xFF8B5E2A);
    const leatherDark = Color(0xFF5A3A10);
    const hairColor = Color(0xFF3A2010);

    final bodyTop = py + pH * 0.26;
    final bodyBot = py + pH * 0.78;
    p.color = leatherColor;
    canvas.drawRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH((px - _kPlayerW * 0.7) * ux, bodyTop * uy,
            _kPlayerW * 1.4 * ux, (bodyBot - bodyTop) * uy),
        const Radius.circular(4)), p);
    p..color = leatherDark..style = PaintingStyle.stroke..strokeWidth = 1.5;
    canvas.drawLine(
        Offset((px - _kPlayerW * 0.7) * ux, (bodyBot - (bodyBot - bodyTop) * 0.15) * uy),
        Offset((px + _kPlayerW * 0.7) * ux, (bodyBot - (bodyBot - bodyTop) * 0.15) * uy), p);
    p.style = PaintingStyle.fill;
    p.color = leatherDark.withOpacity(0.5);
    canvas.drawRect(Rect.fromLTWH(
        (px - _kPlayerW * 0.62) * ux, (bodyTop + 0.02) * uy,
        _kPlayerW * 0.15 * ux, (bodyBot - bodyTop) * 0.40 * uy), p);

    final headH = pH * 0.28;
    final headTop = py;
    final headBot = py + headH;
    p.color = skinColor;
    canvas.drawRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH((px - _kPlayerW * 0.55) * ux, headTop * uy,
            _kPlayerW * 1.1 * ux, headH * uy),
        const Radius.circular(4)), p);
    if (!isDucking) {
      p.color = hairColor;
      final hairPath = Path();
      final hl = (px - _kPlayerW * 0.55) * ux;
      final hr = (px + _kPlayerW * 0.55) * ux;
      final ht = headTop * uy;
      hairPath.moveTo(hl, ht + 2);
      for (int i = 0; i < 5; i++) {
        final hx = hl + (hr - hl) * (i / 4.0);
        hairPath.lineTo(hx, ht - 6 - (i.isEven ? 6 : 2));
        hairPath.lineTo(hx + (hr - hl) * 0.12, ht + 2);
      }
      hairPath.close();
      canvas.drawPath(hairPath, p);
    }
    p.color = Colors.black;
    canvas.drawCircle(
        Offset((px + _kPlayerW * 0.38) * ux, (headTop + headH * 0.42) * uy), 2.2, p);
    p.color = Colors.white;
    canvas.drawCircle(
        Offset((px + _kPlayerW * 0.32) * ux, (headTop + headH * 0.38) * uy), 0.9, p);
    p..color = hairColor.withOpacity(0.45)..style = PaintingStyle.stroke..strokeWidth = 1;
    canvas.drawArc(Rect.fromLTWH(
        (px - _kPlayerW * 0.32) * ux, (headTop + headH * 0.62) * uy,
        _kPlayerW * 0.70 * ux, headH * 0.30 * uy), 0, pi, false, p);
    p.style = PaintingStyle.fill;

    if (!isDucking) {
      final armY = bodyTop + (bodyBot - bodyTop) * 0.18;
      p.color = skinColor;
      canvas.drawRect(Rect.fromLTWH(
          (px + _kPlayerW * 0.65) * ux, armY * uy,
          _kPlayerW * 0.22 * ux, (bodyBot - bodyTop) * 0.25 * uy), p);
      p.color = leatherDark;
      canvas.drawRRect(RRect.fromRectAndRadius(
          Rect.fromLTWH((px + _kPlayerW * 0.82) * ux, (armY - 0.12) * uy,
              _kPlayerW * 0.18 * ux, pH * 0.38 * uy),
          const Radius.circular(3)), p);
      p.color = const Color(0xFF888888);
      canvas.drawOval(Rect.fromLTWH(
          (px + _kPlayerW * 0.76) * ux, (armY - 0.28) * uy,
          _kPlayerW * 0.30 * ux, pH * 0.20 * uy), p);

      final legW = _kPlayerW * 0.45 * ux;
      final legBaseY = bodyBot * uy;
      const fixedLegH = _kPlayerHStand * 0.22;
      final fullLegH = fixedLegH * uy;
      final sinV = onGround ? sin(legPhase) : 0.0;
      final liftL = max(0.0, sinV) * fullLegH * 0.5;
      final liftR = max(0.0, -sinV) * fullLegH * 0.5;
      final legLH = fullLegH - liftL;
      final legRH = fullLegH - liftR;
      p.color = leatherColor;
      canvas.drawRRect(RRect.fromRectAndRadius(
          Rect.fromLTWH((px - _kPlayerW * 0.60) * ux, legBaseY, legW, legLH),
          const Radius.circular(3)), p);
      canvas.drawRRect(RRect.fromRectAndRadius(
          Rect.fromLTWH((px + _kPlayerW * 0.15) * ux, legBaseY, legW, legRH),
          const Radius.circular(3)), p);
      p.color = leatherDark;
      if (liftL < fullLegH * 0.25) {
        canvas.drawRRect(RRect.fromRectAndRadius(
            Rect.fromLTWH((px - _kPlayerW * 0.65) * ux, (legBaseY + legLH - 4),
                legW + 6, 5), const Radius.circular(2)), p);
      }
      if (liftR < fullLegH * 0.25) {
        canvas.drawRRect(RRect.fromRectAndRadius(
            Rect.fromLTWH((px + _kPlayerW * 0.10) * ux, (legBaseY + legRH - 4),
                legW + 6, 5), const Radius.circular(2)), p);
      }
    }
  }

  static void _drawPorkLeg(Canvas canvas, double px, double py, double ux, double uy,
      bool isDucking) {
    final p = Paint()..isAntiAlias = true;
    const pH = _kPlayerHStand;
    final cx = px * ux;
    final meatTop = (py + pH * 0.05) * uy;
    final meatW = _kPlayerW * 1.1 * ux;
    final meatH = pH * 0.58 * uy;

    p.color = const Color(0xFFF5F5E0);
    final boneX = cx - _kPlayerW * 0.06 * ux;
    final boneW = _kPlayerW * 0.12 * ux;
    canvas.drawRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(boneX, meatTop + meatH * 0.45, boneW, meatH * 0.55),
        const Radius.circular(4)), p);
    canvas.drawCircle(Offset(cx, meatTop + meatH * 0.98), 8, p);

    p.color = const Color(0xFFC47A30);
    canvas.drawOval(Rect.fromLTWH(cx - meatW * 0.50, meatTop, meatW, meatH * 0.72), p);
    canvas.drawOval(Rect.fromLTWH(cx - meatW * 0.30, meatTop + meatH * 0.50,
        meatW * 0.60, meatH * 0.35), p);

    p.color = const Color(0xFFD88C3A);
    canvas.drawOval(Rect.fromLTWH(cx - meatW * 0.35, meatTop + 3, meatW * 0.70, meatH * 0.42), p);

    p.color = const Color(0xFF7A3A10).withOpacity(0.55);
    canvas.drawCircle(Offset(cx - meatW * 0.20, meatTop + meatH * 0.22), 6, p);
    canvas.drawCircle(Offset(cx + meatW * 0.22, meatTop + meatH * 0.40), 5, p);
    canvas.drawCircle(Offset(cx - meatW * 0.10, meatTop + meatH * 0.58), 4, p);

    p.color = Colors.white.withOpacity(0.30);
    canvas.drawOval(Rect.fromLTWH(cx - meatW * 0.28, meatTop + 5, meatW * 0.30, meatH * 0.22), p);
  }

  bool get _mauling => maulPhase > 0 && maulPhase < 60;

  static void _drawDino(Canvas canvas, double dx, double ux, double uy,
      {bool chomping = false, double legPhase = 0.0, bool mauling = false}) {
    final p = Paint()..isAntiAlias = true;
    final clr = mauling ? const Color(0xFF106E30) : const Color(0xFF178844);
    const clrDark = Color(0xFF0A4A20);
    const clrLight = Color(0xFF28CC66);
    const clrBelly = Color(0xFF90C890);

    final bob = chomping ? 0.0 : sin(legPhase * 2.0).abs() * 0.035;

    final bodyTop = _kGroundY - 1.20 - bob;
    final bodyBot = _kGroundY - 0.22 - bob;
    const bodyLeft = -0.55;
    const bodyRight = 0.42;
    final bodyMidY = (bodyTop + bodyBot) / 2;

    p..color = clr.withOpacity(mauling ? 0.30 : 0.12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawOval(Rect.fromCenter(
        center: Offset(dx * ux, (_kGroundY - 0.55 - bob) * uy),
        width: 2.2 * ux, height: 1.4 * uy), p);
    p.maskFilter = null;

    final tailSway = chomping ? 0.0 : cos(legPhase) * 0.09;
    p.color = clrDark;
    final tailPath = Path()
      ..moveTo((dx + bodyLeft) * ux, (_kGroundY - 0.45 - bob) * uy)
      ..quadraticBezierTo(
          (dx - 0.90) * ux, (_kGroundY - 0.50 + tailSway - bob) * uy,
          (dx - 1.30) * ux, (_kGroundY - 0.18 + tailSway * 1.5 - bob) * uy)
      ..lineTo((dx - 1.20) * ux, (_kGroundY - 0.10 - bob) * uy)
      ..quadraticBezierTo(
          (dx - 0.80) * ux, (_kGroundY - 0.28 + tailSway - bob) * uy,
          (dx + bodyLeft) * ux, (_kGroundY - 0.85 - bob) * uy)
      ..close();
    canvas.drawPath(tailPath, p);
    p.color = clr;
    final tailHPath = Path()
      ..moveTo((dx + bodyLeft) * ux, (_kGroundY - 0.60 - bob) * uy)
      ..quadraticBezierTo(
          (dx - 0.65) * ux, (_kGroundY - 0.55 + tailSway * 0.6 - bob) * uy,
          (dx - 1.05) * ux, (_kGroundY - 0.22 + tailSway - bob) * uy)
      ..lineTo((dx - 0.98) * ux, (_kGroundY - 0.16 - bob) * uy)
      ..quadraticBezierTo(
          (dx - 0.60) * ux, (_kGroundY - 0.40 + tailSway * 0.5 - bob) * uy,
          (dx + bodyLeft) * ux, (_kGroundY - 0.78 - bob) * uy)
      ..close();
    canvas.drawPath(tailHPath, p);

    p.color = clr;
    canvas.drawRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH((dx + bodyLeft) * ux, bodyTop * uy,
            (bodyRight - bodyLeft) * ux, (bodyBot - bodyTop) * uy),
        const Radius.circular(8)), p);

    p.color = clrBelly.withOpacity(0.5);
    canvas.drawOval(Rect.fromLTWH(
        (dx + bodyLeft + 0.12) * ux, (bodyTop + (bodyBot - bodyTop) * 0.30) * uy,
        (bodyRight - bodyLeft - 0.28) * ux, (bodyBot - bodyTop) * 0.55 * uy), p);

    p.color = clrDark.withOpacity(0.35);
    for (int i = 0; i < 6; i++) {
      final sx = dx + bodyLeft + 0.10 + i * 0.14;
      final sy = bodyTop + (bodyBot - bodyTop) * (0.20 + (i % 2) * 0.25);
      canvas.drawCircle(Offset(sx * ux, sy * uy), 3, p);
    }

    p.color = clrDark;
    for (int i = 0; i < 5; i++) {
      final rx = dx + bodyLeft + 0.15 + i * 0.17;
      canvas.drawOval(Rect.fromLTWH(
          rx * ux - 5, (bodyTop - 0.05 - bob) * uy, 10, 8), p);
    }

    p.color = clrLight.withOpacity(0.30);
    canvas.drawRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH((dx + bodyLeft + 0.06) * ux, (bodyTop + 0.04) * uy,
            0.22 * ux, (bodyBot - bodyTop) * 0.28 * uy),
        const Radius.circular(3)), p);

    p.color = clrDark;
    canvas.drawRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH((dx + 0.22) * ux, (bodyTop + 0.15) * uy, 0.18 * ux, 0.14 * uy),
        const Radius.circular(2)), p);
    p..style = PaintingStyle.stroke..strokeWidth = 1.2;
    for (int i = 0; i < 3; i++) {
      canvas.drawLine(
          Offset((dx + 0.40) * ux, (bodyTop + 0.28) * uy),
          Offset((dx + 0.40 + i * 0.04) * ux, (bodyTop + 0.36) * uy), p);
    }
    p..style = PaintingStyle.fill;

    const headW = 0.78;
    const headH = 0.58;
    final headLeft = dx + 0.05;
    final headTop = bodyTop - headH + 0.08;
    final snoutRight = headLeft + headW;

    final jawOpen = chomping || mauling;
    final jawGap = jawOpen ? 0.26 : 0.0;

    p.color = clr;
    canvas.drawRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(headLeft * ux, headTop * uy, headW * ux, (headH * 0.55) * uy),
        const Radius.circular(6)), p);
    canvas.drawOval(Rect.fromLTWH(
        (snoutRight - 0.12) * ux, headTop * uy, 0.18 * ux, headH * 0.50 * uy), p);

    p.color = clrDark.withOpacity(0.85);
    final lowerJawTop = headTop + headH * 0.50 + jawGap;
    canvas.drawRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(headLeft * ux, lowerJawTop * uy, headW * 0.85 * ux, headH * 0.30 * uy),
        const Radius.circular(4)), p);

    if (jawOpen) {
      p.color = const Color(0xFF440000);
      canvas.drawRect(Rect.fromLTWH(
          (headLeft + 0.08) * ux, (headTop + headH * 0.50) * uy,
          headW * 0.75 * ux, jawGap * uy), p);

      p.color = const Color(0xFFCC3344);
      canvas.drawOval(Rect.fromLTWH(
          (headLeft + 0.18) * ux, (headTop + headH * 0.52) * uy,
          headW * 0.45 * ux, jawGap * 0.50 * uy), p);
    }

    p.color = Colors.white.withOpacity(0.95);
    final toothCount = jawOpen ? 5 : 4;
    for (int i = 0; i < toothCount; i++) {
      final tx = (headLeft + 0.10 + i * (headW * 0.72 / toothCount)) * ux;
      final ty = (headTop + headH * 0.50) * uy;
      final th = (jawOpen ? 0.14 : 0.05) * uy;
      final tw = 0.045 * ux;
      final toothPath = Path()
        ..moveTo(tx, ty)
        ..lineTo(tx + tw, ty)
        ..lineTo(tx + tw / 2, ty + th)
        ..close();
      canvas.drawPath(toothPath, p);
    }

    if (jawOpen) {
      for (int i = 0; i < 4; i++) {
        final tx = (headLeft + 0.14 + i * (headW * 0.62 / 4)) * ux;
        final ty = lowerJawTop * uy;
        final th = 0.11 * uy;
        final tw = 0.040 * ux;
        final toothPath = Path()
          ..moveTo(tx, ty + th)
          ..lineTo(tx + tw, ty + th)
          ..lineTo(tx + tw / 2, ty)
          ..close();
        canvas.drawPath(toothPath, p);
      }
      p.color = Colors.white.withOpacity(0.50);
      canvas.drawOval(Rect.fromLTWH(
          (headLeft + 0.25) * ux, (headTop + headH * 0.48 + jawGap * 0.6) * uy,
          0.05 * ux, 0.10 * uy), p);
    }

    p.color = clrDark.withOpacity(0.60);
    canvas.drawOval(Rect.fromLTWH(
        (snoutRight - 0.08) * ux, (headTop + headH * 0.12) * uy,
        0.06 * ux, 0.05 * uy), p);

    final eyeCx = (headLeft + 0.22) * ux;
    final eyeCy = (headTop + headH * 0.22) * uy;
    p..color = clrDark
      ..style = PaintingStyle.stroke
      ..strokeWidth = mauling ? 3.0 : 2.0;
    canvas.drawLine(Offset(eyeCx - 10, eyeCy + 7), Offset(eyeCx + 8, eyeCy - 2), p);
    p..style = PaintingStyle.fill;

    if (mauling) {
      p..color = Colors.red.withOpacity(0.60)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      canvas.drawCircle(Offset(eyeCx, eyeCy + 4), 12, p);
      p.maskFilter = null;
    }

    p.color = (mauling ? const Color(0xFFFF2200) : const Color(0xFFFFCC00)).withOpacity(0.95);
    canvas.drawOval(Rect.fromCenter(
        center: Offset(eyeCx, eyeCy + 4), width: 9.0, height: 14.0), p);
    p.color = Colors.black;
    canvas.drawOval(Rect.fromCenter(
        center: Offset(eyeCx, eyeCy + 4), width: 3.5, height: 11.0), p);
    p.color = Colors.white.withOpacity(0.80);
    canvas.drawCircle(Offset(eyeCx - 2.0, eyeCy), 2.0, p);

    p.color = clr;
    if (chomping) {
      for (final lx in [dx - 0.30, dx + 0.10]) {
        canvas.drawRRect(RRect.fromRectAndRadius(
            Rect.fromLTWH(lx * ux, bodyBot * uy, 0.25 * ux, 0.22 * uy),
            const Radius.circular(3)), p);
        p.color = clrDark;
        canvas.drawRRect(RRect.fromRectAndRadius(
            Rect.fromLTWH((lx - 0.05) * ux, (bodyBot + 0.18) * uy, 0.34 * ux, 0.06 * uy),
            const Radius.circular(2)), p);
        p.color = clr;
      }
    } else {
      final liftL = max(0.0, sin(legPhase)) * 0.16;
      final liftR = max(0.0, -sin(legPhase)) * 0.16;
      final legLH = (0.22 + bob - liftL).clamp(0.05, 0.35);
      final legRH = (0.22 + bob - liftR).clamp(0.05, 0.35);
      for (final entry in [(dx - 0.30, legLH, liftL), (dx + 0.10, legRH, liftR)]) {
        final (lx, lh, lift) = entry;
        p.color = clr;
        canvas.drawRRect(RRect.fromRectAndRadius(
            Rect.fromLTWH(lx * ux, bodyBot * uy, 0.25 * ux, lh * uy),
            const Radius.circular(3)), p);
        if (lift < 0.04) {
          p.color = clrDark;
          canvas.drawRRect(RRect.fromRectAndRadius(
              Rect.fromLTWH((lx - 0.05) * ux, (bodyBot + lh - 0.06) * uy,
                  0.34 * ux, 0.06 * uy),
              const Radius.circular(2)), p);
        }
      }
    }
  }
}
