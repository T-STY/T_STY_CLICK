import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'arcade_input_controller.dart';
import 'high_score_service.dart';

// ─── Piece data ───────────────────────────────────────────────────────────────

const _kShapes = [
  // I (4×4 box)
  [
    [[1, 0], [1, 1], [1, 2], [1, 3]],
    [[0, 2], [1, 2], [2, 2], [3, 2]],
    [[2, 0], [2, 1], [2, 2], [2, 3]],
    [[0, 1], [1, 1], [2, 1], [3, 1]]
  ],
  // O (2×2)
  [
    [[0, 0], [0, 1], [1, 0], [1, 1]],
    [[0, 0], [0, 1], [1, 0], [1, 1]],
    [[0, 0], [0, 1], [1, 0], [1, 1]],
    [[0, 0], [0, 1], [1, 0], [1, 1]]
  ],
  // T (3×3)
  [
    [[0, 1], [1, 0], [1, 1], [1, 2]],
    [[0, 0], [1, 0], [1, 1], [2, 0]],
    [[1, 0], [1, 1], [1, 2], [2, 1]],
    [[0, 2], [1, 1], [1, 2], [2, 2]]
  ],
  // S
  [
    [[0, 1], [0, 2], [1, 0], [1, 1]],
    [[0, 0], [1, 0], [1, 1], [2, 1]],
    [[0, 1], [0, 2], [1, 0], [1, 1]],
    [[0, 0], [1, 0], [1, 1], [2, 1]]
  ],
  // Z
  [
    [[0, 0], [0, 1], [1, 1], [1, 2]],
    [[0, 1], [1, 0], [1, 1], [2, 0]],
    [[0, 0], [0, 1], [1, 1], [1, 2]],
    [[0, 1], [1, 0], [1, 1], [2, 0]]
  ],
  // J
  [
    [[0, 0], [1, 0], [1, 1], [1, 2]],
    [[0, 0], [0, 1], [1, 0], [2, 0]],
    [[1, 0], [1, 1], [1, 2], [2, 2]],
    [[0, 1], [1, 1], [2, 0], [2, 1]]
  ],
  // L
  [
    [[0, 2], [1, 0], [1, 1], [1, 2]],
    [[0, 0], [1, 0], [2, 0], [2, 1]],
    [[1, 0], [1, 1], [1, 2], [2, 0]],
    [[0, 0], [0, 1], [1, 1], [2, 1]]
  ],
];

const _kColors = [
  Color(0xFF00E5FF), // I – cyan
  Color(0xFFFFD700), // O – gold
  Color(0xFFCC00FF), // T – purple
  Color(0xFF00E676), // S – green
  Color(0xFFFF1744), // Z – red
  Color(0xFF2979FF), // J – blue
  Color(0xFFFF6D00), // L – orange
];

const _kScoreTable = [0, 100, 300, 500, 800];

// ─── Game state enum ──────────────────────────────────────────────────────────

enum _GameState { start, playing, paused, dead, complete }

const int _kMaxLines = 400; // 40-point cap

// ─── Widget ───────────────────────────────────────────────────────────────────

class TetrisScreen extends StatefulWidget {
  final String userId;
  final DocumentReference rewardsDocRef;
  final double currentSaldo;
  final ArcadeInputController controller;
  final void Function(double) onSaldoChanged;

  const TetrisScreen({
    super.key,
    required this.userId,
    required this.rewardsDocRef,
    required this.currentSaldo,
    required this.controller,
    required this.onSaldoChanged,
  });

  @override
  State<TetrisScreen> createState() => _TetrisScreenState();
}

class _TetrisScreenState extends State<TetrisScreen> {
  // Grid: 0 = empty, 1-7 = locked piece color index+1
  late List<List<int>> _grid;

  // Current piece
  int _pieceType = 0;
  int _rot = 0;
  int _pieceRow = 0;
  int _pieceCol = 3;

  // Next piece
  int _nextType = 0;

  // Scoring / progress
  int _score = 0;
  int _hiScore = 0;
  int _level = 1;
  int _totalLines = 0;
  late double _saldo;

  // State
  _GameState _state = _GameState.start;

