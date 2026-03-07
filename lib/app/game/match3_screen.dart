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
const _kCandyTypes = 6;
const _kRoundTime = 30;  // seconds per round
const _kMinMatch = 3;

// Candy colour palette — bright & distinct
const _kCandyPalette = [
  Color(0xFFFF2266), // strawberry red
  Color(0xFFFF7700), // orange
  Color(0xFFFFDD00), // lemon yellow
  Color(0xFF22CC44), // lime green
  Color(0xFF3388FF), // blueberry blue
  Color(0xFFCC44FF), // grape purple
];

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
  late List<List<int>> _board;

  int _cursorCol = 3, _cursorRow = 3;
  int? _selCol, _selRow;

  int _score = 0;
  int _round = 1;
  int _timeLeft = _kRoundTime;
  int _roundTarget = 300;
  int _hiScore = 0;
  late double _saldo;

  bool _isPlaying = false;
  bool _isDead = false;
  bool _roundComplete = false;
  bool _roundCompleteDelay = false;
  bool _swapFlash = false;
  int _comboCount = 0;

  // Swipe state
  Offset? _swipeStartPos;
  int? _swipeStartCol, _swipeStartRow;

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
    _secondTicker?.cancel();
    widget.controller.removeListener(_onControllerEvent);
    super.dispose();
  }

  // ── Board init ─────────────────────────────────────────────────────────────

  void _initBoard() {
    _board = List.generate(_kRows, (_) =>
        List.generate(_kCols, (_) => _rng.nextInt(_kCandyTypes)));
    for (int r = 0; r < _kRows; r++) {
      for (int c = 0; c < _kCols; c++) {
        int gem = _board[r][c];
        int tries = 0;
        while (_wouldMatchAt(r, c, gem) && tries < 20) {
          gem = _rng.nextInt(_kCandyTypes);
          tries++;
        }
        _board[r][c] = gem;
      }
    }
  }

  bool _wouldMatchAt(int r, int c, int gem) {
    if (c >= 2 && _board[r][c - 1] == gem && _board[r][c - 2] == gem) return true;
    if (r >= 2 && _board[r - 1][c] == gem && _board[r - 2][c] == gem) return true;
    return false;
  }

  // ── D-pad / button input ───────────────────────────────────────────────────

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
      setState(() { _selCol = _cursorCol; _selRow = _cursorRow; });
      HapticFeedback.mediumImpact();
    } else {
      final dc = (_cursorCol - _selCol!).abs();
      final dr = (_cursorRow - _selRow!).abs();
      if ((dc == 1 && dr == 0) || (dc == 0 && dr == 1)) {
        _doSwap(_selCol!, _selRow!, _cursorCol, _cursorRow);
      } else {
        setState(() { _selCol = _cursorCol; _selRow = _cursorRow; });
        HapticFeedback.lightImpact();
      }
    }
  }

  // ── Swipe touch input ──────────────────────────────────────────────────────

  void _onBoardPanStart(DragStartDetails d, double cellW, double cellH, double boardTop) {
    final x = d.localPosition.dx, y = d.localPosition.dy - boardTop;
    _swipeStartPos = d.localPosition;
    _swipeStartCol = (x / cellW).floor().clamp(0, _kCols - 1);
    _swipeStartRow = (y / cellH).floor().clamp(0, _kRows - 1);
  }

  void _onBoardPanEnd(DragEndDetails d) {
    if (_swipeStartPos == null || !_isPlaying || _roundCompleteDelay) return;
    final vel = d.velocity.pixelsPerSecond;
    final dx = vel.dx, dy = vel.dy;
    if (dx.abs() < 100 && dy.abs() < 100) { _swipeStartPos = null; return; }

    int dc = 0, dr = 0;
    if (dx.abs() > dy.abs()) {
      dc = dx > 0 ? 1 : -1;
    } else {
      dr = dy > 0 ? 1 : -1;
    }
    final c1 = _swipeStartCol!, r1 = _swipeStartRow!;
    final c2 = (c1 + dc).clamp(0, _kCols - 1);
    final r2 = (r1 + dr).clamp(0, _kRows - 1);
    if (c2 != c1 || r2 != r1) {
      setState(() { _cursorCol = c1; _cursorRow = r1; _selCol = null; _selRow = null; });
      _doSwap(c1, r1, c2, r2);
    }
    _swipeStartPos = null;
  }

  // ── Match logic ────────────────────────────────────────────────────────────

  void _doSwap(int c1, int r1, int c2, int r2) {
    final tmp = _board[r1][c1];
    _board[r1][c1] = _board[r2][c2];
    _board[r2][c2] = tmp;

    final matches = _findMatches();
    if (matches.isEmpty) {
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
    _score += matches.length * 10 * _comboCount;
    HapticFeedback.mediumImpact();
    if (_comboCount >= 2) HapticFeedback.heavyImpact();

    for (final pos in matches) _board[pos.$1][pos.$2] = -1;

    // Gravity
    for (int c = 0; c < _kCols; c++) {
      final col = [for (int r = 0; r < _kRows; r++) _board[r][c]];
      final gems = col.where((g) => g != -1).toList();
      final newCol = [...List.filled(_kRows - gems.length, -1), ...gems];
      for (int r = 0; r < _kRows; r++) _board[r][c] = newCol[r];
    }

    for (int r = 0; r < _kRows; r++) {
      for (int c = 0; c < _kCols; c++) {
        if (_board[r][c] == -1) _board[r][c] = _rng.nextInt(_kCandyTypes);
      }
    }

    setState(() {});
    Future.delayed(const Duration(milliseconds: 220), _resolveMatches);
  }

  List<(int, int)> _findMatches() {
    final Set<(int, int)> matched = {};
    for (int r = 0; r < _kRows; r++) {
      int run = 1;
      for (int c = 1; c < _kCols; c++) {
        if (_board[r][c] != -1 && _board[r][c] == _board[r][c - 1]) { run++; }
        else {
          if (run >= _kMinMatch) for (int k = c - run; k < c; k++) matched.add((r, k));
          run = 1;
        }
      }
      if (run >= _kMinMatch) for (int k = _kCols - run; k < _kCols; k++) matched.add((r, k));
    }
    for (int c = 0; c < _kCols; c++) {
      int run = 1;
      for (int r = 1; r < _kRows; r++) {
        if (_board[r][c] != -1 && _board[r][c] == _board[r - 1][c]) { run++; }
        else {
          if (run >= _kMinMatch) for (int k = r - run; k < r; k++) matched.add((k, c));
          run = 1;
        }
      }
      if (run >= _kMinMatch) for (int k = _kRows - run; k < _kRows; k++) matched.add((k, c));
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
    _timeLeft = max(15, _kRoundTime - (_round - 1) * 3);
    _roundComplete = false;
    _roundCompleteDelay = false;
    _comboCount = 0;
    _initBoard();
    setState(() {});
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  void _startGame() {
    setState(() {
      _score = 0; _round = 1; _timeLeft = _kRoundTime;
      _roundTarget = 300; _isDead = false;
      _roundComplete = false; _roundCompleteDelay = false;
      _comboCount = 0; _cursorCol = 3; _cursorRow = 3;
      _selCol = null; _selRow = null; _isPlaying = true;
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
    _isDead = true; _isPlaying = false;
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
      final ref = FirebaseFirestore.instance
          .collection('users').doc(widget.userId)
          .collection('rewardsCard').doc('cardInfo');
      final batch = FirebaseFirestore.instance.batch();
      batch.update(ref, {'saldo': newSaldo});
      batch.update(widget.rewardsDocRef, {'saldo': newSaldo});
      await batch.commit();
    } catch (e) { debugPrint('DulceRacha Firestore: $e'); }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A000E),
      body: Stack(children: [
        // Main layout: left deco | board | right HUD
        LayoutBuilder(builder: (ctx, constraints) {
          final totalW = constraints.maxWidth;
          final totalH = constraints.maxHeight;
          const leftW = 26.0, rightW = 58.0;
          final boardW = totalW - leftW - rightW;
          final cellW = boardW / _kCols;
          const topBarH = 42.0;
          final cellH = (totalH - topBarH - 4) / _kRows;

          return Row(children: [
            // ── Left decorative panel ──────────────────────────────────────
            SizedBox(
              width: leftW, height: totalH,
              child: CustomPaint(painter: _CandySidePainter(side: 0, h: totalH)),
            ),

            // ── Center: top bar + swipeable candy board ────────────────────
            SizedBox(
              width: boardW,
              child: Column(children: [
                // Top bar
                SizedBox(
                  height: topBarH,
                  child: _buildTopBar(boardW, topBarH),
                ),
                // Swipeable board
                Expanded(
                  child: GestureDetector(
                    onPanStart: _isPlaying
                        ? (d) => _onBoardPanStart(d, cellW, cellH, 0)
                        : null,
                    onPanEnd: _isPlaying ? _onBoardPanEnd : null,
                    child: CustomPaint(
                      painter: _CandyBoardPainter(
                        board: _board,
                        cursorCol: _cursorCol, cursorRow: _cursorRow,
                        selCol: _selCol, selRow: _selRow,
                        comboCount: _comboCount,
                        showCursor: _isPlaying,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ]),
            ),

            // ── Right HUD panel ────────────────────────────────────────────
            SizedBox(
              width: rightW, height: totalH,
              child: _buildRightHud(rightW, totalH),
            ),
          ]);
        }),

        // Round complete banner
        if (_roundComplete && !_isDead)
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black87,
                border: Border.all(color: Colors.amberAccent, width: 2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('🍬 ¡DULCE RACHA!',
                  style: TextStyle(color: Colors.amberAccent, fontSize: 18,
                      fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                const SizedBox(height: 4),
                const Text('+1 pto real 🌟',
                  style: TextStyle(color: Colors.white70, fontSize: 11)),
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

  // ── Top bar ────────────────────────────────────────────────────────────────

  Widget _buildTopBar(double w, double h) {
    final timeFrac = (_timeLeft / _kRoundTime).clamp(0.0, 1.0);
    final barColor = timeFrac > 0.40
        ? const Color(0xFF22DD55)
        : timeFrac > 0.20 ? const Color(0xFFFF9900) : const Color(0xFFFF2200);

    return Container(
      color: const Color(0xFF1A000E),
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 2),
      child: Column(children: [
        // Timer bar
        Container(
          height: 8,
          decoration: BoxDecoration(
            color: const Color(0xFF330020),
            borderRadius: BorderRadius.circular(4),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: timeFrac,
            child: Container(
              decoration: BoxDecoration(
                color: barColor,
                borderRadius: BorderRadius.circular(4),
                boxShadow: [BoxShadow(color: barColor.withOpacity(0.60), blurRadius: 4)],
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(children: [
          Text('⏱ $_timeLeft s',
            style: const TextStyle(color: Colors.white70, fontSize: 9,
                fontFamily: 'monospace', fontWeight: FontWeight.bold)),
          const Spacer(),
          Text('META: $_roundTarget',
            style: const TextStyle(color: Colors.pinkAccent, fontSize: 9,
                fontFamily: 'monospace', fontWeight: FontWeight.bold)),
        ]),
      ]),
    );
  }

  // ── Right HUD ──────────────────────────────────────────────────────────────

  Widget _buildRightHud(double w, double h) {
    return Container(
      color: const Color(0xFF120008),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          const SizedBox(height: 6),
          _hudLabel('RONDA'),
          _hudValue('$_round', Colors.amberAccent),
          const SizedBox(height: 14),
          _hudLabel('PUNTOS'),
          _hudValue('$_score', Colors.pinkAccent),
          const SizedBox(height: 14),
          _hudLabel('RÉCORD'),
          _hudValue('$_hiScore', Colors.white38),
          const SizedBox(height: 14),
          if (_comboCount >= 2) ...[
            _hudLabel('COMBO'),
            _hudValue('x$_comboCount', Colors.yellowAccent),
            const SizedBox(height: 8),
          ],
          const Spacer(),
          // Candy stripe decoration
          CustomPaint(
            painter: _CandySidePainter(side: 1, h: 80),
            child: const SizedBox(width: 50, height: 80),
          ),
          const SizedBox(height: 6),
          const Text('desliza\n🍬',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white24, fontSize: 8,
                fontFamily: 'monospace')),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _hudLabel(String text) => Text(text,
    style: const TextStyle(color: Colors.white30, fontSize: 7,
        letterSpacing: 1.5, fontWeight: FontWeight.w700));

  Widget _hudValue(String text, Color color) => Text(text,
    style: TextStyle(color: color, fontSize: 14,
        fontFamily: 'monospace', fontWeight: FontWeight.bold,
        shadows: [Shadow(color: color.withOpacity(0.60), blurRadius: 6)]));

  // ── Overlays ───────────────────────────────────────────────────────────────

  Widget _buildStartOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.88),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('🍬', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 10),
          const Text('DULCE RACHA',
            style: TextStyle(color: Colors.pinkAccent, fontSize: 22,
                fontWeight: FontWeight.bold, letterSpacing: 3,
                fontFamily: 'monospace')),
          const SizedBox(height: 6),
          const Text('Combina 3 o más dulces',
            style: TextStyle(color: Colors.white60, fontSize: 11)),
          const SizedBox(height: 4),
          const Text('Desliza en pantalla o usa D-pad + A',
            style: TextStyle(color: Colors.white38, fontSize: 10)),
          const SizedBox(height: 22),
          Text('Meta: $_roundTarget puntos en $_kRoundTime s',
            style: const TextStyle(color: Colors.amberAccent, fontSize: 11)),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _startGame,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF880040),
                  foregroundColor: Colors.white,
                  shape: const StadiumBorder()),
                child: const Text('¡Jugar!'),
              ),
            ),
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
            style: TextStyle(color: Color(0xFFFF2200), fontSize: 20,
                fontWeight: FontWeight.bold, fontFamily: 'monospace',
                letterSpacing: 2)),
          const SizedBox(height: 16),
          Text('Puntuación: $_score',
            style: const TextStyle(color: Colors.white, fontSize: 18,
                fontFamily: 'monospace')),
          Text('Ronda: $_round',
            style: const TextStyle(color: Colors.white70, fontSize: 13,
                fontFamily: 'monospace')),
          Text('Récord: $_hiScore',
            style: const TextStyle(color: Colors.amberAccent, fontSize: 12,
                fontFamily: 'monospace')),
          const SizedBox(height: 26),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _restart,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF880040),
                  foregroundColor: Colors.white,
                  shape: const StadiumBorder()),
                child: const Text('Nueva Partida'),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ─── Candy Board Painter ──────────────────────────────────────────────────────

class _CandyBoardPainter extends CustomPainter {
  final List<List<int>> board;
  final int cursorCol, cursorRow;
  final int? selCol, selRow;
  final int comboCount;
  final bool showCursor;

  const _CandyBoardPainter({
    required this.board,
    required this.cursorCol, required this.cursorRow,
    required this.selCol, required this.selRow,
    required this.comboCount, required this.showCursor,
  });

  @override
  bool shouldRepaint(_CandyBoardPainter old) => true;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..isAntiAlias = false;

    // Background
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..shader = const LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Color(0xFF1A000E), Color(0xFF2A001A)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)));

    final cellW = size.width / _kCols;
    final cellH = size.height / _kRows;

    // Subtle grid lines
    p.color = const Color(0xFF440028).withOpacity(0.50);
    p.style = PaintingStyle.stroke; p.strokeWidth = 0.5;
    for (int c = 0; c <= _kCols; c++) {
      canvas.drawLine(Offset(c * cellW, 0), Offset(c * cellW, size.height), p);
    }
    for (int r = 0; r <= _kRows; r++) {
      canvas.drawLine(Offset(0, r * cellH), Offset(size.width, r * cellH), p);
    }
    p.style = PaintingStyle.fill;

    // Candies
    for (int r = 0; r < _kRows; r++) {
      for (int c = 0; c < _kCols; c++) {
        final candy = board[r][c];
        if (candy == -1) continue;
        _drawCandy(canvas, p, candy,
          4 + c * cellW, r * cellH, cellW - 4, cellH,
          isSelected: selCol == c && selRow == r);
      }
    }

    // Cursor
    if (showCursor) {
      final cx = 4 + cursorCol * cellW;
      final cy = cursorRow * cellH;
      p.color = Colors.white;
      p.style = PaintingStyle.stroke; p.strokeWidth = 2.0;
      canvas.drawRect(Rect.fromLTWH(cx + 1, cy + 1, cellW - 6, cellH - 2), p);
      p.style = PaintingStyle.fill;
    }

    // Combo label
    if (comboCount >= 2) {
      final tp = TextPainter(
        text: TextSpan(text: '🍬 x$comboCount COMBO!',
          style: const TextStyle(color: Colors.amberAccent, fontSize: 13,
              fontWeight: FontWeight.bold, fontFamily: 'monospace')),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(size.width / 2 - tp.width / 2, 6));
      tp.dispose();
    }
  }

  void _drawCandy(Canvas canvas, Paint p, int type, double gx, double gy,
      double cellW, double cellH, {bool isSelected = false}) {
    final color = _kCandyPalette[type];
    final cx = gx + cellW / 2;
    final cy = gy + cellH / 2;
    final r = min(cellW, cellH) * 0.40;

    if (isSelected) {
      p.color = color.withOpacity(0.35);
      p.isAntiAlias = true;
      canvas.drawCircle(Offset(cx, cy), r + 5, p);
    }

    // Candy body (circle)
    p.isAntiAlias = true;
    // Dark base
    p.color = Color.fromARGB(255,
      (color.red * 0.50).round(),
      (color.green * 0.50).round(),
      (color.blue * 0.50).round());
    canvas.drawCircle(Offset(cx, cy), r, p);
    // Main colour
    p.color = color;
    canvas.drawCircle(Offset(cx, cy), r - 2, p);

    // Stripe (diagonal band across candy)
    p.color = Colors.white.withOpacity(0.22);
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(gx, gy, cellW + 4, cellH));
    canvas.translate(cx, cy);
    canvas.rotate(0.6);
    canvas.drawRect(Rect.fromLTWH(-r + 2, -r * 0.35, r * 2 - 4, r * 0.70), p);
    canvas.restore();

    // Top shine arc
    p.color = Colors.white.withOpacity(0.55);
    canvas.drawOval(Rect.fromLTWH(cx - r*0.55, cy - r*0.72, r*0.55, r*0.32), p);

    // Tiny sparkle dot
    p.color = Colors.white.withOpacity(0.80);
    canvas.drawCircle(Offset(cx - r*0.32, cy - r*0.38), r * 0.12, p);

    p.isAntiAlias = false;
  }
}

// ─── Side Panel Painter ────────────────────────────────────────────────────────

class _CandySidePainter extends CustomPainter {
  final int side; // 0 = left strip, 1 = right mini
  final double h;
  const _CandySidePainter({required this.side, required this.h});

  @override
  bool shouldRepaint(_CandySidePainter old) => false;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final p = Paint()..isAntiAlias = false;

    // Dark background
    p.color = const Color(0xFF120008);
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), p);

    if (side == 0) {
      // Left panel: vertical candy-cane stripe
      p.color = const Color(0xFFFF2266).withOpacity(0.18);
      for (int i = 0; i < (h / 14).ceil(); i++) {
        if (i % 2 == 0) canvas.drawRect(Rect.fromLTWH(0, i * 14.0, w, 7), p);
      }
      // Candy dots
      final dotColors = [
        const Color(0xFFFF2266), const Color(0xFFFF9900),
        const Color(0xFF22CC44), const Color(0xFF3388FF),
      ];
      for (int i = 0; i < 6; i++) {
        p.isAntiAlias = true;
        p.color = dotColors[i % dotColors.length].withOpacity(0.55);
        canvas.drawCircle(Offset(w / 2, 18.0 + i * (h / 6)), w * 0.32, p);
        p.color = Colors.white.withOpacity(0.25);
        canvas.drawCircle(Offset(w * 0.35, 14.0 + i * (h / 6)), w * 0.12, p);
      }
      p.isAntiAlias = false;
    } else {
      // Right mini: small candy row
      final cc = [
        const Color(0xFFFF2266), const Color(0xFFFFDD00),
        const Color(0xFF22CC44), const Color(0xFF3388FF),
      ];
      p.isAntiAlias = true;
      for (int i = 0; i < cc.length; i++) {
        p.color = cc[i].withOpacity(0.75);
        canvas.drawCircle(Offset(w / 2, 12.0 + i * (h / (cc.length + 1))), w * 0.35, p);
        p.color = Colors.white.withOpacity(0.40);
        canvas.drawOval(Rect.fromLTWH(
          w * 0.25, 6.0 + i * (h / (cc.length + 1)), w * 0.25, h * 0.06), p);
      }
      p.isAntiAlias = false;
    }
  }
}
