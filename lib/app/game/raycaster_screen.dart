import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'arcade_input_controller.dart';
import 'high_score_service.dart';

// ─── Map ──────────────────────────────────────────────────────────────────────

const _kMapW = 16, _kMapH = 16;
const _kMap = <List<int>>[
  [1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,1,1,0,0,0,0,1,1,0,0,0,1],
  [1,0,0,0,1,0,0,0,0,0,0,1,0,0,0,1],
  [1,0,1,0,0,0,0,1,1,0,0,0,0,1,0,1],
  [1,0,1,0,0,0,0,0,0,0,0,0,0,1,0,1],
  [1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],
  [1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,1,0,0,0,1,1,0,0,0,1,0,0,1],
  [1,0,0,1,0,0,0,0,0,0,0,0,1,0,0,1],
  [1,0,0,0,0,1,1,0,0,1,1,0,0,0,0,1],
  [1,0,1,0,0,0,0,0,0,0,0,0,0,1,0,1],
  [1,0,1,0,0,0,0,1,1,0,0,0,0,1,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1],
];

// ─── Enemy ────────────────────────────────────────────────────────────────────

class _Enemy {
  double x, y, hp;
  bool alive;
  _Enemy(this.x, this.y) : hp = 3, alive = true;
}

// ─── Game state enum ──────────────────────────────────────────────────────────

enum _GameState { start, playing, dead }

// ─── Widget ───────────────────────────────────────────────────────────────────

class RaycasterScreen extends StatefulWidget {
  final String userId;
  final DocumentReference rewardsDocRef;
  final double currentSaldo;
  final ArcadeInputController controller;
  final void Function(double) onSaldoChanged;
  const RaycasterScreen({super.key, required this.userId, required this.rewardsDocRef,
      required this.currentSaldo, required this.controller, required this.onSaldoChanged});
  @override State<RaycasterScreen> createState() => _RaycasterScreenState();
}

// ─── State ────────────────────────────────────────────────────────────────────

class _RaycasterScreenState extends State<RaycasterScreen> {
  // Player
  double _posX = 2.5, _posY = 2.5;
  double _dirX = 1.0, _dirY = 0.0;
  double _planeX = 0.0, _planeY = 0.66;
  int _health = 100;
  int _kills = 0;
  int _wave = 1;
  int _ammo = 30;
  double _fireTimer = 0;

  // Saldo
  late double _saldo;

  // High score
  int _hiScore = 0;

  // Game state
  _GameState _state = _GameState.start;
  Timer? _gameTimer;
  DateTime? _lastTick;

  // Hit flash
  double _hitFlash = 0;

  // Wave banner
  double _waveBannerTimer = 0;

  // Enemies
  final List<_Enemy> _enemies = [];

  // Z-buffer (120 columns)
  final List<double> _zBuf = List<double>.filled(120, 0);

  // Random
  final Random _rng = Random();

  static const double _moveSpeed = 3.0;
  static const double _rotSpeed = 2.2;

  @override
  void initState() {
    super.initState();
    _saldo = widget.currentSaldo;
    widget.controller.addListener(_onControllerEvent);
    HighScoreService.load('raycaster').then((v) => setState(() => _hiScore = v));
  }

  @override
  void dispose() {
    _gameTimer?.cancel();
    widget.controller.removeListener(_onControllerEvent);
    super.dispose();
  }

  // ─── Controller event (one-shot actions) ────────────────────────────────────

  void _onControllerEvent() {
    final event = widget.controller.lastEvent;
    if (event == null) return;

    if (_state == _GameState.start) {
      if (event.isDown && event.button == ArcadeButton.start) {
        _startGame();
      }
      return;
    }

    if (_state == _GameState.dead) return;

    // Playing — one-shot: fire
    if (event.isDown && event.button == ArcadeButton.a) {
      _fire();
    }
  }

  // ─── Start / restart ────────────────────────────────────────────────────────

  void _startGame() {
    setState(() {
      _posX = 2.5; _posY = 2.5;
      _dirX = 1.0; _dirY = 0.0;
      _planeX = 0.0; _planeY = 0.66;
      _health = 100;
      _kills = 0;
      _wave = 1;
      _ammo = 30;
      _fireTimer = 0;
      _hitFlash = 0;
      _waveBannerTimer = 0;
      _state = _GameState.playing;
    });
    _spawnWave(1);
    _lastTick = DateTime.now();
    _gameTimer?.cancel();
    _gameTimer = Timer.periodic(const Duration(milliseconds: 16), _tick);
  }

