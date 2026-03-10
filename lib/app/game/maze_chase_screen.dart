import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'arcade_input_controller.dart';
import 'high_score_service.dart';

// ─── Maze constants ──────────────────────────────────────────────────────────

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

// Direction indices: 0=up, 1=right, 2=down, 3=left
const _kDR = [-1, 0, 1, 0];
const _kDC = [0, 1, 0, -1];

// ─── Ghost model ─────────────────────────────────────────────────────────────

class _Ghost {
  int row, col;
  int dir; // 0=up,1=right,2=down,3=left
  bool scared;
  Color color;
  _Ghost(this.row, this.col, this.color)
      : dir = 2,
        scared = false;
}

// ─── Widget ──────────────────────────────────────────────────────────────────

class MazeChasScreen extends StatefulWidget {
  final String userId;
  final DocumentReference rewardsDocRef;
  final double currentSaldo;
  final ArcadeInputController controller;
  final void Function(double) onSaldoChanged;

  const MazeChasScreen({
    super.key,
    required this.userId,
    required this.rewardsDocRef,
    required this.currentSaldo,
    required this.controller,
    required this.onSaldoChanged,
  });

  @override
  State<MazeChasScreen> createState() => _MazeChasScreenState();
}

class _MazeChasScreenState extends State<MazeChasScreen> {
  // ── State ──────────────────────────────────────────────────────────────────
  late List<List<int>> _grid;

  int _playerRow = 11, _playerCol = 7;
  int _queuedDir = 1; // default: right
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

  Timer? _playerTimer;
  Timer? _ghostTimer;
  Timer? _scaredTimer;
  Timer? _blinkTimer;
  Timer? _levelCompleteTimer;

  bool _pelletBlink = false;
  bool _scaredBlink = false;
  int _ghostIntervalMs = 300;

  final _rng = Random();

  // ── Init ───────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _saldo = widget.currentSaldo;
    _buildGrid();
    _spawnGhosts();
    widget.controller.addListener(_onControllerEvent);
    HighScoreService.load('maze').then((v) {
      if (mounted) setState(() => _hiScore = v);
    });
    // Blink timer for pellet + scared ghost flash
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (mounted) setState(() => _pelletBlink = !_pelletBlink);
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

  // ── Grid helpers ───────────────────────────────────────────────────────────

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

  // ── Ghost spawn ────────────────────────────────────────────────────────────

  void _spawnGhosts() {
    _ghosts = [
      _Ghost(6, 7, const Color(0xFFFF0000)),  // red – chaser
      _Ghost(7, 6, const Color(0xFFFF69B4)),  // pink – ahead
      _Ghost(7, 8, const Color(0xFF00FFFF)),  // cyan – random
      _Ghost(8, 7, const Color(0xFFFFB347)),  // orange – hybrid
    ];
  }

  // ── Controller input ───────────────────────────────────────────────────────

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

  // ── Game lifecycle ─────────────────────────────────────────────────────────

  void _startGame() {
    if (!mounted) return;
    setState(() => _isRunning = true);
    _startTimers();
  }

  void _startTimers() {
    _playerTimer?.cancel();
    _ghostTimer?.cancel();
    _playerTimer = Timer.periodic(
      const Duration(milliseconds: 200),
      _playerStep,
    );
    _ghostTimer = Timer.periodic(
      Duration(milliseconds: _ghostIntervalMs),
      _ghostsStep,
    );
  }

  void _stopTimers() {
    _playerTimer?.cancel();
    _ghostTimer?.cancel();
    _playerTimer = null;
    _ghostTimer = null;
  }

