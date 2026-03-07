import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'arcade_input_controller.dart';
import 'high_score_service.dart';

// ─── Game object models ──────────────────────────────────────────────────────

class _Log {
  double x;
  int row;
  double speed;
  int len;
  _Log(this.row, this.x, this.speed, this.len);
}

class _Car {
  double x;
  int row;
  double speed;
  int len;
  Color color;
  _Car(this.row, this.x, this.speed, this.len, this.color);
}

enum _Facing { up, down, left, right }

enum _GamePhase { start, playing, dead, levelComplete }

// ─── Widget ──────────────────────────────────────────────────────────────────

class TrafficHopperScreen extends StatefulWidget {
  final String userId;
  final DocumentReference rewardsDocRef;
  final double currentSaldo;
  final ArcadeInputController controller;
  final void Function(double) onSaldoChanged;
  const TrafficHopperScreen({super.key, required this.userId, required this.rewardsDocRef,
      required this.currentSaldo, required this.controller, required this.onSaldoChanged});
  @override State<TrafficHopperScreen> createState() => _TrafficHopperScreenState();
}

// ─── State ───────────────────────────────────────────────────────────────────

class _TrafficHopperScreenState extends State<TrafficHopperScreen> {
  // ── Grid constants ──────────────────────────────────────────────────────
  static const int kCols = 13;
  static const List<int> kLilyPadCols = [1, 3, 5, 7, 9];
  static const List<int> kRiverRows = [1, 2, 3, 4, 5];
  static const List<int> kRoadRows = [7, 8, 9, 10, 11];

  // ── State ───────────────────────────────────────────────────────────────
  late double _saldo;
  int _score = 0;
  int _hiScore = 0;
  int _lives = 3;
  int _level = 1;
  _GamePhase _phase = _GamePhase.start;

  // Frog position (col is floating for river drift)
  double _frogX = 6.0; // fractional column
  int _frogRow = 13;
  _Facing _frogFacing = _Facing.up;
  bool _deathFlash = false;

  // Score tracking per crossing
  int _highestRowThisCrossing = 13;

  // Lily pads filled this level
  final Set<int> _filledPads = {};

  // Game objects
  List<_Log> _logs = [];
  List<_Car> _cars = [];

  // Timers
  Timer? _tickTimer;
  Timer? _deathTimer;
  Timer? _levelCompleteTimer;

  final _rng = Random();

