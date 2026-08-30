import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'arcade_center_screen.dart' show AppLanguage;
import 'arcade_input_controller.dart';
import 'game_saldo.dart';
import 'high_score_service.dart';

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

class TrafficHopperScreen extends StatefulWidget {
  final String userId;
  final DocumentReference rewardsDocRef;
  final double currentSaldo;
  final ArcadeInputController controller;
  final void Function(double) onSaldoChanged;
  final AppLanguage language;
  const TrafficHopperScreen({super.key, required this.userId, required this.rewardsDocRef,
      required this.currentSaldo, required this.controller, required this.onSaldoChanged,
      this.language = AppLanguage.spanish});
  @override State<TrafficHopperScreen> createState() => _TrafficHopperScreenState();
}

class _TrafficHopperScreenState extends State<TrafficHopperScreen> {
  static const int kCols = 13;
  static const List<int> kLilyPadCols = [1, 3, 5, 7, 9];
  static const List<int> kRiverRows = [1, 2, 3, 4, 5];
  static const List<int> kRoadRows = [7, 8, 9, 10, 11];

  late double _saldo;
  late double _lastCommitted;
  int _score = 0;
  int _hiScore = 0;
  int _lives = 3;
  int _level = 1;
  _GamePhase _phase = _GamePhase.start;
  bool _paused = false;

  double _frogX = 6.0;
  int _frogRow = 13;
  _Facing _frogFacing = _Facing.up;
  bool _deathFlash = false;

  int _highestRowThisCrossing = 13;

  final Set<int> _filledPads = {};

  List<_Log> _logs = [];
  List<_Car> _cars = [];

  Timer? _tickTimer;
  Timer? _deathTimer;
  Timer? _levelCompleteTimer;

  final _rng = Random();

  String _t(String es, String en) =>
      widget.language == AppLanguage.spanish ? es : en;