  void _restart() => _startGame();

  // ─── Spawn enemies ──────────────────────────────────────────────────────────

  void _spawnWave(int wave) {
    _enemies.clear();
    final count = wave + 2;
    if (wave == 1) {
      // Predetermined starting positions
      _enemies.addAll([
        _Enemy(8.5, 8.5),
        _Enemy(12.5, 3.5),
        _Enemy(4.5, 12.5),
      ]);
      // If wave 1 needs more than 3 (it does: 1+2=3), we're good.
      return;
    }
    // Random open cells
    int spawned = 0;
    int tries = 0;
    while (spawned < count && tries < 500) {
      tries++;
      final cx = 1 + _rng.nextInt(_kMapW - 2);
      final cy = 1 + _rng.nextInt(_kMapH - 2);
      if (_kMap[cy][cx] == 1) continue;
      final ex = cx + 0.5;
      final ey = cy + 0.5;
      // Don't spawn too close to player
      final dx = ex - _posX, dy = ey - _posY;
      if (dx * dx + dy * dy < 9) continue;
      _enemies.add(_Enemy(ex, ey));
      spawned++;
    }
  }

  // ─── Fire ───────────────────────────────────────────────────────────────────

  void _fire() {
    if (_ammo <= 0 || _fireTimer > 0) return;
    _ammo--;
    _fireTimer = 0.3;

    // Cast a ray forward, check enemy hits
    double bestDist = 8.0;
    _Enemy? target;
    for (final e in _enemies) {
      if (!e.alive) continue;
      final dx = e.x - _posX, dy = e.y - _posY;
      // Project enemy onto player direction
      final dot = dx * _dirX + dy * _dirY;
      if (dot <= 0 || dot > bestDist) continue;
      // Perpendicular distance from ray
      final perp = (dx * _dirY - dy * _dirX).abs();
      if (perp < 0.5) {
        bestDist = dot;
        target = e;
      }
    }
    if (target != null) {
      target.hp--;
      if (target.hp <= 0) {
        target.alive = false;
        _kills++;
        _checkWaveComplete();
      }
    }
  }

  // ─── Wave complete check ─────────────────────────────────────────────────────

  void _checkWaveComplete() {
    if (_enemies.any((e) => e.alive)) return;
    // Wave cleared
    _wave++;
    _ammo += 20;
    _saldo += 1;
    widget.onSaldoChanged(_saldo);
    _updateFirestore(_saldo);
    _waveBannerTimer = 1.5;
    _spawnWave(_wave);
  }

  // ─── Game tick ──────────────────────────────────────────────────────────────

  void _tick(Timer t) {
    if (_state != _GameState.playing) return;

    final now = DateTime.now();
    final dt = _lastTick == null ? 0.016 : now.difference(_lastTick!).inMicroseconds / 1e6;
    _lastTick = now;
    final dts = dt.clamp(0.001, 0.1);

    _processMovement(dts);
    _updateEnemies(dts);
    _updateTimers(dts);

    setState(() {});
  }

  void _processMovement(double dt) {
    final c = widget.controller;

    // Move forward
    if (c.isHeld(ArcadeButton.up)) {
      final nx = _posX + _dirX * _moveSpeed * dt;
      final ny = _posY + _dirY * _moveSpeed * dt;
      if (_kMap[_posY.floor()][nx.floor()] == 0) _posX = nx;
      if (_kMap[ny.floor()][_posX.floor()] == 0) _posY = ny;
    }

    // Move backward
    if (c.isHeld(ArcadeButton.down)) {
      final nx = _posX - _dirX * _moveSpeed * dt;
      final ny = _posY - _dirY * _moveSpeed * dt;
      if (_kMap[_posY.floor()][nx.floor()] == 0) _posX = nx;
      if (_kMap[ny.floor()][_posX.floor()] == 0) _posY = ny;
    }

    // Rotate left
    if (c.isHeld(ArcadeButton.left)) {
      final angle = _rotSpeed * dt;
      _rotate(angle);
    }

    // Rotate right
    if (c.isHeld(ArcadeButton.right)) {
      final angle = -_rotSpeed * dt;
      _rotate(angle);
    }
  }