  // ── Init ────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _saldo = widget.currentSaldo;
    HighScoreService.load('hopper').then((v) => setState(() => _hiScore = v));
    widget.controller.addListener(_onControllerEvent);
    _initObjects();
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _deathTimer?.cancel();
    _levelCompleteTimer?.cancel();
    widget.controller.removeListener(_onControllerEvent);
    super.dispose();
  }

  // ── Object initialisation ───────────────────────────────────────────────

  void _initObjects() {
    _logs = _buildLogs();
    _cars = _buildCars();
  }

  List<_Log> _buildLogs() {
    final logs = <_Log>[];
    // Speed multiplier scales with level
    final sm = 1.0 + (_level - 1) * 0.15;

    // Rows 1,3,5 → move right; rows 2,4 → move left
    final rowConfigs = {
      1: (speed: 2.0 * sm, dir: 1),
      2: (speed: 1.8 * sm, dir: -1),
      3: (speed: 2.3 * sm, dir: 1),
      4: (speed: 1.6 * sm, dir: -1),
      5: (speed: 2.1 * sm, dir: 1),
    };

    for (final entry in rowConfigs.entries) {
      final r = entry.key;
      final spd = entry.value.speed * entry.value.dir.toDouble();
      final count = 2 + _rng.nextInt(2); // 2 or 3 logs
      double xPos = _rng.nextDouble() * kCols;
      for (int i = 0; i < count; i++) {
        final len = 2 + _rng.nextInt(2); // 2 or 3 cells
        logs.add(_Log(r, xPos, spd, len));
        xPos += len + 2 + _rng.nextDouble() * 3;
        if (xPos >= kCols) xPos -= kCols;
      }
    }
    return logs;
  }

  List<_Car> _buildCars() {
    final cars = <_Car>[];
    final sm = 1.0 + (_level - 1) * 0.18;

    final rowConfigs = {
      7:  (speed: 3.0 * sm, dir: -1, color: const Color(0xFFDD2222)),
      8:  (speed: 2.5 * sm, dir:  1, color: const Color(0xFF2244DD)),
      9:  (speed: 3.5 * sm, dir: -1, color: const Color(0xFFDDCC00)),
      10: (speed: 2.8 * sm, dir:  1, color: const Color(0xFF22AA44)),
      11: (speed: 4.0 * sm, dir: -1, color: const Color(0xFFEEEEEE)),
    };

    for (final entry in rowConfigs.entries) {
      final r = entry.key;
      final spd = entry.value.speed * entry.value.dir.toDouble();
      final col = entry.value.color;
      final count = 2 + _rng.nextInt(2);
      double xPos = _rng.nextDouble() * kCols;
      for (int i = 0; i < count; i++) {
        final len = 1 + _rng.nextInt(2); // 1 or 2 cells
        cars.add(_Car(r, xPos, spd, len, col));
        xPos += len + 2 + _rng.nextDouble() * 2;
        if (xPos >= kCols) xPos -= kCols;
      }
    }
    return cars;
  }

  // ── Game loop ───────────────────────────────────────────────────────────

  void _startTicker() {
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(const Duration(milliseconds: 16), (_) => _tick());
  }

  void _tick() {
    if (_phase != _GamePhase.playing) return;
    if (!mounted) return;

    const dt = 16.0 / 1000.0; // seconds per tick

    // Update log positions
    for (final log in _logs) {
      log.x += log.speed * dt;
      final gridWidth = kCols.toDouble();
      final logWidth = log.len.toDouble();
      if (log.speed > 0 && log.x > gridWidth) {
        log.x = -logWidth;
      } else if (log.speed < 0 && log.x < -logWidth) {
        log.x = gridWidth;
      }
    }

    // Update car positions
    for (final car in _cars) {
      car.x += car.speed * dt;
      final gridWidth = kCols.toDouble();
      final carWidth = car.len.toDouble();
      if (car.speed > 0 && car.x > gridWidth) {
        car.x = -carWidth;
      } else if (car.speed < 0 && car.x < -carWidth) {
        car.x = gridWidth;
      }
    }

    // Drift frog if on river
    if (kRiverRows.contains(_frogRow)) {
      final log = _logUnderFrog();
      if (log != null) {
        _frogX += log.speed * dt;
        // Kill if drifted off screen
        if (_frogX < -0.5 || _frogX > kCols - 0.5) {
          _triggerDeath();
          return;
        }
      } else {
        // Not on a log → die
        _triggerDeath();
        return;
      }
    }

    // Check road collision
    if (kRoadRows.contains(_frogRow)) {
      if (_carUnderFrog() != null) {
        _triggerDeath();
        return;
      }
    }

    setState(() {});
  }

  _Log? _logUnderFrog() {
    final frogCol = _frogX;
    for (final log in _logs) {
      if (log.row != _frogRow) continue;
      // log occupies cells [log.x .. log.x + log.len)
      if (frogCol + 0.4 > log.x && frogCol - 0.4 < log.x + log.len) {
        return log;
      }
    }
    return null;
  }

  _Car? _carUnderFrog() {
    final frogCol = _frogX;
    for (final car in _cars) {
      if (car.row != _frogRow) continue;
      if (frogCol + 0.3 > car.x && frogCol - 0.3 < car.x + car.len) {
        return car;
      }
    }
    return null;
  }

  // ── Input ───────────────────────────────────────────────────────────────

  void _onControllerEvent() {
    final event = widget.controller.lastEvent;
    if (event == null || !event.isDown) return;
    final btn = event.button;

    if (_phase == _GamePhase.start) {
      if (btn == ArcadeButton.a || btn == ArcadeButton.start ||
          btn == ArcadeButton.up || btn == ArcadeButton.down ||
          btn == ArcadeButton.left || btn == ArcadeButton.right) {
        _startGame();
      }
      return;
    }

    if (_phase == _GamePhase.dead) {
      if (btn == ArcadeButton.a || btn == ArcadeButton.start) {
        _restart();
      }
      return;
    }

    if (_phase == _GamePhase.levelComplete) return;

    // playing
    switch (btn) {
      case ArcadeButton.up:
        _moveFrog(0, -1, _Facing.up);
      case ArcadeButton.down:
        _moveFrog(0, 1, _Facing.down);
      case ArcadeButton.left:
        _moveFrog(-1, 0, _Facing.left);
      case ArcadeButton.right:
        _moveFrog(1, 0, _Facing.right);
      default:
        break;
    }
  }

  void _moveFrog(int dc, int dr, _Facing facing) {
    if (_phase != _GamePhase.playing) return;

    final newRow = (_frogRow + dr).clamp(0, 13);
    final newCol = (_frogX + dc).clamp(0.0, (kCols - 1).toDouble());

    setState(() {
      _frogX = newCol;
      _frogRow = newRow;
      _frogFacing = facing;
    });

    // Award row points only for new highest row reached
    if (_frogRow < _highestRowThisCrossing) {
      _score += 10;
      _highestRowThisCrossing = _frogRow;
    }

    // Check home row arrival
    if (_frogRow == 0) {
      _checkHomeRow();
    }
  }

  void _checkHomeRow() {
    final col = _frogX.round();
    if (kLilyPadCols.contains(col)) {
      // Valid lily pad
      if (_filledPads.contains(col)) {
        // Already filled — treat as death
        _triggerDeath();
        return;
      }
      setState(() {
        _filledPads.add(col);
        _score += 200;
      });
      HapticFeedback.mediumImpact();
      if (_filledPads.length >= 5) {
        _levelComplete();
      } else {
        _respawnFrog();
      }
    } else {
      // Not a lily pad
      _triggerDeath();
    }
  }

  void _respawnFrog() {
    setState(() {
      _frogX = 6.0;
      _frogRow = 13;
      _frogFacing = _Facing.up;
      _highestRowThisCrossing = 13;
    });
  }

  // ── Death ───────────────────────────────────────────────────────────────

  void _triggerDeath() {
    HapticFeedback.heavyImpact();
    setState(() => _deathFlash = true);

    _deathTimer?.cancel();
    _deathTimer = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      setState(() {
        _deathFlash = false;
        _lives--;
      });
      if (_lives <= 0) {
        _gameOver();
      } else {
        _respawnFrog();
      }
    });
  }

  void _gameOver() {
    _tickTimer?.cancel();
    HighScoreService.submit('hopper', _score);
    setState(() {
      _phase = _GamePhase.dead;
      if (_score > _hiScore) _hiScore = _score;
    });
  }

  // ── Level complete ──────────────────────────────────────────────────────

  void _levelComplete() {
    _tickTimer?.cancel();
    setState(() {
      _score += 500;
      _phase = _GamePhase.levelComplete;
    });

    // Award saldo
    final newSaldo = _saldo + 1.0;
    _updateFirestore(newSaldo);
    if (mounted) {
      setState(() => _saldo = newSaldo);
      widget.onSaldoChanged(newSaldo);
    }

    _levelCompleteTimer?.cancel();
    _levelCompleteTimer = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      setState(() {
        _level++;
        _filledPads.clear();
        _phase = _GamePhase.playing;
      });
      _initObjects(); // rebuild with faster speeds
      _respawnFrog();
      _startTicker();
    });
  }

  // ── Start / Restart ─────────────────────────────────────────────────────

  void _startGame() {
    setState(() {
      _score = 0;
      _lives = 3;
      _level = 1;
      _filledPads.clear();
      _highestRowThisCrossing = 13;
      _phase = _GamePhase.playing;
    });
    _initObjects();
    _respawnFrog();
    _startTicker();
  }

  void _restart() {
    _tickTimer?.cancel();
    _startGame();
  }

  // ── Firestore ───────────────────────────────────────────────────────────

  Future<void> _updateFirestore(double newSaldo) async {
    try {
      final userCardRef = FirebaseFirestore.instance.collection('users').doc(widget.userId).collection('rewardsCard').doc('cardInfo');
      final batch = FirebaseFirestore.instance.batch();
      batch.update(userCardRef, {'saldo': newSaldo});
      batch.update(widget.rewardsDocRef, {'saldo': newSaldo});
      await batch.commit();
    } catch (e) { debugPrint('Hopper Firestore: $e'); }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _buildCanvas(),
        _buildScoreBar(),
        if (_phase == _GamePhase.start) _buildStartOverlay(),
        if (_phase == _GamePhase.dead) _buildGameOverOverlay(),
        if (_phase == _GamePhase.levelComplete) _buildLevelCompleteOverlay(),
      ],
    );
  }

  Widget _buildScoreBar() {
    return Positioned(
      top: 0, left: 0, right: 0,
      child: Container(
        color: Colors.black.withOpacity(0.65),
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: Text(
          'Lvl $_level  ·  Score: $_score  ·  Best: $_hiScore  ·  Lives: $_lives  ·  ${_saldo.toStringAsFixed(0)} pts',
          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildCanvas() {
    return LayoutBuilder(builder: (ctx, constraints) {
      return CustomPaint(
        painter: _HopperPainter(
          logs: _logs,
          cars: _cars,
          frogX: _frogX,
          frogRow: _frogRow,
          frogFacing: _frogFacing,
          deathFlash: _deathFlash,
          filledPads: _filledPads,
          phase: _phase,
        ),
        child: SizedBox(width: constraints.maxWidth, height: constraints.maxHeight),
      );
    });
  }

  Widget _buildStartOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.82),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('CRUCE PELIGROSO 🐸',
                style: TextStyle(color: Colors.greenAccent, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 2)),
            const SizedBox(height: 20),
            const Text('D-pad: mover rana', style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 6),
            const Text('Llega a las 5 ranas en la orilla', style: TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 6),
            const Text('+1 pto por nivel', style: TextStyle(color: Colors.amber, fontSize: 12)),
            const SizedBox(height: 28),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: SizedBox(width: double.infinity,
                child: ElevatedButton(
                  onPressed: _startGame,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white, shape: const StadiumBorder()),
                  child: const Text('Nueva Partida'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGameOverOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.88),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('GAME OVER', style: TextStyle(color: Colors.red, fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 4)),
            const SizedBox(height: 16),
            Text('Puntuación: $_score', style: const TextStyle(color: Colors.white, fontSize: 20)),
            const SizedBox(height: 6),
            Text('Mejor: $_hiScore', style: const TextStyle(color: Colors.white54, fontSize: 16)),
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: SizedBox(width: double.infinity,
                child: ElevatedButton(
                  onPressed: _restart,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white, shape: const StadiumBorder()),
                  child: const Text('Nueva Partida'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLevelCompleteOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.75),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('¡NIVEL $_level!',
                style: const TextStyle(color: Colors.greenAccent, fontSize: 36, fontWeight: FontWeight.bold, letterSpacing: 4)),
            const SizedBox(height: 12),
            const Text('+500 pts  ·  +1 pto', style: TextStyle(color: Colors.amber, fontSize: 18)),
          ],
        ),
      ),
    );
  }
}

