import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'arcade_input_controller.dart';
import 'game_saldo.dart';
import 'high_score_service.dart';

enum _Direction { up, down, left, right }

class SnakeGameScreen extends StatefulWidget {
  final String userId;
  final DocumentReference rewardsDocRef;
  final double currentSaldo;
  final ArcadeInputController controller;
  final void Function(double) onSaldoChanged;

  const SnakeGameScreen({
    super.key,
    required this.userId,
    required this.rewardsDocRef,
    required this.currentSaldo,
    required this.controller,
    required this.onSaldoChanged,
  });

  @override
  State<SnakeGameScreen> createState() => _SnakeGameScreenState();
}

class _SnakeGameScreenState extends State<SnakeGameScreen> {
  static const int kGridW = 18;
  static const int kGridH = 26;
  static const int kFoodForLevel = 3;
  static const double kStartTickMs = 190.0;

  final _rng = Random();

  List<Point<int>> _snake = [];
  late Point<int> _food;
  _Direction _dir = _Direction.right;
  _Direction _nextDir = _Direction.right;

  int _score = 0;
  int _level = 1;
  bool _isRunning = false;
  bool _isDead = false;

  Timer? _ticker;
  late double _saldo;
  bool _awardingPoints = false;
  bool _paused = false;
  int _bestScore = 0;

