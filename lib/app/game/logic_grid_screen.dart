import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'arcade_center_screen.dart' show AppLanguage;
import 'arcade_input_controller.dart';
import 'game_saldo.dart';
import 'high_score_service.dart';

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

class LogicGridScreen extends StatefulWidget {
  final String userId;
  final DocumentReference rewardsDocRef;
  final double currentSaldo;
  final ArcadeInputController controller;
  final void Function(double) onSaldoChanged;
  final AppLanguage language;

  const LogicGridScreen({
    super.key,
    required this.userId,
    required this.rewardsDocRef,
    required this.currentSaldo,
    required this.controller,
    required this.onSaldoChanged,
    this.language = AppLanguage.spanish,
  });

  @override
  State<LogicGridScreen> createState() => _LogicGridScreenState();
}

class _LogicGridScreenState extends State<LogicGridScreen> {
  late List<List<_Cell>> _grid;
  int _cursorRow = 4, _cursorCol = 4;
  bool _firstReveal = true;
  int _revealedCount = 0;
  int _flagCount = 0;
  int _score = 0;
  int _hiScore = 0;
  late double _saldo;
  late double _lastCommitted;
  bool _awardingPoints = false;
  bool _isRunning = false;
  bool _isWon = false;
  bool _isLost = false;
  bool _paused = false;
  Timer? _ticker;
  int _elapsedSeconds = 0;

  int _triggeredMineRow = -1;
  int _triggeredMineCol = -1;

  String _t(String es, String en) =>
      widget.language == AppLanguage.spanish ? es : en;

  @override
  void initState() {
    super.initState();
    _saldo = widget.currentSaldo;
    _lastCommitted = widget.currentSaldo;
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

  Future<void> _restart() async {
    final ns = await chargeForReplay(
        userId: widget.userId,
        rewardsDocRef: widget.rewardsDocRef,
        currentSaldo: _saldo);
    if (ns == null) return;
    if (!mounted) return;
    widget.onSaldoChanged(ns);
    _ticker?.cancel();
    _ticker = null;
    _isRunning = false;
    _isWon = false;
    _isLost = false;
    _score = 0;
    _awardingPoints = false;
    _initGrid();

    _lastCommitted = ns;
    setState(() => _saldo = ns);
  }

  static const int _kMineCount = 15;

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

  void _checkWin() {
    if (_revealedCount >= 81 - _kMineCount) {
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

  void _onControllerEvent() {
    final event = widget.controller.lastEvent;
    if (event == null || !event.isDown) return;

    if (_isWon || _isLost) {
      if (event.button == ArcadeButton.start || event.button == ArcadeButton.a) {
        _restart();
      }
      return;
    }

    if (!_isRunning) {
      setState(() => _isRunning = true);
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
          if (_isRunning && !_isWon && !_isLost) {
            setState(() => _paused = !_paused);
            if (_paused) { _ticker?.cancel(); _ticker = null; }
            else if (!_firstReveal) {
              _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
                if (mounted && !_isWon && !_isLost && !_paused) setState(() => _elapsedSeconds++);
              });
            }
          } else {
            _restart();
          }
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
    if (_firstReveal) return;
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

  Future<void> _updateFirestore(double newSaldo) async {

    final delta = newSaldo - _lastCommitted;
    if (delta == 0) return;
    final result = await applyArcadeDelta(
      delta: delta,
      reason: 'logic_grid',
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
    return Scaffold(
      backgroundColor: const Color(0xFF110E08),
      body: Stack(
        children: [
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
                language: widget.language,
              ),
            ),
          ),
          if (!_isRunning) _buildStartOverlay(),
          if (_isWon) _buildWinOverlay(),
          if (_isLost) _buildLossOverlay(),
          if (_paused && _isRunning) _buildPauseOverlay(),
        ],
      ),
    );
  }

  Widget _buildStartOverlay() {
    return Positioned.fill(
      child: Container(
        color: const Color(0xDD110E08),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_t('💣 CAMPO MINADO', '💣 MINEFIELD'),
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFF6600),
                      letterSpacing: 2)),
              const SizedBox(height: 4),
              Text(_t('ZONA PELIGROSA', 'DANGER ZONE'),
                  style: const TextStyle(fontSize: 11, color: Color(0xFFCCAA44), letterSpacing: 3)),
              const SizedBox(height: 20),
              Text(_t('← → ↑ ↓ : mover cursor', '← → ↑ ↓ : move cursor'),
                  style: const TextStyle(fontSize: 13, color: Color(0xFFCCBB88))),
              const SizedBox(height: 6),
              Text(_t('A : revelar   B : bandera', 'A : reveal   B : flag'),
                  style: const TextStyle(fontSize: 13, color: Color(0xFFCCBB88))),
              const SizedBox(height: 6),
              Text(_t('12 minas · 1000−(t×5)+banderas×20', '12 mines · 1000−(t×5)+flags×20'),
                  style: const TextStyle(fontSize: 11, color: Color(0xFFFFCC00))),
              const SizedBox(height: 4),
              Text(_t('+1 pto por tablero completado', '+1 pt per board cleared'),
                  style: const TextStyle(fontSize: 11, color: Color(0xFFFFCC00))),
              const SizedBox(height: 20),
              Text(_t('Pulsa cualquier botón para empezar', 'Press any button to start'),
                  style: const TextStyle(fontSize: 12, color: Color(0xFF887755))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWinOverlay() {
    return Positioned.fill(
      child: Container(
        color: const Color(0xDD110E08),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_t('✅ ¡CAMPO LIMPIO!', '✅ FIELD CLEARED!'),
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF88FF44),
                      letterSpacing: 1)),
              const SizedBox(height: 4),
              Text(_t('TODAS LAS MINAS NEUTRALIZADAS', 'ALL MINES NEUTRALIZED'),
                  style: const TextStyle(fontSize: 10, color: Color(0xFFCCAA44), letterSpacing: 2)),
              const SizedBox(height: 12),
              Text(_t('Tiempo: ${_elapsedSeconds}s', 'Time: ${_elapsedSeconds}s'),
                  style: const TextStyle(fontSize: 14, color: Color(0xFFCCBB88))),
              const SizedBox(height: 6),
              Text(_t('Puntuación: $_score', 'Score: $_score'),
                  style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _restart,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6600),
                        foregroundColor: Colors.white,
                        shape: const StadiumBorder()),
                    child: Text(_t('Nueva Partida', 'New Game'),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
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
        color: const Color(0xDD110E08),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_t('💥 ¡EXPLOSIÓN!', '💥 BOOM!'),
                  style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFF3300),
                      letterSpacing: 2)),
              const SizedBox(height: 4),
              Text(_t('HAS PISADO UNA MINA', 'YOU STEPPED ON A MINE'),
                  style: const TextStyle(fontSize: 11, color: Color(0xFFFF8844), letterSpacing: 2)),
              const SizedBox(height: 16),
              Text(_t('Puntuación: $_score', 'Score: $_score'),
                  style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(_t('Mejor: $_hiScore', 'Best: $_hiScore'),
                  style: const TextStyle(fontSize: 14, color: Color(0xFFFFCC00))),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _restart,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF3300),
                        foregroundColor: Colors.white,
                        shape: const StadiumBorder()),
                    child: Text(_t('Intentar de nuevo', 'Try Again'),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ],
          ),
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
          Text(_t('PAUSA', 'PAUSED'), style: const TextStyle(color: Color(0xFF88DDFF), fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 6)),
          const SizedBox(height: 16),
          Text(_t('START para continuar', 'START to resume'), style: const TextStyle(color: Color(0xFF446677), fontSize: 12)),
        ],
      ),
    ),
  );
}

