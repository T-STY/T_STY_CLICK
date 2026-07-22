import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'arcade_center_screen.dart' show AppLanguage;
import 'arcade_input_controller.dart';
import 'game_saldo.dart';
import 'high_score_service.dart';

const _kMazeRows = 15, _kMazeCols = 15;
const _kMap = <List<int>>[
  [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
  [1, 2, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 2, 1],
  [1, 0, 1, 1, 0, 1, 0, 0, 0, 1, 0, 1, 1, 0, 1],
  [1, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 1],
  [1, 0, 0, 0, 1, 1, 0, 0, 0, 1, 1, 0, 0, 0, 1],
  [1, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 1],
  [1, 0, 0, 0, 1, 0, 3, 3, 3, 0, 1, 0, 0, 0, 1],
  [1, 1, 0, 1, 0, 0, 3, 3, 3, 0, 0, 1, 0, 1, 1],
  [1, 0, 0, 0, 1, 0, 3, 3, 3, 0, 1, 0, 0, 0, 1],
  [1, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 1],
  [1, 0, 0, 0, 1, 1, 0, 0, 0, 1, 1, 0, 0, 0, 1],
  [1, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 1],
  [1, 0, 1, 1, 0, 1, 0, 0, 0, 1, 0, 1, 1, 0, 1],
  [1, 2, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 2, 1],
  [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
];

const _kDR = [-1, 0, 1, 0];
const _kDC = [0, 1, 0, -1];

class _Ghost {
  int row, col;
  int dir;
  bool scared;
  Color color;
  _Ghost(this.row, this.col, this.color)
      : dir = 2,
        scared = false;
}

class MazeChasScreen extends StatefulWidget {
  final String userId;
  final DocumentReference rewardsDocRef;
  final double currentSaldo;
  final ArcadeInputController controller;
  final void Function(double) onSaldoChanged;
  final AppLanguage language;

  const MazeChasScreen({
    super.key,
    required this.userId,
    required this.rewardsDocRef,
    required this.currentSaldo,
    required this.controller,
    required this.onSaldoChanged,
    this.language = AppLanguage.spanish,
  });

  @override
  State<MazeChasScreen> createState() => _MazeChasScreenState();
}

class _MazeChasScreenState extends State<MazeChasScreen> {
  late List<List<int>> _grid;

  int _playerRow = 11, _playerCol = 7;
  int _queuedDir = 1;
  int _currentDir = 1;

  late List<_Ghost> _ghosts;

  int _score = 0;
  int _hiScore = 0;
  int _level = 1;
  int _lives = 3;

  bool _isRunning = false;
  bool _isDead = false;
  bool _levelComplete = false;
  bool _paused = false;
  bool _scaredActive = false;

  double _saldo = 0;
  late double _lastCommitted;

  Timer? _playerTimer;
  Timer? _ghostTimer;
  Timer? _scaredTimer;
  Timer? _blinkTimer;
  Timer? _levelCompleteTimer;

  bool _pelletBlink = false;
  bool _scaredBlink = false;
  int _ghostIntervalMs = 300;

  final _rng = Random();

  String _t(String es, String en) =>
      widget.language == AppLanguage.spanish ? es : en;

  @override
  void initState() {
    super.initState();
    _saldo = widget.currentSaldo;
    _lastCommitted = widget.currentSaldo;
    _buildGrid();
    _spawnGhosts();
    widget.controller.addListener(_onControllerEvent);
    HighScoreService.load('maze').then((v) {
      if (mounted) setState(() => _hiScore = v);
    });
  }

  @override
  void dispose() {
    _playerTimer?.cancel();
    _ghostTimer?.cancel();
    _scaredTimer?.cancel();
    _blinkTimer?.cancel();
    _levelCompleteTimer?.cancel();
    widget.controller.removeListener(_onControllerEvent);
    super.dispose();
  }

  void _buildGrid() {
    _grid = List.generate(
      _kMazeRows,
      (r) => List<int>.from(_kMap[r]),
    );
  }

  bool _isWall(int r, int c) {
    if (r < 0 || r >= _kMazeRows || c < 0 || c >= _kMazeCols) return true;
    return _grid[r][c] == 1;
  }

  bool _isWalkable(int r, int c) => !_isWall(r, c);

  int _dotsRemaining() {
    int count = 0;
    for (final row in _grid) {
      for (final cell in row) {
        if (cell == 0 || cell == 2) count++;
      }
    }
    return count;
  }

  void _spawnGhosts() {
    _ghosts = [
      _Ghost(6, 7, const Color(0xFFFF0000)),
      _Ghost(7, 6, const Color(0xFFFF69B4)),
      _Ghost(7, 8, const Color(0xFF00FFFF)),
      _Ghost(8, 7, const Color(0xFFFFB347)),
    ];
  }

  void _onControllerEvent() {
    final event = widget.controller.lastEvent;
    if (event == null || !event.isDown) return;
    final btn = event.button;

    switch (btn) {
      case ArcadeButton.up:
        _queuedDir = 0;
        if (!_isRunning && !_isDead && !_levelComplete) _startGame();
      case ArcadeButton.down:
        _queuedDir = 2;
        if (!_isRunning && !_isDead && !_levelComplete) _startGame();
      case ArcadeButton.left:
        _queuedDir = 3;
        if (!_isRunning && !_isDead && !_levelComplete) _startGame();
      case ArcadeButton.right:
        _queuedDir = 1;
        if (!_isRunning && !_isDead && !_levelComplete) _startGame();
      case ArcadeButton.a:
        if (_isDead) {
          _restart();
        } else if (!_isRunning && !_levelComplete) {
          _startGame();
        }
      case ArcadeButton.start:
        if (_isDead) {
          _restart();
        } else if (_isRunning && !_levelComplete) {
          setState(() => _paused = !_paused);
          if (_paused) _stopTimers();
          else _startTimers();
        } else if (!_isRunning && !_levelComplete) {
          _startGame();
        }
      default:
        break;
    }
  }

  void _startGame() {
    if (!mounted) return;
    setState(() => _isRunning = true);
    _startTimers();
  }

  void _startTimers() {
    _playerTimer?.cancel();
    _ghostTimer?.cancel();
    _blinkTimer?.cancel();
    _playerTimer = Timer.periodic(
      const Duration(milliseconds: 200),
      _playerStep,
    );
    _ghostTimer = Timer.periodic(
      Duration(milliseconds: _ghostIntervalMs),
      _ghostsStep,
    );
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (mounted) setState(() => _pelletBlink = !_pelletBlink);
    });
  }

  void _stopTimers() {
    _playerTimer?.cancel();
    _ghostTimer?.cancel();
    _blinkTimer?.cancel();
    _playerTimer = null;
    _ghostTimer = null;
    _blinkTimer = null;
  }

  Future<void> _restart() async {
    final ns = await chargeForReplay(
        userId: widget.userId,
        rewardsDocRef: widget.rewardsDocRef,
        currentSaldo: _saldo);
    if (ns == null) return;
    if (!mounted) return;
    widget.onSaldoChanged(ns);
    _stopTimers();
    _scaredTimer?.cancel();
    _levelCompleteTimer?.cancel();
    setState(() {
      _saldo = ns;
      // Resync the ledger: the replay charge already committed on the
      // server, so _lastCommitted must follow _saldo. Otherwise the next
      // credit's delta (newSaldo - _lastCommitted) comes out negative and
      // debits the player instead of paying them.
      _lastCommitted = ns;
      _buildGrid();
      _spawnGhosts();
      _playerRow = 11;
      _playerCol = 7;
      _queuedDir = 1;
      _currentDir = 1;
      _score = 0;
      _level = 1;
      _lives = 3;
      _isDead = false;
      _levelComplete = false;
      _isRunning = false;
      _scaredActive = false;
      _ghostIntervalMs = 350;
    });
  }

  void _playerStep(Timer _) {
    if (!_isRunning || _isDead) return;

    final qr = _playerRow + _kDR[_queuedDir];
    final qc = _playerCol + _kDC[_queuedDir];

    int nextDir = _currentDir;
    if (_isWalkable(qr, qc)) {
      nextDir = _queuedDir;
    }

    final nr = _playerRow + _kDR[nextDir];
    final nc = _playerCol + _kDC[nextDir];

    if (_isWall(nr, nc)) return;

    if (!mounted) return;
    setState(() {
      _playerRow = nr;
      _playerCol = nc;
      _currentDir = nextDir;

      final cell = _grid[_playerRow][_playerCol];
      if (cell == 0) {
        _grid[_playerRow][_playerCol] = -1;
        _score += 10;
      } else if (cell == 2) {
        _grid[_playerRow][_playerCol] = -1;
        _score += 50;
        _activatePowerPellet();
      }
    });

    _checkPlayerGhostCollision();

    if (_dotsRemaining() == 0) {
      _triggerLevelComplete();
    }
  }

  void _activatePowerPellet() {
    _scaredTimer?.cancel();
    _scaredActive = true;
    for (final g in _ghosts) {
      g.scared = true;
    }
    _scaredTimer = Timer(const Duration(seconds: 6), () {
      if (!mounted) return;
      setState(() {
        _scaredActive = false;
        for (final g in _ghosts) {
          g.scared = false;
        }
      });
    });
  }

  Duration get _scaredTimeRemaining {
    return Duration.zero;
  }

  void _ghostsStep(Timer _) {
    if (!_isRunning || _isDead) return;
    if (!mounted) return;

    setState(() {
      for (int i = 0; i < _ghosts.length; i++) {
        _moveGhost(i);
      }
    });

    _checkPlayerGhostCollision();
  }

  void _moveGhost(int idx) {
    final g = _ghosts[idx];
    final oppositeDir = (g.dir + 2) % 4;

    final validDirs = <int>[];
    for (int d = 0; d < 4; d++) {
      if (d == oppositeDir) continue;
      final nr = g.row + _kDR[d];
      final nc = g.col + _kDC[d];
      if (_isWalkable(nr, nc)) validDirs.add(d);
    }

    if (validDirs.isEmpty) {
      final nr = g.row + _kDR[oppositeDir];
      final nc = g.col + _kDC[oppositeDir];
      if (_isWalkable(nr, nc)) validDirs.add(oppositeDir);
    }

    if (validDirs.isEmpty) return;

    int chosenDir;
    if (g.scared) {
      chosenDir = validDirs[_rng.nextInt(validDirs.length)];
    } else {
      int targetRow, targetCol;
      switch (idx) {
        case 0:
          targetRow = _playerRow;
          targetCol = _playerCol;
        case 1:
          targetRow = _playerRow + _kDR[_currentDir] * 3;
          targetCol = _playerCol + _kDC[_currentDir] * 3;
          targetRow = targetRow.clamp(0, _kMazeRows - 1);
          targetCol = targetCol.clamp(0, _kMazeCols - 1);
        case 2:
          chosenDir = validDirs[_rng.nextInt(validDirs.length)];
          g.dir = chosenDir;
          g.row += _kDR[chosenDir];
          g.col += _kDC[chosenDir];
          return;
        case 3:
          final dist = (_playerRow - g.row).abs() + (_playerCol - g.col).abs();
          if (dist > 6) {
            targetRow = _playerRow;
            targetCol = _playerCol;
          } else {
            chosenDir = validDirs[_rng.nextInt(validDirs.length)];
            g.dir = chosenDir;
            g.row += _kDR[chosenDir];
            g.col += _kDC[chosenDir];
            return;
          }
        default:
          targetRow = _playerRow;
          targetCol = _playerCol;
      }

      int bestDist = 999999;
      chosenDir = validDirs[0];
      for (final d in validDirs) {
        final nr = g.row + _kDR[d];
        final nc = g.col + _kDC[d];
        final dist = (targetRow - nr).abs() + (targetCol - nc).abs();
        if (dist < bestDist) {
          bestDist = dist;
          chosenDir = d;
        }
      }
    }

    g.dir = chosenDir;
    g.row += _kDR[chosenDir];
    g.col += _kDC[chosenDir];
  }

  void _checkPlayerGhostCollision() {
    if (!mounted) return;
    for (final g in _ghosts) {
      if (g.row == _playerRow && g.col == _playerCol) {
        if (g.scared) {
          setState(() {
            g.row = 7;
            g.col = 7;
            g.scared = false;
            g.dir = 2;
            _score += 200;
          });
        } else {
          _loseLife();
          return;
        }
      }
    }
  }

  void _loseLife() {
    _stopTimers();
    HapticFeedback.heavyImpact();
    if (!mounted) return;

    setState(() {
      _lives--;
      _scaredActive = false;
      for (final g in _ghosts) {
        g.scared = false;
      }
      _scaredTimer?.cancel();
    });

    if (_lives <= 0) {
      _triggerGameOver();
    } else {
      setState(() {
        _playerRow = 11;
        _playerCol = 7;
        _queuedDir = 1;
        _currentDir = 1;
        _spawnGhosts();
      });
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted && _isRunning) _startTimers();
      });
    }
  }

  Future<void> _triggerGameOver() async {
    setState(() {
      _isDead = true;
      _isRunning = false;
    });
    await HighScoreService.submit('maze', _score);
    final best = await HighScoreService.load('maze');
    if (mounted) setState(() => _hiScore = best);
  }

  void _triggerLevelComplete() {
    _stopTimers();
    _scaredTimer?.cancel();
    if (!mounted) return;

    setState(() {
      _levelComplete = true;
      _isRunning = false;
      _scaredActive = false;
    });

    // +1 punto per level clear. _updateFirestore is the only writer of
    // _saldo here — it applies the server's authoritative result. Adding
    // it again locally paid the player twice from level 2 onward.
    _updateFirestore(_saldo + 1).then((_) {
      if (!mounted) return;
      widget.onSaldoChanged(_saldo);
    });

    _levelCompleteTimer = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      setState(() {
        _level++;
        _ghostIntervalMs = max(150, 350 - (_level - 1) * 20);
        _buildGrid();
        _spawnGhosts();
        _playerRow = 11;
        _playerCol = 7;
        _queuedDir = 1;
        _currentDir = 1;
        _levelComplete = false;
        _isRunning = true;
      });
      _startTimers();
    });
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
      reason: 'maze_chase',
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
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF0A0014),
                  Color(0xFF110022),
                  Color(0xFF0D001A),
                ],
              ),
            ),
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            return CustomPaint(
              painter: _MazePainter(
                grid: _grid,
                playerRow: _playerRow,
                playerCol: _playerCol,
                playerDir: _currentDir,
                ghosts: _ghosts,
                score: _score,
                lives: _lives,
                level: _level,
                pelletBlink: _pelletBlink,
                scaredBlink: _pelletBlink,
                language: widget.language,
              ),
              child: SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
              ),
            );
          },
        ),
        if (!_isRunning && !_isDead && !_levelComplete) _buildStartOverlay(),
        if (_isDead) _buildGameOverOverlay(),
        if (_levelComplete) _buildLevelCompleteOverlay(),
        if (_paused && _isRunning) _buildPauseOverlay(),
      ],
    );
  }

  Widget _buildStartOverlay() {
    return Positioned.fill(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xF2060018),
              Color(0xF5090020),
              Color(0xF2040012),
            ],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _bigGhostIcon(const Color(0xFFFF3333)),
                const SizedBox(width: 8),
                _bigGhostIcon(const Color(0xFFFF88CC)),
                const SizedBox(width: 8),
                _bigGhostIcon(const Color(0xFF00DDFF)),
                const SizedBox(width: 8),
                _bigGhostIcon(const Color(0xFFFFAA33)),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _t('COMECOCOS', 'GHOST MAZE'),
              style: TextStyle(
                color: const Color(0xFFFFFF22),
                fontSize: 30,
                fontWeight: FontWeight.bold,
                letterSpacing: 5,
                shadows: [
                  Shadow(color: const Color(0xFFFFFF00).withOpacity(0.95), blurRadius: 14),
                  Shadow(color: const Color(0xFFFFCC00).withOpacity(0.6), blurRadius: 28),
                  Shadow(color: const Color(0xFFFF8800).withOpacity(0.3), blurRadius: 48),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(11, (i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2.5),
                child: Container(
                  width: i == 5 ? 11 : 7,
                  height: i == 5 ? 11 : 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == 5
                        ? const Color(0xFFFFFFAA)
                        : const Color(0xFFFFEE77),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFFFF00).withOpacity(i == 5 ? 0.9 : 0.5),
                        blurRadius: i == 5 ? 10 : 5,
                      ),
                    ],
                  ),
                ),
              )),
            ),
            const SizedBox(height: 20),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF00CCFF), width: 1.5),
                borderRadius: BorderRadius.circular(16),
                color: const Color(0xFF030818).withOpacity(0.97),
                boxShadow: [
                  BoxShadow(color: const Color(0xFF00AAFF).withOpacity(0.35), blurRadius: 20),
                  BoxShadow(color: const Color(0xFF6600FF).withOpacity(0.15), blurRadius: 30),
                ],
              ),
              child: Column(children: [
                _instrRow('D-pad', _t('Mover por el laberinto', 'Move through the maze'), const Color(0xFF00EEFF)),
                const SizedBox(height: 8),
                _instrRow('', _t('Come todos los puntos para pasar de nivel', 'Eat every dot to clear the level'), Colors.white70),
                const SizedBox(height: 8),
                _instrRow(_t('Pastilla', 'Power'), _t('¡Fantasmas comestibles!', 'Ghosts turn edible!'), const Color(0xFF00FF99)),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF003322), Color(0xFF004422)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF00FF77), width: 1.2),
                    boxShadow: [
                      BoxShadow(color: const Color(0xFF00FF66).withOpacity(0.3), blurRadius: 10),
                    ],
                  ),
                  child: Text(
                    _t('🪙  +1 PTO REAL POR NIVEL', '🪙  +1 REAL POINT PER LEVEL'),
                    style: const TextStyle(
                      color: Color(0xFF00FF99),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1144DD), Color(0xFF0022AA)],
                ),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: const Color(0xFF4499FF), width: 1.5),
                boxShadow: [
                  BoxShadow(color: const Color(0xFF2266FF).withOpacity(0.55), blurRadius: 16),
                ],
              ),
              child: Text(
                _t('Presiona A o START para jugar', 'Press A or START to play'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _instrRow(String label, String text, Color color) {
    return Row(
      children: [
        if (label.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: color.withOpacity(0.5), width: 1),
            ),
            child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(text, style: TextStyle(color: color, fontSize: 11), textAlign: TextAlign.center),
        ),
      ],
    );
  }

  Widget _miniGhostIcon(Color color) {
    return Container(
      width: 14,
      height: 16,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.fromARGB(255,
              (color.red + 80).clamp(0, 255),
              (color.green + 80).clamp(0, 255),
              (color.blue + 80).clamp(0, 255)),
            color,
          ],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
        boxShadow: [BoxShadow(color: color.withOpacity(0.7), blurRadius: 8, spreadRadius: 1)],
      ),
    );
  }

  Widget _bigGhostIcon(Color color) {
    final highlight = Color.fromARGB(255,
      (color.red + 70).clamp(0, 255),
      (color.green + 70).clamp(0, 255),
      (color.blue + 70).clamp(0, 255),
    );
    return Container(
      width: 26,
      height: 30,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [highlight, color, color],
          stops: const [0.0, 0.5, 1.0],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.7), blurRadius: 12, spreadRadius: 1),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            left: 4, top: 8,
            child: Container(
              width: 8, height: 8,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
              child: Center(
                child: Container(
                  width: 4, height: 4,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF0022AA),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 4, top: 8,
            child: Container(
              width: 8, height: 8,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
              child: Center(
                child: Container(
                  width: 4, height: 4,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF0022AA),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGameOverOverlay() {
    return Positioned.fill(
      child: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.0,
            colors: [
              Color(0xF0280010),
              Color(0xF5120008),
              Color(0xF2050010),
            ],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _bigGhostIcon(const Color(0xFFFF3333)),
                const SizedBox(width: 6),
                _bigGhostIcon(const Color(0xFFFF66AA)),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _t('ATRAPADO', 'CAUGHT'),
              style: TextStyle(
                color: const Color(0xFFFF2255),
                fontSize: 36,
                fontWeight: FontWeight.bold,
                letterSpacing: 5,
                shadows: [
                  Shadow(color: const Color(0xFFFF0044).withOpacity(0.95), blurRadius: 18),
                  Shadow(color: const Color(0xFFFF3388).withOpacity(0.55), blurRadius: 38),
                  Shadow(color: const Color(0xFFAA0033).withOpacity(0.3), blurRadius: 60),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _t('Un fantasma te ha engullido', 'A ghost gobbled you up'),
              style: TextStyle(
                color: const Color(0xFFBB6688),
                fontSize: 12,
                shadows: [Shadow(color: const Color(0xFFFF0066).withOpacity(0.3), blurRadius: 8)],
              ),
            ),
            const SizedBox(height: 20),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 28),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF200014), Color(0xFF100008)],
                ),
                border: Border.all(color: const Color(0xFFAA0033), width: 1.5),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: const Color(0xFFFF0055).withOpacity(0.25), blurRadius: 20),
                ],
              ),
              child: Column(children: [
                Text(
                  '$_score',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    shadows: [
                      Shadow(color: Colors.white.withOpacity(0.4), blurRadius: 10),
                    ],
                  ),
                ),
                Text(
                  _t('PUNTOS', 'POINTS'),
                  style: const TextStyle(
                    color: Color(0xFF886688),
                    fontSize: 11,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  height: 1,
                  color: const Color(0xFF660033),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _t('RÉCORD  ', 'RECORD  '),
                      style: const TextStyle(color: Color(0xFF886688), fontSize: 12, letterSpacing: 1),
                    ),
                    Text(
                      '$_hiScore',
                      style: TextStyle(
                        color: const Color(0xFFFFFF33),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        shadows: [
                          Shadow(color: const Color(0xFFFFFF00).withOpacity(0.7), blurRadius: 10),
                        ],
                      ),
                    ),
                  ],
                ),
              ]),
            ),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: _restart,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 13),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1155EE), Color(0xFF0033BB)],
                  ),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: const Color(0xFF4499FF), width: 1.5),
                  boxShadow: [
                    BoxShadow(color: const Color(0xFF2266FF).withOpacity(0.6), blurRadius: 18),
                  ],
                ),
                child: Text(
                  _t('Nueva Partida', 'New Game'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLevelCompleteOverlay() {
    return Positioned.fill(
      child: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 0.9,
            colors: [
              Color(0xEA004422),
              Color(0xF0010812),
            ],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF003322), Color(0xFF004422)],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF00FF88), width: 1.2),
                boxShadow: [
                  BoxShadow(color: const Color(0xFF00FF88).withOpacity(0.4), blurRadius: 12),
                ],
              ),
              child: Text(
                _t('¡NIVEL $_level!', 'LEVEL $_level!'),
                style: TextStyle(
                  color: const Color(0xFF00FF99),
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 3,
                  shadows: [Shadow(color: const Color(0xFF00FF88).withOpacity(0.9), blurRadius: 12)],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _t('COMPLETADO', 'COMPLETE'),
              style: TextStyle(
                color: const Color(0xFFFFFF22),
                fontSize: 32,
                fontWeight: FontWeight.bold,
                letterSpacing: 4,
                shadows: [
                  Shadow(color: const Color(0xFFFFFF00).withOpacity(0.95), blurRadius: 18),
                  Shadow(color: const Color(0xFFFFAA00).withOpacity(0.55), blurRadius: 36),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF003322), Color(0xFF004422)],
                ),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: const Color(0xFF00FF77), width: 1.5),
                boxShadow: [
                  BoxShadow(color: const Color(0xFF00FF66).withOpacity(0.4), blurRadius: 14),
                ],
              ),
              child: Text(
                _t('🪙  +1 pto real añadido', '🪙  +1 real point added'),
                style: const TextStyle(
                  color: Color(0xFF00FF99),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPauseOverlay() => Positioned.fill(
    child: Container(
      color: const Color(0xCC040010),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF0A0830),
              border: Border.all(color: const Color(0xFF00DDFF), width: 1.5),
              boxShadow: [
                BoxShadow(color: const Color(0xFF00AAFF).withOpacity(0.5), blurRadius: 18),
              ],
            ),
            child: const Center(
              child: Text('⏸', style: TextStyle(fontSize: 32)),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            _t('PAUSA', 'PAUSE'),
            style: TextStyle(
              color: const Color(0xFFFFFF33),
              fontSize: 32,
              fontWeight: FontWeight.bold,
              letterSpacing: 8,
              shadows: [
                Shadow(color: const Color(0xFFFFFF00).withOpacity(0.8), blurRadius: 18),
                Shadow(color: const Color(0xFFFFAA00).withOpacity(0.4), blurRadius: 32),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0020),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF4444AA), width: 1),
            ),
            child: Text(
              _t('START para continuar', 'Press START to continue'),
              style: const TextStyle(
                color: Color(0xFF9999CC),
                fontSize: 12,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _MazePainter extends CustomPainter {
  final List<List<int>> grid;
  final int playerRow, playerCol, playerDir;
  final List<_Ghost> ghosts;
  final int score, lives, level;
  final bool pelletBlink;
  final bool scaredBlink;
  final AppLanguage language;

  const _MazePainter({
    required this.grid,
    required this.playerRow,
    required this.playerCol,
    required this.playerDir,
    required this.ghosts,
    required this.score,
    required this.lives,
    required this.level,
    required this.pelletBlink,
    required this.scaredBlink,
    this.language = AppLanguage.spanish,
  });

  String _pt(String es, String en) =>
      language == AppLanguage.spanish ? es : en;

  @override
  void paint(Canvas canvas, Size size) {
    final cs = min(size.width / _kMazeCols, size.height / (_kMazeRows + 2))
        .floorToDouble();
    final offsetX = ((size.width - cs * _kMazeCols) / 2).floorToDouble();
    final offsetY = ((size.height - cs * _kMazeRows) / 2).floorToDouble();

    final bgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: const [
          Color(0xFF0C0020),
          Color(0xFF130028),
          Color(0xFF080018),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    final vignettePaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 1.05,
        colors: const [
          Color(0x00000000),
          Color(0xAA000000),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), vignettePaint);

    final bezelRect = Rect.fromLTWH(
      offsetX - 4, offsetY - 4,
      cs * _kMazeCols + 8, cs * _kMazeRows + 8,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bezelRect, const Radius.circular(8)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = const Color(0xFF8800FF).withOpacity(0.50),
    );
    final bezelPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xFF44FFFF);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bezelRect, const Radius.circular(8)),
      bezelPaint,
    );

    for (int r = 0; r < _kMazeRows; r++) {
      for (int c = 0; c < _kMazeCols; c++) {
        final x = offsetX + c * cs;
        final y = offsetY + r * cs;
        final cell = grid[r][c];

        switch (cell) {
          case 1:
            _drawWall(canvas, x, y, cs, r, c);
          case 0:
            _drawDot(canvas, x, y, cs);
          case 2:
            _drawPowerPellet(canvas, x, y, cs);
          case 3:
            canvas.drawRect(Rect.fromLTWH(x, y, cs, cs), Paint()..color = const Color(0xFF120028));
            _drawFloorTile(canvas, x, y, cs, const Color(0xFF3A0066));
            canvas.drawRect(Rect.fromLTWH(x, y, cs, cs), Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.0
              ..color = const Color(0xFFEE00FF).withOpacity(0.35));
          default:
            canvas.drawRect(Rect.fromLTWH(x, y, cs, cs), Paint()..color = const Color(0xFF0C0018));
            _drawFloorTile(canvas, x, y, cs, const Color(0xFF1E0035));
        }
      }
    }

    for (final g in ghosts) {
      _drawGhost(canvas, g, offsetX, offsetY, cs);
    }

    _drawPlayer(canvas, playerRow, playerCol, playerDir, offsetX, offsetY, cs);

    _drawHud(canvas, size, cs, offsetX, offsetY);
  }

  void _drawFloorTile(Canvas canvas, double x, double y, double cs, Color lineColor) {
    final tilePaint = Paint()
      ..color = lineColor.withOpacity(0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    canvas.drawLine(Offset(x + cs, y), Offset(x + cs, y + cs), tilePaint);
    canvas.drawLine(Offset(x, y + cs), Offset(x + cs, y + cs), tilePaint);
  }

  void _drawWall(Canvas canvas, double x, double y, double cs, int r, int c) {
    final rect = Rect.fromLTWH(x, y, cs, cs);

    canvas.drawRect(rect, Paint()..color = const Color(0xFF100020));

    final hasTop    = r > 0 && _kMap[r - 1][c] != 1;
    final hasBottom = r < _kMazeRows - 1 && _kMap[r + 1][c] != 1;
    final hasLeft   = c > 0 && _kMap[r][c - 1] != 1;
    final hasRight  = c < _kMazeCols - 1 && _kMap[r][c + 1] != 1;

    const neonCoreColor = Color(0xFFAAFFFF);

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(0.9, cs * 0.08)
      ..color = neonCoreColor.withOpacity(0.95);

    void drawEdge(Offset a, Offset b) {
      canvas.drawLine(a, b, borderPaint);
    }

    if (hasTop)    drawEdge(Offset(x, y),        Offset(x + cs, y));
    if (hasBottom) drawEdge(Offset(x, y + cs),   Offset(x + cs, y + cs));
    if (hasLeft)   drawEdge(Offset(x, y),        Offset(x, y + cs));
    if (hasRight)  drawEdge(Offset(x + cs, y),   Offset(x + cs, y + cs));
  }

  void _drawDot(Canvas canvas, double x, double y, double cs) {
    final cx = x + cs / 2;
    final cy = y + cs / 2;
    final r = max(1.8, cs * 0.13);

    canvas.drawCircle(Offset(cx, cy), r, Paint()..color = const Color(0xFFFFEE55));
  }

  void _drawPowerPellet(Canvas canvas, double x, double y, double cs) {
    final cx = x + cs / 2;
    final cy = y + cs / 2;

    final baseR = cs * 0.25;
    final r = pelletBlink ? baseR * 1.22 : baseR * 0.85;

    canvas.drawCircle(Offset(cx, cy), r * 1.8,
      Paint()..color = const Color(0xFFFFAA00).withOpacity(pelletBlink ? 0.40 : 0.20));

    final corePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white,
          const Color(0xFFFFFF00),
          const Color(0xFFFFAA00),
          const Color(0xFFFF6600),
        ],
        stops: const [0.0, 0.35, 0.7, 1.0],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r));
    canvas.drawCircle(Offset(cx, cy), r, corePaint);

    canvas.drawCircle(
      Offset(cx - r * 0.28, cy - r * 0.28),
      r * 0.28,
      Paint()..color = Colors.white.withOpacity(0.8),
    );
  }

  void _drawGhost(
    Canvas canvas,
    _Ghost g,
    double offsetX,
    double offsetY,
    double cs,
  ) {
    final x = offsetX + g.col * cs;
    final y = offsetY + g.row * cs;

    final bodyW = cs * 0.78;
    final bodyH = cs * 0.82;
    final bx = x + (cs - bodyW) / 2;
    final by = y + (cs - bodyH) / 2 - cs * 0.02;

    Color ghostColor;
    Color ghostHighlight;
    Color ghostDark;
    if (g.scared) {
      ghostColor = scaredBlink
          ? const Color(0xFF5555FF)
          : const Color(0xFF1A0FAA);
      ghostHighlight = scaredBlink
          ? const Color(0xFF9999FF)
          : const Color(0xFF3333DD);
      ghostDark = scaredBlink
          ? const Color(0xFF2222AA)
          : const Color(0xFF080855);
    } else {
      ghostColor = g.color;
      final hR = (ghostColor.red + 90).clamp(0, 255);
      final hG = (ghostColor.green + 90).clamp(0, 255);
      final hB = (ghostColor.blue + 90).clamp(0, 255);
      ghostHighlight = Color.fromARGB(255, hR, hG, hB);
      final dR = (ghostColor.red ~/ 2).clamp(0, 255);
      final dG = (ghostColor.green ~/ 2).clamp(0, 255);
      final dB = (ghostColor.blue ~/ 2).clamp(0, 255);
      ghostDark = Color.fromARGB(255, dR, dG, dB);
    }

    final path = Path();
    final domeRadius = bodyW / 2;
    final domeCenterX = bx + bodyW / 2;
    final domeCenterY = by + domeRadius;

    path.addArc(
      Rect.fromCircle(center: Offset(domeCenterX, domeCenterY), radius: domeRadius),
      pi,
      pi,
    );

    final skirtTop = by + domeRadius;
    final skirtBottom = by + bodyH;
    path.lineTo(bx + bodyW, skirtTop);

    const waveCount = 3;
    final waveW = bodyW / waveCount;
    final waveAmp = bodyH * 0.16;

    path.lineTo(bx + bodyW, skirtBottom - waveAmp);
    for (int i = waveCount - 1; i >= 0; i--) {
      final midX = bx + i * waveW + waveW / 2;
      final midY = (i % 2 == 0)
          ? skirtBottom + waveAmp * 0.5
          : skirtBottom - waveAmp * 0.3;
      final endX = bx + i * waveW;
      final endY = skirtBottom - waveAmp * 0.1;
      path.quadraticBezierTo(midX, midY, endX, endY);
    }
    path.lineTo(bx, skirtTop);
    path.close();

    final bodyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [ghostHighlight, ghostColor, ghostDark],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromLTWH(bx, by, bodyW, bodyH));
    canvas.drawPath(path, bodyPaint);

    final glossPath = Path();
    final glossR = domeRadius * 0.58;
    final glossCX = domeCenterX - domeRadius * 0.22;
    final glossCY = domeCenterY - domeRadius * 0.35;
    glossPath.addArc(
      Rect.fromCircle(center: Offset(glossCX, glossCY), radius: glossR),
      pi * 1.1,
      pi * 0.7,
    );
    canvas.drawPath(
      glossPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(0.8, cs * 0.07)
        ..color = Colors.white.withOpacity(0.38),
    );

    final eyeScleraR = max(2.8, cs * 0.145);
    final leftEyeX = bx + bodyW * 0.30;
    final rightEyeX = bx + bodyW * 0.70;
    final eyeY = by + bodyH * 0.28;

    if (g.scared) {
      final eyePaint = Paint()..color = Colors.white.withOpacity(0.9);
      canvas.drawCircle(Offset(leftEyeX, eyeY), eyeScleraR * 0.7, eyePaint);
      canvas.drawCircle(Offset(rightEyeX, eyeY), eyeScleraR * 0.7, eyePaint);

      final xPaint = Paint()
        ..color = ghostDark
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(0.9, cs * 0.07)
        ..strokeCap = StrokeCap.round;
      final xR = eyeScleraR * 0.45;
      for (final ex in [leftEyeX, rightEyeX]) {
        canvas.drawLine(
          Offset(ex - xR, eyeY - xR), Offset(ex + xR, eyeY + xR), xPaint);
        canvas.drawLine(
          Offset(ex + xR, eyeY - xR), Offset(ex - xR, eyeY + xR), xPaint);
      }

      final mouthPaint = Paint()
        ..color = Colors.white.withOpacity(0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1.0, cs * 0.07)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final mouthPath = Path();
      final mouthY = by + bodyH * 0.60;
      final mx0 = bx + bodyW * 0.18;
      final mx1 = bx + bodyW * 0.82;
      final mw = mx1 - mx0;
      mouthPath.moveTo(mx0, mouthY);
      mouthPath.lineTo(mx0 + mw * 0.17, mouthY + cs * 0.07);
      mouthPath.lineTo(mx0 + mw * 0.34, mouthY - cs * 0.04);
      mouthPath.lineTo(mx0 + mw * 0.50, mouthY + cs * 0.07);
      mouthPath.lineTo(mx0 + mw * 0.67, mouthY - cs * 0.04);
      mouthPath.lineTo(mx0 + mw * 0.83, mouthY + cs * 0.07);
      mouthPath.lineTo(mx1, mouthY);
      canvas.drawPath(mouthPath, mouthPaint);
    } else {
      canvas.drawCircle(Offset(leftEyeX, eyeY), eyeScleraR,
          Paint()..color = Colors.white);
      canvas.drawCircle(Offset(rightEyeX, eyeY), eyeScleraR,
          Paint()..color = Colors.white);

      final irisR = eyeScleraR * 0.68;
      final irisPaint = Paint()..color = const Color(0xFF2255FF);
      canvas.drawCircle(Offset(leftEyeX, eyeY), irisR, irisPaint);
      canvas.drawCircle(Offset(rightEyeX, eyeY), irisR, irisPaint);

      final pupilR = eyeScleraR * 0.38;
      final pupilPaint = Paint()..color = Colors.black;
      canvas.drawCircle(Offset(leftEyeX, eyeY), pupilR, pupilPaint);
      canvas.drawCircle(Offset(rightEyeX, eyeY), pupilR, pupilPaint);

      final glintR = pupilR * 0.55;
      final glintPaint = Paint()..color = Colors.white;
      canvas.drawCircle(
        Offset(leftEyeX - pupilR * 0.32, eyeY - pupilR * 0.32), glintR, glintPaint);
      canvas.drawCircle(
        Offset(rightEyeX - pupilR * 0.32, eyeY - pupilR * 0.32), glintR, glintPaint);

      canvas.drawArc(
        Rect.fromCircle(center: Offset(leftEyeX, eyeY), radius: eyeScleraR * 0.85),
        pi * 1.1, pi * 0.55,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = max(0.5, cs * 0.04)
          ..color = Colors.white.withOpacity(0.6),
      );
      canvas.drawArc(
        Rect.fromCircle(center: Offset(rightEyeX, eyeY), radius: eyeScleraR * 0.85),
        pi * 1.1, pi * 0.55,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = max(0.5, cs * 0.04)
          ..color = Colors.white.withOpacity(0.6),
      );
    }
  }

  void _drawPlayer(
    Canvas canvas,
    int row,
    int col,
    int dir,
    double offsetX,
    double offsetY,
    double cs,
  ) {
    final x = offsetX + col * cs;
    final y = offsetY + row * cs;

    final radius = cs * 0.40;
    final cx = x + cs / 2;
    final cy = y + cs / 2;

    final mouthHalf = pelletBlink ? 0.42 : 0.08;
    final dirAngle = [
      -pi / 2,
      0.0,
      pi / 2,
      pi,
    ][dir];

    final startAngle = dirAngle + mouthHalf;
    final sweepAngle = 2 * pi - 2 * mouthHalf;

    final bodyPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.35, -0.35),
        radius: 1.05,
        colors: [
          const Color(0xFFFFFFCC),
          const Color(0xFFFFEE00),
          const Color(0xFFFFCC00),
          const Color(0xFFFF9900),
        ],
        stops: const [0.0, 0.30, 0.65, 1.0],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: radius));

    final path = Path()
      ..moveTo(cx, cy)
      ..arcTo(
        Rect.fromCircle(center: Offset(cx, cy), radius: radius),
        startAngle,
        sweepAngle,
        false,
      )
      ..close();
    canvas.drawPath(path, bodyPaint);

    final mouthLinePaint = Paint()
      ..color = const Color(0xFF1A0800)
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(0.7, cs * 0.04)
      ..strokeCap = StrokeCap.butt;
    final ux = cx + cos(dirAngle + mouthHalf) * radius;
    final uy = cy + sin(dirAngle + mouthHalf) * radius;
    canvas.drawLine(Offset(cx, cy), Offset(ux, uy), mouthLinePaint);
    final lx = cx + cos(dirAngle - mouthHalf) * radius;
    final ly = cy + sin(dirAngle - mouthHalf) * radius;
    canvas.drawLine(Offset(cx, cy), Offset(lx, ly), mouthLinePaint);

    final glossStartAngle = dirAngle - pi / 2 + pi * 0.8;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx - radius * 0.18, cy - radius * 0.18), radius: radius * 0.68),
      glossStartAngle,
      pi * 0.6,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1.2, radius * 0.28)
        ..color = Colors.white.withOpacity(0.45),
    );

    final eyeAngle = dirAngle - pi / 2;
    final ex = cx + cos(eyeAngle) * radius * 0.52 - sin(eyeAngle) * radius * 0.22;
    final ey = cy + sin(eyeAngle) * radius * 0.52 + cos(eyeAngle) * radius * 0.22;
    canvas.drawCircle(Offset(ex, ey), max(1.5, radius * 0.18), Paint()..color = const Color(0xFF0A0400));
    canvas.drawCircle(
      Offset(ex - radius * 0.07, ey - radius * 0.07),
      max(0.7, radius * 0.08),
      Paint()..color = Colors.white,
    );
  }

  void _drawHud(Canvas canvas, Size size, double cs, double offsetX, double offsetY) {
    final hudY = offsetY - cs * 1.35;
    final hudH = cs * 1.15;
    final hudRect = Rect.fromLTWH(offsetX, hudY, cs * _kMazeCols, hudH);
    final hudRRect = RRect.fromRectAndRadius(hudRect, const Radius.circular(6));

    canvas.drawRRect(hudRRect, Paint()..color = const Color(0xFF070616));

    final hudBorderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0xFF00CCFF).withOpacity(0.85);
    canvas.drawRRect(hudRRect, hudBorderPaint);

    final textY = hudY + hudH / 2;
    final fontSize = (cs * 0.54).clamp(8.0, 15.0);

    _paintHudText(
      canvas,
      _pt('PUNTOS  $score', 'SCORE  $score'),
      Offset(offsetX + cs * 0.45, textY),
      const Color(0xFFFFFF33),
      fontSize,
      bold: true,
      glowColor: const Color(0xFFFFFF00),
      align: TextAlign.left,
    );

    _paintHudText(
      canvas,
      _pt('NVL $level', 'LVL $level'),
      Offset(offsetX + cs * _kMazeCols / 2, textY),
      const Color(0xFF00FFFF),
      fontSize,
      bold: true,
      glowColor: const Color(0xFF00EEEE),
      align: TextAlign.center,
    );

    _drawLivesIcons(canvas, lives, offsetX + cs * (_kMazeCols - 0.4), textY, cs, fontSize);
  }

  void _paintHudText(
    Canvas canvas,
    String text,
    Offset position,
    Color color,
    double fontSize, {
    bool bold = false,
    Color? glowColor,
    TextAlign align = TextAlign.left,
  }) {
    if (glowColor != null) {
      final glowTp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: glowColor.withOpacity(0.5),
            fontSize: fontSize,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            fontFamily: 'monospace',
            shadows: [Shadow(color: glowColor, blurRadius: 10)],
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: align,
      )..layout();
      double dx;
      if (align == TextAlign.center) {
        dx = position.dx - glowTp.width / 2;
      } else if (align == TextAlign.right) {
        dx = position.dx - glowTp.width;
      } else {
        dx = position.dx;
      }
      glowTp.paint(canvas, Offset(dx, position.dy - glowTp.height / 2));
    }

    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
    )..layout();

    double dx;
    if (align == TextAlign.center) {
      dx = position.dx - tp.width / 2;
    } else if (align == TextAlign.right) {
      dx = position.dx - tp.width;
    } else {
      dx = position.dx;
    }
    tp.paint(canvas, Offset(dx, position.dy - tp.height / 2));
  }

  void _drawLivesIcons(
    Canvas canvas,
    int lives,
    double rightEdgeX,
    double centerY,
    double cs,
    double fontSize,
  ) {
    final iconR = (cs * 0.22).clamp(3.0, 9.0);
    final spacing = iconR * 2.6;
    final count = lives.clamp(0, 5);

    for (int i = 0; i < count; i++) {
      final ix = rightEdgeX - (count - i) * spacing;
      _drawMiniPacman(canvas, ix, centerY, iconR);
    }

    final labelTp = TextPainter(
      text: TextSpan(
        text: _pt('VIDAS', 'LIVES'),
        style: TextStyle(
          color: const Color(0xFF88AAFF),
          fontSize: (fontSize * 0.75).clamp(6.0, 11.0),
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    labelTp.paint(
      canvas,
      Offset(rightEdgeX - count * spacing - labelTp.width - 4, centerY - labelTp.height / 2),
    );
  }

  void _drawMiniPacman(Canvas canvas, double cx, double cy, double r) {
    final paint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.3, -0.3),
        radius: 1.0,
        colors: [
          const Color(0xFFFFFFCC),
          const Color(0xFFFFEE00),
          const Color(0xFFFFAA00),
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r));

    final path = Path()
      ..moveTo(cx, cy)
      ..arcTo(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        0.35,
        2 * pi - 0.7,
        false,
      )
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_MazePainter old) =>
      language != old.language ||
      pelletBlink != old.pelletBlink ||
      scaredBlink != old.scaredBlink ||
      playerRow != old.playerRow ||
      playerCol != old.playerCol ||
      playerDir != old.playerDir ||
      score != old.score ||
      lives != old.lives ||
      level != old.level ||
      ghosts.length != old.ghosts.length ||
      ghosts.any((g) {
        final og = old.ghosts.firstWhere(
          (o) => o.color == g.color, orElse: () => g);
        return g.row != og.row || g.col != og.col || g.scared != og.scared;
      });
}
