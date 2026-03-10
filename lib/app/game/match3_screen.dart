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
const _kRoundTime = 25;  // seconds per round (was 30)
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

class _Match3ScreenState extends State<Match3Screen> with SingleTickerProviderStateMixin {
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
  bool _paused = false;
  bool _roundComplete = false;
  bool _roundCompleteDelay = false;
  int _comboCount = 0;

  // Swipe state
  Offset? _swipeStartPos;
  int? _swipeStartCol, _swipeStartRow;

  // Swap animation
  late AnimationController _swapAnimCtrl;
  int _animC1 = -1, _animR1 = -1, _animC2 = -1, _animR2 = -1;
  bool _isAnimating = false;
  bool _swapForward = true; // true = forward swap, false = reverse (invalid)

  Timer? _secondTicker;
  final Random _rng = Random();

  @override
  void initState() {
    super.initState();
    _saldo = widget.currentSaldo;
    _swapAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _swapAnimCtrl.addListener(() => setState(() {}));
    _swapAnimCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) _onSwapAnimDone();
    });
    widget.controller.addListener(_onControllerEvent);
    HighScoreService.load('match3').then((v) => setState(() => _hiScore = v));
    _initBoard();
  }

  @override
  void dispose() {
    _swapAnimCtrl.dispose();
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
    if (btn == ArcadeButton.start) { _togglePause(); return; }
    if (_paused) return;
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
    if (_isAnimating) return;
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
    if (_swipeStartPos == null || !_isPlaying || _roundCompleteDelay || _isAnimating) return;
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
    if (_isAnimating) return;
    _animC1 = c1; _animR1 = r1;
    _animC2 = c2; _animR2 = r2;
    _swapForward = true;
    _isAnimating = true;
    _swapAnimCtrl.forward(from: 0.0);
  }

  void _onSwapAnimDone() {
    if (_swapForward) {
      // Commit swap in board
      final tmp = _board[_animR1][_animC1];
      _board[_animR1][_animC1] = _board[_animR2][_animC2];
      _board[_animR2][_animC2] = tmp;

      final matches = _findMatches();
      if (matches.isEmpty) {
        // Invalid swap — reverse: swap back in board and animate back
        final tmp2 = _board[_animR1][_animC1];
        _board[_animR1][_animC1] = _board[_animR2][_animC2];
        _board[_animR2][_animC2] = tmp2;
        HapticFeedback.lightImpact();
        _swapForward = false;
        _swapAnimCtrl.forward(from: 0.0);
      } else {
        _isAnimating = false;
        _animC1 = _animR1 = _animC2 = _animR2 = -1;
        _selCol = null; _selRow = null;
        _comboCount = 0;
        _resolveMatches();
      }
    } else {
      // Reverse animation done
      _isAnimating = false;
      _animC1 = _animR1 = _animC2 = _animR2 = -1;
      setState(() { _selCol = null; _selRow = null; });
    }
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

  void _togglePause() {
    if (!_isPlaying || _isDead) return;
    setState(() => _paused = !_paused);
  }

  void _onSecondTick(Timer _) {
    if (!_isPlaying || _paused || _roundComplete || _roundCompleteDelay) return;
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
      backgroundColor: const Color(0xFF55AADE),
      body: Stack(children: [
        // Candy sky background
        const SizedBox.expand(child: CustomPaint(painter: _CandySkyPainter())),

        // Main content
        LayoutBuilder(builder: (ctx, constraints) {
          final totalW = constraints.maxWidth;
          final totalH = constraints.maxHeight;
          final headerH = 76.0 + MediaQuery.of(ctx).padding.top;
          const footerH = 72.0;
          const hPad = 8.0;
          final boardH = totalH - headerH - footerH;
          final cellW = (totalW - hPad * 2) / _kCols;
          final cellH = boardH / _kRows;

          return Column(children: [
            // Header bar
            _buildHeader(totalW, headerH),

            // Board in dark wooden container
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: hPad),
              child: Container(
                height: boardH,
                decoration: BoxDecoration(
                  color: const Color(0xFF3D2510),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 4))],
                  border: Border.all(color: const Color(0xFF7A4E28), width: 2.5),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: GestureDetector(
                    onPanStart: (_isPlaying && !_paused)
                        ? (d) => _onBoardPanStart(d, cellW, cellH, 0)
                        : null,
                    onPanEnd: (_isPlaying && !_paused) ? _onBoardPanEnd : null,
                    child: CustomPaint(
                      painter: _CandyBoardPainter(
                        board: _board,
                        cursorCol: _cursorCol, cursorRow: _cursorRow,
                        selCol: _selCol, selRow: _selRow,
                        comboCount: _comboCount,
                        showCursor: _isPlaying && !_paused,
                        animProgress: _isAnimating ? _swapAnimCtrl.value : -1.0,
                        animForward: _swapForward,
                        animC1: _animC1, animR1: _animR1,
                        animC2: _animC2, animR2: _animR2,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            ),

            // Bottom candy landscape
            Expanded(
              child: CustomPaint(
                painter: const _CandyLandPainter(),
                child: const SizedBox.expand(),
              ),
            ),
          ]);
        }),

        // Round complete banner
        if (_roundComplete && !_isDead)
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.black87,
                border: Border.all(color: Colors.amberAccent, width: 2),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.amber.withOpacity(0.4), blurRadius: 16)],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('🍬 ¡CASCADA DULCE!',
                  style: TextStyle(color: Colors.amberAccent, fontSize: 20,
                      fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                const SizedBox(height: 4),
                const Text('+1 pto real 🌟',
                  style: TextStyle(color: Colors.white70, fontSize: 12)),
              ]),
            ),
          ),

        // Pause overlay
        if (_paused && _isPlaying)
          Container(
            color: Colors.black.withOpacity(0.75),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                decoration: BoxDecoration(
                  color: const Color(0xFF3D2510),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.amberAccent, width: 2),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('⏸ PAUSA', style: TextStyle(color: Colors.amberAccent, fontSize: 22,
                      fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                  const SizedBox(height: 8),
                  const Text('Start para continuar', style: TextStyle(color: Colors.white60, fontSize: 12)),
                ]),
              ),
            ),
          ),

        // Start overlay
        if (!_isPlaying && !_isDead) _buildStartOverlay(),

        // Death overlay
        if (_isDead) _buildDeathOverlay(),
      ]),
    );
  }

  // ── Header (candy-crush style) ─────────────────────────────────────────────

  Widget _buildHeader(double w, double h) {
    final timeFrac = (_timeLeft / _kRoundTime).clamp(0.0, 1.0);
    final timerColor = _timeLeft > 10
        ? const Color(0xFF22DD55)
        : _timeLeft > 5 ? const Color(0xFFFF9900) : const Color(0xFFFF2200);

    return Container(
      height: h,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Color(0xFFCB8C55), Color(0xFF9A5E2A)],
        ),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 3))],
      ),
      child: Padding(
          padding: EdgeInsets.fromLTRB(10, MediaQuery.of(context).padding.top + 4, 10, 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            // Left: circular timer
            SizedBox(
              width: 52, height: 52,
              child: Stack(alignment: Alignment.center, children: [
                CircularProgressIndicator(
                  value: timeFrac,
                  strokeWidth: 5,
                  backgroundColor: Colors.black26,
                  color: timerColor,
                ),
                Text('$_timeLeft',
                  style: TextStyle(color: timerColor, fontSize: 14,
                      fontWeight: FontWeight.bold, fontFamily: 'monospace')),
              ]),
            ),
            const SizedBox(width: 8),

            // Center: score + level + candy-type mini icons
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Candy type color dots with counts
                  Row(mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(min(_kCandyTypes, 4), (t) {
                      final cnt = _board.expand((r) => r).where((c) => c == t).length;
                      final col = _kCandyPalette[t];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Container(
                            width: 12, height: 12,
                            decoration: BoxDecoration(
                              color: col, shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: col.withOpacity(0.6), blurRadius: 3)],
                            ),
                          ),
                          Text('$cnt', style: const TextStyle(color: Colors.white,
                              fontSize: 8, fontWeight: FontWeight.bold)),
                        ]),
                      );
                    }),
                  ),
                  const SizedBox(height: 2),
                  Text('$_score',
                    style: const TextStyle(color: Colors.white, fontSize: 18,
                        fontWeight: FontWeight.bold, fontFamily: 'monospace',
                        shadows: [Shadow(color: Colors.black45, blurRadius: 3, offset: Offset(1, 1))])),
                  Text('Ronda $_round  •  Meta $_roundTarget',
                    style: const TextStyle(color: Colors.white70, fontSize: 8, fontFamily: 'monospace')),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Right: pause button
            GestureDetector(
              onTap: _togglePause,
              child: Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFF22AA44),
                  shape: BoxShape.circle,
                  boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2))],
                ),
                child: Icon(_paused ? Icons.play_arrow : Icons.pause,
                    color: Colors.white, size: 22),
              ),
            ),
          ]),
        ),
    );
  }

  // ── Overlays ───────────────────────────────────────────────────────────────

  Widget _buildStartOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.80),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          decoration: BoxDecoration(
            color: const Color(0xFF3D2510),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF9A6030), width: 2),
            boxShadow: [BoxShadow(color: Colors.amber.withOpacity(0.3), blurRadius: 20)],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('🍬', style: TextStyle(fontSize: 52)),
            const SizedBox(height: 8),
            const Text('CASCADA DULCE',
              style: TextStyle(color: Colors.amberAccent, fontSize: 22,
                  fontWeight: FontWeight.bold, letterSpacing: 2,
                  fontFamily: 'monospace')),
            const SizedBox(height: 6),
            const Text('Combina 3 o más dulces',
              style: TextStyle(color: Colors.white70, fontSize: 11)),
            const SizedBox(height: 2),
            const Text('Desliza o usa D-pad + A',
              style: TextStyle(color: Colors.white38, fontSize: 10)),
            const SizedBox(height: 16),
            Text('Meta: $_roundTarget pts en $_kRoundTime s',
              style: const TextStyle(color: Colors.orange, fontSize: 11,
                  fontFamily: 'monospace')),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _startGame,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF22AA44),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text('¡Jugar!', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildDeathOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.85),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          decoration: BoxDecoration(
            color: const Color(0xFF3D2510),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.redAccent, width: 2),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('⏰ TIEMPO AGOTADO',
              style: TextStyle(color: Color(0xFFFF2200), fontSize: 20,
                  fontWeight: FontWeight.bold, fontFamily: 'monospace',
                  letterSpacing: 1)),
            const SizedBox(height: 14),
            Text('Puntuación: $_score',
              style: const TextStyle(color: Colors.white, fontSize: 20,
                  fontFamily: 'monospace', fontWeight: FontWeight.bold)),
            Text('Ronda: $_round',
              style: const TextStyle(color: Colors.white70, fontSize: 13,
                  fontFamily: 'monospace')),
            Text('Récord: $_hiScore',
              style: const TextStyle(color: Colors.amberAccent, fontSize: 12,
                  fontFamily: 'monospace')),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _restart,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF22AA44),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text('Nueva Partida', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ),
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
  // Swap animation: animProgress < 0 means no animation
  final double animProgress;
  final bool animForward;
  final int animC1, animR1, animC2, animR2;

  const _CandyBoardPainter({
    required this.board,
    required this.cursorCol, required this.cursorRow,
    required this.selCol, required this.selRow,
    required this.comboCount, required this.showCursor,
    this.animProgress = -1.0,
    this.animForward = true,
    this.animC1 = -1, this.animR1 = -1,
    this.animC2 = -1, this.animR2 = -1,
  });

  @override
  bool shouldRepaint(_CandyBoardPainter old) => true;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..isAntiAlias = false;

    // Dark board background with subtle stone-tile grid
    p.color = const Color(0xFF2A1A0A);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), p);

    final cellW = size.width / _kCols;
    final cellH = size.height / _kRows;

    // Stone tiles — alternating dark squares like a game board
    for (int r = 0; r < _kRows; r++) {
      for (int c = 0; c < _kCols; c++) {
        final tileColor = (r + c).isEven
            ? const Color(0xFF3D2814)
            : const Color(0xFF321E0E);
        p.color = tileColor;
        canvas.drawRect(Rect.fromLTWH(c * cellW + 1, r * cellH + 1,
            cellW - 2, cellH - 2), p);
        // Subtle inner bevel
        p.color = Colors.white.withOpacity(0.05);
        canvas.drawRect(Rect.fromLTWH(c * cellW + 1, r * cellH + 1, cellW - 2, 2), p);
      }
    }

    // Grid separators
    p.color = const Color(0xFF1A0A00).withOpacity(0.80);
    p.style = PaintingStyle.stroke; p.strokeWidth = 2;
    for (int c = 0; c <= _kCols; c++) {
      canvas.drawLine(Offset(c * cellW, 0), Offset(c * cellW, size.height), p);
    }
    for (int r = 0; r <= _kRows; r++) {
      canvas.drawLine(Offset(0, r * cellH), Offset(size.width, r * cellH), p);
    }
    p..style = PaintingStyle.fill..isAntiAlias = true;

    // Candies (with optional swap animation)
    final bool hasAnim = animProgress >= 0 && animC1 >= 0;
    for (int r = 0; r < _kRows; r++) {
      for (int c = 0; c < _kCols; c++) {
        final candy = board[r][c];
        if (candy == -1) continue;

        double baseX = 4 + c * cellW;
        double baseY = r * cellH;

        if (hasAnim) {
          // t: 0→1 = moving toward target position (both forward and reverse phases)
          final t = animProgress;
          if (r == animR1 && c == animC1) {
            final tx = 4 + animC2 * cellW;
            final ty = animR2 * cellH;
            if (animForward) {
              baseX += (tx - baseX) * t;
              baseY += (ty - baseY) * t;
            } else {
              baseX = tx + (baseX - tx) * t;
              baseY = ty + (baseY - ty) * t;
            }
          } else if (r == animR2 && c == animC2) {
            final tx = 4 + animC1 * cellW;
            final ty = animR1 * cellH;
            if (animForward) {
              baseX += (tx - baseX) * t;
              baseY += (ty - baseY) * t;
            } else {
              baseX = tx + (baseX - tx) * t;
              baseY = ty + (baseY - ty) * t;
            }
          }
        }

        _drawCandy(canvas, p, candy,
          baseX, baseY, cellW - 4, cellH,
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
    p.isAntiAlias = true;

    // Selection glow ring
    if (isSelected) {
      p.color = color.withOpacity(0.45);
      p.style = PaintingStyle.stroke;
      p.strokeWidth = 3;
      canvas.drawCircle(Offset(cx, cy), r + 5, p);
      p.style = PaintingStyle.fill;
    }

    // Shadow
    p.color = Colors.black.withOpacity(0.35);
    canvas.drawCircle(Offset(cx + 1.5, cy + 2), r, p);

    // Dark base border
    p.color = Color.fromARGB(255,
      (color.red * 0.45).round(),
      (color.green * 0.45).round(),
      (color.blue * 0.45).round());
    canvas.drawCircle(Offset(cx, cy), r, p);

    switch (type) {
      case 0: // Red — heart shape
        _drawHeart(canvas, p, cx, cy, r, color);
      case 1: // Orange — star
        _drawStar(canvas, p, cx, cy, r, color, 5);
      case 2: // Yellow — lemon drop (oval)
        _drawLemon(canvas, p, cx, cy, r, color);
      case 3: // Green — rounded diamond
        _drawDiamond(canvas, p, cx, cy, r, color);
      case 4: // Blue — rounded square
        _drawSquare(canvas, p, cx, cy, r, color);
      default: // Purple — star4
        _drawStar(canvas, p, cx, cy, r, color, 4);
    }

    // Top-left shine (glossy effect on all types)
    p.color = Colors.white.withOpacity(0.50);
    canvas.drawOval(Rect.fromLTWH(cx - r * 0.58, cy - r * 0.75, r * 0.52, r * 0.30), p);
    p.color = Colors.white.withOpacity(0.85);
    canvas.drawCircle(Offset(cx - r * 0.35, cy - r * 0.40), r * 0.11, p);

    p.isAntiAlias = false;
  }

  void _drawHeart(Canvas canvas, Paint p, double cx, double cy, double r, Color color) {
    p.color = color;
    final path = Path();
    final s = r * 0.72;
    path.moveTo(cx, cy + s * 0.6);
    path.cubicTo(cx - s * 1.1, cy - s * 0.2, cx - s * 1.2, cy - s * 1.1, cx, cy - s * 0.4);
    path.cubicTo(cx + s * 1.2, cy - s * 1.1, cx + s * 1.1, cy - s * 0.2, cx, cy + s * 0.6);
    canvas.drawPath(path, p);
    p.color = color.withOpacity(0.55);
    canvas.drawOval(Rect.fromLTWH(cx - s * 0.55, cy - s * 0.95, s * 0.55, s * 0.45), p);
  }

  void _drawStar(Canvas canvas, Paint p, double cx, double cy, double r, Color color, int points) {
    p.color = color;
    final path = Path();
    final inner = r * 0.42;
    for (int i = 0; i < points * 2; i++) {
      final angle = (i * pi / points) - pi / 2;
      final rad = i.isEven ? r * 0.88 : inner;
      final x = cx + rad * cos(angle);
      final y = cy + rad * sin(angle);
      if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
    }
    path.close();
    canvas.drawPath(path, p);
    // Center glow
    p.color = color.withOpacity(0.6);
    canvas.drawCircle(Offset(cx, cy), r * 0.30, p);
  }

  void _drawLemon(Canvas canvas, Paint p, double cx, double cy, double r, Color color) {
    p.color = color;
    canvas.drawOval(Rect.fromLTWH(cx - r * 0.75, cy - r, r * 1.5, r * 2.0), p);
    // Stripe
    p.color = Colors.white.withOpacity(0.20);
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(cx - r, cy - r, r * 2, r * 2));
    canvas.translate(cx, cy);
    canvas.rotate(0.4);
    canvas.drawRect(Rect.fromLTWH(-r, -r * 0.25, r * 2, r * 0.50), p);
    canvas.restore();
  }

  void _drawDiamond(Canvas canvas, Paint p, double cx, double cy, double r, Color color) {
    p.color = color;
    final path = Path()
      ..moveTo(cx, cy - r * 0.92)
      ..lineTo(cx + r * 0.72, cy)
      ..lineTo(cx, cy + r * 0.92)
      ..lineTo(cx - r * 0.72, cy)
      ..close();
    canvas.drawPath(path, p);
    p.color = color.withOpacity(0.45);
    canvas.drawPath(Path()
      ..moveTo(cx, cy - r * 0.92)
      ..lineTo(cx + r * 0.72, cy)
      ..lineTo(cx, cy)
      ..close(), p);
  }

  void _drawSquare(Canvas canvas, Paint p, double cx, double cy, double r, Color color) {
    p.color = color;
    final rr = r * 0.85;
    canvas.drawRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - rr, cy - rr, rr * 2, rr * 2),
        Radius.circular(rr * 0.28)), p);
    // Bottom-right shadow for 3D effect
    p.color = Color.fromARGB(255,
      (color.red * 0.60).round(), (color.green * 0.60).round(), (color.blue * 0.60).round());
    canvas.drawRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - rr + 2, cy, rr * 2 - 2, rr - 2),
        Radius.circular(rr * 0.20)), p);
  }
}

