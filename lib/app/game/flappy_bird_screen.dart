import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'arcade_input_controller.dart';
import 'high_score_service.dart';

// ─── Data ─────────────────────────────────────────────────────────────────────

class _Pipe {
  double x;
  double gapY; // centre of the gap
  bool scored; // has this pipe already been counted
  _Pipe(this.x, this.gapY) : scored = false;
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
  static const double kGapHStart = 3.4; // gap height at wave 1 (was 3.8)
  // Min gap must be >= 1.5 × bird diameter (kBirdR*2=0.76 → 1.5×=1.14).
  static const double kGapHMin = 2.0; // minimum gap height (was 2.2)
  static const double kSpeedStart = 3.6; // pipe scroll speed (was 3.2)
  static const double kSpeedMax = 7.0;

  // Ground
  static const double kGroundY = 14.8;

  final _rng = Random();

  // Bird state
  double _birdY = kH / 2;
  double _birdVy = 0;

  // Pipes & world
  List<_Pipe> _pipes = [];
  double _pipeSpeed = kSpeedStart;
  double _nextPipeX = 0;

  // Score & saldo
  int _pipesPassed = 0; // raw count
  int _displayScore = 0; // pipesPassed ~/ 10 (shown as "pts in game")
  late double _saldo;
  bool _awardingPoints = false;
  int _bestPipes = 0;

  // State
  bool _isRunning = false;
  bool _isDead = false;
  bool _paused = false;

  // Wing flap animation
  double _flapAngle = 0;

  Timer? _ticker;
  DateTime? _lastTick;

  @override
  void initState() {
    super.initState();
    _saldo = widget.currentSaldo;
    _resetGame();
    widget.controller.addListener(_onControllerEvent);
    HighScoreService.load('flappy').then((v) { if (mounted) setState(() => _bestPipes = v); });
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

    // Start pauses/resumes when running
    if (btn == ArcadeButton.start) {
      if (_isRunning) {
        setState(() => _paused = !_paused);
      } else {
        _flap();
        _startGame();
      }
      return;
    }

    // Any other action button = flap
    if (btn == ArcadeButton.a ||
        btn == ArcadeButton.b ||
        btn == ArcadeButton.x ||
        btn == ArcadeButton.y ||
        btn == ArcadeButton.up) {
      if (_paused) return;
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
    if (_isDead || _paused) return;
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
    HighScoreService.submit('flappy', _pipesPassed).then((isNew) {
      if (isNew && mounted) setState(() => _bestPipes = _pipesPassed);
    });
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
            pipesPassed: _pipesPassed,
            currentGapH: _currentGapH,
            pipeSpeed: _pipeSpeed,
            time: DateTime.now().millisecondsSinceEpoch / 1000.0,
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
        if (_paused && _isRunning) _buildPauseOverlay(),
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
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xCC5EC8E8), Color(0xCC70E080)],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🐦', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 8),
            const Text('VUELO KAMIKAZE',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 4,
                    shadows: [Shadow(color: Color(0xFF008822), blurRadius: 8)])),
            const SizedBox(height: 4),
            const Text('Alas de Cromo',
                style: TextStyle(color: Colors.white70, fontSize: 12, letterSpacing: 2)),
            const SizedBox(height: 22),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 32),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.35),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Column(children: [
                Text('Pulsa A, B o ↑ para aletear',
                    style: TextStyle(color: Colors.white, fontSize: 13)),
                SizedBox(height: 4),
                Text('Pasa entre los tubos sin chocar',
                    style: TextStyle(color: Colors.white70, fontSize: 11)),
                SizedBox(height: 4),
                Text('+1 pto real cada 10 tubos',
                    style: TextStyle(
                        color: Color(0xFFFFEE44),
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ]),
            ),
            const SizedBox(height: 8),
            const Text('SELECT para volver al menú',
                style: TextStyle(color: Colors.white38, fontSize: 10)),
          ],
        ),
      ),
    );

  Widget _buildDeathOverlay() => Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black.withOpacity(0.85), const Color(0xCC441100)],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('💥', style: TextStyle(fontSize: 56)),
            const Text('¡CHOCASTE!',
                style: TextStyle(
                    color: Color(0xFFFF8800),
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2)),
            const SizedBox(height: 4),
            const Text('El pájaro no pudo esquivar',
                style: TextStyle(color: Color(0xFF886644), fontSize: 11)),
            const SizedBox(height: 16),
            Text('Tubos pasados: $_pipesPassed',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            Text('Puntos reales: $_displayScore',
                style:
                    const TextStyle(color: Colors.white70, fontSize: 13)),
            if (_bestPipes > 0)
              Text('Récord: $_bestPipes tubos',
                  style: const TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 13,
                      fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    _resetGame();
                    _startGame();
                  },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF5EC8E8),
                      foregroundColor: Colors.white,
                      shape: const StadiumBorder()),
                  child: const Text('Volar de nuevo',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text('SELECT para volver al menú',
                style: TextStyle(color: Colors.white38, fontSize: 10)),
          ],
        ),
      ),
    );

  Widget _buildPauseOverlay() => Positioned.fill(
    child: Container(
      color: const Color(0xCC000000),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('⏸', style: TextStyle(fontSize: 48)),
          SizedBox(height: 8),
          Text('PAUSA', style: TextStyle(color: Color(0xFF5EC8E8), fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 6)),
          SizedBox(height: 16),
          Text('START para continuar', style: TextStyle(color: Color(0xFF3A8899), fontSize: 12)),
        ],
      ),
    ),
  );
}

