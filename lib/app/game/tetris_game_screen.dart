import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'arcade_center_screen.dart' show AppLanguage;
import 'arcade_input_controller.dart';
import 'game_saldo.dart';
import 'high_score_service.dart';

const _kShapes = [
  [
    [[1, 0], [1, 1], [1, 2], [1, 3]],
    [[0, 2], [1, 2], [2, 2], [3, 2]],
    [[2, 0], [2, 1], [2, 2], [2, 3]],
    [[0, 1], [1, 1], [2, 1], [3, 1]]
  ],
  [
    [[0, 0], [0, 1], [1, 0], [1, 1]],
    [[0, 0], [0, 1], [1, 0], [1, 1]],
    [[0, 0], [0, 1], [1, 0], [1, 1]],
    [[0, 0], [0, 1], [1, 0], [1, 1]]
  ],
  [
    [[0, 1], [1, 0], [1, 1], [1, 2]],
    [[0, 0], [1, 0], [1, 1], [2, 0]],
    [[1, 0], [1, 1], [1, 2], [2, 1]],
    [[0, 2], [1, 1], [1, 2], [2, 2]]
  ],
  [
    [[0, 1], [0, 2], [1, 0], [1, 1]],
    [[0, 0], [1, 0], [1, 1], [2, 1]],
    [[0, 1], [0, 2], [1, 0], [1, 1]],
    [[0, 0], [1, 0], [1, 1], [2, 1]]
  ],
  [
    [[0, 0], [0, 1], [1, 1], [1, 2]],
    [[0, 1], [1, 0], [1, 1], [2, 0]],
    [[0, 0], [0, 1], [1, 1], [1, 2]],
    [[0, 1], [1, 0], [1, 1], [2, 0]]
  ],
  [
    [[0, 0], [1, 0], [1, 1], [1, 2]],
    [[0, 0], [0, 1], [1, 0], [2, 0]],
    [[1, 0], [1, 1], [1, 2], [2, 2]],
    [[0, 1], [1, 1], [2, 0], [2, 1]]
  ],
  [
    [[0, 2], [1, 0], [1, 1], [1, 2]],
    [[0, 0], [1, 0], [2, 0], [2, 1]],
    [[1, 0], [1, 1], [1, 2], [2, 0]],
    [[0, 0], [0, 1], [1, 1], [2, 1]]
  ],
];

const _kColors = [
  Color(0xFF00E5FF),
  Color(0xFFFFD700),
  Color(0xFFCC00FF),
  Color(0xFF00E676),
  Color(0xFFFF1744),
  Color(0xFF2979FF),
  Color(0xFFFF6D00),
];

const _kScoreTable = [0, 100, 300, 500, 800];

enum _GameState { start, playing, paused, dead, complete }

const int _kMaxLines = 400;

class TetrisScreen extends StatefulWidget {
  final String userId;
  final DocumentReference rewardsDocRef;
  final double currentSaldo;
  final ArcadeInputController controller;
  final void Function(double) onSaldoChanged;
  final AppLanguage language;

  const TetrisScreen({
    super.key,
    required this.userId,
    required this.rewardsDocRef,
    required this.currentSaldo,
    required this.controller,
    required this.onSaldoChanged,
    this.language = AppLanguage.spanish,
  });

  @override
  State<TetrisScreen> createState() => _TetrisScreenState();
}

class _TetrisScreenState extends State<TetrisScreen> {
  late List<List<int>> _grid;

  int _pieceType = 0;
  int _rot = 0;
  int _pieceRow = 0;
  int _pieceCol = 3;

  int _nextType = 0;

  int _score = 0;
  int _hiScore = 0;
  int _level = 1;
  int _totalLines = 0;
  late double _saldo;
  late double _lastCommitted;

  _GameState _state = _GameState.start;

  // The arcade shell already charged kArcadePlayCost to launch this
  // cartridge, so the first start of a fresh run is free. Every restart
  // after it pays again.
  bool _entryPaid = true;