// ─── Candy Sky Background ─────────────────────────────────────────────────────

class _CandySkyPainter extends CustomPainter {
  const _CandySkyPainter();

  @override bool shouldRepaint(_) => false;

  @override
  void paint(Canvas canvas, Size size) {
    // Sky gradient — light blue
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..shader = const LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Color(0xFF5AC8F5), Color(0xFF88D8F0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)));

    final p = Paint()..isAntiAlias = true;

    // Fluffy clouds
    void cloud(double x, double y, double s) {
      p.color = Colors.white.withOpacity(0.88);
      canvas.drawCircle(Offset(x, y), s, p);
      canvas.drawCircle(Offset(x + s * 1.1, y + s * 0.1), s * 0.75, p);
      canvas.drawCircle(Offset(x - s * 0.8, y + s * 0.15), s * 0.65, p);
      canvas.drawCircle(Offset(x + s * 0.4, y - s * 0.4), s * 0.55, p);
      // Bottom fill
      p.color = Colors.white;
      canvas.drawRect(Rect.fromLTWH(x - s * 0.9, y, s * 2.1, s * 0.5), p);
    }
    cloud(size.width * 0.18, size.height * 0.08, 20);
    cloud(size.width * 0.72, size.height * 0.05, 16);
    cloud(size.width * 0.45, size.height * 0.13, 13);
  }
}