  // Timers
  Timer? _gravTimer;
  Timer? _dasTimer;
  Timer? _dasRepeat;

  final _rng = Random();

  // ─── Init / dispose ────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _saldo = widget.currentSaldo;
    _initGrid();
    HighScoreService.load('tetris').then((v) => setState(() => _hiScore = v));
    widget.controller.addListener(_onControllerEvent);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerEvent);
    _gravTimer?.cancel();
    _dasTimer?.cancel();
    _dasRepeat?.cancel();
    super.dispose();
  }

  // ─── Grid helpers ──────────────────────────────────────────────────────────

  void _initGrid() {
    _grid = List.generate(20, (_) => List.filled(10, 0));
  }

  List<List<int>> get _currentShape => _kShapes[_pieceType][_rot] as List<List<int>>;

  bool _isValid(int row, int col, int rot) {
    for (final cell in _kShapes[_pieceType][rot] as List<List<int>>) {
      final r = row + cell[0];
      final c = col + cell[1];
      if (r < 0 || r >= 20 || c < 0 || c >= 10) return false;
      if (_grid[r][c] != 0) return false;
    }
    return true;
  }

  // Ghost piece: drop position
  int _ghostRow() {
    int r = _pieceRow;
    while (_isValid(r + 1, _pieceCol, _rot)) {
      r++;
    }
    return r;
  }

  // ─── Gravity ───────────────────────────────────────────────────────────────

  int get _gravInterval => (650 - (_level - 1) * 65).clamp(65, 650);

  void _startGravity() {
    _gravTimer?.cancel();
    _gravTimer = Timer.periodic(Duration(milliseconds: _gravInterval), (_) => _gravTick());
  }

  void _gravTick() {
    if (_state != _GameState.playing) return;
    if (_isValid(_pieceRow + 1, _pieceCol, _rot)) {
      setState(() => _pieceRow++);
    } else {
      _lockPiece();
    }
  }

  // ─── Piece management ─────────────────────────────────────────────────────

  void _spawnPiece() {
    _pieceType = _nextType;
    _rot = 0;
    _pieceRow = 0;
    _pieceCol = 3;
    _nextType = _rng.nextInt(7);

    if (!_isValid(0, 3, 0)) {
      _triggerGameOver();
    }
  }

  void _lockPiece() {
    final colorIndex = _pieceType + 1;
    for (final cell in _currentShape) {
      final r = _pieceRow + cell[0];
      final c = _pieceCol + cell[1];
      if (r >= 0 && r < 20 && c >= 0 && c < 10) {
        _grid[r][c] = colorIndex;
      }
    }
    _clearLines();
    _spawnPiece();
  }

  void _clearLines() {
    int cleared = 0;
    int r = 19;
    while (r >= 0) {
      if (_grid[r].every((cell) => cell != 0)) {
        _grid.removeAt(r);
        _grid.insert(0, List.filled(10, 0));
        cleared++;
        // Do NOT decrement r — new row at same index must be checked
      } else {
        r--;
      }
    }

    if (cleared == 0) return;

    final prevLines = _totalLines;
    _totalLines += cleared;

    // Cap at 400 lines (= 40 pts max)
    if (_totalLines >= _kMaxLines) {
      _totalLines = _kMaxLines;
      final lineScore = _level * _kScoreTable[cleared.clamp(0, 4)];
      setState(() => _score += lineScore);
      _completeGame();
      return;
    }

    final newLevel = (_totalLines ~/ 10) + 1;
    final lineScore = _level * _kScoreTable[cleared.clamp(0, 4)];
    final levelChanged = newLevel > _level;

    setState(() {
      _score += lineScore;
      _level = newLevel;
    });

    // Restart gravity on every line clear (refreshes interval if level changed)
    if (levelChanged) {
      _startGravity();
    }

    // Saldo: +1 per 10 lines (cumulative), capped at 40 pts total (400 lines)
    final prevSaldoThreshold = prevLines ~/ 10;
    final newSaldoThreshold = _totalLines ~/ 10;
    if (newSaldoThreshold > prevSaldoThreshold) {
      final earned = (newSaldoThreshold - prevSaldoThreshold).toDouble();
      final newSaldo = _saldo + earned;
      _updateFirestore(newSaldo).then((_) {
        if (mounted) {
          setState(() => _saldo = newSaldo);
          widget.onSaldoChanged(newSaldo);
        }
      });
      _saldo = newSaldo; // optimistic local update
    }
  }

  // ─── Game state transitions ────────────────────────────────────────────────

  void _startGame() {
    _initGrid();
    _score = 0;
    _level = 1;
    _totalLines = 0;
    _nextType = _rng.nextInt(7);
    _spawnPiece();
    setState(() => _state = _GameState.playing);
    _startGravity();
  }

  void _restart() {
    _gravTimer?.cancel();
    _dasTimer?.cancel();
    _dasRepeat?.cancel();
    _startGame();
  }

  void _completeGame() {
    _gravTimer?.cancel();
    HapticFeedback.heavyImpact();
    HighScoreService.submit('tetris', _score);
    if (_score > _hiScore) setState(() => _hiScore = _score);
    setState(() => _state = _GameState.complete);
  }

  void _triggerGameOver() {
    _gravTimer?.cancel();
    HapticFeedback.heavyImpact();
    HighScoreService.submit('tetris', _score);
    if (_score > _hiScore) {
      setState(() {
        _hiScore = _score;
        _state = _GameState.dead;
      });
    } else {
      setState(() => _state = _GameState.dead);
    }
  }

  void _togglePause() {
    if (_state == _GameState.playing) {
      _gravTimer?.cancel();
      setState(() => _state = _GameState.paused);
    } else if (_state == _GameState.paused) {
      setState(() => _state = _GameState.playing);
      _startGravity();
    }
  }

  // ─── Movement ─────────────────────────────────────────────────────────────

  void _moveLeft() {
    if (_state != _GameState.playing) return;
    if (_isValid(_pieceRow, _pieceCol - 1, _rot)) {
      setState(() => _pieceCol--);
    }
  }

  void _moveRight() {
    if (_state != _GameState.playing) return;
    if (_isValid(_pieceRow, _pieceCol + 1, _rot)) {
      setState(() => _pieceCol++);
    }
  }

  void _moveDown() {
    if (_state != _GameState.playing) return;
    if (_isValid(_pieceRow + 1, _pieceCol, _rot)) {
      setState(() {
        _pieceRow++;
        _score += 1;
      });
    } else {
      _lockPiece();
    }
  }

  void _rotateCW() {
    if (_state != _GameState.playing) return;
    final newRot = (_rot + 1) % 4;
    _tryRotate(newRot);
  }

  void _rotateCCW() {
    if (_state != _GameState.playing) return;
    final newRot = (_rot + 3) % 4;
    _tryRotate(newRot);
  }

  void _tryRotate(int newRot) {
    // Try kicks: 0, -1, +1, -2, +2 col offsets only.
    // No upward row kick — prevents exploiting infinite spin on the floor.
    const colKicks = [0, -1, 1, -2, 2];
    for (final dc in colKicks) {
      if (_isValid(_pieceRow, _pieceCol + dc, newRot)) {
        setState(() {
          _rot = newRot;
          _pieceCol += dc;
        });
        return;
      }
    }
  }

  void _hardDrop() {
    if (_state != _GameState.playing) return;
    final ghost = _ghostRow();
    final fallen = ghost - _pieceRow;
    setState(() {
      _pieceRow = ghost;
      _score += fallen * 2;
    });
    _lockPiece();
  }

  // ─── DAS (Delayed Auto Shift) ──────────────────────────────────────────────

  void _startDas(void Function() action) {
    _cancelDas();
    action(); // immediate move
    _dasTimer = Timer(const Duration(milliseconds: 150), () {
      _dasRepeat = Timer.periodic(const Duration(milliseconds: 60), (_) => action());
    });
  }

  void _cancelDas() {
    _dasTimer?.cancel();
    _dasRepeat?.cancel();
    _dasTimer = null;
    _dasRepeat = null;
  }

  // ─── Controller input ─────────────────────────────────────────────────────

  void _onControllerEvent() {
    final event = widget.controller.lastEvent;
    if (event == null) return;
    final btn = event.button;
    final isDown = event.isDown;

    if (isDown) {
      switch (btn) {
        case ArcadeButton.start:
          if (_state == _GameState.start || _state == _GameState.dead || _state == _GameState.complete) {
            _restart();
          } else {
            _togglePause();
          }
        case ArcadeButton.a:
          if (_state == _GameState.dead || _state == _GameState.start || _state == _GameState.complete) {
            _restart();
          } else {
            _rotateCW();
          }
        case ArcadeButton.b:
          _rotateCCW();
        case ArcadeButton.up:
          _rotateCW();
        case ArcadeButton.left:
          _startDas(_moveLeft);
        case ArcadeButton.right:
          _startDas(_moveRight);
        case ArcadeButton.down:
          _startDas(_moveDown);
        case ArcadeButton.y:
          _hardDrop();
        default:
          break;
      }
    } else {
      // Release: cancel DAS for directional buttons
      if (btn == ArcadeButton.left ||
          btn == ArcadeButton.right ||
          btn == ArcadeButton.down) {
        _cancelDas();
      }
    }
  }

  // ─── Firestore ────────────────────────────────────────────────────────────

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
      debugPrint('Tetris Firestore: $e');
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Game canvas (always present)
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return CustomPaint(
                painter: _TetrisPainter(
                  grid: _grid,
                  pieceType: _state == _GameState.start ? -1 : _pieceType,
                  rot: _rot,
                  pieceRow: _pieceRow,
                  pieceCol: _pieceCol,
                  ghostRow: _state == _GameState.playing ? _ghostRow() : _pieceRow,
                  nextType: _nextType,
                  score: _score,
                  hiScore: _hiScore,
                  level: _level,
                  totalLines: _totalLines,
                ),
                child: SizedBox(
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                ),
              );
            },
          ),
        ),

        // Overlays
        if (_state == _GameState.start) _buildStartOverlay(),
        if (_state == _GameState.dead) _buildDeathOverlay(),
        if (_state == _GameState.paused) _buildPauseOverlay(),
        if (_state == _GameState.complete) _buildCompleteOverlay(),
      ],
    );
  }

  // ─── Shared overlay decoration helpers ────────────────────────────────────

  Widget _buildOverlayBackground({required Color tint, required Widget child}) {
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF0A0015).withOpacity(0.96),
              tint.withOpacity(0.18),
              const Color(0xFF00001A).withOpacity(0.96),
            ],
          ),
        ),
        child: child,
      ),
    );
  }

  Widget _buildNeonTitle(String text, Color color, double size) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: color,
        fontSize: size,
        fontWeight: FontWeight.w900,
        letterSpacing: 5,
        shadows: [
          Shadow(color: color.withOpacity(0.9), blurRadius: 12),
          Shadow(color: color.withOpacity(0.5), blurRadius: 28),
          Shadow(color: Colors.white.withOpacity(0.15), blurRadius: 4),
        ],
      ),
    );
  }

  Widget _buildHudCard({required String label, required String value, required Color accent}) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 24),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0x33FFFFFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withOpacity(0.45), width: 1.2),
        boxShadow: [
          BoxShadow(color: accent.withOpacity(0.18), blurRadius: 10, spreadRadius: 1),
        ],
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: accent,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              shadows: [
                Shadow(color: accent.withOpacity(0.7), blurRadius: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNeonButton(String label, VoidCallback onTap, {Color accent = const Color(0xFF00E5FF)}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: SizedBox(
        width: double.infinity,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [accent.withOpacity(0.85), accent.withOpacity(0.5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: accent, width: 1.5),
              boxShadow: [
                BoxShadow(color: accent.withOpacity(0.4), blurRadius: 14, spreadRadius: 2),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
                shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStartOverlay() {
    return _buildOverlayBackground(
      tint: const Color(0xFF00E5FF),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildNeonTitle('BLOQUES\nCAÍDOS', const Color(0xFF00E5FF), 36),
          const SizedBox(height: 28),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
            decoration: BoxDecoration(
              color: const Color(0x22FFFFFF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0x4400E5FF), width: 1),
            ),
            child: const Text(
              'A / UP  →  Rotar\nLEFT / RIGHT  →  Mover\nDOWN  →  Bajar\nY  →  Caída rápida\nSTART  →  Pausa',
              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.9),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '1L=100  2L=300  3L=500  4L=800  ×nivel\n+1 pto cada 10 líneas',
            style: TextStyle(
              color: Color(0xFFFFD700),
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
              shadows: [Shadow(color: Color(0xFFFFD700), blurRadius: 8)],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          _buildNeonButton('Pulsa A o START para empezar', _restart, accent: const Color(0xFF00E5FF)),
        ],
      ),
    );
  }

  Widget _buildDeathOverlay() {
    return _buildOverlayBackground(
      tint: const Color(0xFFFF1744),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildNeonTitle('GAME OVER', const Color(0xFFFF1744), 38),
          const SizedBox(height: 22),
          _buildHudCard(label: 'PUNTUACIÓN', value: '$_score', accent: const Color(0xFF00E5FF)),
          _buildHudCard(label: 'RÉCORD', value: '$_hiScore', accent: const Color(0xFFFFD700)),
          const SizedBox(height: 22),
          _buildNeonButton('Nueva Partida', _restart, accent: const Color(0xFFFF1744)),
        ],
      ),
    );
  }

  Widget _buildPauseOverlay() {
    return _buildOverlayBackground(
      tint: const Color(0xFF8800FF),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'PAUSA',
            style: TextStyle(
              color: Colors.white,
              fontSize: 42,
              fontWeight: FontWeight.w900,
              letterSpacing: 8,
              shadows: [
                Shadow(color: Color(0xFF8800FF), blurRadius: 18),
                Shadow(color: Color(0xFF8800FF), blurRadius: 36),
              ],
            ),
          ),
          SizedBox(height: 16),
          Text(
            'Pulsa START para continuar',
            style: TextStyle(color: Colors.white54, fontSize: 13, letterSpacing: 1),
          ),
        ],
      ),
    );
  }

  Widget _buildCompleteOverlay() {
    return _buildOverlayBackground(
      tint: const Color(0xFFFFD700),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🏆', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 10),
          _buildNeonTitle('¡COMPLETO!', const Color(0xFFFFD700), 34),
          const SizedBox(height: 6),
          const Text(
            '400 LÍNEAS ALCANZADAS',
            style: TextStyle(
              color: Color(0xFF00E5FF),
              fontSize: 12,
              letterSpacing: 3,
              shadows: [Shadow(color: Color(0xFF00E5FF), blurRadius: 8)],
            ),
          ),
          const SizedBox(height: 18),
          _buildHudCard(label: 'PUNTUACIÓN', value: '$_score', accent: const Color(0xFF00E5FF)),
          _buildHudCard(label: 'RÉCORD', value: '$_hiScore', accent: const Color(0xFFFFD700)),
          const SizedBox(height: 6),
          const Text(
            '+40 pts ganados',
            style: TextStyle(
              color: Color(0xFF00E676),
              fontSize: 14,
              fontWeight: FontWeight.bold,
              shadows: [Shadow(color: Color(0xFF00E676), blurRadius: 8)],
            ),
          ),
          const SizedBox(height: 24),
          _buildNeonButton('Nueva Partida', _restart, accent: const Color(0xFFFFD700)),
        ],
      ),
    );
  }
}