  void _restart() {
    _stopTimers();
    _scaredTimer?.cancel();
    _levelCompleteTimer?.cancel();
    setState(() {
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

  // ── Player step ────────────────────────────────────────────────────────────

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

    if (_isWall(nr, nc)) return; // blocked, stay in place

    if (!mounted) return;
    setState(() {
      _playerRow = nr;
      _playerCol = nc;
      _currentDir = nextDir;

      final cell = _grid[_playerRow][_playerCol];
      if (cell == 0) {
        _grid[_playerRow][_playerCol] = -1; // consumed
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

  // ── Power pellet ───────────────────────────────────────────────────────────

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
    // We can't directly query timer, so use a rough approach:
    // We track via the scared flag; blinking is handled separately.
    return Duration.zero;
  }

  // ── Ghost step ─────────────────────────────────────────────────────────────

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

    // Gather valid directions (walkable, not reverse)
    final validDirs = <int>[];
    for (int d = 0; d < 4; d++) {
      if (d == oppositeDir) continue;
      final nr = g.row + _kDR[d];
      final nc = g.col + _kDC[d];
      if (_isWalkable(nr, nc)) validDirs.add(d);
    }

    // If no valid non-reverse direction, allow reverse
    if (validDirs.isEmpty) {
      final nr = g.row + _kDR[oppositeDir];
      final nc = g.col + _kDC[oppositeDir];
      if (_isWalkable(nr, nc)) validDirs.add(oppositeDir);
    }

    if (validDirs.isEmpty) return;

    int chosenDir;
    if (g.scared) {
      // Random movement when scared
      chosenDir = validDirs[_rng.nextInt(validDirs.length)];
    } else {
      // Determine target cell for each ghost personality
      int targetRow, targetCol;
      switch (idx) {
        case 0: // Red: chase player directly
          targetRow = _playerRow;
          targetCol = _playerCol;
        case 1: // Pink: target 3 cells ahead of player
          targetRow = _playerRow + _kDR[_currentDir] * 3;
          targetCol = _playerCol + _kDC[_currentDir] * 3;
          targetRow = targetRow.clamp(0, _kMazeRows - 1);
          targetCol = targetCol.clamp(0, _kMazeCols - 1);
        case 2: // Cyan: random
          chosenDir = validDirs[_rng.nextInt(validDirs.length)];
          g.dir = chosenDir;
          g.row += _kDR[chosenDir];
          g.col += _kDC[chosenDir];
          return;
        case 3: // Orange: chase if far, random if close
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

      // Pick direction minimizing Manhattan distance to target
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

  // ── Collision ──────────────────────────────────────────────────────────────

  void _checkPlayerGhostCollision() {
    if (!mounted) return;
    for (final g in _ghosts) {
      if (g.row == _playerRow && g.col == _playerCol) {
        if (g.scared) {
          // Player eats ghost
          setState(() {
            g.row = 7;
            g.col = 7;
            g.scared = false;
            g.dir = 2;
            _score += 200;
          });
        } else {
          // Ghost eats player
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
      // Reset positions
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

    _updateFirestore(_saldo + 1).then((_) {
      if (!mounted) return;
      final newSaldo = _saldo + 1;
      setState(() => _saldo = newSaldo);
      widget.onSaldoChanged(newSaldo);
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

  // ── Firestore ──────────────────────────────────────────────────────────────

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
      debugPrint('MazeChase Firestore error: $e');
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Deep midnight purple spooky background gradient
        Positioned.fill(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF0A0014), // near-black deep purple at top
                  Color(0xFF110022), // midnight purple
                  Color(0xFF0D001A), // dark indigo base
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
                scaredBlink: _pelletBlink, // reuse 300ms blink
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

  // ── Start overlay ──────────────────────────────────────────────────────────

  Widget _buildStartOverlay() {
    return Positioned.fill(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xF0000020), Color(0xF5000814), Color(0xF0001030)],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Neon title with double shadow glow
            Text(
              'COMECOCOS',
              style: TextStyle(
                color: const Color(0xFFFFFF00),
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: 5,
                shadows: [
                  Shadow(color: const Color(0xFFFFFF00).withOpacity(0.9), blurRadius: 16),
                  Shadow(color: const Color(0xFFFFAA00).withOpacity(0.6), blurRadius: 32),
                ],
              ),
            ),
            const SizedBox(height: 6),
            // Pellet dots row
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(9, (i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFFFFAA),
                    boxShadow: [
                      BoxShadow(color: const Color(0xFFFFFF00).withOpacity(0.8), blurRadius: 6),
                    ],
                  ),
                ),
              )),
            ),
            const SizedBox(height: 22),
            // Instructions card
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF0080FF), width: 1.5),
                borderRadius: BorderRadius.circular(12),
                color: const Color(0xFF000830).withOpacity(0.95),
                boxShadow: [
                  BoxShadow(color: const Color(0xFF0080FF).withOpacity(0.3), blurRadius: 16),
                ],
              ),
              child: Column(children: [
                _instrRow('D-pad', 'Mover por el laberinto', const Color(0xFF00CCFF)),
                const SizedBox(height: 8),
                _instrRow('', 'Come todos los puntos para pasar de nivel', Colors.white70),
                const SizedBox(height: 8),
                _instrRow('Pastilla', '¡Fantasmas comestibles!', const Color(0xFF00FFAA)),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF003300),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF00FF66), width: 1),
                  ),
                  child: const Text(
                    '+1 PTO REAL POR NIVEL',
                    style: TextStyle(
                      color: Color(0xFF00FF88),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 24),
            // Ghost warning row
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _miniGhostIcon(const Color(0xFFFF4444)),
                const SizedBox(width: 6),
                const Text(
                  'Cuidado con los fantasmas',
                  style: TextStyle(color: Color(0xFFFF8888), fontSize: 12),
                ),
                const SizedBox(width: 6),
                _miniGhostIcon(const Color(0xFFFF69B4)),
              ],
            ),
            const SizedBox(height: 18),
            // Press to start — pulsing style via blink
            Text(
              'Presiona A o START para jugar',
              style: TextStyle(
                color: const Color(0xFF6699FF),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                shadows: [
                  Shadow(color: const Color(0xFF0066FF).withOpacity(0.7), blurRadius: 10),
                ],
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
        color: color,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
        boxShadow: [BoxShadow(color: color.withOpacity(0.6), blurRadius: 6)],
      ),
    );
  }

  // ── Game over overlay ──────────────────────────────────────────────────────

  Widget _buildGameOverOverlay() {
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xF2200010),
              const Color(0xF5100005),
              const Color(0xF2000010),
            ],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Large ghost emoji with glow container
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: const Color(0xFFFF2266).withOpacity(0.5), blurRadius: 24),
                ],
              ),
              child: const Center(child: Text('👻', style: TextStyle(fontSize: 52))),
            ),
            const SizedBox(height: 10),
            Text(
              'ATRAPADO',
              style: TextStyle(
                color: const Color(0xFFFF2266),
                fontSize: 34,
                fontWeight: FontWeight.bold,
                letterSpacing: 5,
                shadows: [
                  Shadow(color: const Color(0xFFFF0044).withOpacity(0.9), blurRadius: 20),
                  Shadow(color: const Color(0xFFFF0044).withOpacity(0.5), blurRadius: 40),
                ],
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Un fantasma te ha engullido',
              style: TextStyle(color: Color(0xFFAA5577), fontSize: 11),
            ),
            const SizedBox(height: 22),
            // Score card
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 32),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF550022), width: 1.5),
                borderRadius: BorderRadius.circular(12),
                color: const Color(0xFF180010).withOpacity(0.9),
                boxShadow: [
                  BoxShadow(color: const Color(0xFFFF0066).withOpacity(0.15), blurRadius: 16),
                ],
              ),
              child: Column(children: [
                Text(
                  '$_score',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    shadows: [Shadow(color: Colors.white.withOpacity(0.3), blurRadius: 8)],
                  ),
                ),
                const Text('PUNTOS', style: TextStyle(color: Color(0xFF886688), fontSize: 11, letterSpacing: 2)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('RÉCORD  ', style: TextStyle(color: Color(0xFF886688), fontSize: 12)),
                    Text(
                      '$_hiScore',
                      style: TextStyle(
                        color: const Color(0xFFFFFF00),
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        shadows: [Shadow(color: const Color(0xFFFFFF00).withOpacity(0.6), blurRadius: 8)],
                      ),
                    ),
                  ],
                ),
              ]),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _restart,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0044BB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    shadowColor: const Color(0xFF0080FF),
                    elevation: 8,
                  ),
                  child: const Text(
                    'Nueva Partida',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 1),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Level complete overlay ─────────────────────────────────────────────────

  Widget _buildLevelCompleteOverlay() {
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 0.9,
            colors: [
              const Color(0xE5003322),
              Colors.black.withOpacity(0.92),
            ],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '¡NIVEL $_level!',
              style: TextStyle(
                color: const Color(0xFF00FF88),
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 3,
                shadows: [Shadow(color: const Color(0xFF00FF88).withOpacity(0.8), blurRadius: 16)],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'COMPLETADO',
              style: TextStyle(
                color: const Color(0xFFFFFF00),
                fontSize: 30,
                fontWeight: FontWeight.bold,
                letterSpacing: 4,
                shadows: [
                  Shadow(color: const Color(0xFFFFFF00).withOpacity(0.9), blurRadius: 20),
                  Shadow(color: const Color(0xFFFFAA00).withOpacity(0.5), blurRadius: 40),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF002211),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF00FF88).withOpacity(0.5), width: 1),
              ),
              child: const Text(
                '+1 pto real añadido',
                style: TextStyle(color: Color(0xFF00FF88), fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPauseOverlay() => Positioned.fill(
    child: Container(
      decoration: BoxDecoration(
        color: const Color(0xCC000020),
        backgroundBlendMode: BlendMode.darken,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('⏸', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 10),
          Text(
            'PAUSA',
            style: TextStyle(
              color: const Color(0xFFFFFF00),
              fontSize: 30,
              fontWeight: FontWeight.bold,
              letterSpacing: 8,
              shadows: [
                Shadow(color: const Color(0xFFFFFF00).withOpacity(0.7), blurRadius: 16),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'START para continuar',
            style: TextStyle(color: Color(0xFF888800), fontSize: 12, letterSpacing: 1),
          ),
        ],
      ),
    ),
  );
}

// ─── CustomPainter ────────────────────────────────────────────────────────────

class _MazePainter extends CustomPainter {
  final List<List<int>> grid;
  final int playerRow, playerCol, playerDir;
  final List<_Ghost> ghosts;
  final int score, lives, level;
  final bool pelletBlink;
  final bool scaredBlink;

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
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cs = min(size.width / _kMazeCols, size.height / (_kMazeRows + 2))
        .floorToDouble();
    final offsetX = ((size.width - cs * _kMazeCols) / 2).floorToDouble();
    final offsetY = ((size.height - cs * _kMazeRows) / 2).floorToDouble();

    // Background — deep midnight purple
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF0A0014), Color(0xFF110022), Color(0xFF0D001A)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Subtle corner vignette
    final vignettePaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 1.1,
        colors: [
          const Color(0x00000000),
          const Color(0x88000000),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), vignettePaint);

    // Outer bezel glow — vivid cyan/purple double ring
    final bezelRect = Rect.fromLTWH(
      offsetX - 3, offsetY - 3,
      cs * _kMazeCols + 6, cs * _kMazeRows + 6,
    );
    // Purple outer glow
    final bezelGlowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = const Color(0xFF9900FF)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bezelRect, const Radius.circular(6)),
      bezelGlowPaint,
    );
    // Cyan inner crisp line
    final bezelPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xFF00FFFF);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bezelRect, const Radius.circular(6)),
      bezelPaint,
    );

    // Draw cells
    for (int r = 0; r < _kMazeRows; r++) {
      for (int c = 0; c < _kMazeCols; c++) {
        final x = offsetX + c * cs;
        final y = offsetY + r * cs;
        final cell = grid[r][c];

        switch (cell) {
          case 1: // Wall — neon blue with glow
            _drawWall(canvas, x, y, cs, r, c);
          case 0: // Regular dot — glowing circle
            _drawDot(canvas, x, y, cs);
          case 2: // Power pellet — pulsing glow
            _drawPowerPellet(canvas, x, y, cs);
          case 3: // Ghost spawn area — deep magenta tinted den
            final spawnPaint = Paint()..color = const Color(0xFF12002A);
            canvas.drawRect(Rect.fromLTWH(x, y, cs, cs), spawnPaint);
            // Subtle tile grid for spawn zone
            _drawFloorTile(canvas, x, y, cs, const Color(0xFF2A005A));
            // Glowing magenta border
            final spawnBorder = Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 0.8
              ..color = const Color(0xFFCC00FF).withOpacity(0.5)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
            canvas.drawRect(Rect.fromLTWH(x, y, cs, cs), spawnBorder);
          default:
            // Consumed cell (-1) — dark floor with subtle tile pattern
            final floorPaint = Paint()..color = const Color(0xFF0D001A);
            canvas.drawRect(Rect.fromLTWH(x, y, cs, cs), floorPaint);
            _drawFloorTile(canvas, x, y, cs, const Color(0xFF180030));
        }
      }
    }

    // Draw ghosts
    for (final g in ghosts) {
      _drawGhost(canvas, g, offsetX, offsetY, cs);
    }

    // Draw player
    _drawPlayer(canvas, playerRow, playerCol, playerDir, offsetX, offsetY, cs);

    // Draw HUD
    _drawHud(canvas, size, cs, offsetX, offsetY);
  }

  // ─── Floor tile helper ────────────────────────────────────────────────────

  void _drawFloorTile(Canvas canvas, double x, double y, double cs, Color lineColor) {
    // Subtle grid tile lines — very faint for texture only
    final tilePaint = Paint()
      ..color = lineColor.withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    // Right edge
    canvas.drawLine(Offset(x + cs, y), Offset(x + cs, y + cs), tilePaint);
    // Bottom edge
    canvas.drawLine(Offset(x, y + cs), Offset(x + cs, y + cs), tilePaint);
  }

  // ─── Wall drawing ────────────────────────────────────────────────────────

  void _drawWall(Canvas canvas, double x, double y, double cs, int r, int c) {
    final rect = Rect.fromLTWH(x, y, cs, cs);

    // Deep dark purple wall interior fill
    final fillPaint = Paint()..color = const Color(0xFF0D0020);
    canvas.drawRect(rect, fillPaint);

    // Inner wall surface gradient — purplish blue sheen
    final wallShinePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFF1E0042).withOpacity(0.8),
          const Color(0xFF0A0018).withOpacity(0.0),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, wallShinePaint);

    // Determine which sides border a non-wall (open space)
    final hasTop    = r > 0 && _kMap[r - 1][c] != 1;
    final hasBottom = r < _kMazeRows - 1 && _kMap[r + 1][c] != 1;
    final hasLeft   = c > 0 && _kMap[r][c - 1] != 1;
    final hasRight  = c < _kMazeCols - 1 && _kMap[r][c + 1] != 1;

    // Outer glow (cyan/purple alternating, based on position parity for variety)
    final isEvenCell = (r + c) % 2 == 0;
    final neonGlowColor = isEvenCell
        ? const Color(0xFF00FFFF)   // cyan
        : const Color(0xFFBB00FF);  // purple
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.5, cs * 0.14)
      ..color = neonGlowColor.withOpacity(0.55)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, cs * 0.18);

    // Crisp neon line on top of glow
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(0.8, cs * 0.07)
      ..color = neonGlowColor.withOpacity(0.9);

    // Draw neon edges only on sides facing open space
    if (hasTop) {
      canvas.drawLine(Offset(x, y), Offset(x + cs, y), glowPaint);
      canvas.drawLine(Offset(x, y), Offset(x + cs, y), borderPaint);
    }
    if (hasBottom) {
      canvas.drawLine(Offset(x, y + cs), Offset(x + cs, y + cs), glowPaint);
      canvas.drawLine(Offset(x, y + cs), Offset(x + cs, y + cs), borderPaint);
    }
    if (hasLeft) {
      canvas.drawLine(Offset(x, y), Offset(x, y + cs), glowPaint);
      canvas.drawLine(Offset(x, y), Offset(x, y + cs), borderPaint);
    }
    if (hasRight) {
      canvas.drawLine(Offset(x + cs, y), Offset(x + cs, y + cs), glowPaint);
      canvas.drawLine(Offset(x + cs, y), Offset(x + cs, y + cs), borderPaint);
    }
  }

  // ─── Dot drawing ─────────────────────────────────────────────────────────

  void _drawDot(Canvas canvas, double x, double y, double cs) {
    final cx = x + cs / 2;
    final cy = y + cs / 2;
    final r = max(1.5, cs * 0.12);

    // Soft outer glow
    final glowPaint = Paint()
      ..color = const Color(0xFFFFFFAA).withOpacity(0.25)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 2.5);
    canvas.drawCircle(Offset(cx, cy), r * 2.2, glowPaint);

    // Main dot with radial gradient
    final dotPaint = Paint()
      ..shader = RadialGradient(
        colors: [Colors.white, const Color(0xFFFFFFAA)],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r));
    canvas.drawCircle(Offset(cx, cy), r, dotPaint);
  }

  // ─── Power pellet drawing ─────────────────────────────────────────────────

  void _drawPowerPellet(Canvas canvas, double x, double y, double cs) {
    final cx = x + cs / 2;
    final cy = y + cs / 2;

    // Pulsing size: slightly larger every other blink cycle
    final baseR = cs * 0.22;
    final r = pelletBlink ? baseR * 1.18 : baseR * 0.88;

    // Outer halo glow
    final haloPaint = Paint()
      ..color = const Color(0xFFFFFF00).withOpacity(pelletBlink ? 0.3 : 0.15)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 3.5);
    canvas.drawCircle(Offset(cx, cy), r * 3.0, haloPaint);

    // Mid glow ring
    final midGlowPaint = Paint()
      ..color = const Color(0xFFFFDD00).withOpacity(0.5)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 1.5);
    canvas.drawCircle(Offset(cx, cy), r * 1.8, midGlowPaint);

    // Core white/yellow radial gradient
    final corePaint = Paint()
      ..shader = RadialGradient(
        colors: [Colors.white, const Color(0xFFFFFF00), const Color(0xFFFFCC00)],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r));
    canvas.drawCircle(Offset(cx, cy), r, corePaint);
  }

  // ─── Ghost drawing ────────────────────────────────────────────────────────

  void _drawGhost(
    Canvas canvas,
    _Ghost g,
    double offsetX,
    double offsetY,
    double cs,
  ) {
    final x = offsetX + g.col * cs;
    final y = offsetY + g.row * cs;

    final bodyW = cs * 0.72;
    final bodyH = cs * 0.78;
    final bx = x + (cs - bodyW) / 2;
    final by = y + (cs - bodyH) / 2;

    // Ghost body color and gradient
    Color ghostColor;
    Color ghostHighlight;
    if (g.scared) {
      ghostColor = scaredBlink
          ? const Color(0xFFBBBBFF)
          : const Color(0xFF1111CC);
      ghostHighlight = scaredBlink
          ? Colors.white
          : const Color(0xFF4444FF);
    } else {
      ghostColor = g.color;
      // Lighten for highlight
      final r = (ghostColor.red + 80).clamp(0, 255);
      final gr = (ghostColor.green + 80).clamp(0, 255);
      final b = (ghostColor.blue + 80).clamp(0, 255);
      ghostHighlight = Color.fromARGB(255, r, gr, b);
    }

    // Outer glow
    final glowPaint = Paint()
      ..color = ghostColor.withOpacity(0.35)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, cs * 0.25);
    canvas.drawOval(
      Rect.fromLTWH(bx - 2, by - 2, bodyW + 4, bodyH + 4),
      glowPaint,
    );

    // Build ghost shape path: dome top + wavy skirt bottom
    final path = Path();

    // Dome top (semi-circle)
    final domeRadius = bodyW / 2;
    final domeCenterX = bx + bodyW / 2;
    final domeCenterY = by + domeRadius;
    path.addArc(
      Rect.fromCircle(center: Offset(domeCenterX, domeCenterY), radius: domeRadius),
      pi, // start at left (180°)
      pi, // sweep to right (180°) — upper semicircle
    );

    // Straight sides down to skirt
    final skirtTop = by + domeRadius;
    final skirtBottom = by + bodyH;
    path.lineTo(bx + bodyW, skirtTop);

    // Wavy skirt — sinusoidal bottom
    const waveCount = 3;
    final waveW = bodyW / waveCount;
    final waveAmp = bodyH * 0.13;

    // Right side down
    path.lineTo(bx + bodyW, skirtBottom - waveAmp);

    // Wave from right to left along bottom
    for (int i = waveCount; i >= 0; i--) {
      final wx = bx + i * waveW;
      final wy = (i % 2 == 0)
          ? skirtBottom - waveAmp * 0.2
          : skirtBottom + waveAmp * 0.5;
      path.lineTo(wx, wy);
    }

    // Left side up
    path.lineTo(bx, skirtTop);
    path.close();

    // Body gradient paint
    final bodyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [ghostHighlight, ghostColor],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromLTWH(bx, by, bodyW, bodyH));
    canvas.drawPath(path, bodyPaint);

    // Eyes
    final eyeR = max(2.0, cs * 0.1);
    final leftEyeX = bx + bodyW * 0.28;
    final rightEyeX = bx + bodyW * 0.68;
    final eyeY = by + bodyH * 0.20;

    if (g.scared) {
      // Scared: worried wide eyes with wavy mouth
      final eyePaint = Paint()..color = Colors.white;
      canvas.drawCircle(Offset(leftEyeX, eyeY), eyeR, eyePaint);
      canvas.drawCircle(Offset(rightEyeX, eyeY), eyeR, eyePaint);

      // Worried mouth: wavy line
      final mouthPaint = Paint()
        ..color = Colors.white.withOpacity(0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1.0, cs * 0.06)
        ..strokeCap = StrokeCap.round;
      final mouthPath = Path();
      final mouthY = by + bodyH * 0.55;
      final mouthX0 = bx + bodyW * 0.2;
      final mouthX1 = bx + bodyW * 0.8;
      final mouthW = mouthX1 - mouthX0;
      mouthPath.moveTo(mouthX0, mouthY);
      mouthPath.cubicTo(
        mouthX0 + mouthW * 0.25, mouthY + cs * 0.08,
        mouthX0 + mouthW * 0.5,  mouthY - cs * 0.08,
        mouthX0 + mouthW * 0.75, mouthY + cs * 0.08,
      );
      mouthPath.lineTo(mouthX1, mouthY);
      canvas.drawPath(mouthPath, mouthPaint);
    } else {
      // Normal eyes: white sclera + coloured pupil
      final sclPaint = Paint()..color = Colors.white;
      canvas.drawCircle(Offset(leftEyeX, eyeY), eyeR, sclPaint);
      canvas.drawCircle(Offset(rightEyeX, eyeY), eyeR, sclPaint);

      // Pupils — direction-tinted
      final pupilColor = Color.alphaBlend(
        ghostColor.withOpacity(0.7),
        const Color(0xFF000066),
      );
      final pupilPaint = Paint()..color = pupilColor;
      final pR = eyeR * 0.55;
      canvas.drawCircle(Offset(leftEyeX, eyeY), pR, pupilPaint);
      canvas.drawCircle(Offset(rightEyeX, eyeY), pR, pupilPaint);

      // Tiny white glint dot
      final glintPaint = Paint()..color = Colors.white.withOpacity(0.9);
      final gR = pR * 0.35;
      canvas.drawCircle(Offset(leftEyeX - pR * 0.3, eyeY - pR * 0.3), gR, glintPaint);
      canvas.drawCircle(Offset(rightEyeX - pR * 0.3, eyeY - pR * 0.3), gR, glintPaint);
    }
  }

  // ─── Player (Pac-Man) drawing ─────────────────────────────────────────────

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

    final radius = cs * 0.38;
    final cx = x + cs / 2;
    final cy = y + cs / 2;

    // Outer glow
    final glowPaint = Paint()
      ..color = const Color(0xFFFFFF00).withOpacity(0.4)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 1.2);
    canvas.drawCircle(Offset(cx, cy), radius * 1.5, glowPaint);

    // Mouth angle: wedge opens 30° each side from facing direction
    // dir: 0=up, 1=right, 2=down, 3=left
    const mouthHalf = 0.22; // radians (~12.6°) — thin open mouth
    final dirAngle = [
      -pi / 2, // up
      0.0,     // right
      pi / 2,  // down
      pi,      // left
    ][dir];

    final startAngle = dirAngle + mouthHalf;
    final sweepAngle = 2 * pi - 2 * mouthHalf;

    // Radial gradient body: bright yellow center → gold edge
    final bodyPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment(-0.3, -0.3),
        radius: 1.0,
        colors: [
          const Color(0xFFFFFFAA),
          const Color(0xFFFFEE00),
          const Color(0xFFFFAA00),
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: radius));

    // Draw arc (mouth cutout handled by wedge shape)
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

    // Thin dark mouth line for crispness
    final mouthPaint = Paint()
      ..color = const Color(0xFF000814)
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(0.8, cs * 0.04);
    // upper jaw line
    final ux = cx + cos(dirAngle + mouthHalf) * radius;
    final uy = cy + sin(dirAngle + mouthHalf) * radius;
    canvas.drawLine(Offset(cx, cy), Offset(ux, uy), mouthPaint);
    // lower jaw line
    final lx = cx + cos(dirAngle - mouthHalf) * radius;
    final ly = cy + sin(dirAngle - mouthHalf) * radius;
    canvas.drawLine(Offset(cx, cy), Offset(lx, ly), mouthPaint);

    // Small white eye
    final eyeAngle = dirAngle - pi / 2; // always above mouth direction
    final eyeDist = radius * 0.5;
    final ex = cx + cos(eyeAngle) * eyeDist * 0.6 - sin(eyeAngle) * eyeDist * 0.4;
    final ey = cy + sin(eyeAngle) * eyeDist * 0.6 + cos(eyeAngle) * eyeDist * 0.4;
    final eyePaint = Paint()..color = Colors.black87;
    canvas.drawCircle(Offset(ex, ey), max(1.2, radius * 0.16), eyePaint);
    // White glint
    canvas.drawCircle(
      Offset(ex - radius * 0.05, ey - radius * 0.05),
      max(0.6, radius * 0.07),
      Paint()..color = Colors.white,
    );
  }

  // ─── HUD drawing ─────────────────────────────────────────────────────────

  void _drawHud(Canvas canvas, Size size, double cs, double offsetX, double offsetY) {
    // HUD positioned above the maze
    final hudY = offsetY - cs * 1.3;
    final hudH = cs * 1.1;

    // HUD background bar
    final hudBgPaint = Paint()
      ..color = const Color(0xFF000D26).withOpacity(0.85);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(offsetX, hudY, cs * _kMazeCols, hudH),
        const Radius.circular(4),
      ),
      hudBgPaint,
    );

    // HUD border glow
    final hudBorderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xFF0055AA).withOpacity(0.7);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(offsetX, hudY, cs * _kMazeCols, hudH),
        const Radius.circular(4),
      ),
      hudBorderPaint,
    );

    final textY = hudY + hudH / 2;
    final fontSize = (cs * 0.52).clamp(8.0, 15.0);

    // Score — left section, neon yellow
    _paintHudText(
      canvas,
      'SCORE  $score',
      Offset(offsetX + cs * 0.4, textY),
      const Color(0xFFFFFF00),
      fontSize,
      bold: true,
      glowColor: const Color(0xFFFFFF00),
      align: TextAlign.left,
    );

    // Level — centre, neon cyan
    _paintHudText(
      canvas,
      'NVL $level',
      Offset(offsetX + cs * _kMazeCols / 2, textY),
      const Color(0xFF00FFFF),
      fontSize,
      glowColor: const Color(0xFF00FFFF),
      align: TextAlign.center,
    );

    // Lives — right section as mini Pac-Man icons
    _drawLivesIcons(canvas, lives, offsetX + cs * (_kMazeCols - 0.5), textY, cs, fontSize);
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
    // Glow pass
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

    // Main text
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

    // Label
    final labelTp = TextPainter(
      text: TextSpan(
        text: 'VIDAS',
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
        colors: [const Color(0xFFFFFFAA), const Color(0xFFFFEE00), const Color(0xFFFFAA00)],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r));

    final path = Path()
      ..moveTo(cx, cy)
      ..arcTo(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        0.3, // start after mouth
        2 * pi - 0.6,
        false,
      )
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_MazePainter old) => true;
}