// ─── Candy Land Bottom Decoration ─────────────────────────────────────────────

class _CandyLandPainter extends CustomPainter {
  const _CandyLandPainter();

  @override bool shouldRepaint(_) => false;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final p = Paint()..isAntiAlias = true;

    // Green candy hills background
    p.color = const Color(0xFF44BB44);
    final hillPath = Path()
      ..moveTo(0, h * 0.6)
      ..quadraticBezierTo(w * 0.15, h * 0.1, w * 0.30, h * 0.5)
      ..quadraticBezierTo(w * 0.45, h * 0.9, w * 0.60, h * 0.4)
      ..quadraticBezierTo(w * 0.75, h * 0.05, w * 0.90, h * 0.5)
      ..quadraticBezierTo(w, h * 0.3, w, h * 0.7)
      ..lineTo(w, h)..lineTo(0, h)..close();
    canvas.drawPath(hillPath, p);

    // Pink hill accent
    p.color = const Color(0xFFFF88AA);
    final hillPath2 = Path()
      ..moveTo(0, h * 0.8)
      ..quadraticBezierTo(w * 0.20, h * 0.5, w * 0.42, h * 0.75)
      ..quadraticBezierTo(w * 0.62, h * 0.95, w * 0.80, h * 0.6)
      ..quadraticBezierTo(w * 0.92, h * 0.45, w, h * 0.65)
      ..lineTo(w, h)..lineTo(0, h)..close();
    canvas.drawPath(hillPath2, p);