class _GridPainter extends CustomPainter {
  final List<List<_Cell>> grid;
  final int cursorRow, cursorCol;
  final bool isLost, isWon;
  final int flagCount, elapsedSeconds, score;
  final int triggeredMineRow, triggeredMineCol;
  final AppLanguage language;

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
    this.language = AppLanguage.spanish,
  });

  String _t(String es, String en) =>
      language == AppLanguage.spanish ? es : en;

  static const int kRows = 9;
  static const int kCols = 9;
  static const int kMines = 12;

  @override
  void paint(Canvas canvas, Size size) {
    final cs = min((size.width - 4) / kCols, (size.height - 40) / kRows).floorToDouble();
    final bx = ((size.width - cs * kCols) / 2).floorToDouble();
    const by = 36.0;

    final fullBg = Paint()..color = const Color(0xFF110E08)..isAntiAlias = false;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), fullBg);

    _paintHud(canvas, size);
    _paintGrid(canvas, cs, bx, by);

    final gridBottom = by + cs * kRows;
    if (gridBottom + 20 < size.height) {
      _paintBottomArt(canvas, size, bx, gridBottom, cs * kCols);
    }
  }

  void _paintHud(Canvas canvas, Size size) {
    final hudPaint = Paint()
      ..color = const Color(0xFF1A1100)
      ..isAntiAlias = false;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 36), hudPaint);

    final stripePaint = Paint()..color = const Color(0xFFFF6600)..isAntiAlias = false;
    canvas.drawRect(Rect.fromLTWH(0, 34, size.width, 2), stripePaint);

    final remaining = kMines - flagCount;
    final tp = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(text: '💣 $remaining', style: const TextStyle(color: Color(0xFFFF6600), fontSize: 12, fontWeight: FontWeight.bold)),
          const TextSpan(text: '   '),
          TextSpan(text: '⏱ ${elapsedSeconds}s', style: const TextStyle(color: Color(0xFFCCBB88), fontSize: 12)),
          const TextSpan(text: '   '),
          TextSpan(text: '★ $score', style: const TextStyle(color: Color(0xFFFFDD44), fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout(maxWidth: size.width);
    tp.paint(canvas, Offset((size.width - tp.width) / 2, (34 - tp.height) / 2));
  }

  void _paintGrid(Canvas canvas, double cs, double bx, double by) {
    final framePaint = Paint()
      ..color = const Color(0xFF5A4A20)
      ..isAntiAlias = false
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(Rect.fromLTWH(bx - 1, by - 1, cs * kCols + 2, cs * kRows + 2), framePaint);

    final bgPaint = Paint()
      ..color = const Color(0xFF1E1A0E)
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

    final cx = bx + cursorCol * cs;
    final cy = by + cursorRow * cs;
    final cursorPaint = Paint()
      ..color = const Color(0xFFFF8C00)
      ..isAntiAlias = false
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(Rect.fromLTWH(cx + 1, cy + 1, cs - 2, cs - 2), cursorPaint);
  }

  void _paintCell(Canvas canvas, _Cell cell, double x, double y, double cs, int r, int c) {
    final rect = Rect.fromLTWH(x, y, cs, cs);

    if (cell.state == _CellState.hidden || cell.state == _CellState.flagged) {
      final basePaint = Paint()
        ..color = const Color(0xFF3D3820)
        ..isAntiAlias = false;
      canvas.drawRect(rect, basePaint);

      final brightPaint = Paint()
        ..color = const Color(0xFF6B6030)
        ..isAntiAlias = false;
      canvas.drawRect(Rect.fromLTWH(x, y, cs, 1), brightPaint);
      canvas.drawRect(Rect.fromLTWH(x, y, 1, cs), brightPaint);

      final darkPaint = Paint()
        ..color = const Color(0xFF1A1600)
        ..isAntiAlias = false;
      canvas.drawRect(Rect.fromLTWH(x, y + cs - 1, cs, 1), darkPaint);
      canvas.drawRect(Rect.fromLTWH(x + cs - 1, y, 1, cs), darkPaint);

      if (cell.state == _CellState.flagged) {
        _paintFlag(canvas, x, y, cs);
      }
    } else {
      if (cell.hasMine) {
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
        final revealedPaint = Paint()
          ..color = const Color(0xFF2A2610)
          ..isAntiAlias = false;
        canvas.drawRect(rect, revealedPaint);

        final innerBorderPaint = Paint()
          ..color = const Color(0xFF1A1600)
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
    Colors.transparent,
    Color(0xFF4444FF),
    Color(0xFF44AA44),
    Color(0xFFFF4444),
    Color(0xFF000088),
    Color(0xFF880000),
    Color(0xFF008888),
    Color(0xFF000000),
    Color(0xFF888888),
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
    final cx = (x + cs / 2).floorToDouble();
    final cy = (y + cs / 2).floorToDouble();

    final minePaint = Paint()
      ..color = const Color(0xFF111111)
      ..isAntiAlias = false;

    canvas.drawRect(Rect.fromLTWH(cx - 2, cy - 1, 5, 3), minePaint);
    canvas.drawRect(Rect.fromLTWH(cx - 1, cy - 2, 3, 5), minePaint);
    canvas.drawRect(Rect.fromLTWH(cx - 3, cy, 7, 1), minePaint);

    canvas.drawRect(Rect.fromLTWH(cx, cy - 4, 1, 2), minePaint);
    canvas.drawRect(Rect.fromLTWH(cx, cy + 3, 1, 2), minePaint);
    canvas.drawRect(Rect.fromLTWH(cx - 4, cy, 2, 1), minePaint);
    canvas.drawRect(Rect.fromLTWH(cx + 3, cy, 2, 1), minePaint);

    final hlPaint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..isAntiAlias = false;
    canvas.drawRect(Rect.fromLTWH(cx - 1, cy - 1, 1, 1), hlPaint);
  }

  void _paintBottomArt(Canvas canvas, Size size, double bx, double gridBottom, double boardW) {
    final artTop = gridBottom + 8;
    final artH = size.height - artTop - 4;
    if (artH < 30) return;

    final stripeH = 8.0;
    final stripeW = 14.0;
    int stripeCount = (boardW / (stripeW * 2)).ceil() + 2;
    for (int i = 0; i < stripeCount; i++) {
      final sx = bx + i * stripeW * 2 - stripeW;
      canvas.drawRect(Rect.fromLTWH(sx, artTop, stripeW, stripeH),
          Paint()..color = const Color(0xFFFFCC00)..isAntiAlias = false);
      canvas.drawRect(Rect.fromLTWH(sx + stripeW, artTop, stripeW, stripeH),
          Paint()..color = const Color(0xFF1A1600)..isAntiAlias = false);
    }
    canvas.drawRect(
      Rect.fromLTWH(0, artTop, bx, stripeH),
      Paint()..color = const Color(0xFF110E08)..isAntiAlias = false,
    );
    canvas.drawRect(
      Rect.fromLTWH(bx + boardW, artTop, size.width - bx - boardW, stripeH),
      Paint()..color = const Color(0xFF110E08)..isAntiAlias = false,
    );

    final contentTop = artTop + stripeH + 6;
    final contentH = size.height - contentTop - 4;
    if (contentH < 20) return;

    final cx = size.width / 2;
    final mineR = (contentH * 0.22).clamp(12.0, 28.0);
    final cy = contentTop + 20 + mineR * 1.6;

    for (int i = 3; i >= 1; i--) {
      canvas.drawCircle(
        Offset(cx, cy),
        mineR + i * 4,
        Paint()
          ..color = Color.fromARGB((40 / i).round(), 255, 80, 0)
          ..style = PaintingStyle.fill
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }

    final minePaint = Paint()..color = const Color(0xFF2A2A2A)..isAntiAlias = true;
    canvas.drawCircle(Offset(cx, cy), mineR, minePaint);

    final shinePaint = Paint()
      ..color = const Color(0xFF555555)
      ..isAntiAlias = true;
    canvas.drawCircle(Offset(cx - mineR * 0.3, cy - mineR * 0.3), mineR * 0.25, shinePaint);

    final spikeL = mineR * 0.55;
    final spikeW = mineR * 0.12;
    final spikePaint = Paint()..color = const Color(0xFF333333)..isAntiAlias = false;
    for (int i = 0; i < 8; i++) {
      final angle = i * pi / 4;
      final tipX = cx + cos(angle) * (mineR + spikeL);
      final tipY = cy + sin(angle) * (mineR + spikeL);
      final baseX1 = cx + cos(angle + pi / 2) * spikeW + cos(angle) * mineR;
      final baseY1 = cy + sin(angle + pi / 2) * spikeW + sin(angle) * mineR;
      final baseX2 = cx + cos(angle - pi / 2) * spikeW + cos(angle) * mineR;
      final baseY2 = cy + sin(angle - pi / 2) * spikeW + sin(angle) * mineR;
      final path = Path()
        ..moveTo(tipX, tipY)
        ..lineTo(baseX1, baseY1)
        ..lineTo(baseX2, baseY2)
        ..close();
      canvas.drawPath(path, spikePaint);
    }

    final fusePaint = Paint()
      ..color = const Color(0xFF886633)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    final fusePath = Path()
      ..moveTo(cx, cy - mineR)
      ..cubicTo(cx + 8, cy - mineR - 10, cx + 14, cy - mineR - 6, cx + 10, cy - mineR - 18);
    canvas.drawPath(fusePath, fusePaint);

    final sparkPaint = Paint()..color = const Color(0xFFFFAA00)..isAntiAlias = true;
    canvas.drawCircle(Offset(cx + 10, cy - mineR - 18), 3, sparkPaint);
    canvas.drawCircle(Offset(cx + 10, cy - mineR - 18), 2, Paint()..color = const Color(0xFFFFFFCC)..isAntiAlias = true);

    final textY = contentTop + 2.0;
    final titlePainter = TextPainter(
      text: TextSpan(
        text: _t('⚠  ZONA PELIGROSA  ⚠', '⚠  DANGER ZONE  ⚠'),
        style: const TextStyle(
          color: Color(0xFFFF6600),
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 2,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    titlePainter.layout(maxWidth: size.width);
    titlePainter.paint(canvas, Offset((size.width - titlePainter.width) / 2, textY));

    final statsY = cy + mineR * 1.6 + 6;
    final statsPainter = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(text: _t('12 MINAS  •  ', '12 MINES  •  '), style: const TextStyle(color: Color(0xFFFF4400), fontSize: 10, fontWeight: FontWeight.bold)),
          TextSpan(text: _t('+1 PTO POR TABLERO', '+1 PT PER BOARD'), style: const TextStyle(color: Color(0xFFCCBB88), fontSize: 10)),
        ],
      ),
      textDirection: TextDirection.ltr,
    );
    statsPainter.layout(maxWidth: size.width);
    statsPainter.paint(canvas, Offset((size.width - statsPainter.width) / 2, statsY));
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

    canvas.drawRect(Rect.fromLTWH(poleX, poleTop, 1, poleH), polePaint);

    final flagW = (cs * 0.35).floorToDouble();
    final flagH = (cs * 0.3).floorToDouble();
    canvas.drawRect(Rect.fromLTWH(poleX + 1, poleTop, flagW, flagH), flagPaint);
  }

  @override
  bool shouldRepaint(_GridPainter old) => true;
}