  void _rotate(double angle) {
    final cosA = cos(angle), sinA = sin(angle);
    final newDirX = _dirX * cosA - _dirY * sinA;
    final newDirY = _dirX * sinA + _dirY * cosA;
    _dirX = newDirX; _dirY = newDirY;
    final newPlaneX = _planeX * cosA - _planeY * sinA;
    final newPlaneY = _planeX * sinA + _planeY * cosA;
    _planeX = newPlaneX; _planeY = newPlaneY;
  }

  void _updateEnemies(double dt) {
    final eSpeed = 0.5 + _wave * 0.1;
    for (final e in _enemies) {
      if (!e.alive) continue;
      final dx = _posX - e.x, dy = _posY - e.y;
      final dist = sqrt(dx * dx + dy * dy);

      if (dist < 0.5) {
        // Deal damage
        _health -= (10 * dt).round();
        _hitFlash = (_hitFlash + dt * 2).clamp(0, 1);
        if (_health <= 0) {
          _health = 0;
          _gameOver();
          return;
        }
        continue;
      }

      final nx = e.x + (dx / dist) * eSpeed * dt;
      final ny = e.y + (dy / dist) * eSpeed * dt;

      // Wall collision per axis
      if (_kMap[e.y.floor()][nx.floor()] == 0) {
        e.x = nx;
      }
      if (_kMap[ny.floor()][e.x.floor()] == 0) {
        e.y = ny;
      }
    }
  }

  void _updateTimers(double dt) {
    if (_fireTimer > 0) _fireTimer -= dt;
    if (_hitFlash > 0) _hitFlash = (_hitFlash - dt * 1.5).clamp(0, 1);
    if (_waveBannerTimer > 0) _waveBannerTimer -= dt;
  }

  // ─── Game over ──────────────────────────────────────────────────────────────

  void _gameOver() {
    _gameTimer?.cancel();
    _state = _GameState.dead;
    HighScoreService.submit('raycaster', _kills);
    HighScoreService.load('raycaster').then((v) => setState(() => _hiScore = v));
  }