// ─── Painter ─────────────────────────────────────────────────────────────────

class _HopperPainter extends CustomPainter {
  final List<_Log> logs;
  final List<_Car> cars;
  final double frogX;
  final int frogRow;
  final _Facing frogFacing;
  final bool deathFlash;
  final Set<int> filledPads;
  final _GamePhase phase;

  _HopperPainter({
    required this.logs,
    required this.cars,
    required this.frogX,
    required this.frogRow,
    required this.frogFacing,
    required this.deathFlash,
    required this.filledPads,
    required this.phase,
  });

  // Cell size computed from canvas size
  double _cs(Size size) => min(size.width / 13, size.height / 14).floorToDouble();
  double _ox(Size size) => ((size.width - _cs(size) * 13) / 2).floorToDouble();
  double _oy(Size size) => ((size.height - _cs(size) * 14) / 2).floorToDouble();

  @override
  void paint(Canvas canvas, Size size) {
    final cs = _cs(size);
    final ox = _ox(size);
    final oy = _oy(size);

    // Background
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = const Color(0xFF111111));

    // Draw rows
    for (int row = 0; row < 14; row++) {
      final rowColor = _rowColor(row);
      final rect = Rect.fromLTWH(ox, oy + row * cs, cs * 13, cs);
      canvas.drawRect(rect, Paint()..color = rowColor);
    }

