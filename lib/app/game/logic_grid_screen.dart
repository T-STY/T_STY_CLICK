import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'arcade_input_controller.dart';
import 'high_score_service.dart';

// ─── Cell State ──────────────────────────────────────────────────────────────

enum _CellState { hidden, revealed, flagged }

class _Cell {
  bool hasMine;
  int neighborCount;
  _CellState state;
  _Cell()
      : hasMine = false,
        neighborCount = 0,
        state = _CellState.hidden;
}

// ─── Screen ──────────────────────────────────────────────────────────────────

class LogicGridScreen extends StatefulWidget {
  final String userId;
  final DocumentReference rewardsDocRef;
  final double currentSaldo;
  final ArcadeInputController controller;
  final void Function(double) onSaldoChanged;

  const LogicGridScreen({
    super.key,
    required this.userId,
    required this.rewardsDocRef,
    required this.currentSaldo,
    required this.controller,
    required this.onSaldoChanged,
  });

  @override
  State<LogicGridScreen> createState() => _LogicGridScreenState();
}

class _LogicGridScreenState extends State<LogicGridScreen> {
  // Grid
  late List<List<_Cell>> _grid;
  int _cursorRow = 4, _cursorCol = 4;
  bool _firstReveal = true;
  int _revealedCount = 0;
  int _flagCount = 0;
  int _score = 0;
  int _hiScore = 0;
  late double _saldo;
  bool _awardingPoints = false;
  bool _isRunning = false;
  bool _isWon = false;
  bool _isLost = false;
  Timer? _ticker;
  int _elapsedSeconds = 0;

  // Track which mine was triggered first (for color highlight)
  int _triggeredMineRow = -1;
  int _triggeredMineCol = -1;

