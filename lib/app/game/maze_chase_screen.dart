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
            // Ghost row icons — colorful mascots
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
            // Title — neon yellow with triple-layer glow
            Text(
              'COMECOCOS',
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
            // Pellet trail row
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(11, (i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2.5),
                child: Container(
                  width: i == 5 ? 11 : 7,  // centre is power pellet
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
            // Instructions card with vivid cyan border + glow
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
                _instrRow('D-pad', 'Mover por el laberinto', const Color(0xFF00EEFF)),
                const SizedBox(height: 8),
                _instrRow('', 'Come todos los puntos para pasar de nivel', Colors.white70),
                const SizedBox(height: 8),
                _instrRow('Pastilla', '¡Fantasmas comestibles!', const Color(0xFF00FF99)),
                const SizedBox(height: 12),
                // Reward pill
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
                  child: const Text(
                    '🪙  +1 PTO REAL POR NIVEL',
                    style: TextStyle(
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
            // Press to play — pill button style
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
              child: const Text(
                'Presiona A o START para jugar',
                style: TextStyle(
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
          // Googly eyes
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

  // ── Game over overlay ──────────────────────────────────────────────────────

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
            // Ghost quartet — all scared/red theme
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _bigGhostIcon(const Color(0xFFFF3333)),
                const SizedBox(width: 6),
                _bigGhostIcon(const Color(0xFFFF66AA)),
              ],
            ),
            const SizedBox(height: 10),
            // GAME OVER title — vivid red-pink neon
            Text(
              'ATRAPADO',
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
              'Un fantasma te ha engullido',
              style: TextStyle(
                color: const Color(0xFFBB6688),
                fontSize: 12,
                shadows: [Shadow(color: const Color(0xFFFF0066).withOpacity(0.3), blurRadius: 8)],
              ),
            ),
            const SizedBox(height: 20),
            // Score card — glowing border
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
                const Text(
                  'PUNTOS',
                  style: TextStyle(
                    color: Color(0xFF886688),
                    fontSize: 11,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 10),
                // Divider line
                Container(
                  height: 1,
                  color: const Color(0xFF660033),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'RÉCORD  ',
                      style: TextStyle(color: Color(0xFF886688), fontSize: 12, letterSpacing: 1),
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
            // Pill button — vivid blue gradient
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
                child: const Text(
                  'Nueva Partida',
                  style: TextStyle(
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

  // ── Level complete overlay ─────────────────────────────────────────────────

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
            // Level badge
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
                '¡NIVEL $_level!',
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
              'COMPLETADO',
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
            // Reward pill — vivid green glow
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
              child: const Text(
                '🪙  +1 pto real añadido',
                style: TextStyle(
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
          // Pause icon with glow
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
            'PAUSA',
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
            child: const Text(
              'START para continuar',
              style: TextStyle(
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

    // Background — deep midnight purple, radially deeper toward edges
    final bgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: const [
          Color(0xFF0C0020), // top-left: deep indigo-purple
          Color(0xFF130028), // centre: rich midnight purple
          Color(0xFF080018), // bottom-right: almost black purple
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);


    // Corner vignette for cinematic depth
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

    // Outer bezel — purple outer glow + cyan crisp ring
    final bezelRect = Rect.fromLTWH(
      offsetX - 4, offsetY - 4,
      cs * _kMazeCols + 8, cs * _kMazeRows + 8,
    );
    // Purple accent ring
    canvas.drawRRect(
      RRect.fromRectAndRadius(bezelRect, const Radius.circular(8)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = const Color(0xFF8800FF).withOpacity(0.50),
    );
    // Crisp bright cyan inner line
    final bezelPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xFF44FFFF);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bezelRect, const Radius.circular(8)),
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
          case 3: // Ghost spawn area — deep magenta-tinted den
            canvas.drawRect(Rect.fromLTWH(x, y, cs, cs), Paint()..color = const Color(0xFF120028));
            _drawFloorTile(canvas, x, y, cs, const Color(0xFF3A0066));
            canvas.drawRect(Rect.fromLTWH(x, y, cs, cs), Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.0
              ..color = const Color(0xFFEE00FF).withOpacity(0.35));
          default:
            // Consumed cell (-1) — deep-indigo floor with tile texture
            canvas.drawRect(Rect.fromLTWH(x, y, cs, cs), Paint()..color = const Color(0xFF0C0018));
            _drawFloorTile(canvas, x, y, cs, const Color(0xFF1E0035));
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
    // Grid lines at edges — subtle stone tile pattern
    final tilePaint = Paint()
      ..color = lineColor.withOpacity(0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    canvas.drawLine(Offset(x + cs, y), Offset(x + cs, y + cs), tilePaint);
    canvas.drawLine(Offset(x, y + cs), Offset(x + cs, y + cs), tilePaint);
  }

  // ─── Wall drawing ────────────────────────────────────────────────────────

  void _drawWall(Canvas canvas, double x, double y, double cs, int r, int c) {
    final rect = Rect.fromLTWH(x, y, cs, cs);

    // Rich deep-indigo wall fill
    canvas.drawRect(rect, Paint()..color = const Color(0xFF100020));

    // Determine which sides border a non-wall (open space)
    final hasTop    = r > 0 && _kMap[r - 1][c] != 1;
    final hasBottom = r < _kMazeRows - 1 && _kMap[r + 1][c] != 1;
    final hasLeft   = c > 0 && _kMap[r][c - 1] != 1;
    final hasRight  = c < _kMazeCols - 1 && _kMap[r][c + 1] != 1;

    // All exposed edges — vivid cyan neon line
    const neonCoreColor = Color(0xFFAAFFFF);

    // Crisp bright core line
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

  // ─── Dot drawing ─────────────────────────────────────────────────────────

  void _drawDot(Canvas canvas, double x, double y, double cs) {
    final cx = x + cs / 2;
    final cy = y + cs / 2;
    final r = max(1.8, cs * 0.13);

    // Bright warm-yellow dot
    canvas.drawCircle(Offset(cx, cy), r, Paint()..color = const Color(0xFFFFEE55));
  }

  // ─── Power pellet drawing ─────────────────────────────────────────────────

  void _drawPowerPellet(Canvas canvas, double x, double y, double cs) {
    final cx = x + cs / 2;
    final cy = y + cs / 2;

    // Pulsing size: slightly larger every other blink cycle
    final baseR = cs * 0.25;
    final r = pelletBlink ? baseR * 1.22 : baseR * 0.85;

    // Outer semi-transparent ring
    canvas.drawCircle(Offset(cx, cy), r * 1.8,
      Paint()..color = const Color(0xFFFFAA00).withOpacity(pelletBlink ? 0.40 : 0.20));

    // Core: white → gold → orange radial
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

    // Tiny white specular highlight
    canvas.drawCircle(
      Offset(cx - r * 0.28, cy - r * 0.28),
      r * 0.28,
      Paint()..color = Colors.white.withOpacity(0.8),
    );
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

    final bodyW = cs * 0.78;
    final bodyH = cs * 0.82;
    final bx = x + (cs - bodyW) / 2;
    final by = y + (cs - bodyH) / 2 - cs * 0.02;

    // Ghost body color
    Color ghostColor;
    Color ghostHighlight;
    Color ghostDark;
    if (g.scared) {
      // Deep blue/purple scared mode — flashes lighter when time is running out
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

    // Build ghost body path: dome top + rounded wavy skirt
    final path = Path();
    final domeRadius = bodyW / 2;
    final domeCenterX = bx + bodyW / 2;
    final domeCenterY = by + domeRadius;

    // Dome (upper semicircle)
    path.addArc(
      Rect.fromCircle(center: Offset(domeCenterX, domeCenterY), radius: domeRadius),
      pi,
      pi,
    );

    final skirtTop = by + domeRadius;
    final skirtBottom = by + bodyH;
    path.lineTo(bx + bodyW, skirtTop);

    // Rounded wavy skirt using quadratic curves — 3 bumps
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

    // Body gradient: bright highlight top-left → vivid colour → dark bottom
    final bodyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [ghostHighlight, ghostColor, ghostDark],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromLTWH(bx, by, bodyW, bodyH));
    canvas.drawPath(path, bodyPaint);

    // Specular gloss arc on the dome (top-left sheen)
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

    // ── Googly eyes ──────────────────────────────────────────────────────────
    // Bigger, more cartoonish — large white sclera with vivid blue pupils
    final eyeScleraR = max(2.8, cs * 0.145);
    final leftEyeX = bx + bodyW * 0.30;
    final rightEyeX = bx + bodyW * 0.70;
    final eyeY = by + bodyH * 0.28;

    if (g.scared) {
      // Scared eyes: smaller, X-shaped or dot with worried squint
      final eyePaint = Paint()..color = Colors.white.withOpacity(0.9);
      canvas.drawCircle(Offset(leftEyeX, eyeY), eyeScleraR * 0.7, eyePaint);
      canvas.drawCircle(Offset(rightEyeX, eyeY), eyeScleraR * 0.7, eyePaint);

      // X marks on the eyes — panicked look
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

      // Scared jagged mouth
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
      // Zigzag scared mouth
      mouthPath.lineTo(mx0 + mw * 0.17, mouthY + cs * 0.07);
      mouthPath.lineTo(mx0 + mw * 0.34, mouthY - cs * 0.04);
      mouthPath.lineTo(mx0 + mw * 0.50, mouthY + cs * 0.07);
      mouthPath.lineTo(mx0 + mw * 0.67, mouthY - cs * 0.04);
      mouthPath.lineTo(mx0 + mw * 0.83, mouthY + cs * 0.07);
      mouthPath.lineTo(mx1, mouthY);
      canvas.drawPath(mouthPath, mouthPaint);
    } else {
      // White sclera
      canvas.drawCircle(Offset(leftEyeX, eyeY), eyeScleraR,
          Paint()..color = Colors.white);
      canvas.drawCircle(Offset(rightEyeX, eyeY), eyeScleraR,
          Paint()..color = Colors.white);

      // Blue iris
      final irisR = eyeScleraR * 0.68;
      final irisPaint = Paint()..color = const Color(0xFF2255FF);
      canvas.drawCircle(Offset(leftEyeX, eyeY), irisR, irisPaint);
      canvas.drawCircle(Offset(rightEyeX, eyeY), irisR, irisPaint);

      // Black pupil
      final pupilR = eyeScleraR * 0.38;
      final pupilPaint = Paint()..color = Colors.black;
      canvas.drawCircle(Offset(leftEyeX, eyeY), pupilR, pupilPaint);
      canvas.drawCircle(Offset(rightEyeX, eyeY), pupilR, pupilPaint);

      // Bright white glint (large) — classic cartoon googly eye
      final glintR = pupilR * 0.55;
      final glintPaint = Paint()..color = Colors.white;
      canvas.drawCircle(
        Offset(leftEyeX - pupilR * 0.32, eyeY - pupilR * 0.32), glintR, glintPaint);
      canvas.drawCircle(
        Offset(rightEyeX - pupilR * 0.32, eyeY - pupilR * 0.32), glintR, glintPaint);

      // Sclera rim highlight arc
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

    final radius = cs * 0.40;
    final cx = x + cs / 2;
    final cy = y + cs / 2;

    // Animated mouth: toggles open/closed with pelletBlink
    // Open = wide wedge, closed = very thin slice
    final mouthHalf = pelletBlink ? 0.42 : 0.08; // radians
    final dirAngle = [
      -pi / 2, // 0=up
      0.0,     // 1=right
      pi / 2,  // 2=down
      pi,      // 3=left
    ][dir];

    final startAngle = dirAngle + mouthHalf;
    final sweepAngle = 2 * pi - 2 * mouthHalf;

    // Vibrant gold radial gradient body: bright warm centre → deep gold rim
    final bodyPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.35, -0.35),
        radius: 1.05,
        colors: [
          const Color(0xFFFFFFCC), // white-yellow highlight
          const Color(0xFFFFEE00), // bright yellow
          const Color(0xFFFFCC00), // rich gold
          const Color(0xFFFF9900), // deep gold rim
        ],
        stops: const [0.0, 0.30, 0.65, 1.0],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: radius));

    // Pie-slice path (full circle minus mouth wedge)
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

    // Thin dark shadow for the mouth gap
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

    // Gloss arc highlight — a bright curved sheen on the upper-left of the body
    // Rotate sheen slightly toward the current direction's "top"
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

    // Eye: dark circle with white pupil glint
    // Positioned perpendicular to mouth direction, slightly offset toward centre
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

  // ─── HUD drawing ─────────────────────────────────────────────────────────

  void _drawHud(Canvas canvas, Size size, double cs, double offsetX, double offsetY) {
    // HUD positioned above the maze
    final hudY = offsetY - cs * 1.35;
    final hudH = cs * 1.15;
    final hudRect = Rect.fromLTWH(offsetX, hudY, cs * _kMazeCols, hudH);
    final hudRRect = RRect.fromRectAndRadius(hudRect, const Radius.circular(6));

    // HUD background — deep dark navy with slight purple tint
    canvas.drawRRect(hudRRect, Paint()..color = const Color(0xFF070616));

    // Crisp cyan border
    final hudBorderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0xFF00CCFF).withOpacity(0.85);
    canvas.drawRRect(hudRRect, hudBorderPaint);

    final textY = hudY + hudH / 2;
    final fontSize = (cs * 0.54).clamp(8.0, 15.0);

    // Score — left, vivid neon yellow with double glow
    _paintHudText(
      canvas,
      'SCORE  $score',
      Offset(offsetX + cs * 0.45, textY),
      const Color(0xFFFFFF33),
      fontSize,
      bold: true,
      glowColor: const Color(0xFFFFFF00),
      align: TextAlign.left,
    );

    // Level — centre, vivid neon cyan
    _paintHudText(
      canvas,
      'NVL $level',
      Offset(offsetX + cs * _kMazeCols / 2, textY),
      const Color(0xFF00FFFF),
      fontSize,
      bold: true,
      glowColor: const Color(0xFF00EEEE),
      align: TextAlign.center,
    );

    // Lives — right section as mini Pac-Man icons
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