    // Road dashes (rows 7-11)
    final dashPaint = Paint()..color = const Color(0xFFFFFFFF);
    for (int row = 7; row <= 11; row++) {
      final y = oy + row * cs + cs * 0.5 - 1;
      for (int col = 0; col < 13; col += 3) {
        canvas.drawRect(Rect.fromLTWH(ox + col * cs + cs * 0.1, y, cs * 1.8, 2), dashPaint);
      }
    }

    // Lily pads (row 0)
    _drawLilyPads(canvas, ox, oy, cs);

    // Logs
    _drawLogs(canvas, ox, oy, cs);

    // Cars
    _drawCars(canvas, ox, oy, cs);

    // Frog (only during playing/levelComplete or after respawn while dead-flash ends)
    if (phase == _GamePhase.playing || phase == _GamePhase.levelComplete) {
      _drawFrog(canvas, ox, oy, cs);
    } else if (phase == _GamePhase.dead && deathFlash) {
      _drawFrog(canvas, ox, oy, cs);
    }
  }

  Color _rowColor(int row) {
    if (row == 0) return const Color(0xFF1A6B1A);
    if (row >= 1 && row <= 5) return const Color(0xFF0055AA);
    if (row == 6) return const Color(0xFF2D5016);
    if (row >= 7 && row <= 11) return const Color(0xFF333333);
    if (row == 12) return const Color(0xFF2D5016);
    return const Color(0xFF2D5016); // row 13
  }

  void _drawLilyPads(Canvas canvas, double ox, double oy, double cs) {
    for (final col in [1, 3, 5, 7, 9]) {
      final filled = filledPads.contains(col);
      final cx = ox + col * cs + cs / 2;
      final cy = oy + cs / 2;
      final padColor = filled ? const Color(0xFF32CD32) : const Color(0xFF228B22);
      canvas.drawRect(
        Rect.fromCenter(center: Offset(cx, cy), width: cs * 0.8, height: cs * 0.6),
        Paint()..color = padColor,
      );
      if (filled) {
        // Yellow dot
        canvas.drawRect(
          Rect.fromCenter(center: Offset(cx, cy), width: cs * 0.25, height: cs * 0.25),
          Paint()..color = const Color(0xFFFFFF00),
        );
      }
    }
  }

  void _drawLogs(Canvas canvas, double ox, double oy, double cs) {
    final logPaint = Paint()..color = const Color(0xFF8B4513);
    final highlightPaint = Paint()..color = const Color(0xFFA0522D);

    for (final log in logs) {
      final x = ox + log.x * cs;
      final y = oy + log.row * cs;
      final w = log.len * cs;

      canvas.drawRect(Rect.fromLTWH(x, y + cs * 0.1, w, cs * 0.8), logPaint);
      // Pixel highlight on top
      canvas.drawRect(Rect.fromLTWH(x, y + cs * 0.1, w, cs * 0.15), highlightPaint);
    }
  }

  void _drawCars(Canvas canvas, double ox, double oy, double cs) {
    for (final car in cars) {
      final x = ox + car.x * cs;
      final y = oy + car.row * cs;
      final w = car.len * cs;

      final bodyPaint = Paint()..color = car.color;
      canvas.drawRect(Rect.fromLTWH(x + 1, y + cs * 0.2, w - 2, cs * 0.65), bodyPaint);

      // Windows (dark rectangles)
      final windowPaint = Paint()..color = const Color(0xFF222222);
      final winW = (w - 6) / 2;
      if (winW > 2) {
        canvas.drawRect(Rect.fromLTWH(x + 3, y + cs * 0.25, winW, cs * 0.25), windowPaint);
        canvas.drawRect(Rect.fromLTWH(x + 3 + winW + 2, y + cs * 0.25, winW, cs * 0.25), windowPaint);
      }
    }
  }

  void _drawFrog(Canvas canvas, double ox, double oy, double cs) {
    final frogColor = deathFlash ? const Color(0xFFFF2200) : const Color(0xFF00AA00);
    final frogPaint = Paint()..color = frogColor;

    final fx = ox + frogX * cs;
    final fy = oy + frogRow * cs;
    final bodySize = cs * 0.7;
    final bodyOffset = (cs - bodySize) / 2;

    canvas.drawRect(
      Rect.fromLTWH(fx + bodyOffset, fy + bodyOffset, bodySize, bodySize),
      frogPaint,
    );

    // Eyes (white 2px dots)
    final eyePaint = Paint()..color = const Color(0xFFFFFFFF);
    final eyeSize = 2.0;

    // Eye positions depend on facing direction
    switch (frogFacing) {
      case _Facing.up:
        canvas.drawRect(Rect.fromLTWH(fx + bodyOffset + bodySize * 0.2, fy + bodyOffset + bodySize * 0.1, eyeSize, eyeSize), eyePaint);
        canvas.drawRect(Rect.fromLTWH(fx + bodyOffset + bodySize * 0.7, fy + bodyOffset + bodySize * 0.1, eyeSize, eyeSize), eyePaint);
      case _Facing.down:
        canvas.drawRect(Rect.fromLTWH(fx + bodyOffset + bodySize * 0.2, fy + bodyOffset + bodySize * 0.75, eyeSize, eyeSize), eyePaint);
        canvas.drawRect(Rect.fromLTWH(fx + bodyOffset + bodySize * 0.7, fy + bodyOffset + bodySize * 0.75, eyeSize, eyeSize), eyePaint);
      case _Facing.left:
        canvas.drawRect(Rect.fromLTWH(fx + bodyOffset + bodySize * 0.1, fy + bodyOffset + bodySize * 0.2, eyeSize, eyeSize), eyePaint);
        canvas.drawRect(Rect.fromLTWH(fx + bodyOffset + bodySize * 0.1, fy + bodyOffset + bodySize * 0.65, eyeSize, eyeSize), eyePaint);
      case _Facing.right:
        canvas.drawRect(Rect.fromLTWH(fx + bodyOffset + bodySize * 0.75, fy + bodyOffset + bodySize * 0.2, eyeSize, eyeSize), eyePaint);
        canvas.drawRect(Rect.fromLTWH(fx + bodyOffset + bodySize * 0.75, fy + bodyOffset + bodySize * 0.65, eyeSize, eyeSize), eyePaint);
    }
  }

  @override
  bool shouldRepaint(_HopperPainter old) => true;
}
