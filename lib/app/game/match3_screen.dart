import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'arcade_input_controller.dart';
import 'high_score_service.dart';

// ─── Constants ────────────────────────────────────────────────────────────────

const _kCols = 7;
const _kRows = 8;
const _kGemColors = 5;   // 5 gem types
const _kRoundTime = 30;  // seconds per round
const _kMinMatch = 3;

// Gem colour palette (vibrant, distinct)
const _kGemPalette = [
  Color(0xFFE53935), // ruby red
  Color(0xFF1E88E5), // sapphire blue
  Color(0xFF43A047), // emerald green
  Color(0xFFFFB300), // amber
  Color(0xFF8E24AA), // amethyst purple
];

const _kGemNames = ['RUBÍ', 'ZAFIRO', 'ESMERALDA', 'ÁMBAR', 'AMATISTA'];

// ─── Widget ──────────────────────────────────────────────────────────────────

class Match3Screen extends StatefulWidget {
  final String userId;
  final DocumentReference rewardsDocRef;
  final double currentSaldo;
  final ArcadeInputController controller;
  final void Function(double) onSaldoChanged;

  const Match3Screen({
    super.key,
    required this.userId,
    required this.rewardsDocRef,
    required this.currentSaldo,
    required this.controller,
    required this.onSaldoChanged,
  });

  @override
  State<Match3Screen> createState() => _Match3ScreenState();
}

// ─── State ────────────────────────────────────────────────────────────────────

class _Match3ScreenState extends State<Match3Screen> {
  // Board: -1 = empty, 0-4 = gem type
  late List<List<int>> _board;

  // Cursor
  int _cursorCol = 3, _cursorRow = 3;

  // Swap selection
  int? _selCol, _selRow;

  // Game stats
  int _score = 0;
  int _round = 1;
  int _timeLeft = _kRoundTime;
  int _roundTarget = 300;    // score needed to clear round
  int _hiScore = 0;
  late double _saldo;

  // Phase
  bool _isPlaying = false;
  bool _isDead = false;
  bool _roundComplete = false;
  bool _roundCompleteDelay = false;

  // Animation
  bool _swapFlash = false;
  int _comboCount = 0;

  Timer? _gameTicker;
  Timer? _secondTicker;
  final Random _rng = Random();

  @override
  void initState() {
    super.initState();
    _saldo = widget.currentSaldo;
    widget.controller.addListener(_onControllerEvent);
    HighScoreService.load('match3').then((v) => setState(() => _hiScore = v));
    _initBoard();
  }

  @override
  void dispose() {
    _gameTicker?.cancel();
    _secondTicker?.cancel();
    widget.controller.removeListener(_onControllerEvent);
    super.dispose();
  }

  // ── Board init ─────────────────────────────────────────────────────────────

  void _initBoard() {
    _board = List.generate(_kRows, (_) =>
        List.generate(_kCols, (_) => _rng.nextInt(_kGemColors)));
    // Ensure no pre-existing matches
    for (int r = 0; r < _kRows; r++) {
      for (int c = 0; c < _kCols; c++) {
        int gem = _board[r][c];
        int tries = 0;
        while (_wouldMatchAt(r, c, gem) && tries < 20) {
          gem = _rng.nextInt(_kGemColors);
          tries++;
        }
        _board[r][c] = gem;
      }
    }
  }

  bool _wouldMatchAt(int r, int c, int gem) {
    // Horizontal
    if (c >= 2 && _board[r][c - 1] == gem && _board[r][c - 2] == gem) return true;
    // Vertical
    if (r >= 2 && _board[r - 1][c] == gem && _board[r - 2][c] == gem) return true;
    return false;
  }

  // ── Input ──────────────────────────────────────────────────────────────────