    // Ground strip
    p.color = const Color(0xFF55CC55);
    canvas.drawRect(Rect.fromLTWH(0, h * 0.82, w, h * 0.18), p);

    // Candy cane poles (decorative)
    for (int i = 0; i < 3; i++) {
      final cx = w * (0.15 + i * 0.35);
      // Pole
      p.color = Colors.white;
      canvas.drawRRect(RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - 3, h * 0.15, 6, h * 0.68), const Radius.circular(3)), p);
      // Red stripes
      p.color = const Color(0xFFDD2244);
      for (double sy = h * 0.15; sy < h * 0.83; sy += h * 0.10) {
        canvas.drawRRect(RRect.fromRectAndRadius(
            Rect.fromLTWH(cx - 3, sy, 6, h * 0.04), const Radius.circular(2)), p);
      }
      // Ball on top
      p.color = const Color(0xFFDD2244);
      canvas.drawCircle(Offset(cx, h * 0.13), 7, p);
      p.color = Colors.white.withOpacity(0.6);
      canvas.drawCircle(Offset(cx - 2, h * 0.11), 2.5, p);
    }

    // Candy dot decorations on hills
    final candyDots = [
      (w * 0.08, h * 0.70, const Color(0xFFFF2266)),
      (w * 0.25, h * 0.60, const Color(0xFFFFDD00)),
      (w * 0.55, h * 0.55, const Color(0xFF3388FF)),
      (w * 0.72, h * 0.68, const Color(0xFF22CC44)),
      (w * 0.88, h * 0.62, const Color(0xFFCC44FF)),
    ];
    for (final (cx, cy, col) in candyDots) {
      p.color = col;
      canvas.drawCircle(Offset(cx, cy), 6, p);
      p.color = Colors.white.withOpacity(0.55);
      canvas.drawCircle(Offset(cx - 2, cy - 2), 2, p);
    }
  }
}