  @override
  void initState() {
    super.initState();
    _saldo = widget.currentSaldo;
    _lastCommitted = widget.currentSaldo;
    HighScoreService.load('hopper').then((v) {
      if (!mounted) return;
      setState(() => _hiScore = v);
    });
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

  void _initObjects() {
    _logs = _buildLogs();
    _cars = _buildCars();
  }

  List<_Log> _buildLogs() {
    final logs = <_Log>[];
    final sm = 1.0 + (_level - 1) * 0.15;

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
      final count = 2 + _rng.nextInt(2);
      double xPos = _rng.nextDouble() * kCols;
      for (int i = 0; i < count; i++) {
        final len = 2 + _rng.nextInt(2);
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
      7:  (speed: 3.4 * sm, dir: -1, color: const Color(0xFFDD2222)),
      8:  (speed: 2.9 * sm, dir:  1, color: const Color(0xFF2244DD)),
      9:  (speed: 4.0 * sm, dir: -1, color: const Color(0xFFDDCC00)),
      10: (speed: 3.2 * sm, dir:  1, color: const Color(0xFF22AA44)),
      11: (speed: 4.6 * sm, dir: -1, color: const Color(0xFFEEEEEE)),
    };

    for (final entry in rowConfigs.entries) {
      final r = entry.key;
      final spd = entry.value.speed * entry.value.dir.toDouble();
      final col = entry.value.color;
      final count = 2 + _rng.nextInt(2);
      double xPos = _rng.nextDouble() * kCols;
      for (int i = 0; i < count; i++) {
        final len = 1 + _rng.nextInt(2);
        cars.add(_Car(r, xPos, spd, len, col));
        xPos += len + 2 + _rng.nextDouble() * 2;
        if (xPos >= kCols) xPos -= kCols;
      }
    }
    return cars;
  }

  void _startTicker() {
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(const Duration(milliseconds: 16), (_) => _tick());
  }

  void _tick() {
    if (_phase != _GamePhase.playing || _paused) return;
    if (!mounted) return;

    const dt = 16.0 / 1000.0;

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

    if (kRiverRows.contains(_frogRow)) {
      final log = _logUnderFrog();
      if (log != null) {
        _frogX += log.speed * dt;
        if (_frogX < -0.5 || _frogX > kCols - 0.5) {
          _triggerDeath();
          return;
        }
      } else {
        _triggerDeath();
        return;
      }
    }

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

    if (btn == ArcadeButton.start) {
      setState(() => _paused = !_paused);
      return;
    }
    if (_paused) return;

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

    if (_frogRow < _highestRowThisCrossing) {
      _score += 10;
      _highestRowThisCrossing = _frogRow;
    }

    if (_frogRow == 0) {
      _checkHomeRow();
    }
  }

  void _checkHomeRow() {
    final col = _frogX.round();
    if (kLilyPadCols.contains(col)) {
      if (_filledPads.contains(col)) {
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

  void _levelComplete() {
    _tickTimer?.cancel();
    setState(() {
      _score += 500;
      _phase = _GamePhase.levelComplete;
    });

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
      _initObjects();
      _respawnFrog();
      _startTicker();
    });
  }

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

  Future<void> _restart() async {
    final ns = await chargeForReplay(
        userId: widget.userId,
        rewardsDocRef: widget.rewardsDocRef,
        currentSaldo: _saldo);
    if (ns == null) return;
    if (!mounted) return;
    setState(() => _saldo = ns);

    _lastCommitted = ns;
    widget.onSaldoChanged(ns);
    _tickTimer?.cancel();
    _startGame();
  }

  Future<void> _updateFirestore(double newSaldo) async {

    final delta = newSaldo - _lastCommitted;
    if (delta == 0) return;
    final result = await applyArcadeDelta(
      delta: delta,
      reason: 'traffic_hopper',
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
    return Stack(
      children: [
        _buildCanvas(),
        _buildScoreBar(),
        if (_phase == _GamePhase.start) _buildStartOverlay(),
        if (_phase == _GamePhase.dead) _buildGameOverOverlay(),
        if (_phase == _GamePhase.levelComplete) _buildLevelCompleteOverlay(),
        if (_paused && _phase == _GamePhase.playing) _buildPauseOverlay(),
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
          _t(
            'Niv $_level  ·  Puntos: $_score  ·  Mejor: $_hiScore  ·  Vidas: $_lives  ·  ${_saldo.toStringAsFixed(0)} pts',
            'Lvl $_level  ·  Score: $_score  ·  Best: $_hiScore  ·  Lives: $_lives  ·  ${_saldo.toStringAsFixed(0)} pts',
          ),
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
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xEE115500), Color(0xEE004488)],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🐸', style: TextStyle(fontSize: 60)),
            const SizedBox(height: 8),
            Text(_t('RANA SALTARINA', 'HOPPING FROG'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold,
                letterSpacing: 4,
                shadows: [Shadow(color: Color(0xFF004400), blurRadius: 8)],
              )),
            const SizedBox(height: 4),
            Text(_t('Cruza el río y la carretera', 'Cross the river and the road'),
              style: const TextStyle(color: Color(0xFF88DDAA), fontSize: 12, letterSpacing: 1)),
            const SizedBox(height: 22),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 28),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.35),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green.withOpacity(0.4), width: 1),
              ),
              child: Column(children: [
                Text(_t('D-pad: mover la rana', 'D-pad: move the frog'),
                  style: const TextStyle(color: Colors.white, fontSize: 13)),
                const SizedBox(height: 5),
                Text(_t('Sube a los troncos para cruzar el río', 'Ride the logs to cross the river'),
                  style: const TextStyle(color: Color(0xFF88DDAA), fontSize: 11),
                  textAlign: TextAlign.center),
                const SizedBox(height: 5),
                Text(_t('Evita los coches en la carretera', 'Dodge the cars on the road'),
                  style: const TextStyle(color: Color(0xFFFFAA44), fontSize: 11),
                  textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(_t('+1 PTO REAL POR NIVEL', '+1 REAL POINT PER LEVEL'),
                  style: const TextStyle(color: Color(0xFFFFDD44), fontSize: 12, fontWeight: FontWeight.bold)),
              ]),
            ),
            const SizedBox(height: 20),
            Text(_t('¡Lleva 5 ranas a la orilla para ganar!', 'Get 5 frogs home to win!'),
              style: const TextStyle(color: Color(0xFF44AA66), fontSize: 11)),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: SizedBox(width: double.infinity,
                child: ElevatedButton(
                  onPressed: _startGame,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF22AA44),
                    foregroundColor: Colors.white,
                    shape: const StadiumBorder()),
                  child: Text(_t('¡A Saltar!', "Let's Hop!"),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
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
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black.withOpacity(0.90), const Color(0xDD220800)],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🚗', style: TextStyle(fontSize: 40)),
            const Text('💀', style: TextStyle(fontSize: 28)),
            const SizedBox(height: 8),
            Text(_t('¡APLASTADA!', 'SQUASHED!'),
              style: const TextStyle(
                color: Color(0xFFFF3300),
                fontSize: 30,
                fontWeight: FontWeight.bold,
                letterSpacing: 3,
              )),
            const SizedBox(height: 4),
            Text(_t('La rana no logró cruzar', 'The frog never made it across'),
              style: const TextStyle(color: Color(0xFF884433), fontSize: 11)),
            const SizedBox(height: 18),
            Text(_t('Puntuación: $_score', 'Score: $_score'),
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(_t('Récord: $_hiScore', 'Best: $_hiScore'),
              style: const TextStyle(color: Color(0xFFFFD700), fontSize: 14)),
            const SizedBox(height: 28),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: SizedBox(width: double.infinity,
                child: ElevatedButton(
                  onPressed: _restart,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF22AA44),
                    foregroundColor: Colors.white,
                    shape: const StadiumBorder()),
                  child: Text(_t('Volver a Saltar', 'Hop Again'),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
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
            Text(_t('¡NIVEL $_level!', 'LEVEL $_level!'),
                style: const TextStyle(color: Colors.greenAccent, fontSize: 36, fontWeight: FontWeight.bold, letterSpacing: 4)),
            const SizedBox(height: 12),
            Text(_t('+500 pts  ·  +1 pto', '+500 pts  ·  +1 point'),
                style: const TextStyle(color: Colors.amber, fontSize: 18)),
          ],
        ),
      ),
    );
  }

  Widget _buildPauseOverlay() => Positioned.fill(
    child: Container(
      color: const Color(0xCC000000),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('⏸', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 8),
          Text(_t('PAUSA', 'PAUSED'),
              style: const TextStyle(color: Colors.greenAccent, fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 6)),
          const SizedBox(height: 16),
          Text(_t('START para continuar', 'START to continue'),
              style: const TextStyle(color: Color(0xFF336633), fontSize: 12)),
        ],
      ),
    ),
  );
}

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

  double _cs(Size size) => min(size.width / 13, size.height / 14).floorToDouble();
  double _ox(Size size) => ((size.width - _cs(size) * 13) / 2).floorToDouble();
  double _oy(Size size) => ((size.height - _cs(size) * 14) / 2).floorToDouble();

  @override
  void paint(Canvas canvas, Size size) {
    final cs = _cs(size);
    final ox = _ox(size);
    final oy = _oy(size);
    final p = Paint()..isAntiAlias = false;

    p.color = const Color(0xFF0A0A12);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), p);

    for (int row = 0; row < 14; row++) {
      _drawTerrainRow(canvas, p, ox, oy, cs, row);
    }

    _drawRoadMarkings(canvas, p, ox, oy, cs);

    _drawLilyPads(canvas, ox, oy, cs);

    _drawLogs(canvas, ox, oy, cs);

    _drawCars(canvas, ox, oy, cs);

    if (phase == _GamePhase.playing || phase == _GamePhase.levelComplete) {
      _drawFrog(canvas, ox, oy, cs);
    } else if (phase == _GamePhase.dead && deathFlash) {
      _drawFrog(canvas, ox, oy, cs);
    }
  }

  void _drawTerrainRow(Canvas canvas, Paint p, double ox, double oy, double cs, int row) {
    final x = ox;
    final y = oy + row * cs;
    final w = cs * 13;

    if (row == 0) {
      p.color = const Color(0xFF155A15);
      canvas.drawRect(Rect.fromLTWH(x, y, w, cs), p);
      p.color = const Color(0xFF1E7A1E);
      canvas.drawRect(Rect.fromLTWH(x, y, w, cs * 0.22), p);
      p.color = const Color(0xFF0A2E0A);
      canvas.drawRect(Rect.fromLTWH(x, y + cs * 0.90, w, cs * 0.10), p);
      p.color = const Color(0xFF3AAA3A);
      for (double bx = x + 1; bx < x + w - 1; bx += 4) {
        canvas.drawRect(Rect.fromLTWH(bx, y + 1, 1.5, cs * 0.14), p);
      }
      for (final emptyCol in [0, 2, 4, 6, 8, 10, 11, 12]) {
        p.color = const Color(0xFF0B3A0B);
        canvas.drawRect(Rect.fromLTWH(ox + emptyCol * cs + cs * 0.05, y + cs * 0.14,
            cs * 0.90, cs * 0.72), p);
      }
    } else if (row >= 1 && row <= 5) {
      final baseBlue = row.isOdd ? const Color(0xFF003880) : const Color(0xFF00408A);
      p.color = baseBlue;
      canvas.drawRect(Rect.fromLTWH(x, y, w, cs), p);
      p.color = const Color(0xFF1A5DC4);
      canvas.drawRect(Rect.fromLTWH(x, y, w, cs * 0.09), p);
      p.color = const Color(0xFF001E55);
      canvas.drawRect(Rect.fromLTWH(x, y + cs * 0.88, w, cs * 0.12), p);
      p.color = const Color(0x304488DD);
      canvas.drawRect(Rect.fromLTWH(x, y + cs * 0.28, w, cs * 0.07), p);
      canvas.drawRect(Rect.fromLTWH(x, y + cs * 0.60, w, cs * 0.05), p);
      p.color = const Color(0x3866AAEE);
      final rippleOffset = row * 13.0 % 9;
      for (double rx = x + rippleOffset; rx < x + w - cs * 0.3; rx += cs * 1.1) {
        canvas.drawRect(Rect.fromLTWH(rx, y + cs * 0.43, cs * 0.38, 1.5), p);
      }
    } else if (row == 6) {
      p.color = const Color(0xFF2A5512);
      canvas.drawRect(Rect.fromLTWH(x, y, w, cs), p);
      p.color = const Color(0xFF3A7A1A);
      canvas.drawRect(Rect.fromLTWH(x, y + cs * 0.12, w, cs * 0.76), p);
      p.color = const Color(0xFFDDAA00);
      canvas.drawRect(Rect.fromLTWH(x, y, w, cs * 0.06), p);
      canvas.drawRect(Rect.fromLTWH(x, y + cs * 0.94, w, cs * 0.06), p);
      p.color = const Color(0xFF55BB22);
      for (double bx = x + 2; bx < x + w - 1; bx += 4) {
        canvas.drawRect(Rect.fromLTWH(bx, y + cs * 0.16, 1.5, cs * 0.16), p);
      }
    } else if (row >= 7 && row <= 11) {
      p.color = const Color(0xFF232323);
      canvas.drawRect(Rect.fromLTWH(x, y, w, cs), p);
      p.color = const Color(0xFF2B2B2B);
      for (double tx = x; tx < x + w; tx += cs * 0.85) {
        canvas.drawRect(Rect.fromLTWH(tx, y + cs * 0.10, cs * 0.42, cs * 0.80), p);
      }
      if (row == 7) {
        p.color = const Color(0xFFDDDDDD);
        canvas.drawRect(Rect.fromLTWH(x, y, w, cs * 0.045), p);
      }
      if (row == 11) {
        p.color = const Color(0xFFDDDDDD);
        canvas.drawRect(Rect.fromLTWH(x, y + cs * 0.955, w, cs * 0.045), p);
      }
    } else {
      p.color = const Color(0xFF1A5A1A);
      canvas.drawRect(Rect.fromLTWH(x, y, w, cs), p);
      p.color = const Color(0xFF237823);
      canvas.drawRect(Rect.fromLTWH(x, y, w, cs * 0.22), p);
      if (row == 12) {
        p.color = const Color(0xFFB0B0B0);
        canvas.drawRect(Rect.fromLTWH(x, y + cs * 0.94, w, cs * 0.06), p);
      }
      if (row == 13) {
        p.color = const Color(0xFF0A300A);
        canvas.drawRect(Rect.fromLTWH(x, y + cs * 0.94, w, cs * 0.06), p);
      }
      p.color = const Color(0xFF44BB33);
      final bOff = row == 12 ? 1.0 : 3.0;
      for (double bx = x + bOff; bx < x + w - 1; bx += 4) {
        canvas.drawRect(Rect.fromLTWH(bx, y + 1, 1.5, cs * 0.13), p);
      }
    }
  }

  void _drawRoadMarkings(Canvas canvas, Paint p, double ox, double oy, double cs) {
    for (int row = 7; row <= 10; row++) {
      final y = oy + (row + 1) * cs - 1.5;
      p.color = const Color(0xBBFFFFFF);
      for (double dx = ox + cs * 0.15; dx < ox + cs * 13 - cs * 0.15; dx += cs * 1.5) {
        canvas.drawRect(Rect.fromLTWH(dx, y, cs * 0.85, 2.5), p);
      }
    }
    final yC = oy + 10 * cs - 1.5;
    p.color = const Color(0xFFDDAA00);
    canvas.drawRect(Rect.fromLTWH(ox, yC - 2.5, cs * 13, 2.0), p);
    canvas.drawRect(Rect.fromLTWH(ox, yC + 1.5, cs * 13, 2.0), p);
  }

  void _drawLilyPads(Canvas canvas, double ox, double oy, double cs) {
    final p = Paint()..isAntiAlias = false;
    for (final col in [1, 3, 5, 7, 9]) {
      final filled = filledPads.contains(col);
      final cx = ox + col * cs + cs / 2;
      final cy = oy + cs / 2;
      final r = cs * 0.42;

      const bands = 9;
      for (int bi = 0; bi < bands; bi++) {
        final t = (bi / (bands - 1)) * 2.0 - 1.0;
        final halfW = r * sqrt(max(0, 1.0 - t * t * 0.55));
        final bandY = cy - r + bi * (r * 2.0 / (bands - 1));
        final bandH = (r * 2.0 / (bands - 1)) + 1;

        final isNotchRow = bi < 3;
        if (isNotchRow && halfW > r * 0.3) {
          p.color = bi < 2
              ? (filled ? const Color(0xFF50D050) : const Color(0xFF2A9A2A))
              : (filled ? const Color(0xFF38C038) : const Color(0xFF1E8A1E));
          canvas.drawRect(Rect.fromLTWH(cx - halfW, bandY, halfW * 0.65, bandH), p);
        } else {
          p.color = bi < 2
              ? (filled ? const Color(0xFF50D050) : const Color(0xFF2A9A2A))
              : bi > bands - 3
                  ? (filled ? const Color(0xFF1A8A1A) : const Color(0xFF146414))
                  : (filled ? const Color(0xFF38C038) : const Color(0xFF1E8A1E));
          canvas.drawRect(Rect.fromLTWH(cx - halfW, bandY, halfW * 2.0, bandH), p);
        }
      }

      p.color = filled ? const Color(0xFF66EE66) : const Color(0xFF2AA82A);
      canvas.drawRect(Rect.fromLTWH(cx - 0.75, cy - r * 0.85, 1.5, r * 0.85), p);
      canvas.drawRect(Rect.fromLTWH(cx - r * 0.85, cy - 0.75, r * 0.85, 1.5), p);
      canvas.drawRect(Rect.fromLTWH(cx - 0.75, cy, 1.5, r * 0.80), p);
      canvas.drawRect(Rect.fromLTWH(cx, cy - 0.75, r * 0.80, 1.5), p);

      if (filled) {
        p.color = const Color(0xFFFFEE00);
        canvas.drawRect(Rect.fromCenter(center: Offset(cx, cy), width: r * 0.55, height: r * 0.55), p);
        p.color = const Color(0xFFFF9900);
        canvas.drawRect(Rect.fromCenter(center: Offset(cx, cy), width: r * 0.22, height: r * 1.0), p);
        canvas.drawRect(Rect.fromCenter(center: Offset(cx, cy), width: r * 1.0, height: r * 0.22), p);
      } else {
        p.color = const Color(0xFFEEEEAA);
        canvas.drawRect(Rect.fromCenter(center: Offset(cx, cy), width: r * 0.22, height: r * 0.22), p);
      }
    }
  }

  void _drawLogs(Canvas canvas, double ox, double oy, double cs) {
    final p = Paint()..isAntiAlias = false;
    for (final log in logs) {
      final x = ox + log.x * cs;
      final y = oy + log.row * cs;
      final w = log.len * cs;
      final logTop = y + cs * 0.10;
      final logH = cs * 0.80;

      p.color = const Color(0x55000033);
      canvas.drawRect(Rect.fromLTWH(x + 2, logTop + logH, w - 2, cs * 0.06), p);

      p.color = const Color(0xFF7A3A10);
      canvas.drawRect(Rect.fromLTWH(x, logTop, w, logH), p);
      p.color = const Color(0xFFA05028);
      canvas.drawRect(Rect.fromLTWH(x, logTop, w, logH * 0.18), p);
      p.color = const Color(0xFF4A2008);
      canvas.drawRect(Rect.fromLTWH(x, logTop + logH * 0.82, w, logH * 0.18), p);

      p.color = const Color(0xFF5A2808);
      final grainCount = (logH / 5).floor().clamp(2, 6);
      for (int i = 1; i < grainCount; i++) {
        final lineY = logTop + (logH * i / grainCount);
        canvas.drawRect(Rect.fromLTWH(x + 2, lineY, w - 4, 1.5), p);
      }
      p.color = const Color(0xFF4A2008);
      final crackSpacing = cs * 0.85;
      for (double cx2 = x + crackSpacing; cx2 < x + w - cs * 0.3; cx2 += crackSpacing) {
        canvas.drawRect(Rect.fromLTWH(cx2, logTop + logH * 0.2, 1.5, logH * 0.6), p);
      }
      p.color = const Color(0xFF3A1A06);
      canvas.drawRect(Rect.fromLTWH(x, logTop, cs * 0.18, logH), p);
      canvas.drawRect(Rect.fromLTWH(x + w - cs * 0.18, logTop, cs * 0.18, logH), p);
      p.color = const Color(0xFF6A3018);
      canvas.drawRect(Rect.fromLTWH(x + cs * 0.06, logTop + logH * 0.25, cs * 0.06, logH * 0.50), p);
      canvas.drawRect(Rect.fromLTWH(x + w - cs * 0.12, logTop + logH * 0.25, cs * 0.06, logH * 0.50), p);
    }
  }

  void _drawCars(Canvas canvas, double ox, double oy, double cs) {
    final p = Paint()..isAntiAlias = false;
    for (final car in cars) {
      final x = ox + car.x * cs;
      final y = oy + car.row * cs;
      final w = car.len * cs;
      final goingRight = car.speed > 0;

      p.color = const Color(0x55000000);
      canvas.drawRect(Rect.fromLTWH(x + 2, y + cs * 0.83, w - 2, cs * 0.13), p);

      p.color = car.color;
      canvas.drawRect(Rect.fromLTWH(x + 1, y + cs * 0.21, w - 2, cs * 0.58), p);

      p.color = _lightenColor(car.color, 0.28);
      canvas.drawRect(Rect.fromLTWH(x + 1, y + cs * 0.21, w - 2, cs * 0.09), p);

      p.color = _darkenColor(car.color, 0.38);
      canvas.drawRect(Rect.fromLTWH(x + 1, y + cs * 0.68, w - 2, cs * 0.11), p);

      if (w > cs * 1.1) {
        final cabX = x + w * 0.22;
        final cabW = w * 0.56;
        p.color = _darkenColor(car.color, 0.18);
        canvas.drawRect(Rect.fromLTWH(cabX, y + cs * 0.09, cabW, cs * 0.12), p);
        p.color = const Color(0xFF7ABFE0);
        canvas.drawRect(Rect.fromLTWH(cabX + 1, y + cs * 0.10, cabW * 0.43, cs * 0.10), p);
        canvas.drawRect(Rect.fromLTWH(cabX + cabW - cabW * 0.40, y + cs * 0.10, cabW * 0.38, cs * 0.10), p);
        p.color = const Color(0x99FFFFFF);
        canvas.drawRect(Rect.fromLTWH(cabX + 2, y + cs * 0.11, cabW * 0.10, cs * 0.04), p);
      }

      final frontX = goingRight ? x + w - cs * 0.16 : x + cs * 0.04;
      final rearX  = goingRight ? x + cs * 0.04     : x + w - cs * 0.16;
      p.color = const Color(0xFFFFFF88);
      canvas.drawRect(Rect.fromLTWH(frontX, y + cs * 0.29, cs * 0.11, cs * 0.14), p);
      canvas.drawRect(Rect.fromLTWH(frontX, y + cs * 0.54, cs * 0.11, cs * 0.14), p);
      p.color = const Color(0xFFFF2233);
      canvas.drawRect(Rect.fromLTWH(rearX, y + cs * 0.29, cs * 0.11, cs * 0.14), p);
      canvas.drawRect(Rect.fromLTWH(rearX, y + cs * 0.54, cs * 0.11, cs * 0.14), p);

      p.color = const Color(0xFF111111);
      canvas.drawRect(Rect.fromLTWH(x + cs * 0.10, y + cs * 0.72, cs * 0.20, cs * 0.17), p);
      canvas.drawRect(Rect.fromLTWH(x + w - cs * 0.30, y + cs * 0.72, cs * 0.20, cs * 0.17), p);
      p.color = const Color(0xFF555555);
      canvas.drawRect(Rect.fromLTWH(x + cs * 0.155, y + cs * 0.745, cs * 0.09, cs * 0.07), p);
      canvas.drawRect(Rect.fromLTWH(x + w - cs * 0.255, y + cs * 0.745, cs * 0.09, cs * 0.07), p);
    }
  }

  Color _lightenColor(Color c, double t) {
    return Color.fromARGB(
      c.alpha,
      (c.red   + (255 - c.red)   * t).round().clamp(0, 255),
      (c.green + (255 - c.green) * t).round().clamp(0, 255),
      (c.blue  + (255 - c.blue)  * t).round().clamp(0, 255),
    );
  }

  Color _darkenColor(Color c, double t) {
    return Color.fromARGB(
      c.alpha,
      (c.red   * (1 - t)).round().clamp(0, 255),
      (c.green * (1 - t)).round().clamp(0, 255),
      (c.blue  * (1 - t)).round().clamp(0, 255),
    );
  }

  void _drawFrog(Canvas canvas, double ox, double oy, double cs) {
    final isDead = deathFlash;
    final bodyGreen  = isDead ? const Color(0xFFFF2200) : const Color(0xFF22CC22);
    final darkGreen  = isDead ? const Color(0xFFAA1100) : const Color(0xFF119911);
    final outlineCol = isDead ? const Color(0xFF660000) : const Color(0xFF0A4A0A);
    final bellyColor = isDead ? const Color(0xFFFF6644) : const Color(0xFF99FF77);
    final irisColor  = isDead ? const Color(0xFFFF8800) : const Color(0xFFCCBB00);

    final p = Paint()..isAntiAlias = false;
    final fx = ox + frogX * cs;
    final fy = oy + frogRow * cs;
    final u = cs / 10.0;

    canvas.save();
    canvas.translate(fx + cs / 2, fy + cs / 2);
    canvas.scale(0.90);
    switch (frogFacing) {
      case _Facing.up:    break;
      case _Facing.down:  canvas.rotate(3.14159); break;
      case _Facing.left:  canvas.rotate(-1.5708); break;
      case _Facing.right: canvas.rotate(1.5708); break;
    }

    p.color = outlineCol;
    canvas.drawRect(Rect.fromLTWH(-5*u,  1*u, 3*u, 4.5*u), p);
    canvas.drawRect(Rect.fromLTWH( 2*u,  1*u, 3*u, 4.5*u), p);
    canvas.drawRect(Rect.fromLTWH(-4.5*u, -2.5*u, 9*u, 6*u), p);
    canvas.drawRect(Rect.fromLTWH(-4.5*u, -6*u, 9*u, 4.5*u), p);
    canvas.drawRect(Rect.fromLTWH(-5.5*u, -3.5*u, 2.5*u, 3.5*u), p);
    canvas.drawRect(Rect.fromLTWH( 3*u,   -3.5*u, 2.5*u, 3.5*u), p);

    p.color = darkGreen;
    canvas.drawRect(Rect.fromLTWH(-4.5*u, 1.5*u, 2.5*u, 3.5*u), p);
    canvas.drawRect(Rect.fromLTWH(-5.8*u, 3.8*u, 1.2*u, 1.2*u), p);
    canvas.drawRect(Rect.fromLTWH(-4.8*u, 4.2*u, 1.2*u, 1.0*u), p);
    canvas.drawRect(Rect.fromLTWH(-3.8*u, 3.8*u, 1.2*u, 1.2*u), p);
    canvas.drawRect(Rect.fromLTWH( 2*u, 1.5*u, 2.5*u, 3.5*u), p);
    canvas.drawRect(Rect.fromLTWH( 2.6*u, 3.8*u, 1.2*u, 1.2*u), p);
    canvas.drawRect(Rect.fromLTWH( 3.6*u, 4.2*u, 1.2*u, 1.0*u), p);
    canvas.drawRect(Rect.fromLTWH( 4.6*u, 3.8*u, 1.2*u, 1.2*u), p);

    p.color = bodyGreen;
    canvas.drawRect(Rect.fromLTWH(-3.5*u, -2*u, 7*u, 5*u), p);
    p.color = darkGreen;
    canvas.drawRect(Rect.fromLTWH(-0.6*u, -2*u, 1.2*u, 4*u), p);

    p.color = bellyColor;
    canvas.drawRect(Rect.fromLTWH(-2*u, -0.5*u, 4*u, 3*u), p);

    p.color = darkGreen;
    canvas.drawRect(Rect.fromLTWH(-2.8*u, -1.5*u, 1.6*u, 1.6*u), p);
    canvas.drawRect(Rect.fromLTWH( 1.2*u, -1.5*u, 1.6*u, 1.6*u), p);

    p.color = darkGreen;
    canvas.drawRect(Rect.fromLTWH(-5*u, -3*u, 2*u, 2.5*u), p);
    canvas.drawRect(Rect.fromLTWH(-5.8*u, -3.5*u, 0.9*u, 0.9*u), p);
    canvas.drawRect(Rect.fromLTWH(-5.0*u, -3.8*u, 0.9*u, 0.9*u), p);
    canvas.drawRect(Rect.fromLTWH(-4.2*u, -3.5*u, 0.9*u, 0.9*u), p);
    canvas.drawRect(Rect.fromLTWH( 3*u, -3*u, 2*u, 2.5*u), p);
    canvas.drawRect(Rect.fromLTWH( 3.3*u, -3.5*u, 0.9*u, 0.9*u), p);
    canvas.drawRect(Rect.fromLTWH( 4.1*u, -3.8*u, 0.9*u, 0.9*u), p);
    canvas.drawRect(Rect.fromLTWH( 4.9*u, -3.5*u, 0.9*u, 0.9*u), p);

    p.color = bodyGreen;
    canvas.drawRect(Rect.fromLTWH(-4*u, -5.5*u, 8*u, 4*u), p);
    p.color = darkGreen;
    canvas.drawRect(Rect.fromLTWH(-3*u, -2.5*u, 6*u, 1*u), p);
    p.color = outlineCol;
    canvas.drawRect(Rect.fromLTWH(-1.5*u, -4.2*u, 0.9*u, 0.9*u), p);
    canvas.drawRect(Rect.fromLTWH( 0.6*u, -4.2*u, 0.9*u, 0.9*u), p);

    p.color = outlineCol;
    canvas.drawRect(Rect.fromLTWH(-5*u, -7.5*u, 3.2*u, 3.2*u), p);
    canvas.drawRect(Rect.fromLTWH( 1.8*u, -7.5*u, 3.2*u, 3.2*u), p);
    p.color = Colors.white;
    canvas.drawRect(Rect.fromLTWH(-4.5*u, -7*u, 2.5*u, 2.5*u), p);
    canvas.drawRect(Rect.fromLTWH( 2*u,   -7*u, 2.5*u, 2.5*u), p);
    p.color = irisColor;
    canvas.drawRect(Rect.fromLTWH(-4.2*u, -6.8*u, 1.9*u, 1.9*u), p);
    canvas.drawRect(Rect.fromLTWH( 2.3*u, -6.8*u, 1.9*u, 1.9*u), p);
    p.color = Colors.black;
    canvas.drawRect(Rect.fromLTWH(-3.8*u, -6.5*u, 1.2*u, 1.2*u), p);
    canvas.drawRect(Rect.fromLTWH( 2.6*u, -6.5*u, 1.2*u, 1.2*u), p);
    p.color = Colors.white;
    canvas.drawRect(Rect.fromLTWH(-3.6*u, -6.8*u, 0.55*u, 0.55*u), p);
    canvas.drawRect(Rect.fromLTWH( 2.8*u, -6.8*u, 0.55*u, 0.55*u), p);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_HopperPainter old) => true;
}