  void _onControllerEvent() {
    final event = widget.controller.lastEvent;
    if (event == null || !event.isDown) return;
    final btn = event.button;

    if (!_isPlaying && !_isDead) {
      if (btn == ArcadeButton.a || btn == ArcadeButton.start) _startGame();
      return;
    }
    if (_isDead) {
      if (btn == ArcadeButton.a || btn == ArcadeButton.start) _restart();
      return;
    }
    if (_roundCompleteDelay) return;

    switch (btn) {
      case ArcadeButton.up:
        setState(() => _cursorRow = (_cursorRow - 1 + _kRows) % _kRows);
        HapticFeedback.selectionClick();
      case ArcadeButton.down:
        setState(() => _cursorRow = (_cursorRow + 1) % _kRows);
        HapticFeedback.selectionClick();
      case ArcadeButton.left:
        setState(() => _cursorCol = (_cursorCol - 1 + _kCols) % _kCols);
        HapticFeedback.selectionClick();
      case ArcadeButton.right:
        setState(() => _cursorCol = (_cursorCol + 1) % _kCols);
        HapticFeedback.selectionClick();
      case ArcadeButton.a:
        _selectOrSwap();
      case ArcadeButton.b:
        setState(() { _selCol = null; _selRow = null; });
        HapticFeedback.lightImpact();
      default:
        break;
    }
  }

  void _selectOrSwap() {
    if (_selCol == null) {
      // First selection
      setState(() { _selCol = _cursorCol; _selRow = _cursorRow; });
      HapticFeedback.mediumImpact();
    } else {
      // Check adjacency
      final dc = (_cursorCol - _selCol!).abs();
      final dr = (_cursorRow - _selRow!).abs();
      if ((dc == 1 && dr == 0) || (dc == 0 && dr == 1)) {
        _doSwap(_selCol!, _selRow!, _cursorCol, _cursorRow);
      } else {
        // Re-select
        setState(() { _selCol = _cursorCol; _selRow = _cursorRow; });
        HapticFeedback.lightImpact();
      }
    }
  }

  void _doSwap(int c1, int r1, int c2, int r2) {
    // Swap
    final tmp = _board[r1][c1];
    _board[r1][c1] = _board[r2][c2];
    _board[r2][c2] = tmp;

    final matches = _findMatches();
    if (matches.isEmpty) {
      // Invalid swap — revert
      _board[r2][c2] = _board[r1][c1];
      _board[r1][c1] = tmp;
      HapticFeedback.lightImpact();
      setState(() { _selCol = null; _selRow = null; });
      return;
    }

    _selCol = null; _selRow = null;
    _comboCount = 0;
    _resolveMatches();
  }

  void _resolveMatches() {
    final matches = _findMatches();
    if (matches.isEmpty) {
      _comboCount = 0;
      setState(() {});
      _checkRoundComplete();
      return;
    }

    _comboCount++;
    final pts = matches.length * 10 * _comboCount;
    _score += pts;
    HapticFeedback.mediumImpact();
    if (_comboCount >= 2) HapticFeedback.heavyImpact();

    // Clear matched cells
    for (final pos in matches) {
      _board[pos.$1][pos.$2] = -1;
    }

    // Gravity — gems fall down
    for (int c = 0; c < _kCols; c++) {
      final col = [for (int r = 0; r < _kRows; r++) _board[r][c]];
      final gems = col.where((g) => g != -1).toList();
      final empties = List.filled(_kRows - gems.length, -1);
      final newCol = [...empties, ...gems];
      for (int r = 0; r < _kRows; r++) _board[r][c] = newCol[r];
    }

    // Fill empty cells from top
    for (int r = 0; r < _kRows; r++) {
      for (int c = 0; c < _kCols; c++) {
        if (_board[r][c] == -1) {
          _board[r][c] = _rng.nextInt(_kGemColors);
        }
      }
    }

    setState(() {});
    // Chain resolve after brief delay
    Future.delayed(const Duration(milliseconds: 220), _resolveMatches);
  }

  List<(int, int)> _findMatches() {
    final Set<(int, int)> matched = {};

    // Horizontal runs
    for (int r = 0; r < _kRows; r++) {
      int run = 1;
      for (int c = 1; c < _kCols; c++) {
        if (_board[r][c] != -1 && _board[r][c] == _board[r][c - 1]) {
          run++;
        } else {
          if (run >= _kMinMatch) {
            for (int k = c - run; k < c; k++) matched.add((r, k));
          }
          run = 1;
        }
      }
      if (run >= _kMinMatch) {
        for (int k = _kCols - run; k < _kCols; k++) matched.add((r, k));
      }
    }

    // Vertical runs
    for (int c = 0; c < _kCols; c++) {
      int run = 1;
      for (int r = 1; r < _kRows; r++) {
        if (_board[r][c] != -1 && _board[r][c] == _board[r - 1][c]) {
          run++;
        } else {
          if (run >= _kMinMatch) {
            for (int k = r - run; k < r; k++) matched.add((k, c));
          }
          run = 1;
        }
      }
      if (run >= _kMinMatch) {
        for (int k = _kRows - run; k < _kRows; k++) matched.add((k, c));
      }
    }

    return matched.toList();
  }