  @override
  void initState() {
    super.initState();
    _saldo = widget.currentSaldo;
    _initGame();
    widget.controller.addListener(_onControllerEvent);
    HighScoreService.load('snake').then((v) { if (mounted) setState(() => _bestScore = v); });
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
      if (btn == ArcadeButton.a || btn == ArcadeButton.start) _restart();
      return;
    }
    switch (btn) {
      case ArcadeButton.up:
        _tryChangeDir(_Direction.up);
      case ArcadeButton.down:
        _tryChangeDir(_Direction.down);
      case ArcadeButton.left:
        _tryChangeDir(_Direction.left);
      case ArcadeButton.right:
        _tryChangeDir(_Direction.right);
      case ArcadeButton.a:
        if (!_isRunning && !_isDead) _beginGame(_nextDir);
      case ArcadeButton.start:
        if (_isRunning && !_isDead) {
          setState(() => _paused = !_paused);
        } else if (!_isRunning && !_isDead) {
          _beginGame(_nextDir);
        }
      default:
        break;
    }
  }

  void _tryChangeDir(_Direction candidate) {
    if (!_isOpposite(candidate, _dir)) _nextDir = candidate;
    if (!_isRunning && !_isDead) _beginGame(candidate);
  }

  void _initGame() {
    final midY = kGridH ~/ 2;
    final midX = kGridW ~/ 2;
    _snake = [
      Point(midX, midY),
      Point(midX - 1, midY),
      Point(midX - 2, midY),
    ];
    _dir = _Direction.right;
    _nextDir = _Direction.right;
    _score = 0;
    _level = 1;
    _isDead = false;
    _isRunning = false;
    _spawnFood();
  }

  void _spawnFood() {
    Point<int> candidate;
    do {
      candidate = Point(_rng.nextInt(kGridW), _rng.nextInt(kGridH));
    } while (_snake.contains(candidate));
    _food = candidate;
  }

  void _startTicker() {
    _ticker?.cancel();
    final ms = (kStartTickMs / (1.0 + (_level - 1) * 0.12)).clamp(100.0, kStartTickMs).round();
    _ticker = Timer.periodic(Duration(milliseconds: ms), (_) => _tick());
  }

  void _tick() {
    if (!_isRunning || _isDead || _paused) return;

    _dir = _nextDir;

    final head = _snake.first;
    final next = _step(head, _dir);

    if (next.x < 0 || next.x >= kGridW || next.y < 0 || next.y >= kGridH) {
      _triggerDeath();
      return;
    }

    if (_snake.sublist(0, _snake.length - 1).contains(next)) {
      _triggerDeath();
      return;
    }

    final ateFood = next == _food;
    final newSnake = [next, ..._snake];
    if (!ateFood) newSnake.removeLast();

    if (!mounted) return;
    setState(() {
      _snake = newSnake;
      if (ateFood) {
        _score++;
        _spawnFood();
        if (_score % kFoodForLevel == 0) {
          _levelUp();
        }
      }
    });
  }

  Point<int> _step(Point<int> p, _Direction d) {
    switch (d) {
      case _Direction.up:
        return Point(p.x, p.y - 1);
      case _Direction.down:
        return Point(p.x, p.y + 1);
      case _Direction.left:
        return Point(p.x - 1, p.y);
      case _Direction.right:
        return Point(p.x + 1, p.y);
    }
  }

  bool _isOpposite(_Direction a, _Direction b) {
    return (a == _Direction.up && b == _Direction.down) ||
        (a == _Direction.down && b == _Direction.up) ||
        (a == _Direction.left && b == _Direction.right) ||
        (a == _Direction.right && b == _Direction.left);
  }

  void _triggerDeath() {
    _ticker?.cancel();
    HapticFeedback.heavyImpact();
    HighScoreService.submit('snake', _score).then((isNew) {
      if (isNew && mounted) setState(() => _bestScore = _score);
    });
    if (mounted) setState(() => _isDead = true);
  }

  Future<void> _levelUp() async {
    _ticker?.cancel();
    _level++;

    if (_level % 5 == 0 && !_awardingPoints) {
      _awardingPoints = true;
      final newSaldo = _saldo + 1.0;
      await _updateFirestore(newSaldo);
      if (mounted) {
        setState(() => _saldo = newSaldo);
        widget.onSaldoChanged(newSaldo);
      }
      _awardingPoints = false;
    }

    if (mounted) _startTicker();
  }

  Future<void> _restart() async {
    final ns = await chargeForReplay(
        userId: widget.userId,
        rewardsDocRef: widget.rewardsDocRef,
        currentSaldo: _saldo);
    if (ns == null) return;
    if (!mounted) return;
    setState(() {
      _saldo = ns;
      _initGame();
    });
    _isRunning = true;
    _startTicker();
  }

  void _beginGame(_Direction firstDir) {
    _nextDir = firstDir;
    _dir = firstDir;
    setState(() => _isRunning = true);
    _startTicker();
  }

  Future<void> _updateFirestore(double newSaldo) async {
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
    } catch (e) {
      debugPrint('Snake Firestore error: $e');
    }
  }

  void _onHorizontalDrag(DragUpdateDetails d) {
    if (d.delta.dx.abs() > 5) {
      _tryChangeDir(d.delta.dx > 0 ? _Direction.right : _Direction.left);
    }
  }

  void _onVerticalDrag(DragUpdateDetails d) {
    if (d.delta.dy.abs() > 5) {
      _tryChangeDir(d.delta.dy > 0 ? _Direction.down : _Direction.up);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: _onHorizontalDrag,
      onVerticalDragUpdate: _onVerticalDrag,
      child: Stack(
        children: [
          _buildGameCanvas(),
          _buildScoreBar(),
          if (!_isRunning && !_isDead) _buildStartOverlay(),
          if (_isDead) _buildGameOverOverlay(),
          if (_paused && _isRunning) _buildPauseOverlay(),
        ],
      ),
    );
  }

  Widget _buildScoreBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        color: Colors.black.withOpacity(0.6),
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: Text(
          'Lvl $_level  ·  ⭐ $_score  ·  💰 ${_saldo.toStringAsFixed(0)} pts',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildGameCanvas() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return CustomPaint(
          painter: _SnakePainter(
            snake: _snake,
            food: _food,
            gridW: kGridW,
            gridH: kGridH,
          ),
          child: SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
          ),
        );
      },
    );
  }

  Widget _buildStartOverlay() {
  return Positioned.fill(
    child: Container(
      color: const Color(0xEE0A1A0A),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🐍', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 10),
          const Text(
            'VÍBORA VELOZ',
            style: TextStyle(
              color: Color(0xFF00FF44),
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: 6,
            ),
          ),
          const SizedBox(height: 4),
          const Text('La serpiente más rápida del oeste',
            style: TextStyle(color: Color(0xFF44AA44), fontSize: 10, letterSpacing: 2)),
          const SizedBox(height: 28),
          const Text('D-pad para dirigir la serpiente',
            style: TextStyle(color: Color(0xFF88CC88), fontSize: 12)),
          const SizedBox(height: 4),
          const Text('Desliza en pantalla para jugar sin control',
            style: TextStyle(color: Color(0xFF557755), fontSize: 11)),
          const SizedBox(height: 16),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 40),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0x6600FF44), width: 1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Column(children: [
              Text('+1 pto cada 5 niveles', style: TextStyle(color: Color(0xFFFFD700), fontSize: 11, fontWeight: FontWeight.bold)),
              Text('Sube de nivel cada 4 frutas', style: TextStyle(color: Color(0xFF88AA88), fontSize: 10)),
            ]),
          ),
          const SizedBox(height: 28),
          const Text('Desliza o pulsa A / START',
            style: TextStyle(color: Color(0xFF336633), fontSize: 12)),
        ],
      ),
    ),
  );
}

  Widget _buildGameOverOverlay() {
  final canRestart = _saldo >= 5;

  return Positioned.fill(
    child: Container(
      color: const Color(0xEE080808),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('☠', style: TextStyle(fontSize: 48, color: Color(0xFF880000))),
          const SizedBox(height: 8),
          const Text(
            'GAME OVER',
            style: TextStyle(
              color: Color(0xFFFF3300),
              fontSize: 34,
              fontWeight: FontWeight.bold,
              letterSpacing: 4,
            ),
          ),
          const SizedBox(height: 4),
          const Text('La serpiente ha mordido algo duro',
            style: TextStyle(color: Color(0xFF884444), fontSize: 11)),
          const SizedBox(height: 20),
          Text('Puntuación: $_score',
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          if (_bestScore > 0)
            Text('Récord: $_bestScore',
              style: const TextStyle(color: Color(0xFFFFD700), fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 28),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: canRestart ? _restart : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: canRestart ? const Color(0xFF00AA33) : Colors.grey.shade800,
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.grey,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: const StadiumBorder(),
                ),
                child: Text(
                  canRestart ? 'Reintentar  (−5 pts)' : 'Sin puntos suficientes',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text('SELECT para volver',
            style: TextStyle(color: Color(0xFF334433), fontSize: 10)),
        ],
      ),
    ),
  );
}

  Widget _buildPauseOverlay() => Positioned.fill(
    child: Container(
      color: const Color(0xCC000000),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('⏸', style: TextStyle(fontSize: 48)),
          SizedBox(height: 8),
          Text('PAUSA', style: TextStyle(color: Color(0xFF00FF44), fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 6)),
          SizedBox(height: 16),
          Text('START para continuar', style: TextStyle(color: Color(0xFF44AA44), fontSize: 12)),
        ],
      ),
    ),
  );
}

