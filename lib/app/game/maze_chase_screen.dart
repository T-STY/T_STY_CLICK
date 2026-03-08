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
  bool _scaredActive = false;

  double _saldo = 0;

  Timer? _playerTimer;
  Timer? _ghostTimer;
  Timer? _scaredTimer;
  Timer? _blinkTimer;
  Timer? _levelCompleteTimer;

  bool _pelletBlink = false;
  bool _scaredBlink = false;
  int _ghostIntervalMs = 350;

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
      case ArcadeButton.start:
        if (_isDead) {
          _restart();
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
      ],
    );
  }

  // ── Start overlay ──────────────────────────────────────────────────────────

  Widget _buildStartOverlay() {
  return Positioned.fill(
    child: Container(
      color: const Color(0xEE000018),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('COMECOCOS',
            style: TextStyle(
              color: Color(0xFFFFFF00),
              fontSize: 26,
              fontWeight: FontWeight.bold,
              letterSpacing: 4,
            )),
          const SizedBox(height: 4),
          const Text('● ● ● ● ● ● ● ● ●',
            style: TextStyle(color: Color(0xFFFFFF00), fontSize: 8, letterSpacing: 4)),
          const SizedBox(height: 20),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 28),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF0066FF), width: 2),
              borderRadius: BorderRadius.circular(4),
              color: const Color(0xFF000033),
            ),
            child: const Column(children: [
              Text('D-pad: mover por el laberinto',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
              SizedBox(height: 6),
              Text('Come todos los puntos para pasar de nivel',
                style: TextStyle(color: Colors.white54, fontSize: 11),
                textAlign: TextAlign.center),
              SizedBox(height: 6),
              Text('Pastilla grande → ¡Fantasmas comestibles!',
                style: TextStyle(color: Color(0xFF00CCFF), fontSize: 11),
                textAlign: TextAlign.center),
              SizedBox(height: 8),
              Text('+1 PTO REAL POR NIVEL',
                style: TextStyle(color: Color(0xFFFFFF00), fontSize: 12, fontWeight: FontWeight.bold)),
            ]),
          ),
          const SizedBox(height: 28),
          const Text('👻  Cuidado con los fantasmas  👻',
            style: TextStyle(color: Color(0xFFFF6699), fontSize: 12)),
          const SizedBox(height: 16),
          const Text('Presiona A o START para jugar',
            style: TextStyle(color: Color(0xFF4444AA), fontSize: 12)),
        ],
      ),
    ),
  );
}

  // ── Game over overlay ──────────────────────────────────────────────────────

  Widget _buildGameOverOverlay() {
  return Positioned.fill(
    child: Container(
      color: const Color(0xEE000018),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('👻', style: TextStyle(fontSize: 52)),
          const SizedBox(height: 8),
          const Text('ATRAPADO',
            style: TextStyle(
              color: Color(0xFFFF2266),
              fontSize: 32,
              fontWeight: FontWeight.bold,
              letterSpacing: 4,
            )),
          const SizedBox(height: 4),
          const Text('Un fantasma te ha engullido',
            style: TextStyle(color: Color(0xFF884466), fontSize: 11)),
          const SizedBox(height: 20),
          Text('Puntuación: $_score',
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Récord: $_hiScore',
            style: const TextStyle(color: Color(0xFFFFFF00), fontSize: 14)),
          const SizedBox(height: 28),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _restart,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0044BB),
                  foregroundColor: Colors.white,
                  shape: const StadiumBorder()),
                child: const Text('Nueva Partida', style: TextStyle(fontWeight: FontWeight.bold)),
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
        color: Colors.black.withOpacity(0.80),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '¡NIVEL $_level COMPLETADO!',
              style: const TextStyle(
                color: Color(0xFFFFFF00),
                fontSize: 26,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              '+1 punto añadido',
              style: TextStyle(color: Colors.white70, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
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

    final paint = Paint()..isAntiAlias = false;

    // Background
    paint.color = const Color(0xFF000000);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);

    // Draw cells
    for (int r = 0; r < _kMazeRows; r++) {
      for (int c = 0; c < _kMazeCols; c++) {
        final x = offsetX + c * cs;
        final y = offsetY + r * cs;
        final cell = grid[r][c];

        switch (cell) {
          case 1: // Wall
            paint.color = const Color(0xFF0033FF);
            canvas.drawRect(Rect.fromLTWH(x, y, cs, cs), paint);
          case 0: // Dot
            paint.color = const Color(0xFFFFFFCC);
            final dotSize = max(2.0, cs * 0.2);
            canvas.drawRect(
              Rect.fromLTWH(
                x + (cs - dotSize) / 2,
                y + (cs - dotSize) / 2,
                dotSize,
                dotSize,
              ),
              paint,
            );
          case 2: // Power pellet
            if (pelletBlink) {
              paint.color = const Color(0xFFFFFF00);
              final pSize = cs * 0.5;
              canvas.drawRect(
                Rect.fromLTWH(
                  x + (cs - pSize) / 2,
                  y + (cs - pSize) / 2,
                  pSize,
                  pSize,
                ),
                paint,
              );
            }
          case 3: // Ghost spawn area
            paint.color = const Color(0xFF1A1A1A);
            canvas.drawRect(Rect.fromLTWH(x, y, cs, cs), paint);
          default:
            break; // consumed cell (-1), draw nothing
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
    _drawHud(canvas, size, cs);
  }

  void _drawGhost(
    Canvas canvas,
    _Ghost g,
    double offsetX,
    double offsetY,
    double cs,
  ) {
    final paint = Paint()..isAntiAlias = false;
    final x = offsetX + g.col * cs;
    final y = offsetY + g.row * cs;

    final bodyW = cs * 0.7;
    final bodyH = cs * 0.8;
    final bx = x + (cs - bodyW) / 2;
    final by = y + (cs - bodyH) / 2;

    // Ghost body color
    Color ghostColor;
    if (g.scared) {
      // Scared: alternate between blue and white if blinking
      ghostColor = scaredBlink
          ? const Color(0xFFFFFFFF)
          : const Color(0xFF0000CC);
    } else {
      ghostColor = g.color;
    }

    paint.color = ghostColor;

    // Top rounded part (upper half)
    final topH = bodyH * 0.6;
    canvas.drawRect(Rect.fromLTWH(bx, by, bodyW, topH), paint);

    // Bottom bumps: 3 rectangles
    final bumpW = bodyW / 3;
    final bumpH = bodyH * 0.4;
    final bumpY = by + topH;
    // bump 0 and bump 2 are drawn (gaps between are skipped)
    canvas.drawRect(Rect.fromLTWH(bx, bumpY, bumpW, bumpH), paint);
    canvas.drawRect(
        Rect.fromLTWH(bx + bumpW * 2, bumpY, bumpW, bumpH), paint);

    // Eyes
    final eyeSize = max(2.0, cs * 0.12);
    final pupilSize = max(1.0, eyeSize * 0.55);

    final leftEyeX = bx + bodyW * 0.22;
    final rightEyeX = bx + bodyW * 0.62;
    final eyeY = by + bodyH * 0.15;

    paint.color = Colors.white;
    canvas.drawRect(
        Rect.fromLTWH(leftEyeX, eyeY, eyeSize, eyeSize), paint);
    canvas.drawRect(
        Rect.fromLTWH(rightEyeX, eyeY, eyeSize, eyeSize), paint);

    paint.color = Colors.black;
    canvas.drawRect(
        Rect.fromLTWH(leftEyeX + (eyeSize - pupilSize) / 2,
            eyeY + (eyeSize - pupilSize) / 2, pupilSize, pupilSize),
        paint);
    canvas.drawRect(
        Rect.fromLTWH(rightEyeX + (eyeSize - pupilSize) / 2,
            eyeY + (eyeSize - pupilSize) / 2, pupilSize, pupilSize),
        paint);
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
    final paint = Paint()..isAntiAlias = false;
    final x = offsetX + col * cs;
    final y = offsetY + row * cs;

    final bodySize = cs * 0.8;
    final bx = x + (cs - bodySize) / 2;
    final by = y + (cs - bodySize) / 2;

    // Yellow body
    paint.color = const Color(0xFFFFFF00);
    canvas.drawRect(Rect.fromLTWH(bx, by, bodySize, bodySize), paint);

    // Pixel-art mouth: 3 small black squares in a wedge on the facing side
    paint.color = const Color(0xFF000000);
    final mSize = max(2.0, cs * 0.18);

    switch (dir) {
      case 1: // right
        final mx = bx + bodySize - mSize;
        final midY = by + (bodySize - mSize) / 2;
        canvas.drawRect(Rect.fromLTWH(mx, midY, mSize, mSize), paint);
        canvas.drawRect(
            Rect.fromLTWH(mx - mSize, midY - mSize, mSize, mSize), paint);
        canvas.drawRect(
            Rect.fromLTWH(mx - mSize, midY + mSize, mSize, mSize), paint);
      case 3: // left
        final mx = bx;
        final midY = by + (bodySize - mSize) / 2;
        canvas.drawRect(Rect.fromLTWH(mx, midY, mSize, mSize), paint);
        canvas.drawRect(
            Rect.fromLTWH(mx + mSize, midY - mSize, mSize, mSize), paint);
        canvas.drawRect(
            Rect.fromLTWH(mx + mSize, midY + mSize, mSize, mSize), paint);
      case 0: // up
        final my = by;
        final midX = bx + (bodySize - mSize) / 2;
        canvas.drawRect(Rect.fromLTWH(midX, my, mSize, mSize), paint);
        canvas.drawRect(
            Rect.fromLTWH(midX - mSize, my + mSize, mSize, mSize), paint);
        canvas.drawRect(
            Rect.fromLTWH(midX + mSize, my + mSize, mSize, mSize), paint);
      case 2: // down
        final my = by + bodySize - mSize;
        final midX = bx + (bodySize - mSize) / 2;
        canvas.drawRect(Rect.fromLTWH(midX, my, mSize, mSize), paint);
        canvas.drawRect(
            Rect.fromLTWH(midX - mSize, my - mSize, mSize, mSize), paint);
        canvas.drawRect(
            Rect.fromLTWH(midX + mSize, my - mSize, mSize, mSize), paint);
    }
  }

  void _drawHud(Canvas canvas, Size size, double cs) {
    final tp = TextPainter(
      text: TextSpan(
        text: 'SCORE: $score   LIVES: $lives   LVL: $level',
        style: TextStyle(
          color: Colors.white,
          fontSize: (cs * 0.55).clamp(9.0, 16.0),
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width);

    final hudY = size.height - cs * 1.2;
    tp.paint(canvas, Offset((size.width - tp.width) / 2, hudY));
  }

  @override
  bool shouldRepaint(_MazePainter old) => true;
}