  void _checkRoundComplete() {
    if (_score >= _roundTarget && !_roundComplete) {
      _roundComplete = true;
      _roundCompleteDelay = true;
      HapticFeedback.heavyImpact();
      _awardRoundSaldo();
      Future.delayed(const Duration(milliseconds: 1800), _startNextRound);
    }
  }

  void _startNextRound() {
    if (!mounted) return;
    _round++;
    _roundTarget = _roundTarget + (_round * 200);
    _timeLeft = max(15, _kRoundTime - (_round - 1) * 3); // fewer seconds each round
    _roundComplete = false;
    _roundCompleteDelay = false;
    _comboCount = 0;
    _initBoard();
    setState(() {});
  }

  // ── Game lifecycle ─────────────────────────────────────────────────────────

  void _startGame() {
    setState(() {
      _score = 0;
      _round = 1;
      _timeLeft = _kRoundTime;
      _roundTarget = 300;
      _isDead = false;
      _roundComplete = false;
      _roundCompleteDelay = false;
      _comboCount = 0;
      _cursorCol = 3; _cursorRow = 3;
      _selCol = null; _selRow = null;
      _isPlaying = true;
    });
    _initBoard();

    _secondTicker?.cancel();
    _secondTicker = Timer.periodic(const Duration(seconds: 1), _onSecondTick);
  }

  void _onSecondTick(Timer _) {
    if (!_isPlaying || _roundComplete || _roundCompleteDelay) return;
    setState(() {
      _timeLeft--;
      if (_timeLeft <= 5) HapticFeedback.lightImpact();
      if (_timeLeft <= 0) _triggerDeath();
    });
  }

  void _triggerDeath() {
    _secondTicker?.cancel();
    _isDead = true;
    _isPlaying = false;
    HapticFeedback.heavyImpact();
    HighScoreService.submit('match3', _score);
    HighScoreService.load('match3').then((v) => setState(() => _hiScore = v));
  }

  void _restart() => _startGame();