  @override
  void initState() {
    super.initState();
    _saldo = widget.currentSaldo;
    _initGrid();
    HighScoreService.load('minesweeper').then((v) {
      if (mounted) setState(() => _hiScore = v);
    });
    widget.controller.addListener(_onControllerEvent);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerEvent);
    _ticker?.cancel();
    super.dispose();
  }

  void _initGrid() {
    _grid = List.generate(9, (_) => List.generate(9, (_) => _Cell()));
    _cursorRow = 4;
    _cursorCol = 4;
    _firstReveal = true;
    _revealedCount = 0;
    _flagCount = 0;
    _elapsedSeconds = 0;
    _triggeredMineRow = -1;
    _triggeredMineCol = -1;
  }

  void _restart() {
    _ticker?.cancel();
    _ticker = null;
    _isRunning = false;
    _isWon = false;
    _isLost = false;
    _score = 0;
    _awardingPoints = false;
    _initGrid();
    setState(() {});
  }

  // ─── Mine Placement ────────────────────────────────────────────────────────

  static const int _kMineCount = 12; // was 10 — harder

  void _placeMines(int safeRow, int safeCol) {
    final rng = Random();
    int placed = 0;
    while (placed < _kMineCount) {
      final r = rng.nextInt(9), c = rng.nextInt(9);
      if ((r - safeRow).abs() <= 1 && (c - safeCol).abs() <= 1) continue;
      if (_grid[r][c].hasMine) continue;
      _grid[r][c].hasMine = true;
      placed++;
    }
    // Count neighbors
    for (int r = 0; r < 9; r++) {
      for (int c = 0; c < 9; c++) {
        if (_grid[r][c].hasMine) continue;
        int count = 0;
        for (int dr = -1; dr <= 1; dr++) {
          for (int dc = -1; dc <= 1; dc++) {
            if (dr == 0 && dc == 0) continue;
            final nr = r + dr, nc = c + dc;
            if (nr >= 0 && nr < 9 && nc >= 0 && nc < 9 && _grid[nr][nc].hasMine) count++;
          }
        }
        _grid[r][c].neighborCount = count;
      }
    }
  }

  // ─── Reveal (flood-fill) ───────────────────────────────────────────────────

  void _reveal(int row, int col) {
    if (row < 0 || row >= 9 || col < 0 || col >= 9) return;
    final cell = _grid[row][col];
    if (cell.state != _CellState.hidden) return;
    cell.state = _CellState.revealed;
    _revealedCount++;
    if (cell.neighborCount == 0 && !cell.hasMine) {
      for (int dr = -1; dr <= 1; dr++) {
        for (int dc = -1; dc <= 1; dc++) {
          if (dr != 0 || dc != 0) _reveal(row + dr, col + dc);
        }
      }
    }
  }

  // ─── Win / Loss ────────────────────────────────────────────────────────────

  void _checkWin() {
    if (_revealedCount >= 81 - _kMineCount) {
      // 81 - 12 mines = 69
      _isWon = true;
      _ticker?.cancel();
      _ticker = null;
      _score = max(0, 1000 - _elapsedSeconds * 5) + _flagCount * 20;
      _awardWin();
    }
  }

  Future<void> _awardWin() async {
    if (_awardingPoints) return;
    _awardingPoints = true;
    HapticFeedback.mediumImpact();
    final newSaldo = _saldo + 1;
    _saldo = newSaldo;
    widget.onSaldoChanged(newSaldo);
    await _updateFirestore(newSaldo);
    await HighScoreService.submit('minesweeper', _score);
    final best = await HighScoreService.load('minesweeper');
    if (mounted) setState(() => _hiScore = best);
  }

  void _triggerLoss() {
    _triggeredMineRow = _cursorRow;
    _triggeredMineCol = _cursorCol;
    // Reveal all mines
    for (int r = 0; r < 9; r++) {
      for (int c = 0; c < 9; c++) {
        if (_grid[r][c].hasMine) {
          _grid[r][c].state = _CellState.revealed;
        }
      }
    }
    _isLost = true;
    _ticker?.cancel();
    _ticker = null;
    _score = _revealedCount * 10;
    HighScoreService.submit('minesweeper', _score).then((_) {
      HighScoreService.load('minesweeper').then((v) {
        if (mounted) setState(() => _hiScore = v);
      });
    });
  }

  // ─── Controller ────────────────────────────────────────────────────────────

  void _onControllerEvent() {
    final event = widget.controller.lastEvent;
    if (event == null || !event.isDown) return;

    // If game over/won, any relevant button restarts
    if (_isWon || _isLost) {
      if (event.button == ArcadeButton.start || event.button == ArcadeButton.a) {
        _restart();
      }
      return;
    }

    // Start screen: mark running on any button press
    if (!_isRunning) {
      setState(() => _isRunning = true);
      // Only navigate or flag after running, fall through to handle input
    }

    setState(() {
      switch (event.button) {
        case ArcadeButton.up:
          _cursorRow = (_cursorRow - 1).clamp(0, 8);
          break;
        case ArcadeButton.down:
          _cursorRow = (_cursorRow + 1).clamp(0, 8);
          break;
        case ArcadeButton.left:
          _cursorCol = (_cursorCol - 1).clamp(0, 8);
          break;
        case ArcadeButton.right:
          _cursorCol = (_cursorCol + 1).clamp(0, 8);
          break;
        case ArcadeButton.a:
          _handleReveal();
          break;
        case ArcadeButton.b:
          _handleFlag();
          break;
        case ArcadeButton.start:
          _restart();
          break;
        default:
          break;
      }
    });
  }

  void _handleReveal() {
    final row = _cursorRow, col = _cursorCol;
    final cell = _grid[row][col];

    if (cell.state == _CellState.flagged) return;
    if (cell.state == _CellState.revealed) return;

    if (_firstReveal) {
      _placeMines(row, col);
      _firstReveal = false;
      // Start timer
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted && !_isWon && !_isLost) {
          setState(() => _elapsedSeconds++);
        }
      });
    }

    if (cell.hasMine) {
      HapticFeedback.heavyImpact();
      _triggerLoss();
    } else {
      HapticFeedback.lightImpact();
      _reveal(row, col);
      _checkWin();
    }
  }

  void _handleFlag() {
    if (_firstReveal) return; // don't allow flags before first reveal
    final cell = _grid[_cursorRow][_cursorCol];
    if (cell.state == _CellState.revealed) return;
    if (cell.state == _CellState.flagged) {
      cell.state = _CellState.hidden;
      _flagCount--;
      HapticFeedback.selectionClick();
    } else {
      if (_flagCount >= _kMineCount) return;
      cell.state = _CellState.flagged;
      _flagCount++;
      HapticFeedback.selectionClick();
    }
  }

  // ─── Firestore ─────────────────────────────────────────────────────────────

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
      debugPrint('LogicGrid Firestore: $e');
    }
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: Stack(
        children: [
          // Main game painter
          Positioned.fill(
            child: CustomPaint(
              painter: _GridPainter(
                grid: _grid,
                cursorRow: _cursorRow,
                cursorCol: _cursorCol,
                isLost: _isLost,
                isWon: _isWon,
                flagCount: _flagCount,
                elapsedSeconds: _elapsedSeconds,
                score: _score,
                triggeredMineRow: _triggeredMineRow,
                triggeredMineCol: _triggeredMineCol,
              ),
            ),
          ),
          // Start overlay
          if (!_isRunning) _buildStartOverlay(),
          // Win overlay
          if (_isWon) _buildWinOverlay(),
          // Loss overlay
          if (_isLost) _buildLossOverlay(),
        ],
      ),
    );
  }

  Widget _buildStartOverlay() {
    return Positioned.fill(
      child: Container(
        color: const Color(0xCC0D0D1E),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('💣 CAMPO MINADO',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 2)),
              const SizedBox(height: 20),
              const Text('← → ↑ ↓ : mover cursor',
                  style: TextStyle(fontSize: 13, color: Color(0xFFCCCCCC))),
              const SizedBox(height: 6),
              const Text('A : revelar   B : bandera',
                  style: TextStyle(fontSize: 13, color: Color(0xFFCCCCCC))),
              const SizedBox(height: 6),
              const Text('12 minas · Ganar: 1000−(t×5)+banderas×20',
                  style: TextStyle(fontSize: 11, color: Color(0xFF00FFCC))),
              const SizedBox(height: 4),
              const Text('+1 pto por tablero completado',
                  style: TextStyle(fontSize: 11, color: Color(0xFF00FFCC))),
              const SizedBox(height: 20),
              const Text('Pulsa cualquier botón para empezar',
                  style: TextStyle(fontSize: 12, color: Color(0xFF888888))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWinOverlay() {
    return Positioned.fill(
      child: Container(
        color: const Color(0xCC0D0D1E),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('✅ ¡CAMPO LIMPIO!',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF44FF44),
                      letterSpacing: 1)),
              const SizedBox(height: 12),
              Text('Tiempo: ${_elapsedSeconds}s',
                  style: const TextStyle(fontSize: 14, color: Color(0xFFCCCCCC))),
              const SizedBox(height: 6),
              Text('Puntuación: $_score',
                  style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _restart,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E88E5),
                        foregroundColor: Colors.white,
                        shape: const StadiumBorder()),
                    child: const Text('Nueva Partida'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLossOverlay() {
    return Positioned.fill(
      child: Container(
        color: const Color(0xCC0D0D1E),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('💥 ¡MINA!',
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFF4444),
                      letterSpacing: 2)),
              const SizedBox(height: 12),
              Text('Puntuación: $_score',
                  style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('Mejor: $_hiScore',
                  style: const TextStyle(fontSize: 14, color: Color(0xFF00FFCC))),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _restart,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E88E5),
                        foregroundColor: Colors.white,
                        shape: const StadiumBorder()),
                    child: const Text('Nueva Partida'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Painter ─────────────────────────────────────────────────────────────────

class _GridPainter extends CustomPainter {
  final List<List<_Cell>> grid;
  final int cursorRow, cursorCol;
  final bool isLost, isWon;
  final int flagCount, elapsedSeconds, score;
  final int triggeredMineRow, triggeredMineCol;

  const _GridPainter({
    required this.grid,
    required this.cursorRow,
    required this.cursorCol,
    required this.isLost,
    required this.isWon,
    required this.flagCount,
    required this.elapsedSeconds,
    required this.score,
    required this.triggeredMineRow,
    required this.triggeredMineCol,
  });

  static const int kRows = 9;
  static const int kCols = 9;
  static const int kMines = 12;

  @override
  void paint(Canvas canvas, Size size) {
    final cs = min((size.width - 4) / kCols, (size.height - 40) / kRows).floorToDouble();
    final bx = ((size.width - cs * kCols) / 2).floorToDouble();
    const by = 36.0;

    _paintHud(canvas, size);
    _paintGrid(canvas, cs, bx, by);
  }

  void _paintHud(Canvas canvas, Size size) {
    final hudPaint = Paint()
      ..color = const Color(0xFF0D0D1E)
      ..isAntiAlias = false;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 36), hudPaint);

    final remaining = kMines - flagCount;
    final hudText = '💣 $remaining  ⏱ ${elapsedSeconds}s  ★ $score';
    final tp = TextPainter(
      text: TextSpan(
          text: hudText,
          style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'monospace')),
      textDirection: TextDirection.ltr,
    );
    tp.layout(maxWidth: size.width);
    tp.paint(canvas, Offset((size.width - tp.width) / 2, (36 - tp.height) / 2));
  }

  void _paintGrid(Canvas canvas, double cs, double bx, double by) {
    // Background
    final bgPaint = Paint()
      ..color = const Color(0xFF1A1A2E)
      ..isAntiAlias = false;
    canvas.drawRect(
        Rect.fromLTWH(bx, by, cs * kCols, cs * kRows), bgPaint);

    for (int r = 0; r < kRows; r++) {
      for (int c = 0; c < kCols; c++) {
        final x = bx + c * cs;
        final y = by + r * cs;
        final cell = grid[r][c];
        _paintCell(canvas, cell, x, y, cs, r, c);
      }
    }

    // Cursor border (on top of cells)
    final cx = bx + cursorCol * cs;
    final cy = by + cursorRow * cs;
    final cursorPaint = Paint()
      ..color = const Color(0xFF00FFCC)
      ..isAntiAlias = false
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(Rect.fromLTWH(cx + 1, cy + 1, cs - 2, cs - 2), cursorPaint);
  }

  void _paintCell(Canvas canvas, _Cell cell, double x, double y, double cs, int r, int c) {
    final rect = Rect.fromLTWH(x, y, cs, cs);

    if (cell.state == _CellState.hidden || cell.state == _CellState.flagged) {
      // Hidden / flagged: embossed look
      final basePaint = Paint()
        ..color = const Color(0xFF3A3A5A)
        ..isAntiAlias = false;
      canvas.drawRect(rect, basePaint);

      // Top edge bright
      final brightPaint = Paint()
        ..color = const Color(0xFF5A5A7A)
        ..isAntiAlias = false;
      canvas.drawRect(Rect.fromLTWH(x, y, cs, 1), brightPaint);
      // Left edge bright
      canvas.drawRect(Rect.fromLTWH(x, y, 1, cs), brightPaint);

      // Bottom edge dark
      final darkPaint = Paint()
        ..color = const Color(0xFF1A1A3A)
        ..isAntiAlias = false;
      canvas.drawRect(Rect.fromLTWH(x, y + cs - 1, cs, 1), darkPaint);
      // Right edge dark
      canvas.drawRect(Rect.fromLTWH(x + cs - 1, y, 1, cs), darkPaint);

      if (cell.state == _CellState.flagged) {
        _paintFlag(canvas, x, y, cs);
      }
    } else {
      // Revealed
      if (cell.hasMine) {
        // Mine background
        final Color mineBgColor;
        if (r == triggeredMineRow && c == triggeredMineCol) {
          mineBgColor = const Color(0xFFFF6600);
        } else {
          mineBgColor = const Color(0xFFFF0000);
        }
        final mineBgPaint = Paint()
          ..color = mineBgColor
          ..isAntiAlias = false;
        canvas.drawRect(rect, mineBgPaint);
        _paintMine(canvas, x, y, cs);
      } else {
        // Revealed empty / numbered
        final revealedPaint = Paint()
          ..color = const Color(0xFF222238)
          ..isAntiAlias = false;
        canvas.drawRect(rect, revealedPaint);

        // Inner border (inset look)
        final innerBorderPaint = Paint()
          ..color = const Color(0xFF1A1A2E)
          ..isAntiAlias = false;
        canvas.drawRect(Rect.fromLTWH(x, y, cs, 1), innerBorderPaint);
        canvas.drawRect(Rect.fromLTWH(x, y, 1, cs), innerBorderPaint);

        if (cell.neighborCount > 0) {
          _paintNumber(canvas, cell.neighborCount, x, y, cs);
        }
      }
    }
  }

  static const List<Color> _numColors = [
    Colors.transparent, // 0 (unused)
    Color(0xFF4444FF), // 1
    Color(0xFF44AA44), // 2
    Color(0xFFFF4444), // 3
    Color(0xFF000088), // 4
    Color(0xFF880000), // 5
    Color(0xFF008888), // 6
    Color(0xFF000000), // 7
    Color(0xFF888888), // 8
  ];

  void _paintNumber(Canvas canvas, int n, double x, double y, double cs) {
    final color = (n >= 1 && n <= 8) ? _numColors[n] : Colors.white;
    final tp = TextPainter(
      text: TextSpan(
          text: '$n',
          style: TextStyle(
              color: color,
              fontSize: cs * 0.55,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace')),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset(x + (cs - tp.width) / 2, y + (cs - tp.height) / 2));
  }

  void _paintMine(Canvas canvas, double x, double y, double cs) {
    // Center a 7×7 sprite area
    final cx = (x + cs / 2).floorToDouble();
    final cy = (y + cs / 2).floorToDouble();

    final minePaint = Paint()
      ..color = const Color(0xFF111111)
      ..isAntiAlias = false;

    // Body: 3 overlapping rects (5×3, 3×5, 7×1 center)
    canvas.drawRect(Rect.fromLTWH(cx - 2, cy - 1, 5, 3), minePaint); // 5×3
    canvas.drawRect(Rect.fromLTWH(cx - 1, cy - 2, 3, 5), minePaint); // 3×5
    canvas.drawRect(Rect.fromLTWH(cx - 3, cy, 7, 1), minePaint); // 7×1 center

    // 4 spikes (1×2 rects)
    canvas.drawRect(Rect.fromLTWH(cx, cy - 4, 1, 2), minePaint); // up
    canvas.drawRect(Rect.fromLTWH(cx, cy + 3, 1, 2), minePaint); // down
    canvas.drawRect(Rect.fromLTWH(cx - 4, cy, 2, 1), minePaint); // left
    canvas.drawRect(Rect.fromLTWH(cx + 3, cy, 2, 1), minePaint); // right

    // Highlight dot
    final hlPaint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..isAntiAlias = false;
    canvas.drawRect(Rect.fromLTWH(cx - 1, cy - 1, 1, 1), hlPaint);
  }

  void _paintFlag(Canvas canvas, double x, double y, double cs) {
    final polePaint = Paint()
      ..color = const Color(0xFF333333)
      ..isAntiAlias = false;
    final flagPaint = Paint()
      ..color = const Color(0xFFFF2222)
      ..isAntiAlias = false;

    final poleX = (x + cs * 0.5).floorToDouble();
    final poleTop = (y + cs * 0.2).floorToDouble();
    final poleH = (cs * 0.6).floorToDouble();

    // Pole: 1px wide
    canvas.drawRect(Rect.fromLTWH(poleX, poleTop, 1, poleH), polePaint);

    // Flag: 3px wide, cs*0.3 tall at top of pole
    final flagW = (cs * 0.35).floorToDouble();
    final flagH = (cs * 0.3).floorToDouble();
    canvas.drawRect(Rect.fromLTWH(poleX + 1, poleTop, flagW, flagH), flagPaint);
  }

  @override
  bool shouldRepaint(_GridPainter old) => true;
}
