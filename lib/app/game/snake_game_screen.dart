import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─── Direction ───────────────────────────────────────────────────────────────

enum _Direction { up, down, left, right }

// ─── Screen ──────────────────────────────────────────────────────────────────

class SnakeGameScreen extends StatefulWidget {
  final String userId;
  final DocumentReference rewardsDocRef;
  final double currentSaldo;

  const SnakeGameScreen({
    super.key,
    required this.userId,
    required this.rewardsDocRef,
    required this.currentSaldo,
  });

  @override
  State<SnakeGameScreen> createState() => _SnakeGameScreenState();
}

class _SnakeGameScreenState extends State<SnakeGameScreen> {
  static const int kGridW = 18;
  static const int kGridH = 26;
  static const int kFoodForLevel = 5;
  static const double kStartTickMs = 250.0;

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

  @override
  void initState() {
    super.initState();
    _saldo = widget.currentSaldo;
    _initGame();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  // ─── Game setup ──────────────────────────────────────────────────────────

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
    final ms = (kStartTickMs / _level).clamp(100.0, kStartTickMs).round();
    _ticker = Timer.periodic(Duration(milliseconds: ms), (_) => _tick());
  }

  // ─── Game loop ───────────────────────────────────────────────────────────

  void _tick() {
    if (!_isRunning || _isDead) return;

    _dir = _nextDir;

    final head = _snake.first;
    final next = _step(head, _dir);

    // Wall collision
    if (next.x < 0 || next.x >= kGridW || next.y < 0 || next.y >= kGridH) {
      _triggerDeath();
      return;
    }

    // Self collision — exclude tail (it will move away)
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
    if (mounted) setState(() => _isDead = true);
  }

  Future<void> _levelUp() async {
    _ticker?.cancel();
    _level++;

    if (!_awardingPoints) {
      _awardingPoints = true;
      final newSaldo = _saldo + 1.0;
      await _updateFirestore(newSaldo);
      if (mounted) setState(() => _saldo = newSaldo);
      _awardingPoints = false;
    }

    if (mounted) _startTicker();
  }

  Future<void> _restart() async {
    if (_saldo < 10) return;
    final newSaldo = _saldo - 10.0;
    await _updateFirestore(newSaldo);
    if (!mounted) return;
    setState(() {
      _saldo = newSaldo;
      _initGame();
    });
    _isRunning = true;
    _startTicker();
  }

  // ─── Direction input ─────────────────────────────────────────────────────

  void _onHorizontalDrag(DragUpdateDetails d) {
    if (d.delta.dx.abs() < 5) return;
    final candidate =
        d.delta.dx > 0 ? _Direction.right : _Direction.left;
    if (!_isOpposite(candidate, _dir)) _nextDir = candidate;
    if (!_isRunning && !_isDead) _beginGame(candidate);
  }

  void _onVerticalDrag(DragUpdateDetails d) {
    if (d.delta.dy.abs() < 5) return;
    final candidate =
        d.delta.dy > 0 ? _Direction.down : _Direction.up;
    if (!_isOpposite(candidate, _dir)) _nextDir = candidate;
    if (!_isRunning && !_isDead) _beginGame(candidate);
  }

  void _beginGame(_Direction firstDir) {
    _nextDir = firstDir;
    _dir = firstDir;
    setState(() => _isRunning = true);
    _startTicker();
  }

  // ─── Firestore ───────────────────────────────────────────────────────────

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

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(),
      body: SafeArea(
        child: Stack(
          children: [
            _buildGameCanvas(),
            if (!_isRunning && !_isDead) _buildStartOverlay(),
            if (_isDead) _buildGameOverOverlay(),
          ],
        ),
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      title: Text(
        'Lvl $_level  ·  ⭐ $_score  ·  💰 ${_saldo.toStringAsFixed(0)} pts',
        style: const TextStyle(
          color: Colors.black,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
      centerTitle: true,
      actions: [
        IconButton(
          icon: const Icon(Icons.close, color: Colors.black),
          onPressed: () {
            _ticker?.cancel();
            Navigator.pop(context);
          },
        ),
      ],
    );
  }

  Widget _buildGameCanvas() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: _onHorizontalDrag,
      onVerticalDragUpdate: _onVerticalDrag,
      child: LayoutBuilder(
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
      ),
    );
  }

  Widget _buildStartOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.white.withOpacity(0.88),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '🐍',
              style: TextStyle(fontSize: 64),
            ),
            const SizedBox(height: 16),
            const Text(
              'SNAKE',
              style: TextStyle(
                color: Colors.black,
                fontSize: 32,
                fontWeight: FontWeight.bold,
                letterSpacing: 6,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Desliza para empezar',
              style: TextStyle(color: Colors.black54, fontSize: 15),
            ),
            const SizedBox(height: 8),
            const Text(
              'Come 5 frutas para subir de nivel (+1 pto)',
              style: TextStyle(color: Colors.black38, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGameOverOverlay() {
    final canRestart = _saldo >= 10;

    return Positioned.fill(
      child: Container(
        color: Colors.white.withOpacity(0.92),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Game Over',
              style: TextStyle(
                color: Colors.black,
                fontSize: 36,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Puntuación: $_score',
              style: const TextStyle(color: Colors.black54, fontSize: 18),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: canRestart ? _restart : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                disabledForegroundColor: Colors.grey.shade500,
                padding: const EdgeInsets.symmetric(
                    horizontal: 32, vertical: 14),
                shape: const StadiumBorder(),
                elevation: 0,
              ),
              child: Text(
                canRestart
                    ? 'Reintentar  (−10 pts)'
                    : 'Sin puntos suficientes',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Salir',
                style: TextStyle(
                    color: Colors.black54,
                    fontSize: 15,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Painter ─────────────────────────────────────────────────────────────────

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

    // White background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.white,
    );

    // Subtle grid dots
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

    // Food — red circle with soft shadow
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

    // Snake body
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