// ─── Painter ─────────────────────────────────────────────────────────────────

class _FlappyPainter extends CustomPainter {
  final double birdY;
  final double flapAngle;
  final List<_Pipe> pipes;
  final int pipesPassed;
  final double currentGapH;
  final double pipeSpeed;
  final double time;

  static const double kW = 10;
  static const double kH = 16;
  static const double kBirdX = 2.2;
  static const double kBirdR = 0.38;
  static const double kPipeW = 1.3;
  static const double kGroundY = 14.8;
  static const double kSpeedStart = 3.6;
  static const double kSpeedMax = 7.0;

  const _FlappyPainter({
    required this.birdY,
    required this.flapAngle,
    required this.pipes,
    required this.pipesPassed,
    required this.currentGapH,
    required this.pipeSpeed,
    required this.time,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cs = size.width / kW;
    double wx(double x) => x * cs;
    double wy(double y) => y * cs;

    // Speed 0-1 factor for intensity effects
    final speedT = ((pipeSpeed - kSpeedStart) / (kSpeedMax - kSpeedStart)).clamp(0.0, 1.0);
    final p = Paint();

    // ── Layered sky: dusk-to-night atmosphere ────────────────────────────────
    // Base sky shifts from deep blue (slow) to deep violet-black (fast)
    final skyTop = Color.lerp(const Color(0xFF0D1B3E), const Color(0xFF05050F), speedT)!;
    final skyBot = Color.lerp(const Color(0xFF1A3A5C), const Color(0xFF1A0828), speedT)!;
    p.shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [skyTop, skyBot],
    ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), p);
    p.shader = null;