// ─── Painter ──────────────────────────────────────────────────────────────────

class _TetrisPainter extends CustomPainter {
  final List<List<int>> grid;
  final int pieceType; // -1 = no active piece
  final int rot;
  final int pieceRow;
  final int pieceCol;
  final int ghostRow;
  final int nextType;
  final int score;
  final int hiScore;
  final int level;
  final int totalLines;

  const _TetrisPainter({
    required this.grid,
    required this.pieceType,
    required this.rot,
    required this.pieceRow,
    required this.pieceCol,
    required this.ghostRow,
    required this.nextType,
    required this.score,
    required this.hiScore,
    required this.level,
    required this.totalLines,
  });

  // Deterministic starfield — same dots every frame (no animation needed)
  static final List<Offset> _stars = List.generate(60, (i) {
    final rng = Random(i * 1337 + 42);
    return Offset(rng.nextDouble(), rng.nextDouble());
  });

  @override
  void paint(Canvas canvas, Size size) {
    // ── Layout calculations ──────────────────────────────────────────────────
    final cellSize = (size.width * 0.60 / 10).floor().toDouble();
    final boardW = cellSize * 10;
    final boardH = cellSize * 20;
    const boardX = 0.0;
    final boardY = ((size.height - boardH) / 2).floorToDouble();

    // ── Deep space / neon-city background gradient ───────────────────────────
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF0B0020), // deep violet
          Color(0xFF060618), // midnight blue
          Color(0xFF020208), // near black
        ],
        stops: [0.0, 0.55, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // ── Starfield dots ───────────────────────────────────────────────────────
    final starPaint = Paint()..isAntiAlias = true;
    for (int i = 0; i < _stars.length; i++) {
      final s = _stars[i];
      final brightness = (i % 3 == 0) ? 0.8 : (i % 3 == 1) ? 0.5 : 0.35;
      final radius = (i % 3 == 0) ? 1.2 : 0.8;
      starPaint.color = Colors.white.withOpacity(brightness);
      canvas.drawCircle(Offset(s.dx * size.width, s.dy * size.height), radius, starPaint);
    }

    // ── Board area – dark slate background ───────────────────────────────────
    final boardBgPaint = Paint()..color = const Color(0xFF0D0D1A);
    canvas.drawRect(Rect.fromLTWH(boardX, boardY, boardW, boardH), boardBgPaint);

    // ── Neon border glow around the board ────────────────────────────────────
    final accentColor = pieceType >= 0 ? _kColors[pieceType] : const Color(0xFF00E5FF);
    final glowPaint = Paint()
      ..color = accentColor.withOpacity(0.22)
      ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawRect(
      Rect.fromLTWH(boardX + 0.5, boardY + 0.5, boardW - 1, boardH - 1),
      glowPaint,
    );
    final borderPaint = Paint()
      ..color = accentColor.withOpacity(0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(
      Rect.fromLTWH(boardX + 0.5, boardY + 0.5, boardW - 1, boardH - 1),
      borderPaint,
    );

    // ── Subtle grid lines (white 5% opacity) ─────────────────────────────────
    final gridPaint = Paint()
      ..color = const Color(0x0DFFFFFF)
      ..isAntiAlias = false;
    for (int c = 1; c < 10; c++) {
      canvas.drawRect(
        Rect.fromLTWH(boardX + c * cellSize, boardY, 1, boardH),
        gridPaint,
      );
    }
    for (int r = 1; r < 20; r++) {
      canvas.drawRect(
        Rect.fromLTWH(boardX, boardY + r * cellSize, boardW, 1),
        gridPaint,
      );
    }

    // ── Locked cells ────────────────────────────────────────────────────────
    for (int r = 0; r < 20; r++) {
      for (int c = 0; c < 10; c++) {
        final colorIndex = grid[r][c];
        if (colorIndex == 0) continue;
        _drawCell(canvas, boardX + c * cellSize, boardY + r * cellSize, cellSize, _kColors[colorIndex - 1], locked: true);
      }
    }

    // ── Ghost piece — dashed/opaque outline ──────────────────────────────────
    if (pieceType >= 0 && ghostRow != pieceRow) {
      final ghostColor = _kColors[pieceType];
      final ghostFill = Paint()
        ..color = ghostColor.withOpacity(0.08)
        ..isAntiAlias = true;
      final ghostBorder = Paint()
        ..color = ghostColor.withOpacity(0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..isAntiAlias = true;
      for (final cell in _kShapes[pieceType][rot] as List<List<int>>) {
        final gr = ghostRow + cell[0];
        final gc = pieceCol + cell[1];
        if (gr >= 0 && gr < 20 && gc >= 0 && gc < 10) {
          final rrect = RRect.fromRectAndRadius(
            Rect.fromLTWH(
              boardX + gc * cellSize + 1.5,
              boardY + gr * cellSize + 1.5,
              cellSize - 3,
              cellSize - 3,
            ),
            const Radius.circular(3),
          );
          canvas.drawRRect(rrect, ghostFill);
          canvas.drawRRect(rrect, ghostBorder);
        }
      }
    }

    // ── Active piece ────────────────────────────────────────────────────────
    if (pieceType >= 0) {
      for (final cell in _kShapes[pieceType][rot] as List<List<int>>) {
        final pr = pieceRow + cell[0];
        final pc = pieceCol + cell[1];
        if (pr >= 0 && pr < 20 && pc >= 0 && pc < 10) {
          _drawCell(canvas, boardX + pc * cellSize, boardY + pr * cellSize, cellSize, _kColors[pieceType], locked: false);
        }
      }
    }

    // ── Right panel ─────────────────────────────────────────────────────────
    final panelX = boardX + boardW + 6;
    final panelW = size.width - panelX - 4;
    _drawRightPanel(canvas, panelX, boardY, panelW, boardH, cellSize);
  }

  void _drawCell(Canvas canvas, double x, double y, double cs, Color color, {required bool locked}) {
    final radius = cs * 0.18;
    final rect = Rect.fromLTWH(x + 1, y + 1, cs - 2, cs - 2);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));

    // Inner glow (same hue, low opacity blur)
    final glowPaint = Paint()
      ..color = color.withOpacity(0.20)
      ..maskFilter = MaskFilter.blur(BlurStyle.inner, cs * 0.25)
      ..isAntiAlias = true;
    canvas.drawRRect(rrect, glowPaint);

    // Main fill
    final mainPaint = Paint()
      ..color = color
      ..isAntiAlias = true;
    canvas.drawRRect(rrect, mainPaint);

    // Glossy top-left bevel highlight (white 40% opacity)
    final highlightRect = Rect.fromLTWH(x + 1, y + 1, cs - 2, (cs - 2) * 0.45);
    final highlightRRect = RRect.fromRectAndCorners(
      highlightRect,
      topLeft: Radius.circular(radius),
      topRight: Radius.circular(radius),
    );
    final highlightPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withOpacity(0.40),
          Colors.white.withOpacity(0.05),
        ],
      ).createShader(highlightRect)
      ..isAntiAlias = true;
    canvas.drawRRect(highlightRRect, highlightPaint);

    // Dark bottom-right shadow edge (black 30% opacity)
    final shadowRect = Rect.fromLTWH(x + 1, y + 1 + (cs - 2) * 0.6, cs - 2, (cs - 2) * 0.4);
    final shadowRRect = RRect.fromRectAndCorners(
      shadowRect,
      bottomLeft: Radius.circular(radius),
      bottomRight: Radius.circular(radius),
    );
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.30)
      ..isAntiAlias = true;
    canvas.drawRRect(shadowRRect, shadowPaint);

    if (locked) {
      // Thin bright top highlight line
      final edgePaint = Paint()
        ..color = Colors.white.withOpacity(0.55)
        ..strokeWidth = 1.2
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke;
      canvas.drawLine(
        Offset(x + 1 + radius, y + 1.6),
        Offset(x + cs - 1 - radius, y + 1.6),
        edgePaint,
      );
    }
  }

  void _drawRightPanel(Canvas canvas, double x, double y, double w, double h, double cellSize) {
    double cy = y + 6;

    // ── NEXT preview box ─────────────────────────────────────────────────────
    _paintLabel(canvas, 'NEXT', x, cy, w, const Color(0xFF00E5FF), 9.5, neonGlow: true);
    cy += 15;

    final previewCs = (cellSize * 0.75).floorToDouble();
    final previewCells = _kShapes[nextType][0] as List<List<int>>;

    int minR = 4, maxR = 0, minC = 4, maxC = 0;
    for (final cell in previewCells) {
      if (cell[0] < minR) minR = cell[0];
      if (cell[0] > maxR) maxR = cell[0];
      if (cell[1] < minC) minC = cell[1];
      if (cell[1] > maxC) maxC = cell[1];
    }
    final previewRows = maxR - minR + 1;
    final previewCols = maxC - minC + 1;
    final previewBoxW = previewCols * previewCs + 10;
    final previewBoxH = previewRows * previewCs + 10;
    final previewBoxX = x + (w - previewBoxW) / 2;
    final previewBoxY = cy;

    // Glowing border box for next piece
    final nextBgPaint = Paint()..color = const Color(0xFF0D0D1A);
    final nextBoxRect = Rect.fromLTWH(previewBoxX - 2, previewBoxY - 2, previewBoxW + 4, previewBoxH + 4);
    final nextBoxRRect = RRect.fromRectAndRadius(nextBoxRect, const Radius.circular(6));
    canvas.drawRRect(nextBoxRRect, nextBgPaint);

    final nextColor = _kColors[nextType];
    final nextGlowPaint = Paint()
      ..color = nextColor.withOpacity(0.20)
      ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(nextBoxRRect, nextGlowPaint);
    final nextBorderPaint = Paint()
      ..color = nextColor.withOpacity(0.50)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawRRect(nextBoxRRect, nextBorderPaint);

    final previewOffX = previewBoxX + 5;
    final previewOffY = previewBoxY + 5;
    for (final cell in previewCells) {
      final pr = cell[0] - minR;
      final pc = cell[1] - minC;
      _drawCell(
        canvas,
        previewOffX + pc * previewCs,
        previewOffY + pr * previewCs,
        previewCs,
        _kColors[nextType],
        locked: true,
      );
    }
    cy += previewBoxH + 8 + 4;

    // ── Divider ──────────────────────────────────────────────────────────────
    _drawDivider(canvas, x, cy, w);
    cy += 9;

    // ── SCORE card ───────────────────────────────────────────────────────────
    _paintLabel(canvas, 'SCORE', x, cy, w, const Color(0xFF00E5FF), 9, neonGlow: true);
    cy += 13;
    _paintLabel(canvas, '$score', x, cy, w, Colors.white, 14, bold: true);
    cy += 19;

    // ── BEST card ────────────────────────────────────────────────────────────
    _paintLabel(canvas, 'BEST', x, cy, w, const Color(0xFFFFD700), 9, neonGlow: true);
    cy += 13;
    _paintLabel(canvas, '$hiScore', x, cy, w, const Color(0xFFFFD700), 13, bold: true);
    cy += 18;

    _drawDivider(canvas, x, cy, w);
    cy += 9;

    // ── LVL card ─────────────────────────────────────────────────────────────
    _paintLabel(canvas, 'LVL', x, cy, w, const Color(0xFFCC00FF), 9, neonGlow: true);
    cy += 13;
    _paintLabel(canvas, '$level', x, cy, w, const Color(0xFFE040FB), 14, bold: true);
    cy += 19;

    // ── LINES card ───────────────────────────────────────────────────────────
    _paintLabel(canvas, 'LINES', x, cy, w, const Color(0xFF00E676), 9, neonGlow: true);
    cy += 13;
    _paintLabel(canvas, '$totalLines', x, cy, w, const Color(0xFF00E676), 13, bold: true);
  }

  void _paintLabel(
    Canvas canvas,
    String text,
    double x,
    double y,
    double w,
    Color color,
    double fontSize, {
    bool bold = false,
    bool neonGlow = false,
  }) {
    final List<Shadow> shadows = neonGlow
        ? [
            Shadow(color: color.withOpacity(0.8), blurRadius: 8),
            Shadow(color: color.withOpacity(0.4), blurRadius: 16),
          ]
        : [];

    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
          letterSpacing: 1.2,
          shadows: shadows,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout(maxWidth: w);
    tp.paint(canvas, Offset(x + (w - tp.width) / 2, y));
    tp.dispose();
  }

  void _drawDivider(Canvas canvas, double x, double y, double w) {
    final divPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          const Color(0xFF00E5FF).withOpacity(0.30),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(x, y, w, 1));
    canvas.drawRect(Rect.fromLTWH(x, y, w, 1), divPaint);
  }

  @override
  bool shouldRepaint(_TetrisPainter old) => true;
}