  Future<void> _awardRoundSaldo() async {
    final newSaldo = _saldo + 1.0;
    setState(() => _saldo = newSaldo);
    widget.onSaldoChanged(newSaldo);
    try {
      final userCardRef = FirebaseFirestore.instance
          .collection('users').doc(widget.userId)
          .collection('rewardsCard').doc('cardInfo');
      final batch = FirebaseFirestore.instance.batch();
      batch.update(userCardRef, {'saldo': newSaldo});
      batch.update(widget.rewardsDocRef, {'saldo': newSaldo});
      await batch.commit();
    } catch (e) { debugPrint('Match3 Firestore: $e'); }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0018),
      body: Stack(children: [
        // Board
        SizedBox.expand(
          child: CustomPaint(
            painter: _Match3Painter(
              board: _board,
              cursorCol: _cursorCol, cursorRow: _cursorRow,
              selCol: _selCol, selRow: _selRow,
              score: _score, round: _round,
              timeLeft: _timeLeft, roundTarget: _roundTarget,
              showHud: _isPlaying || _isDead,
              comboCount: _comboCount,
            ),
          ),
        ),

        // Round complete banner
        if (_roundComplete && !_isDead)
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.black87,
                border: Border.all(color: Colors.amberAccent, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('¡RONDA SUPERADA! ✨',
                  style: TextStyle(color: Colors.amberAccent, fontSize: 20,
                      fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                const SizedBox(height: 4),
                const Text('+1 pto real', style: TextStyle(color: Colors.white70, fontSize: 12)),
              ]),
            ),
          ),

        // Start overlay
        if (!_isPlaying && !_isDead) _buildStartOverlay(),

        // Death overlay
        if (_isDead) _buildDeathOverlay(),
      ]),
    );
  }

  Widget _buildStartOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.88),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('💎', style: TextStyle(fontSize: 52)),
          const SizedBox(height: 10),
          const Text('GEMAS DEL ABISMO',
            style: TextStyle(color: Colors.amberAccent, fontSize: 20,
                fontWeight: FontWeight.bold, letterSpacing: 2, fontFamily: 'monospace')),
          const SizedBox(height: 18),
          const Text('D-pad: mover cursor',
            style: TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 4),
          const Text('A: seleccionar / confirmar intercambio',
            style: TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 2),
          const Text('B: cancelar selección',
            style: TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 16),
          Text('Alcanza ${_roundTarget} pts antes del tiempo',
            style: const TextStyle(color: Colors.amberAccent, fontSize: 11)),
          const SizedBox(height: 28),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: SizedBox(width: double.infinity,
              child: ElevatedButton(
                onPressed: _startGame,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6A0080),
                  foregroundColor: Colors.white, shape: const StadiumBorder()),
                child: const Text('Jugar'),
              )),
          ),
        ]),
      ),
    );
  }

  Widget _buildDeathOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.90),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('⏰ TIEMPO AGOTADO',
            style: TextStyle(color: Color(0xFFFF2200), fontSize: 22,
                fontWeight: FontWeight.bold, fontFamily: 'monospace', letterSpacing: 2)),
          const SizedBox(height: 16),
          Text('Puntuación: $_score',
            style: const TextStyle(color: Colors.white, fontSize: 18, fontFamily: 'monospace')),
          Text('Ronda: $_round',
            style: const TextStyle(color: Colors.white70, fontSize: 14, fontFamily: 'monospace')),
          Text('Récord: $_hiScore',
            style: const TextStyle(color: Colors.amberAccent, fontSize: 12, fontFamily: 'monospace')),
          const SizedBox(height: 28),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: SizedBox(width: double.infinity,
              child: ElevatedButton(
                onPressed: _restart,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6A0080),
                  foregroundColor: Colors.white, shape: const StadiumBorder()),
                child: const Text('Nueva Partida'),
              )),
          ),
        ]),
      ),
    );
  }
}

// ─── Painter ──────────────────────────────────────────────────────────────────

class _Match3Painter extends CustomPainter {
  final List<List<int>> board;
  final int cursorCol, cursorRow;
  final int? selCol, selRow;
  final int score, round, timeLeft, roundTarget;
  final bool showHud;
  final int comboCount;

  const _Match3Painter({
    required this.board,
    required this.cursorCol, required this.cursorRow,
    required this.selCol, required this.selRow,
    required this.score, required this.round,
    required this.timeLeft, required this.roundTarget,
    required this.showHud, required this.comboCount,
  });

  @override
  bool shouldRepaint(_Match3Painter old) => true;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..isAntiAlias = false;