  Timer? _gravTimer;
  Timer? _dasTimer;
  Timer? _dasRepeat;

  final _rng = Random();

  String _t(String es, String en) =>
      widget.language == AppLanguage.spanish ? es : en;

  @override
  void initState() {
    super.initState();
    _saldo = widget.currentSaldo;
    _lastCommitted = widget.currentSaldo;
    _initGrid();
    HighScoreService.load('tetris').then((v) {
      if (!mounted) return;
      setState(() => _hiScore = v);
    });
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

  int _ghostRow() {
    int r = _pieceRow;
    while (_isValid(r + 1, _pieceCol, _rot)) {
      r++;
    }
    return r;
  }

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
      } else {
        r--;
      }
    }

    if (cleared == 0) return;

    final prevLines = _totalLines;
    _totalLines += cleared;

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

    if (levelChanged) {
      _startGravity();
    }

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
      _saldo = newSaldo;
    }
  }

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

  Future<void> _restart() async {
    // First start of a freshly-launched run: the shell already paid for it.
    if (_entryPaid) {
      _entryPaid = false;
      _gravTimer?.cancel();
      _dasTimer?.cancel();
      _dasRepeat?.cancel();
      _startGame();
      return;
    }
    final ns = await chargeForReplay(
        userId: widget.userId,
        rewardsDocRef: widget.rewardsDocRef,
        currentSaldo: _saldo);
    if (ns == null) return;
    if (!mounted) return;
    // The charge moved the server saldo without going through
    // _updateFirestore, so the ledger has to be resynced here — otherwise
    // the next credit's delta is measured against the pre-charge base and
    // comes out negative, debiting the player instead of paying them.
    _lastCommitted = ns;
    setState(() => _saldo = ns);
    widget.onSaldoChanged(ns);
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

  void _startDas(void Function() action) {
    _cancelDas();
    action();
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
      if (btn == ArcadeButton.left ||
          btn == ArcadeButton.right ||
          btn == ArcadeButton.down) {
        _cancelDas();
      }
    }
  }

  Future<void> _updateFirestore(double newSaldo) async {
    // Routes through the server-side `updateRewardsSaldo`
    // callable instead of writing rewards/{docId} directly
    // (admin-only collection — direct writes failed silently
    // for every non-admin user). The CF resolves the wallet,
    // applies the delta in a transaction, and mirrors the
    // result to the owner-readable card cache.
    final delta = newSaldo - _lastCommitted;
    if (delta == 0) return;
    final result = await applyArcadeDelta(
      delta: delta,
      reason: 'tetris',
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
                  language: widget.language,
                ),
                child: SizedBox(
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                ),
              );
            },
          ),
        ),

        if (_state == _GameState.start) _buildStartOverlay(),
        if (_state == _GameState.dead) _buildDeathOverlay(),
        if (_state == _GameState.paused) _buildPauseOverlay(),
        if (_state == _GameState.complete) _buildCompleteOverlay(),
      ],
    );
  }

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
              textAlign: TextAlign.center,
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
          _buildNeonTitle(_t('BLOQUES\nCAÍDOS', 'BLOCK\nDROP'), const Color(0xFF00E5FF), 36),
          const SizedBox(height: 28),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
            decoration: BoxDecoration(
              color: const Color(0x22FFFFFF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0x4400E5FF), width: 1),
            ),
            child: Text(
              _t(
                'A / UP  →  Rotar\nLEFT / RIGHT  →  Mover\nDOWN  →  Bajar\nY  →  Caída rápida\nSTART  →  Pausa',
                'A / UP  →  Rotate\nLEFT / RIGHT  →  Move\nDOWN  →  Soft drop\nY  →  Hard drop\nSTART  →  Pause',
              ),
              style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.9),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _t(
              '1L=100  2L=300  3L=500  4L=800  ×nivel\n+1 pto cada 10 líneas',
              '1L=100  2L=300  3L=500  4L=800  ×level\n+1 pt every 10 lines',
            ),
            style: const TextStyle(
              color: Color(0xFFFFD700),
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
              shadows: [Shadow(color: Color(0xFFFFD700), blurRadius: 8)],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          _buildNeonButton(_t('Pulsa A o START para empezar', 'Press A or START to begin'),
              _restart, accent: const Color(0xFF00E5FF)),
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
          // Left untranslated: idiomatic in Spanish arcades, and "FIN DEL
          // JUEGO" wrapped to two lines at fontSize 38.
          _buildNeonTitle('GAME OVER', const Color(0xFFFF1744), 38),
          const SizedBox(height: 22),
          _buildHudCard(label: _t('PUNTUACIÓN', 'SCORE'), value: '$_score', accent: const Color(0xFF00E5FF)),
          _buildHudCard(label: _t('RÉCORD', 'BEST'), value: '$_hiScore', accent: const Color(0xFFFFD700)),
          const SizedBox(height: 22),
          _buildNeonButton(_t('Nueva Partida', 'New Game'), _restart, accent: const Color(0xFFFF1744)),
        ],
      ),
    );
  }

  Widget _buildPauseOverlay() {
    return _buildOverlayBackground(
      tint: const Color(0xFF8800FF),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _t('PAUSA', 'PAUSED'),
            style: const TextStyle(
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
          const SizedBox(height: 16),
          Text(
            _t('Pulsa START para continuar', 'Press START to continue'),
            style: const TextStyle(color: Colors.white54, fontSize: 13, letterSpacing: 1),
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
          _buildNeonTitle(_t('¡COMPLETO!', 'COMPLETE!'), const Color(0xFFFFD700), 34),
          const SizedBox(height: 6),
          Text(
            _t('400 LÍNEAS ALCANZADAS', '400 LINES CLEARED'),
            style: const TextStyle(
              color: Color(0xFF00E5FF),
              fontSize: 12,
              letterSpacing: 3,
              shadows: [Shadow(color: Color(0xFF00E5FF), blurRadius: 8)],
            ),
          ),
          const SizedBox(height: 18),
          _buildHudCard(label: _t('PUNTUACIÓN', 'SCORE'), value: '$_score', accent: const Color(0xFF00E5FF)),
          _buildHudCard(label: _t('RÉCORD', 'BEST'), value: '$_hiScore', accent: const Color(0xFFFFD700)),
          const SizedBox(height: 6),
          Text(
            _t('+40 pts ganados', '+40 pts earned'),
            style: const TextStyle(
              color: Color(0xFF00E676),
              fontSize: 14,
              fontWeight: FontWeight.bold,
              shadows: [Shadow(color: Color(0xFF00E676), blurRadius: 8)],
            ),
          ),
          const SizedBox(height: 24),
          _buildNeonButton(_t('Nueva Partida', 'New Game'), _restart, accent: const Color(0xFFFFD700)),
        ],
      ),
    );
  }
}