// ─── Side Panel Painter (Chrome Vending Machine Pillars) ─────────────────────

class _CandySidePainter extends CustomPainter {
  final int side; // 0 = left pillar, 1 = right pillar
  final double h;
  const _CandySidePainter({required this.side, required this.h});

  @override
  bool shouldRepaint(_CandySidePainter old) => false;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final p = Paint()..isAntiAlias = true;

    // Chrome pillar gradient
    final chromeShader = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: side == 0
          ? [const Color(0xFF5A3060), const Color(0xFF2A1030), const Color(0xFF1A000E)]
          : [const Color(0xFF1A000E), const Color(0xFF2A1030), const Color(0xFF5A3060)],
      stops: const [0.0, 0.5, 1.0],
    ).createShader(Rect.fromLTWH(0, 0, w, h));
    p.shader = chromeShader;
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), p);
    p.shader = null;

    // Inner edge highlight (glass tube wall)
    p.style = PaintingStyle.stroke;
    p.strokeWidth = 1.5;
    p.color = Colors.white.withOpacity(0.25);
    final edgeX = side == 0 ? w - 2.0 : 2.0;
    canvas.drawLine(Offset(edgeX, 0), Offset(edgeX, h), p);
    p.style = PaintingStyle.fill;

    // Candy spheres floating in the tube
    final candyColors = [
      const Color(0xFFFF2266),
      const Color(0xFFFF7700),
      const Color(0xFFFFDD00),
      const Color(0xFF22CC44),
      const Color(0xFF3388FF),
      const Color(0xFFCC44FF),
    ];
    final ballR = (w * 0.38).clamp(4.0, 10.0);
    // Use actual canvas height so balls don't overlap in short panels
    final actualH = size.height;
    // Fit as many balls as actually fit with no overlap
    final maxBalls = (actualH / (ballR * 2 + 2)).floor().clamp(1, 7);
    final step = actualH / (maxBalls + 0.5);
    for (int i = 0; i < maxBalls; i++) {
      final cy = step * 0.5 + i * step;
      final cx = w / 2 + (i.isEven ? 2.0 : -2.0);
      final col = candyColors[i % candyColors.length];
      // Shadow
      p.color = Colors.black.withOpacity(0.30);
      canvas.drawCircle(Offset(cx + 1, cy + 1), ballR, p);
      // Body
      p.color = col;
      canvas.drawCircle(Offset(cx, cy), ballR, p);
      // Stripe
      p.color = Colors.white.withOpacity(0.18);
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(cx - ballR, cy - ballR, ballR * 2, ballR * 2));
      canvas.rotate(0.5);
      canvas.drawRect(Rect.fromLTWH(cx - ballR * 0.8, cy - ballR * 0.2, ballR * 1.6, ballR * 0.4), p);
      canvas.restore();
      // Shine
      p.color = Colors.white.withOpacity(0.50);
      canvas.drawOval(Rect.fromLTWH(cx - ballR * 0.45, cy - ballR * 0.65, ballR * 0.45, ballR * 0.28), p);
    }

    if (side == 1) {
      // Coin slot at bottom right pillar
      final slotY = h - 28.0;
      final slotX = w * 0.2;
      final slotW = w * 0.6;
      // Slot background
      p.color = const Color(0xFF0A0005);
      canvas.drawRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(slotX, slotY, slotW, 6), const Radius.circular(3)), p);
      // Slot highlight
      p.color = Colors.white.withOpacity(0.15);
      p.style = PaintingStyle.stroke;
      p.strokeWidth = 1;
      canvas.drawRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(slotX, slotY, slotW, 6), const Radius.circular(3)), p);
      p.style = PaintingStyle.fill;
    }
  }
}