    // Horizon glow — neon blue-purple
    final glowCol = Color.lerp(const Color(0x55004488), const Color(0x88660099), speedT)!;
    p.shader = LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [glowCol, const Color(0x00000000)],
    ).createShader(Rect.fromLTWH(0, size.height * 0.45, size.width, size.height * 0.30));
    canvas.drawRect(Rect.fromLTWH(0, size.height * 0.45, size.width, size.height * 0.30), p);
    p.shader = null;

    // ── Star field — more stars + brighter at high speed ─────────────────────
    final rng = Random(42);
    final starCount = 60 + (speedT * 80).round();
    for (int i = 0; i < starCount; i++) {
      final sx = rng.nextDouble() * size.width;
      final sy = rng.nextDouble() * size.height * 0.70;
      final starBright = 0.35 + rng.nextDouble() * 0.65;
      final twinkle = 0.6 + sin(time * (1.5 + rng.nextDouble() * 2) + i) * 0.4;
      p.color = Colors.white.withOpacity((starBright * twinkle).clamp(0.0, 1.0));
      canvas.drawCircle(Offset(sx, sy), 0.7 + rng.nextDouble() * 0.8, p);
    }

    // ── Speed streaks — white/cyan horizontal lines at high speed ────────────
    // Fixed seed so positions never jump; only horizontal scroll changes with time.
    if (speedT > 0.15) {
      final streakOpacity = ((speedT - 0.15) / 0.85).clamp(0.0, 1.0);
      final streakRng = Random(999); // fixed seed — positions never jump
      for (int i = 0; i < 18; i++) {
        final sy = streakRng.nextDouble() * size.height * 0.82;
        final baseLen = 30 + streakRng.nextDouble() * 80;
        final len = baseLen * speedT;
        final opacity = streakOpacity * (0.20 + streakRng.nextDouble() * 0.30);
        final sx = (time * (80 + i * 14) * speedT) % (size.width + len);
        final col = i % 3 == 0
            ? const Color(0xFF00DDFF)
            : (i % 3 == 1 ? const Color(0xFFAA88FF) : Colors.white);
        p.color = col.withOpacity(opacity);
        canvas.drawRect(Rect.fromLTWH(size.width - sx, sy, len, 1.2), p);
      }
    }

    // ── Background city silhouette (parallax, slow layer) ────────────────────
    _drawCitySilhouette(canvas, size, p, speedT, time);

    // ── Pipes — chrome industrial columns with neon ring accents ─────────────
    for (final pipe in pipes) {
      final px = wx(pipe.x);
      final pw = kPipeW * cs;
      final gapTop = wy(pipe.gapY - currentGapH / 2);
      final gapBot = wy(pipe.gapY + currentGapH / 2);
      _drawChromePipe(canvas, p, px, pw, 0, gapTop, gapTop, size, speedT, time, pipe.x);
      _drawChromePipe(canvas, p, px, pw, gapBot, size.height, size.height - gapBot, size, speedT, time, pipe.x + 0.5);
    }

    // ── Ground — dark tarmac with neon runway markings ───────────────────────
    _drawRunway(canvas, size, p, wx, wy, speedT, time, pipesPassed);

    // ── Aircraft (chrome eagle) ───────────────────────────────────────────────
    final bx = wx(kBirdX);
    final by = wy(birdY);
    final br = kBirdR * cs;
    _drawAircraft(canvas, p, bx, by, br, flapAngle, speedT, time);
  }

  // ── Chrome industrial pipe column ────────────────────────────────────────────

  void _drawChromePipe(Canvas canvas, Paint p, double px, double pw,
      double top, double bottom, double totalH,
      Size size, double speedT, double time, double idSeed) {
    if (totalH <= 0) return;
    final isTop = top == 0;

    // Main body — dark gunmetal steel
    p.shader = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: const [
        Color(0xFF1A1A2E), Color(0xFF252540),
        Color(0xFF3A3A5C), Color(0xFF252540), Color(0xFF0E0E1A),
      ],
      stops: const [0.0, 0.18, 0.50, 0.82, 1.0],
    ).createShader(Rect.fromLTWH(px, top, pw, totalH));
    canvas.drawRect(Rect.fromLTWH(px, top, pw, totalH), p);
    p.shader = null;

    // Left/right chrome edge highlights
    p.color = const Color(0xFF6688CC);
    canvas.drawRect(Rect.fromLTWH(px, top, pw * 0.07, totalH), p);
    p.color = const Color(0xFF334466);
    canvas.drawRect(Rect.fromLTWH(px + pw * 0.93, top, pw * 0.07, totalH), p);

    // Neon ring bands — fixed to each pipe, no global time scroll
    final neonCol = Color.lerp(const Color(0xFF0088FF), const Color(0xFFAA00FF), speedT)!;
    final ringSpacing = pw * 2.2; // slightly wider spacing, less cluttered
    // Phase offset is fixed per pipe via idSeed, so rings stay put on the pipe
    final ringPhase = (idSeed * 1.618) % 1.0; // golden-ratio scatter
    final ringOffset = ringPhase * ringSpacing;
    for (double ry = top + ringOffset; ry < bottom; ry += ringSpacing) {
      final dist = (ry - top).clamp(0, totalH);
      final opacity = (0.55 - (dist / totalH).clamp(0.0, 0.4)).clamp(0.08, 0.65);
      p.color = neonCol.withOpacity(opacity);
      canvas.drawRect(Rect.fromLTWH(px - pw * 0.08, ry, pw * 1.16, pw * 0.10), p);
      // Inner bright ring centre
      p.color = Colors.white.withOpacity(opacity * 0.4);
      canvas.drawRect(Rect.fromLTWH(px, ry + pw * 0.03, pw, pw * 0.03), p);
    }

    // Cap / muzzle — wider chrome collar
    final capH = pw * 0.35;
    final capExW = pw * 0.14;
    final capY = isTop ? bottom - capH : top;
    p.shader = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: const [Color(0xFF2244AA), Color(0xFF6699FF), Color(0xFF2244AA)],
    ).createShader(Rect.fromLTWH(px - capExW, capY, pw + capExW * 2, capH));
    canvas.drawRect(Rect.fromLTWH(px - capExW, capY, pw + capExW * 2, capH), p);
    p.shader = null;
    // Cap highlight line
    p.color = const Color(0xFFAADDFF);
    canvas.drawRect(Rect.fromLTWH(px - capExW, capY, pw + capExW * 2, pw * 0.06), p);

    // Inner bore / darkness at cap mouth
    p.color = const Color(0xFF000000);
    canvas.drawRect(Rect.fromLTWH(px + pw * 0.12, capY, pw * 0.76, capH * 0.5), p);
  }

  // ── Background city silhouette ───────────────────────────────────────────────

  void _drawCitySilhouette(Canvas canvas, Size size, Paint p, double speedT, double time) {
    final horizonY = size.height * 0.68;
    // Slow parallax scroll
    final scroll = (time * 12.0 * (0.3 + speedT * 0.4)) % size.width;
    final rng = Random(77);

    p.color = Color.lerp(const Color(0xFF0A0A1A), const Color(0xFF120520), speedT)!;

    // Draw buildings twice for seamless scroll
    for (int pass = 0; pass < 2; pass++) {
      double bx = -scroll + pass * size.width;
      while (bx < size.width + 80) {
        final bw = 18.0 + rng.nextDouble() * 34;
        final bh = 20.0 + rng.nextDouble() * 90;
        canvas.drawRect(Rect.fromLTWH(bx, horizonY - bh, bw, bh), p);
        // Window lights — tiny bright dots
        final winPaint = Paint()..color = Color.lerp(
          const Color(0xFF0066AA), const Color(0xFF6600AA), speedT)!.withOpacity(0.6);
        for (int wy2 = 0; wy2 < (bh / 8).floor(); wy2++) {
          for (int wx2 = 0; wx2 < (bw / 7).floor(); wx2++) {
            if (rng.nextInt(3) != 0) continue;
            canvas.drawRect(Rect.fromLTWH(
              bx + 4 + wx2 * 7, horizonY - bh + 5 + wy2 * 8, 3, 2), winPaint);
          }
        }
        bx += bw + 4 + rng.nextDouble() * 6;
      }
    }
  }

  // ── Runway ground ────────────────────────────────────────────────────────────

  void _drawRunway(Canvas canvas, Size size, Paint p,
      double Function(double) wx, double Function(double) wy,
      double speedT, double time, int pipesPassed) {
    final groundY = wy(kGroundY);

    // Tarmac base
    p.shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [const Color(0xFF1A1A1A), const Color(0xFF0A0A0A)],
    ).createShader(Rect.fromLTWH(0, groundY, size.width, size.height - groundY));
    canvas.drawRect(Rect.fromLTWH(0, groundY, size.width, size.height - groundY), p);
    p.shader = null;

    // Top edge — neon strip
    final edgeCol = Color.lerp(const Color(0xFF0088FF), const Color(0xFFAA00FF), speedT)!;
    p.color = edgeCol.withOpacity(0.8);
    canvas.drawRect(Rect.fromLTWH(0, groundY, size.width, 2.5), p);
    p.color = Colors.white.withOpacity(0.3);
    canvas.drawRect(Rect.fromLTWH(0, groundY, size.width, 1.0), p);

    // Runway centre-line dashes scrolling with speed
    final dashW = size.width * 0.06;
    final dashGap = size.width * 0.08;
    final dashPeriod = dashW + dashGap;
    final dashOffset = (time * 60 * speedT.clamp(0.2, 1.0)) % dashPeriod;
    p.color = const Color(0xFF444444);
    for (double dx = -dashOffset; dx < size.width; dx += dashPeriod) {
      canvas.drawRect(Rect.fromLTWH(dx, groundY + 8, dashW, 3), p);
    }

    // Side chevron markers
    final chevronOffset = (time * 40 * speedT.clamp(0.2, 1.0)) % (size.width * 0.15);
    p.color = edgeCol.withOpacity(0.3);
    for (double cx = -chevronOffset; cx < size.width; cx += size.width * 0.15) {
      final path = Path()
        ..moveTo(cx, groundY + 18)
        ..lineTo(cx + 10, groundY + 12)
        ..lineTo(cx + 18, groundY + 18);
      canvas.drawPath(path, p..style = PaintingStyle.stroke..strokeWidth = 1.5);
      p.style = PaintingStyle.fill;
    }
  }

  // ── Chrome aircraft (wing-swept eagle silhouette) ────────────────────────────

  void _drawAircraft(Canvas canvas, Paint p, double bx, double by, double br,
      double tilt, double speedT, double time) {
    canvas.save();
    canvas.translate(bx, by);
    canvas.rotate(tilt);

    // Afterburner exhaust trail — glowing cone behind craft
    if (speedT > 0.1) {
      final exhaustLen = br * (2.5 + speedT * 3.0);
      final exhaustW = br * 0.55;
      p.shader = LinearGradient(
        begin: Alignment.centerRight,
        end: Alignment.centerLeft,
        colors: [
          Color.lerp(const Color(0xFFFF6600), const Color(0xFF9900FF), speedT)!.withOpacity(0.9),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(-exhaustLen - br, -exhaustW, exhaustLen, exhaustW * 2));
      canvas.drawPath(
        Path()
          ..moveTo(-br * 0.9, 0)
          ..lineTo(-br * 0.9 - exhaustLen, -exhaustW * (0.2 + sin(time * 18) * 0.1))
          ..lineTo(-br * 0.9 - exhaustLen, exhaustW * (0.2 + sin(time * 18 + 1) * 0.1))
          ..close(),
        p,
      );
      p.shader = null;
      // Hot inner core
      p.color = Colors.white.withOpacity(0.7 * speedT);
      canvas.drawPath(
        Path()
          ..moveTo(-br * 0.85, 0)
          ..lineTo(-br * 0.85 - exhaustLen * 0.4, -exhaustW * 0.08)
          ..lineTo(-br * 0.85 - exhaustLen * 0.4, exhaustW * 0.08)
          ..close(),
        p,
      );
    }

    // Fuselage — sleek chrome teardrop
    p.shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: const [Color(0xFFCCDDEE), Color(0xFF445566), Color(0xFF223344)],
      stops: const [0.0, 0.5, 1.0],
    ).createShader(Rect.fromLTWH(-br, -br * 0.45, br * 2, br * 0.9));
    canvas.drawPath(
      Path()
        ..moveTo(br * 1.1, 0)
        ..cubicTo(br * 0.8, -br * 0.38, -br * 0.6, -br * 0.38, -br * 0.95, 0)
        ..cubicTo(-br * 0.6, br * 0.38, br * 0.8, br * 0.38, br * 1.1, 0),
      p,
    );
    p.shader = null;

    // Main swept wings — thin and wide
    p.shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: const [Color(0xFF7799BB), Color(0xFF334455)],
    ).createShader(Rect.fromLTWH(-br * 0.5, -br * 1.5, br, br * 3.0));
    canvas.drawPath(
      Path()
        ..moveTo(br * 0.55, 0)
        ..lineTo(-br * 0.15, -br * 1.45)
        ..lineTo(-br * 0.55, -br * 1.45)
        ..lineTo(-br * 0.80, 0)
        ..lineTo(-br * 0.55, br * 1.45)
        ..lineTo(-br * 0.15, br * 1.45)
        ..close(),
      p,
    );
    p.shader = null;

    // Wing edge highlight — neon blue
    final wingGlow = Color.lerp(const Color(0xFF0088FF), const Color(0xFFAA00FF), speedT)!;
    p.color = wingGlow.withOpacity(0.75);
    p.style = PaintingStyle.stroke;
    p.strokeWidth = 1.2;
    canvas.drawPath(
      Path()
        ..moveTo(-br * 0.15, -br * 1.42)
        ..lineTo(-br * 0.55, -br * 1.42)
        ..lineTo(-br * 0.78, 0)
        ..lineTo(-br * 0.55, br * 1.42)
        ..lineTo(-br * 0.15, br * 1.42),
      p,
    );
    p.style = PaintingStyle.fill;

    // Tail stabilisers
    p.color = const Color(0xFF334455);
    canvas.drawPath(
      Path()
        ..moveTo(-br * 0.65, 0)
        ..lineTo(-br * 1.0, -br * 0.55)
        ..lineTo(-br * 1.0, 0)
        ..close(),
      p,
    );
    canvas.drawPath(
      Path()
        ..moveTo(-br * 0.65, 0)
        ..lineTo(-br * 1.0, br * 0.55)
        ..lineTo(-br * 1.0, 0)
        ..close(),
      p,
    );

    // Nose cone — bright chrome tip
    p.shader = RadialGradient(
      center: const Alignment(0.6, -0.3),
      radius: 1.0,
      colors: const [Colors.white, Color(0xFF88AACC), Color(0xFF334455)],
    ).createShader(Rect.fromCircle(center: Offset(br * 0.8, 0), radius: br * 0.4));
    canvas.drawPath(
      Path()
        ..moveTo(br * 1.1, 0)
        ..lineTo(br * 0.55, -br * 0.18)
        ..lineTo(br * 0.55, br * 0.18)
        ..close(),
      p,
    );
    p.shader = null;

    // Cockpit canopy — tinted glass
    p.shader = RadialGradient(
      center: const Alignment(-0.2, -0.6),
      radius: 1.2,
      colors: [
        Colors.white.withOpacity(0.55),
        Color.lerp(const Color(0xFF0066AA), const Color(0xFF6600AA), speedT)!.withOpacity(0.45),
      ],
    ).createShader(Rect.fromLTWH(br * 0.05, -br * 0.30, br * 0.55, br * 0.60));
    canvas.drawOval(Rect.fromLTWH(br * 0.05, -br * 0.30, br * 0.55, br * 0.60), p);
    p.shader = null;

    // Speed glow halo around craft
    if (speedT > 0.4) {
      p.color = wingGlow.withOpacity((speedT - 0.4) * 0.25);
      canvas.drawOval(Rect.fromLTWH(-br * 1.1, -br * 1.6, br * 2.2, br * 3.2), p);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_FlappyPainter old) => true;
}