    // Background
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..shader = const LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Color(0xFF0A0018), Color(0xFF1A003A)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)));

    if (showHud) _drawHud(canvas, size);

    final hudH = showHud ? 36.0 : 0.0;
    final boardTop = hudH + 4;
    final cellW = (size.width - 8) / _kCols;
    final cellH = (size.height - boardTop - 4) / _kRows;

    // Board background
    p.color = const Color(0xFF12002A);
    canvas.drawRect(Rect.fromLTWH(4, boardTop, size.width - 8, size.height - boardTop - 4), p);

    // Grid lines
    p.color = const Color(0xFF2A006A).withOpacity(0.60);
    p.style = PaintingStyle.stroke;
    p.strokeWidth = 0.5;
    for (int c = 0; c <= _kCols; c++) {
      canvas.drawLine(
        Offset(4 + c * cellW, boardTop),
        Offset(4 + c * cellW, size.height - 4), p);
    }
    for (int r = 0; r <= _kRows; r++) {
      canvas.drawLine(
        Offset(4, boardTop + r * cellH),
        Offset(size.width - 4, boardTop + r * cellH), p);
    }
    p.style = PaintingStyle.fill;

    // Gems
    for (int r = 0; r < _kRows; r++) {
      for (int c = 0; c < _kCols; c++) {
        final gem = board[r][c];
        if (gem == -1) continue;
        final gx = 4 + c * cellW;
        final gy = boardTop + r * cellH;
        _drawGem(canvas, p, gem, gx, gy, cellW, cellH,
          isSelected: selCol == c && selRow == r);
      }
    }

    // Cursor
    final cx = 4 + cursorCol * cellW;
    final cy = boardTop + cursorRow * cellH;
    p.color = Colors.white;
    p.style = PaintingStyle.stroke;
    p.strokeWidth = 2.0;
    canvas.drawRect(Rect.fromLTWH(cx + 1, cy + 1, cellW - 2, cellH - 2), p);
    p.style = PaintingStyle.fill;

    // Combo glow
    if (comboCount >= 2) {
      final tp = TextPainter(
        text: TextSpan(text: 'x$comboCount COMBO!',
          style: const TextStyle(color: Colors.amberAccent, fontSize: 14,
              fontWeight: FontWeight.bold, fontFamily: 'monospace')),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(size.width / 2 - tp.width / 2, boardTop + 8));
      tp.dispose();
    }
  }

  void _drawGem(Canvas canvas, Paint p, int gem, double gx, double gy,
      double cellW, double cellH, {bool isSelected = false}) {
    final color = _kGemPalette[gem];
    final margin = 4.0;
    final x = gx + margin;
    final y = gy + margin;
    final w = cellW - margin * 2;
    final h = cellH - margin * 2;

    if (isSelected) {
      // Glow
      p.color = color.withOpacity(0.40);
      canvas.drawRect(Rect.fromLTWH(gx, gy, cellW, cellH), p);
    }

    // Gem body (diamond/rhombus shape approximated with rects)
    p.color = Color.fromARGB(255,
      (color.red * 0.55).round(),
      (color.green * 0.55).round(),
      (color.blue * 0.55).round());
    canvas.drawRect(Rect.fromLTWH(x, y, w, h), p); // dark base

    // Main face (slightly inset)
    p.color = color;
    canvas.drawRect(Rect.fromLTWH(x + 2, y + 2, w - 4, h - 4), p);

    // Top highlight (bright)
    p.color = Color.fromARGB(200,
      min(255, color.red + 80),
      min(255, color.green + 80),
      min(255, color.blue + 80));
    canvas.drawRect(Rect.fromLTWH(x + 2, y + 2, w - 4, h * 0.35), p);

    // Center sparkle dot
    p.color = Colors.white.withOpacity(0.75);
    final sx = x + w * 0.28;
    final sy = y + h * 0.22;
    canvas.drawRect(Rect.fromLTWH(sx, sy, w * 0.22, h * 0.15), p);

    // Bottom shadow
    p.color = Colors.black.withOpacity(0.35);
    canvas.drawRect(Rect.fromLTWH(x, y + h - h * 0.25, w, h * 0.25), p);
  }

  void _drawHud(Canvas canvas, Size size) {
    final p = Paint()..isAntiAlias = false;
    p.color = Colors.black.withOpacity(0.78);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 36), p);

    // Timer bar
    final timeFrac = timeLeft / _kRoundTime;
    final barColor = timeFrac > 0.40
        ? const Color(0xFF22CC44)
        : timeFrac > 0.20 ? const Color(0xFFFF8800) : const Color(0xFFCC1111);
    p.color = const Color(0xFF222222);
    canvas.drawRect(Rect.fromLTWH(4, 6, size.width - 8, 10), p);
    p.color = barColor;
    canvas.drawRect(Rect.fromLTWH(4, 6, (size.width - 8) * timeFrac, 10), p);

    // Stats text
    _txt(canvas, '⏱ $timeLeft s', 6, 18, color: Colors.white70, size: 9);
    _txt(canvas, '💎 $score / $roundTarget', size.width * 0.30, 18,
      color: Colors.amberAccent, size: 9);
    _txt(canvas, 'RONDA $round', size.width * 0.74, 18,
      color: Colors.white54, size: 9);
  }

  void _txt(Canvas canvas, String text, double x, double y,
      {Color color = Colors.white, double size = 10}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: color, fontSize: size,
          fontFamily: 'monospace', fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset(x, y));
    tp.dispose();
  }
}