class _TetrisPainter extends CustomPainter {
  final List<List<int>> grid;
  final int pieceType;
  final int rot;
  final int pieceRow;
  final int pieceCol;
  final int ghostRow;
  final int nextType;
  final int score;
  final int hiScore;
  final int level;
  final int totalLines;
  final AppLanguage language;

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
    this.language = AppLanguage.spanish,
  });

  String _pt(String es, String en) =>
      language == AppLanguage.spanish ? es : en;

  static final List<Offset> _stars = List.generate(60, (i) {
    final rng = Random(i * 1337 + 42);
    return Offset(rng.nextDouble(), rng.nextDouble());
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cellSizeW = (size.width * 0.60 / 10).floor().toDouble();
    final cellSizeH = (size.height * 0.92 / 20).floor().toDouble();
    final cellSize = min(cellSizeW, cellSizeH);
    final boardW = cellSize * 10;
    final boardH = cellSize * 20;
    const boardX = 0.0;
    final boardY = ((size.height - boardH) / 2).floorToDouble();

    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF0B0020),
          Color(0xFF060618),
          Color(0xFF020208),
        ],
        stops: [0.0, 0.55, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    final starPaint = Paint()..isAntiAlias = true;
    for (int i = 0; i < _stars.length; i++) {
      final s = _stars[i];
      final brightness = (i % 3 == 0) ? 0.8 : (i % 3 == 1) ? 0.5 : 0.35;
      final radius = (i % 3 == 0) ? 1.2 : 0.8;
      starPaint.color = Colors.white.withOpacity(brightness);
      canvas.drawCircle(Offset(s.dx * size.width, s.dy * size.height), radius, starPaint);
    }

    final boardBgPaint = Paint()..color = const Color(0xFF0D0D1A);
    canvas.drawRect(Rect.fromLTWH(boardX, boardY, boardW, boardH), boardBgPaint);

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

    for (int r = 0; r < 20; r++) {
      for (int c = 0; c < 10; c++) {
        final colorIndex = grid[r][c];
        if (colorIndex == 0) continue;
        _drawCell(canvas, boardX + c * cellSize, boardY + r * cellSize, cellSize, _kColors[colorIndex - 1], locked: true);
      }
    }

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

    if (pieceType >= 0) {
      for (final cell in _kShapes[pieceType][rot] as List<List<int>>) {
        final pr = pieceRow + cell[0];
        final pc = pieceCol + cell[1];
        if (pr >= 0 && pr < 20 && pc >= 0 && pc < 10) {
          _drawCell(canvas, boardX + pc * cellSize, boardY + pr * cellSize, cellSize, _kColors[pieceType], locked: false);
        }
      }
    }

    final panelX = boardX + boardW + 6;
    final panelW = size.width - panelX - 4;
    _drawRightPanel(canvas, panelX, boardY, panelW, boardH, cellSize);
  }

  void _drawCell(Canvas canvas, double x, double y, double cs, Color color, {required bool locked}) {
    final radius = cs * 0.18;
    final rect = Rect.fromLTWH(x + 1, y + 1, cs - 2, cs - 2);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));

    final glowPaint = Paint()
      ..color = color.withOpacity(0.20)
      ..maskFilter = MaskFilter.blur(BlurStyle.inner, cs * 0.25)
      ..isAntiAlias = true;
    canvas.drawRRect(rrect, glowPaint);

    final mainPaint = Paint()
      ..color = color
      ..isAntiAlias = true;
    canvas.drawRRect(rrect, mainPaint);

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

    _paintLabel(canvas, _pt('SIGUIENTE', 'NEXT'), x, cy, w, const Color(0xFF00E5FF), 9.5, neonGlow: true);
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

    _drawDivider(canvas, x, cy, w);
    cy += 9;

    _paintLabel(canvas, _pt('PUNTOS', 'SCORE'), x, cy, w, const Color(0xFF00E5FF), 9, neonGlow: true);
    cy += 13;
    _paintLabel(canvas, '$score', x, cy, w, Colors.white, 14, bold: true);
    cy += 19;

    _paintLabel(canvas, _pt('RÉCORD', 'BEST'), x, cy, w, const Color(0xFFFFD700), 9, neonGlow: true);
    cy += 13;
    _paintLabel(canvas, '$hiScore', x, cy, w, const Color(0xFFFFD700), 13, bold: true);
    cy += 18;

    _drawDivider(canvas, x, cy, w);
    cy += 9;

    _paintLabel(canvas, _pt('NIV', 'LVL'), x, cy, w, const Color(0xFFCC00FF), 9, neonGlow: true);
    cy += 13;
    _paintLabel(canvas, '$level', x, cy, w, const Color(0xFFE040FB), 14, bold: true);
    cy += 19;

    _paintLabel(canvas, _pt('LÍNEAS', 'LINES'), x, cy, w, const Color(0xFF00E676), 9, neonGlow: true);
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