  // ─── Firestore ──────────────────────────────────────────────────────────────

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
    } catch (e) { debugPrint('Raycaster Firestore: $e'); }
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 3D viewport
          SizedBox.expand(
            child: CustomPaint(
              painter: _RaycasterPainter(
                posX: _posX, posY: _posY,
                dirX: _dirX, dirY: _dirY,
                planeX: _planeX, planeY: _planeY,
                enemies: _enemies,
                zBuf: _zBuf,
                health: _health,
                kills: _kills,
                ammo: _ammo,
                wave: _wave,
                hitFlash: _hitFlash,
                showHud: _state == _GameState.playing || _state == _GameState.dead,
              ),
            ),
          ),
          // Wave banner
          if (_state == _GameState.playing && _waveBannerTimer > 0)
            _buildWaveBanner(),
          // Start overlay
          if (_state == _GameState.start)
            _buildStartOverlay(),
          // Death overlay
          if (_state == _GameState.dead)
            _buildDeathOverlay(),
        ],
      ),
    );
  }

  Widget _buildWaveBanner() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          border: Border.all(color: Colors.red.shade700, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '¡OLA $_wave!',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 36,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
            letterSpacing: 4,
          ),
        ),
      ),
    );
  }

  Widget _buildStartOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.85),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('INVASOR 3D 👾',
              style: TextStyle(color: Colors.white, fontSize: 32,
                fontWeight: FontWeight.bold, fontFamily: 'monospace', letterSpacing: 3)),
            const SizedBox(height: 24),
            const Text('↑↓: mover   ←→: girar   A: disparar',
              style: TextStyle(color: Colors.green, fontSize: 14, fontFamily: 'monospace')),
            const SizedBox(height: 8),
            const Text('+1 pto por ola',
              style: TextStyle(color: Colors.yellow, fontSize: 14, fontFamily: 'monospace')),
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _startGame,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade900,
                    foregroundColor: Colors.white,
                    shape: const StadiumBorder(),
                  ),
                  child: const Text('Iniciar'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeathOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.85),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('ELIMINADO 💀',
              style: TextStyle(color: Colors.red, fontSize: 32,
                fontWeight: FontWeight.bold, fontFamily: 'monospace', letterSpacing: 3)),
            const SizedBox(height: 16),
            Text('Bajas: $_kills',
              style: const TextStyle(color: Colors.white, fontSize: 18, fontFamily: 'monospace')),
            Text('Ola alcanzada: $_wave',
              style: const TextStyle(color: Colors.white, fontSize: 16, fontFamily: 'monospace')),
            Text('Récord: $_hiScore bajas',
              style: const TextStyle(color: Colors.yellow, fontSize: 14, fontFamily: 'monospace')),
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _restart,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade900,
                    foregroundColor: Colors.white,
                    shape: const StadiumBorder(),
                  ),
                  child: const Text('Nueva Partida'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Raycaster Painter ────────────────────────────────────────────────────────

class _RaycasterPainter extends CustomPainter {
  final double posX, posY, dirX, dirY, planeX, planeY;
  final List<_Enemy> enemies;
  final List<double> zBuf;
  final int health, kills, ammo, wave;
  final double hitFlash;
  final bool showHud;

  _RaycasterPainter({
    required this.posX, required this.posY,
    required this.dirX, required this.dirY,
    required this.planeX, required this.planeY,
    required this.enemies,
    required this.zBuf,
    required this.health,
    required this.kills,
    required this.ammo,
    required this.wave,
    required this.hitFlash,
    required this.showHud,
  });

  @override
  bool shouldRepaint(_RaycasterPainter old) => true;

  @override
  void paint(Canvas canvas, Size size) {
    final pxW = size.width / 120.0;
    final pxH = size.height / 80.0;

    // ── Ceiling ────────────────────────────────────────────────────────────────
    final ceilPaint = Paint()
      ..isAntiAlias = false
      ..color = const Color(0xFF383838);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height / 2), ceilPaint);

    // ── Floor ──────────────────────────────────────────────────────────────────
    final floorPaint = Paint()
      ..isAntiAlias = false
      ..color = const Color(0xFF252525);
    canvas.drawRect(Rect.fromLTWH(0, size.height / 2, size.width, size.height / 2), floorPaint);

    // ── Wall columns ──────────────────────────────────────────────────────────
    final wallPaint = Paint()..isAntiAlias = false;

    for (int x = 0; x < 120; x++) {
      final cameraX = 2 * x / 120.0 - 1.0;
      final rayDirX = dirX + planeX * cameraX;
      final rayDirY = dirY + planeY * cameraX;

      int mapX = posX.floor(), mapY = posY.floor();

      final deltaDistX = rayDirX.abs() < 1e-20 ? 1e30 : (1.0 / rayDirX.abs());
      final deltaDistY = rayDirY.abs() < 1e-20 ? 1e30 : (1.0 / rayDirY.abs());

      int stepX, stepY;
      double sideDistX, sideDistY;

      if (rayDirX < 0) {
        stepX = -1;
        sideDistX = (posX - mapX) * deltaDistX;
      } else {
        stepX = 1;
        sideDistX = (mapX + 1.0 - posX) * deltaDistX;
      }
      if (rayDirY < 0) {
        stepY = -1;
        sideDistY = (posY - mapY) * deltaDistY;
      } else {
        stepY = 1;
        sideDistY = (mapY + 1.0 - posY) * deltaDistY;
      }

      int side = 0;
      int safety = 0;
      while (safety < 64) {
        safety++;
        if (sideDistX < sideDistY) {
          sideDistX += deltaDistX;
          mapX += stepX;
          side = 0;
        } else {
          sideDistY += deltaDistY;
          mapY += stepY;
          side = 1;
        }
        if (mapX < 0 || mapX >= _kMapW || mapY < 0 || mapY >= _kMapH) break;
        if (_kMap[mapY][mapX] == 1) break;
      }

      final perpWallDist = side == 0
          ? sideDistX - deltaDistX
          : sideDistY - deltaDistY;

      zBuf[x] = perpWallDist;

      final lineHeight = (80 / perpWallDist).round().clamp(1, 80);
      final drawStart = (40 - lineHeight ~/ 2).clamp(0, 79);
      final drawEnd = (40 + lineHeight ~/ 2).clamp(0, 79);

      // Wall color based on side
      final int baseR = side == 0 ? 0x8B : 0x6B;
      final int baseG = side == 0 ? 0x3A : 0x2A;
      final int baseB = side == 0 ? 0x3A : 0x2A;

      final brightness = (1.0 / (1.0 + perpWallDist * 0.3)).clamp(0.2, 1.0);
      wallPaint.color = Color.fromRGBO(
        (baseR * brightness).round(),
        (baseG * brightness).round(),
        (baseB * brightness).round(),
        1,
      );

      canvas.drawRect(
        Rect.fromLTWH(x * pxW, drawStart * pxH, pxW + 0.5, (drawEnd - drawStart) * pxH + 0.5),
        wallPaint,
      );
    }

    // ── Enemy sprites ──────────────────────────────────────────────────────────
    final aliveEnemies = enemies.where((e) => e.alive).toList();
    aliveEnemies.sort((a, b) {
      final da = (a.x - posX) * (a.x - posX) + (a.y - posY) * (a.y - posY);
      final db = (b.x - posX) * (b.x - posX) + (b.y - posY) * (b.y - posY);
      return db.compareTo(da); // furthest first
    });

    final spritePaint = Paint()..isAntiAlias = false;
    for (final e in aliveEnemies) {
      final dx = e.x - posX, dy = e.y - posY;
      final invDet = 1.0 / (planeX * dirY - dirX * planeY);
      final transformX = invDet * (dirY * dx - dirX * dy);
      final transformY = invDet * (-planeY * dx + planeX * dy);

      if (transformY <= 0) continue;

      final spriteScreenX = (60 * (1 + transformX / transformY)).round();
      final spriteH = (80 / transformY).abs().round().clamp(1, 80);
      final spriteW = spriteH;

      final drawStartX = spriteScreenX - spriteW ~/ 2;
      final drawEndX = spriteScreenX + spriteW ~/ 2;
      final drawStartY = (40 - spriteH ~/ 2).clamp(0, 79);
      final drawEndY = (40 + spriteH ~/ 2).clamp(0, 79);

      // Pick color by hp
      final int spriteColor;
      if (e.hp >= 3) {
        spriteColor = 0xFF00FF41; // alien green
      } else if (e.hp == 2) {
        spriteColor = 0xFFFFFF00; // yellow
      } else {
        spriteColor = 0xFFFF4400; // orange-red
      }
      spritePaint.color = Color(spriteColor);

      for (int sx = drawStartX; sx < drawEndX; sx++) {
        if (sx < 0 || sx >= 120) continue;
        if (transformY >= zBuf[sx]) continue;
        canvas.drawRect(
          Rect.fromLTWH(sx * pxW, drawStartY * pxH, pxW, (drawEndY - drawStartY) * pxH),
          spritePaint,
        );
      }
    }

    // ── Hit flash ─────────────────────────────────────────────────────────────
    if (hitFlash > 0) {
      final flashPaint = Paint()
        ..isAntiAlias = false
        ..color = Colors.red.withOpacity(hitFlash * 0.5);
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), flashPaint);
    }

    // ── HUD ───────────────────────────────────────────────────────────────────
    if (showHud) {
      // Top bar background
      final hudBgPaint = Paint()
        ..isAntiAlias = false
        ..color = Colors.black.withOpacity(0.55);
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 22), hudBgPaint);

      final hudText = '❤ $health%   💀 $kills   🔫 $ammo   OLA $wave';
      final textSpan = TextSpan(
        text: hudText,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontFamily: 'monospace',
          fontWeight: FontWeight.bold,
        ),
      );
      final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
      tp.layout();
      tp.paint(canvas, const Offset(6, 5));

      // Crosshair: 2×6 (vertical) and 6×2 (horizontal) centered
      final crossPaint = Paint()
        ..isAntiAlias = false
        ..color = Colors.white;
      final cx = size.width / 2, cy = size.height / 2;
      // vertical bar: 2 wide, 6 tall
      canvas.drawRect(Rect.fromLTWH(cx - 1, cy - 3, 2, 6), crossPaint);
      // horizontal bar: 6 wide, 2 tall
      canvas.drawRect(Rect.fromLTWH(cx - 3, cy - 1, 6, 2), crossPaint);
    }
  }
}
