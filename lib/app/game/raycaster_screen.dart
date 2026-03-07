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
  double hitFlash; // 0–1, flashes white when hit
  _Enemy(this.x, this.y) : hp = 3, alive = true, hitFlash = 0;
}

// ─── Game state ───────────────────────────────────────────────────────────────

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

  // Hit flash (player was hit)
  double _hitFlash = 0;

  // Shoot flash (player fired)
  double _shootFlash = 0;

  // Wave banner
  double _waveBannerTimer = 0;

  // Enemies
  final List<_Enemy> _enemies = [];

  // Z-buffer (120 columns)
  final List<double> _zBuf = List<double>.filled(120, 0);

  // Random
  final Random _rng = Random();

  static const double _moveSpeed = 3.2;
  static const double _rotSpeed = 2.5;

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

  // ─── Controller event (one-shot actions) ─────────────────────────────────

  void _onControllerEvent() {
    final event = widget.controller.lastEvent;
    if (event == null) return;

    if (_state == _GameState.start) {
      if (event.isDown && (event.button == ArcadeButton.start || event.button == ArcadeButton.a)) {
        _startGame();
      }
      return;
    }

    if (_state == _GameState.dead) {
      if (event.isDown && (event.button == ArcadeButton.start || event.button == ArcadeButton.a)) {
        _restart();
      }
      return;
    }

    // Playing — one-shot: fire
    if (event.isDown && event.button == ArcadeButton.a) {
      _fire();
    }
  }

  // ─── Start / restart ──────────────────────────────────────────────────────

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
      _shootFlash = 0;
      _waveBannerTimer = 0;
      _state = _GameState.playing;
    });
    _spawnWave(1);
    _lastTick = DateTime.now();
    _gameTimer?.cancel();
    _gameTimer = Timer.periodic(const Duration(milliseconds: 16), _tick);
  }

  void _restart() => _startGame();

  // ─── Spawn enemies ────────────────────────────────────────────────────────

  void _spawnWave(int wave) {
    _enemies.clear();
    final count = wave + 3; // wave 1 = 4 enemies (was 3)
    if (wave == 1) {
      _enemies.addAll([
        _Enemy(8.5, 8.5),
        _Enemy(12.5, 3.5),
        _Enemy(4.5, 12.5),
        _Enemy(10.5, 12.5),
      ]);
      return;
    }
    int spawned = 0;
    int tries = 0;
    while (spawned < count && tries < 500) {
      tries++;
      final cx = 1 + _rng.nextInt(_kMapW - 2);
      final cy = 1 + _rng.nextInt(_kMapH - 2);
      if (_kMap[cy][cx] == 1) continue;
      final ex = cx + 0.5;
      final ey = cy + 0.5;
      final dx = ex - _posX, dy = ey - _posY;
      if (dx * dx + dy * dy < 9) continue;
      _enemies.add(_Enemy(ex, ey));
      spawned++;
    }
  }

  // ─── Fire ─────────────────────────────────────────────────────────────────

  void _fire() {
    if (_fireTimer > 0) return;
    if (_ammo <= 0) {
      HapticFeedback.lightImpact(); // dry-fire click
      return;
    }
    _ammo--;
    _fireTimer = 0.25;
    _shootFlash = 1.0;
    HapticFeedback.lightImpact(); // fire feedback

    // Cast a ray forward, check enemy hits
    double bestDist = 10.0;
    _Enemy? target;
    for (final e in _enemies) {
      if (!e.alive) continue;
      final dx = e.x - _posX, dy = e.y - _posY;
      final dot = dx * _dirX + dy * _dirY;
      if (dot <= 0 || dot > bestDist) continue;
      final perp = (dx * _dirY - dy * _dirX).abs();
      if (perp < 0.55) {
        bestDist = dot;
        target = e;
      }
    }
    if (target != null) {
      target.hp--;
      target.hitFlash = 1.0;
      if (target.hp <= 0) {
        target.alive = false;
        _kills++;
        HapticFeedback.mediumImpact(); // kill feedback
        _checkWaveComplete();
      }
    }
  }

  // ─── Wave complete check ──────────────────────────────────────────────────

  void _checkWaveComplete() {
    if (_enemies.any((e) => e.alive)) return;
    _wave++;
    _ammo += 20;
    _health = (_health + 20).clamp(0, 100); // partial heal on wave clear
    _saldo += 1;
    widget.onSaldoChanged(_saldo);
    _updateFirestore(_saldo);
    _waveBannerTimer = 2.0;
    HapticFeedback.heavyImpact(); // wave clear feedback
    _spawnWave(_wave);
  }

  // ─── Game tick ────────────────────────────────────────────────────────────

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

    if (c.isHeld(ArcadeButton.up)) {
      final nx = _posX + _dirX * _moveSpeed * dt;
      final ny = _posY + _dirY * _moveSpeed * dt;
      if (_kMap[_posY.floor()][nx.floor()] == 0) _posX = nx;
      if (_kMap[ny.floor()][_posX.floor()] == 0) _posY = ny;
    }

    if (c.isHeld(ArcadeButton.down)) {
      final nx = _posX - _dirX * _moveSpeed * dt;
      final ny = _posY - _dirY * _moveSpeed * dt;
      if (_kMap[_posY.floor()][nx.floor()] == 0) _posX = nx;
      if (_kMap[ny.floor()][_posX.floor()] == 0) _posY = ny;
    }

    // LEFT = turn left (negative angle in screen space)
    if (c.isHeld(ArcadeButton.left)) {
      _rotate(-_rotSpeed * dt);
    }

    // RIGHT = turn right (positive angle in screen space)
    if (c.isHeld(ArcadeButton.right)) {
      _rotate(_rotSpeed * dt);
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
    // Enemy speed scales faster with wave now
    final eSpeed = 0.7 + _wave * 0.15;
    for (final e in _enemies) {
      if (!e.alive) continue;
      final dx = _posX - e.x, dy = _posY - e.y;
      final dist = sqrt(dx * dx + dy * dy);

      if (dist < 0.5) {
        _health -= (12 * dt).round();
        _hitFlash = (_hitFlash + dt * 2.5).clamp(0, 1);
        if (_health <= 0) {
          _health = 0;
          _gameOver();
          return;
        }
        continue;
      }

      final nx = e.x + (dx / dist) * eSpeed * dt;
      final ny = e.y + (dy / dist) * eSpeed * dt;

      if (_kMap[e.y.floor()][nx.floor()] == 0) e.x = nx;
      if (_kMap[ny.floor()][e.x.floor()] == 0) e.y = ny;
    }
  }

  void _updateTimers(double dt) {
    if (_fireTimer > 0) _fireTimer -= dt;
    if (_hitFlash > 0) _hitFlash = (_hitFlash - dt * 2.0).clamp(0, 1);
    if (_shootFlash > 0) _shootFlash = (_shootFlash - dt * 8.0).clamp(0, 1);
    if (_waveBannerTimer > 0) _waveBannerTimer -= dt;
    for (final e in _enemies) {
      if (e.hitFlash > 0) e.hitFlash = (e.hitFlash - dt * 6.0).clamp(0, 1);
    }
  }

  // ─── Game over ────────────────────────────────────────────────────────────

  void _gameOver() {
    _gameTimer?.cancel();
    _state = _GameState.dead;
    HapticFeedback.heavyImpact();
    HighScoreService.submit('raycaster', _kills);
    HighScoreService.load('raycaster').then((v) => setState(() => _hiScore = v));
  }

  // ─── Firestore ────────────────────────────────────────────────────────────

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
    } catch (e) { debugPrint('DungeonBlitz Firestore: $e'); }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
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
                shootFlash: _shootFlash,
                isFiring: _fireTimer > 0,
                showHud: _state == _GameState.playing || _state == _GameState.dead,
              ),
            ),
          ),
          if (_state == _GameState.playing && _waveBannerTimer > 0)
            _buildWaveBanner(),
          if (_state == _GameState.start)
            _buildStartOverlay(),
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
          color: Colors.black.withOpacity(0.75),
          border: Border.all(color: Colors.red.shade700, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '¡OLEADA $_wave!',
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
      color: Colors.black.withOpacity(0.88),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('DUNGEON BLITZ 🔥',
              style: TextStyle(color: Colors.white, fontSize: 28,
                fontWeight: FontWeight.bold, fontFamily: 'monospace', letterSpacing: 3)),
            const SizedBox(height: 8),
            const Text('Demonios acechan en la oscuridad',
              style: TextStyle(color: Colors.redAccent, fontSize: 12, fontFamily: 'monospace')),
            const SizedBox(height: 24),
            const Text('↑↓: mover   ←→: girar   A: disparar',
              style: TextStyle(color: Colors.green, fontSize: 13, fontFamily: 'monospace')),
            const SizedBox(height: 8),
            const Text('+1 pto por oleada  ·  3 disparos por enemigo',
              style: TextStyle(color: Colors.yellow, fontSize: 12, fontFamily: 'monospace')),
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _startGame,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade900,
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
      color: Colors.black.withOpacity(0.88),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('CAÍDO EN COMBATE 💀',
              style: TextStyle(color: Colors.red, fontSize: 26,
                fontWeight: FontWeight.bold, fontFamily: 'monospace', letterSpacing: 2)),
            const SizedBox(height: 16),
            Text('Bajas: $_kills',
              style: const TextStyle(color: Colors.white, fontSize: 18, fontFamily: 'monospace')),
            Text('Oleada alcanzada: $_wave',
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
  final double hitFlash, shootFlash;
  final bool isFiring, showHud;

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
    required this.shootFlash,
    required this.isFiring,
    required this.showHud,
  });

  @override
  bool shouldRepaint(_RaycasterPainter old) => true;

  @override
  void paint(Canvas canvas, Size size) {
    final pxW = size.width / 120.0;
    final pxH = size.height / 80.0;

    // ── Ceiling ──────────────────────────────────────────────────────────────
    final ceilPaint = Paint()..isAntiAlias = false..color = const Color(0xFF1A0A0A);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height / 2), ceilPaint);

    // ── Floor ────────────────────────────────────────────────────────────────
    final floorPaint = Paint()..isAntiAlias = false..color = const Color(0xFF0D0505);
    canvas.drawRect(Rect.fromLTWH(0, size.height / 2, size.width, size.height / 2), floorPaint);

    // ── Wall columns ─────────────────────────────────────────────────────────
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
        stepX = -1; sideDistX = (posX - mapX) * deltaDistX;
      } else {
        stepX = 1; sideDistX = (mapX + 1.0 - posX) * deltaDistX;
      }
      if (rayDirY < 0) {
        stepY = -1; sideDistY = (posY - mapY) * deltaDistY;
      } else {
        stepY = 1; sideDistY = (mapY + 1.0 - posY) * deltaDistY;
      }

      int side = 0;
      int safety = 0;
      while (safety < 64) {
        safety++;
        if (sideDistX < sideDistY) {
          sideDistX += deltaDistX; mapX += stepX; side = 0;
        } else {
          sideDistY += deltaDistY; mapY += stepY; side = 1;
        }
        if (mapX < 0 || mapX >= _kMapW || mapY < 0 || mapY >= _kMapH) break;
        if (_kMap[mapY][mapX] == 1) break;
      }

      final perpWallDist = side == 0 ? sideDistX - deltaDistX : sideDistY - deltaDistY;
      zBuf[x] = perpWallDist;

      final lineHeight = (80 / perpWallDist).round().clamp(1, 80);
      final drawStart = (40 - lineHeight ~/ 2).clamp(0, 79);
      final drawEnd = (40 + lineHeight ~/ 2).clamp(0, 79);

      // Dark red brick-like walls
      final int baseR = side == 0 ? 0x7A : 0x55;
      final int baseG = side == 0 ? 0x20 : 0x16;
      final int baseB = side == 0 ? 0x20 : 0x16;

      final brightness = (1.0 / (1.0 + perpWallDist * 0.35)).clamp(0.15, 1.0);
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

    // ── Enemy sprites (demon-style pixel art) ─────────────────────────────
    final aliveEnemies = enemies.where((e) => e.alive).toList();
    aliveEnemies.sort((a, b) {
      final da = (a.x - posX) * (a.x - posX) + (a.y - posY) * (a.y - posY);
      final db = (b.x - posX) * (b.x - posX) + (b.y - posY) * (b.y - posY);
      return db.compareTo(da);
    });

    final spritePaint = Paint()..isAntiAlias = false;
    for (final e in aliveEnemies) {
      final dx = e.x - posX, dy = e.y - posY;
      final invDet = 1.0 / (planeX * dirY - dirX * planeY);
      final transformX = invDet * (dirY * dx - dirX * dy);
      final transformY = invDet * (-planeY * dx + planeX * dy);

      if (transformY <= 0.1) continue;

      final spriteScreenX = (60 * (1 + transformX / transformY)).round();
      final spriteH = (80 / transformY).abs().round().clamp(2, 80);
      final spriteW = spriteH;

      final drawStartX = spriteScreenX - spriteW ~/ 2;
      final drawStartY = (40 - spriteH ~/ 2).clamp(0, 79);
      final drawEndY = (40 + spriteH ~/ 2).clamp(0, 79);

      // Hit flash: white when recently hit
      final flash = e.hitFlash;

      // Demon color scheme based on HP
      final Color bodyColor;
      final Color detailColor;
      final Color eyeColor;
      if (e.hp >= 3) {
        bodyColor = Color.fromARGB(255, (0x8B * (1 - flash) + 255 * flash).round(), (0x20 * (1 - flash)).round(), (0x20 * (1 - flash)).round());
        detailColor = const Color(0xFF4A0A0A);
        eyeColor = const Color(0xFFFF2200);
      } else if (e.hp == 2) {
        bodyColor = Color.fromARGB(255, (0xCC * (1 - flash) + 255 * flash).round(), (0x55 * (1 - flash)).round(), 0);
        detailColor = const Color(0xFF663300);
        eyeColor = const Color(0xFFFFAA00);
      } else {
        bodyColor = Color.fromARGB(255, (0xFF * (1 - flash) + 255 * flash).round(), (0x22 * (1 - flash)).round(), (0x88 * (1 - flash)).round());
        detailColor = const Color(0xFF880055);
        eyeColor = const Color(0xFFFF00FF);
      }

      // Draw demon sprite using relative coordinates within sprite bounds
      // Unit = spriteW/16 pixels wide
      final u = spriteW / 16.0;
      final v = spriteH / 20.0;
      final bx = drawStartX * pxW;
      final by = drawStartY * pxH;

      for (int sx = drawStartX; sx < drawStartX + spriteW; sx++) {
        if (sx < 0 || sx >= 120) continue;
        if (transformY >= zBuf[sx]) continue;

        // Only draw demon body pixels for visible columns
        final localX = sx - drawStartX; // 0..spriteW-1
        final frac = localX / spriteW.toDouble(); // 0..1

        spritePaint.color = bodyColor;
        // Main body column (center ~60% width = cols 3-13 out of 16)
        if (frac >= 0.19 && frac <= 0.81) {
          canvas.drawRect(
            Rect.fromLTWH(sx * pxW, by + v * 4, pxW, (drawEndY - drawStartY) * pxH - v * 5),
            spritePaint,
          );
        }

        // Head (cols 4-12, rows 1-5)
        if (frac >= 0.25 && frac <= 0.75) {
          canvas.drawRect(
            Rect.fromLTWH(sx * pxW, by + v * 1, pxW, v * 4),
            spritePaint,
          );
        }

        // Horns (cols 2-4 and 12-14, rows 0-2)
        if ((frac >= 0.13 && frac <= 0.31) || (frac >= 0.69 && frac <= 0.87)) {
          spritePaint.color = detailColor;
          canvas.drawRect(
            Rect.fromLTWH(sx * pxW, by, pxW, v * 2.5),
            spritePaint,
          );
        }

        // Eyes (cols 5-6 and 10-11, row 2-3)
        if ((frac >= 0.31 && frac <= 0.44) || (frac >= 0.56 && frac <= 0.69)) {
          spritePaint.color = eyeColor;
          canvas.drawRect(
            Rect.fromLTWH(sx * pxW, by + v * 2, pxW, v * 1.5),
            spritePaint,
          );
        }

        // Arm outlines (cols 1-2 and 14-15, rows 5-12)
        if ((frac >= 0.06 && frac <= 0.19) || (frac >= 0.81 && frac <= 0.94)) {
          spritePaint.color = detailColor;
          canvas.drawRect(
            Rect.fromLTWH(sx * pxW, by + v * 5, pxW, v * 7),
            spritePaint,
          );
        }

        // Legs (cols 4-6 and 10-12, rows 14-20)
        if ((frac >= 0.25 && frac <= 0.44) || (frac >= 0.56 && frac <= 0.75)) {
          spritePaint.color = bodyColor;
          canvas.drawRect(
            Rect.fromLTWH(sx * pxW, by + v * 14, pxW, v * 6),
            spritePaint,
          );
        }
      }

      // Hit mark: bright cross when hitFlash > 0.5
      if (flash > 0.5) {
        final cx = spriteScreenX * pxW;
        final cy = (drawStartY + (drawEndY - drawStartY) / 2.0) * pxH;
        final markPaint = Paint()..color = Colors.white..isAntiAlias = false;
        canvas.drawRect(Rect.fromLTWH(cx - 4, cy - 1, 8, 2), markPaint);
        canvas.drawRect(Rect.fromLTWH(cx - 1, cy - 4, 2, 8), markPaint);
      }
    }

    // ── Shoot flash overlay ─────────────────────────────────────────────────
    if (shootFlash > 0) {
      final sfPaint = Paint()
        ..isAntiAlias = false
        ..color = Colors.orange.withOpacity(shootFlash * 0.25);
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), sfPaint);
    }

    // ── Hit flash overlay ────────────────────────────────────────────────────
    if (hitFlash > 0) {
      final flashPaint = Paint()
        ..isAntiAlias = false
        ..color = Colors.red.withOpacity(hitFlash * 0.55);
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), flashPaint);
    }

    // ── HUD ─────────────────────────────────────────────────────────────────
    if (showHud) {
      // Top bar
      final hudBgPaint = Paint()..isAntiAlias = false..color = Colors.black.withOpacity(0.65);
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 22), hudBgPaint);

      final hudText = '❤ $health%   💀 $kills   🔫 $ammo   OLA $wave';
      final tp = TextPainter(
        text: TextSpan(text: hudText,
          style: const TextStyle(color: Colors.white, fontSize: 11,
            fontFamily: 'monospace', fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, const Offset(6, 5));
      tp.dispose();

      // Crosshair
      final crossPaint = Paint()..isAntiAlias = false..color = Colors.white;
      final cx = size.width / 2, cy = size.height / 2;
      canvas.drawRect(Rect.fromLTWH(cx - 1, cy - 4, 2, 8), crossPaint);
      canvas.drawRect(Rect.fromLTWH(cx - 4, cy - 1, 8, 2), crossPaint);

      // Weapon sprite at bottom center
      _drawWeapon(canvas, size, isFiring);
    }
  }

  void _drawWeapon(Canvas canvas, Size size, bool firing) {
    final cx = size.width / 2;
    final cy = size.height;
    final p = Paint()..isAntiAlias = false;

    // Gun body offset (bob down slightly when not firing)
    final yOff = firing ? 0.0 : size.height * 0.02;

    // Muzzle flash
    if (firing) {
      p.color = const Color(0xFFFFCC00);
      canvas.drawRect(Rect.fromLTWH(cx - 6, cy - size.height * 0.35 + yOff, 12, 8), p);
      p.color = Colors.white;
      canvas.drawRect(Rect.fromLTWH(cx - 3, cy - size.height * 0.38 + yOff, 6, 5), p);
    }

    // Barrel
    p.color = const Color(0xFF555555);
    canvas.drawRect(Rect.fromLTWH(cx - 4, cy - size.height * 0.30 + yOff, 8, size.height * 0.12), p);

    // Barrel highlight
    p.color = const Color(0xFF888888);
    canvas.drawRect(Rect.fromLTWH(cx - 4, cy - size.height * 0.30 + yOff, 2, size.height * 0.12), p);

    // Gun body
    p.color = const Color(0xFF333333);
    canvas.drawRect(Rect.fromLTWH(cx - 18, cy - size.height * 0.22 + yOff, 36, size.height * 0.25), p);

    // Body highlight
    p.color = const Color(0xFF666666);
    canvas.drawRect(Rect.fromLTWH(cx - 18, cy - size.height * 0.22 + yOff, 36, 3), p);

    // Grip
    p.color = const Color(0xFF222222);
    canvas.drawRect(Rect.fromLTWH(cx + 6, cy - size.height * 0.15 + yOff, 14, size.height * 0.20), p);

    // Trigger guard
    p.color = const Color(0xFF444444);
    canvas.drawRect(Rect.fromLTWH(cx + 2, cy - size.height * 0.13 + yOff, 6, 4), p);

    // No ammo indicator
    if (ammo == 0) {
      final tp = TextPainter(
        text: const TextSpan(text: 'SIN BALA',
          style: TextStyle(color: Colors.red, fontSize: 10,
            fontFamily: 'monospace', fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(cx - tp.width / 2, cy - size.height * 0.38));
      tp.dispose();
    }
  }
}
