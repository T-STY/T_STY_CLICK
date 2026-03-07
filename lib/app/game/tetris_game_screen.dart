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

enum _GameState { start, playing, paused, dead }

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

  int get _gravInterval => (800 - (_level - 1) * 50).clamp(80, 800);

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

    // Saldo: +1 per 10 lines (cumulative)
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
    // Try kicks: 0, -1, +1, -2, +2 col offsets, then -1 row
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
    // Try row kick
    if (_isValid(_pieceRow - 1, _pieceCol, newRot)) {
      setState(() {
        _rot = newRot;
        _pieceRow -= 1;
      });
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
          if (_state == _GameState.start || _state == _GameState.dead) {
            _restart();
          } else {
            _togglePause();
          }
        case ArcadeButton.a:
          if (_state == _GameState.dead || _state == _GameState.start) {
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
      ],
    );
  }

  Widget _buildStartOverlay() {
    return Positioned.fill(
      child: Container(
        color: const Color(0xCC000000),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'TETRIS',
              style: TextStyle(
                color: Color(0xFF00E5FF),
                fontSize: 48,
                fontWeight: FontWeight.bold,
                letterSpacing: 8,
              ),
            ),
            SizedBox(height: 32),
            Text(
              'A / UP  →  Rotar\nLEFT / RIGHT  →  Mover\nDOWN  →  Bajar\nY  →  Caída rápida\nSTART  →  Pausa',
              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.8),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 24),
            Text(
              '+1 pto cada 10 líneas',
              style: TextStyle(color: Color(0xFFFFD700), fontSize: 13, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 32),
            Text(
              'Pulsa A o START para empezar',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeathOverlay() {
    return Positioned.fill(
      child: Container(
        color: const Color(0xDD000000),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'GAME OVER',
              style: TextStyle(
                color: Color(0xFFFF1744),
                fontSize: 36,
                fontWeight: FontWeight.bold,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'SCORE: $_score',
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'BEST: $_hiScore',
              style: const TextStyle(color: Color(0xFFFFD700), fontSize: 16),
            ),
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _restart,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyan.shade700,
                    foregroundColor: Colors.white,
                    shape: const StadiumBorder(),
                  ),
                  child: const Text('Nueva Partida'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPauseOverlay() {
    return Positioned.fill(
      child: Container(
        color: const Color(0xBB000000),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'PAUSA',
              style: TextStyle(
                color: Colors.white,
                fontSize: 40,
                fontWeight: FontWeight.bold,
                letterSpacing: 6,
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Pulsa START para continuar',
              style: TextStyle(color: Colors.white54, fontSize: 14),
            ),
          ],
        ),
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

  @override
  void paint(Canvas canvas, Size size) {
    // ── Layout calculations ──────────────────────────────────────────────────
    final cellSize = (size.width * 0.60 / 10).floor().toDouble();
    final boardW = cellSize * 10;
    final boardH = cellSize * 20;
    final boardX = 0.0;
    final boardY = ((size.height - boardH) / 2).floorToDouble();

    // ── Background ──────────────────────────────────────────────────────────
    final bgPaint = Paint()
      ..color = const Color(0xFF0D0D0D)
      ..isAntiAlias = false;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // ── Board background ────────────────────────────────────────────────────
    final boardBgPaint = Paint()
      ..color = const Color(0xFF111111)
      ..isAntiAlias = false;
    canvas.drawRect(Rect.fromLTWH(boardX, boardY, boardW, boardH), boardBgPaint);

    // ── Grid lines ──────────────────────────────────────────────────────────
    final gridPaint = Paint()
      ..color = const Color(0xFF222222)
      ..isAntiAlias = false;
    for (int c = 0; c <= 10; c++) {
      canvas.drawRect(
        Rect.fromLTWH(boardX + c * cellSize, boardY, 1, boardH),
        gridPaint,
      );
    }
    for (int r = 0; r <= 20; r++) {
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

    // ── Ghost piece ─────────────────────────────────────────────────────────
    if (pieceType >= 0 && ghostRow != pieceRow) {
      final ghostColor = _kColors[pieceType].withOpacity(0.25);
      final ghostOutline = Paint()
        ..color = ghostColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..isAntiAlias = false;
      for (final cell in _kShapes[pieceType][rot] as List<List<int>>) {
        final gr = ghostRow + cell[0];
        final gc = pieceCol + cell[1];
        if (gr >= 0 && gr < 20 && gc >= 0 && gc < 10) {
          canvas.drawRect(
            Rect.fromLTWH(
              boardX + gc * cellSize + 1,
              boardY + gr * cellSize + 1,
              cellSize - 2,
              cellSize - 2,
            ),
            ghostOutline,
          );
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
    final mainPaint = Paint()
      ..color = color
      ..isAntiAlias = false;
    canvas.drawRect(Rect.fromLTWH(x + 1, y + 1, cs - 2, cs - 2), mainPaint);

    if (locked) {
      // Bright highlight top + left (2px)
      final highlightPaint = Paint()
        ..color = Color.fromARGB(180, 255, 255, 255)
        ..isAntiAlias = false;
      // Top edge
      canvas.drawRect(Rect.fromLTWH(x + 1, y + 1, cs - 2, 2), highlightPaint);
      // Left edge
      canvas.drawRect(Rect.fromLTWH(x + 1, y + 1, 2, cs - 2), highlightPaint);

      // Dark shadow bottom + right (2px)
      final shadowPaint = Paint()
        ..color = const Color(0x99000000)
        ..isAntiAlias = false;
      // Bottom edge
      canvas.drawRect(Rect.fromLTWH(x + 1, y + cs - 3, cs - 2, 2), shadowPaint);
      // Right edge
      canvas.drawRect(Rect.fromLTWH(x + cs - 3, y + 1, 2, cs - 2), shadowPaint);
    }
  }

  void _drawRightPanel(Canvas canvas, double x, double y, double w, double h, double cellSize) {
    double cy = y + 8;

    // ── NEXT ────────────────────────────────────────────────────────────────
    _paintLabel(canvas, 'NEXT', x, cy, w, const Color(0xFF888888), 10);
    cy += 16;

    final previewCs = (cellSize * 0.75).floorToDouble();
    final previewCells = _kShapes[nextType][0] as List<List<int>>;
    // Find bounding box of preview
    int minR = 4, maxR = 0, minC = 4, maxC = 0;
    for (final cell in previewCells) {
      if (cell[0] < minR) minR = cell[0];
      if (cell[0] > maxR) maxR = cell[0];
      if (cell[1] < minC) minC = cell[1];
      if (cell[1] > maxC) maxC = cell[1];
    }
    final previewRows = maxR - minR + 1;
    final previewCols = maxC - minC + 1;
    final previewOffX = x + (w - previewCols * previewCs) / 2;
    final previewOffY = cy;

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
    cy += previewRows * previewCs + 12;

    // Divider
    _drawDivider(canvas, x, cy, w);
    cy += 8;

    // ── SCORE ───────────────────────────────────────────────────────────────
    _paintLabel(canvas, 'SCORE', x, cy, w, const Color(0xFF888888), 10);
    cy += 14;
    _paintLabel(canvas, '$score', x, cy, w, Colors.white, 13);
    cy += 18;

    // ── BEST ────────────────────────────────────────────────────────────────
    _paintLabel(canvas, 'BEST', x, cy, w, const Color(0xFF888888), 10);
    cy += 14;
    _paintLabel(canvas, '$hiScore', x, cy, w, const Color(0xFFFFD700), 13);
    cy += 18;

    _drawDivider(canvas, x, cy, w);
    cy += 8;

    // ── LVL ─────────────────────────────────────────────────────────────────
    _paintLabel(canvas, 'LVL', x, cy, w, const Color(0xFF888888), 10);
    cy += 14;
    _paintLabel(canvas, '$level', x, cy, w, const Color(0xFF00E5FF), 13);
    cy += 18;

    // ── LINES ───────────────────────────────────────────────────────────────
    _paintLabel(canvas, 'LINES', x, cy, w, const Color(0xFF888888), 10);
    cy += 14;
    _paintLabel(canvas, '$totalLines', x, cy, w, const Color(0xFF00E676), 13);
  }

  void _paintLabel(Canvas canvas, String text, double x, double y, double w, Color color, double fontSize) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
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
      ..color = const Color(0xFF333333)
      ..isAntiAlias = false;
    canvas.drawRect(Rect.fromLTWH(x, y, w, 1), divPaint);
  }

  @override
  bool shouldRepaint(_TetrisPainter old) => true;
}