class _SnakePainter extends CustomPainter {
  final List<Point<int>> snake;
  final Point<int> food;
  final int gridW;
  final int gridH;

  const _SnakePainter({
    required this.snake,
    required this.food,
    required this.gridW,
    required this.gridH,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = size.width / gridW;
    final cellH = size.height / gridH;

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.white,
    );

    final dotPaint = Paint()..color = const Color(0xFFE8E8E8);
    for (int x = 0; x < gridW; x++) {
      for (int y = 0; y < gridH; y++) {
        canvas.drawCircle(
          Offset(x * cellW + cellW / 2, y * cellH + cellH / 2),
          1.2,
          dotPaint,
        );
      }
    }

    final foodCenter = Offset(
      food.x * cellW + cellW / 2,
      food.y * cellH + cellH / 2,
    );
    canvas.drawCircle(
      foodCenter,
      (cellW * 0.38).clamp(4.0, 14.0),
      Paint()
        ..color = Colors.red.shade400.withOpacity(0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(
      foodCenter,
      (cellW * 0.34).clamp(3.0, 12.0),
      Paint()..color = Colors.red.shade600,
    );

    final bodyPaint = Paint()..color = const Color(0xFF1A1A1A);
    final headPaint = Paint()..color = Colors.black;
    final r = (cellW * 0.15).clamp(1.0, 4.0);

    for (int i = 0; i < snake.length; i++) {
      final seg = snake[i];
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          seg.x * cellW + 1.5,
          seg.y * cellH + 1.5,
          cellW - 3,
          cellH - 3,
        ),
        Radius.circular(r),
      );
      canvas.drawRRect(rect, i == 0 ? headPaint : bodyPaint);
    }
  }

  @override
  bool shouldRepaint(_SnakePainter old) =>
      old.snake != snake || old.food != food;
}
