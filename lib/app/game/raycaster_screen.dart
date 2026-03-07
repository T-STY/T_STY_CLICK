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

// Lava pool positions (map cells that glow orange on floor)
const _kLavaCells = <List<int>>[
  [7, 7], [7, 8], [8, 7], [8, 8],
  [3, 12], [4, 12],
  [11, 3], [11, 4],
  [13, 10], [13, 11],
];

// ─── Enemy types ──────────────────────────────────────────────────────────────

enum _EnemyType { demon, cacodemon, skeleton }

class _Enemy {
  double x, y;
  double hp;
  bool alive;
  double hitFlash;
  _EnemyType type;

  _Enemy(this.x, this.y, {this.type = _EnemyType.demon})
      : hp = _baseHp(type).toDouble(),
        alive = true,
        hitFlash = 0;

  static int _baseHp(_EnemyType t) {
    switch (t) {
      case _EnemyType.demon: return 3;
      case _EnemyType.cacodemon: return 2;
      case _EnemyType.skeleton: return 2;
    }
  }

  double get spriteScale {
    switch (type) {
      case _EnemyType.demon: return 0.58;    // was 0.72, -20%
      case _EnemyType.cacodemon: return 0.60;
      case _EnemyType.skeleton: return 0.60; // was 0.75, -20%
    }
  }

  double get speed => type == _EnemyType.skeleton ? 0.65 : (type == _EnemyType.cacodemon ? 1.1 : 1.0);
  double get damage => type == _EnemyType.skeleton ? 15.0 : (type == _EnemyType.cacodemon ? 7.0 : 10.0);
}

// ─── Weapon ───────────────────────────────────────────────────────────────────

enum _WeaponType { pistol, shotgun }

// ─── Game state ───────────────────────────────────────────────────────────────

enum _GameState { start, playing, dead }

// ─── Widget ───────────────────────────────────────────────────────────────────

class RaycasterScreen extends StatefulWidget {
  final String userId;
  final DocumentReference rewardsDocRef;
  final double currentSaldo;
  final ArcadeInputController controller;
  final void Function(double) onSaldoChanged;

  const RaycasterScreen({
    super.key,
    required this.userId,
    required this.rewardsDocRef,
    required this.currentSaldo,
    required this.controller,
    required this.onSaldoChanged,
  });

  @override
  State<RaycasterScreen> createState() => _RaycasterScreenState();
}

// ─── State ────────────────────────────────────────────────────────────────────

class _RaycasterScreenState extends State<RaycasterScreen> {
  double _posX = 2.5, _posY = 2.5;
  double _dirX = 1.0, _dirY = 0.0;
  double _planeX = 0.0, _planeY = 0.66;
  double _health = 100.0; // double so fractional damage accumulates correctly
  int _kills = 0;
  int _wave = 1;
  int _ammo = 30;         // pistol ammo
  int _shotgunAmmo = 0;
  bool _shotgunUnlocked = false;
  _WeaponType _weapon = _WeaponType.pistol;
  double _fireTimer = 0;
  double _time = 0; // for animations (flames, bobbing)
  double _damageCooldown = 0; // haptic cooldown when taking damage

  late double _saldo;
  int _hiScore = 0;

  _GameState _state = _GameState.start;
  Timer? _gameTimer;
  DateTime? _lastTick;

  double _hitFlash = 0;
  double _shootFlash = 0;
  double _waveBannerTimer = 0;
  double _dimFlash = 0;       // atmospheric darkness pulse (0=normal, 1=fully dimmed)
  double _dimTimer = 0;       // countdown to next dim event

  final List<_Enemy> _enemies = [];
  final List<double> _zBuf = List<double>.filled(120, 0);
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
    if (event.isDown && event.button == ArcadeButton.a) {
      _fire();
    }
    if (event.isDown && event.button == ArcadeButton.b && _shotgunUnlocked) {
      setState(() => _weapon = _weapon == _WeaponType.pistol ? _WeaponType.shotgun : _WeaponType.pistol);
      HapticFeedback.selectionClick();
    }
  }

  void _startGame() {
    setState(() {
      _posX = 2.5; _posY = 2.5;
      _dirX = 1.0; _dirY = 0.0;
      _planeX = 0.0; _planeY = 0.66;
      _health = 100.0;
      _kills = 0;
      _wave = 1;
      _ammo = 30;
      _shotgunAmmo = 0;
      _shotgunUnlocked = false;
      _weapon = _WeaponType.pistol;
      _fireTimer = 0;
      _time = 0;
      _damageCooldown = 0;
      _hitFlash = 0;
      _shootFlash = 0;
      _waveBannerTimer = 0;
      _dimFlash = 0;
      _dimTimer = 4.0 + _rng.nextDouble() * 6.0;
      _state = _GameState.playing;
    });
    _spawnWave(1);
    _lastTick = DateTime.now();
    _gameTimer?.cancel();
    _gameTimer = Timer.periodic(const Duration(milliseconds: 16), _tick);
  }

  void _restart() => _startGame();

  _EnemyType _randomType(int wave) {
    if (wave == 1) return _EnemyType.demon;
    if (wave == 2) return _rng.nextBool() ? _EnemyType.demon : _EnemyType.cacodemon;
    final r = _rng.nextInt(3);
    return _EnemyType.values[r];
  }

  void _spawnWave(int wave) {
    _enemies.clear();
    if (wave == 1) {
      _enemies.addAll([
        _Enemy(8.5, 8.5, type: _EnemyType.demon),
        _Enemy(12.5, 3.5, type: _EnemyType.cacodemon),
        _Enemy(4.5, 12.5, type: _EnemyType.demon),
        _Enemy(10.5, 12.5, type: _EnemyType.skeleton),
      ]);
      return;
    }
    final count = wave + 3;
    int spawned = 0, tries = 0;
    while (spawned < count && tries < 500) {
      tries++;
      final cx = 1 + _rng.nextInt(_kMapW - 2);
      final cy = 1 + _rng.nextInt(_kMapH - 2);
      if (_kMap[cy][cx] == 1) continue;
      final ex = cx + 0.5, ey = cy + 0.5;
      final dx = ex - _posX, dy = ey - _posY;
      if (dx * dx + dy * dy < 9) continue;
      _enemies.add(_Enemy(ex, ey, type: _randomType(wave)));
      spawned++;
    }
  }

  void _fire() {
    if (_weapon == _WeaponType.shotgun) {
      _fireShotgun();
    } else {
      _firePistol();
    }
  }

  void _firePistol() {
    if (_fireTimer > 0) return;
    if (_ammo <= 0) { HapticFeedback.lightImpact(); return; }
    _ammo--;
    _fireTimer = 0.25;
    _shootFlash = 1.0;
    HapticFeedback.lightImpact();
    _checkCenterHit(_dirX, _dirY, 12.0, damage: 1);
  }

  void _fireShotgun() {
    if (_fireTimer > 0) return;
    if (_shotgunAmmo <= 0) { HapticFeedback.lightImpact(); return; }
    _shotgunAmmo--;
    _fireTimer = 0.55; // slower
    _shootFlash = 1.0;
    HapticFeedback.heavyImpact(); // bigger kick

    // 7 pellets spread ±22°
    const pellets = 7;
    const spread = 0.38; // radians total half-spread
    for (int p = 0; p < pellets; p++) {
      final angle = -spread + (p / (pellets - 1)) * 2 * spread;
      final cosA = cos(angle), sinA = sin(angle);
      final rDx = _dirX * cosA - _dirY * sinA;
      final rDy = _dirX * sinA + _dirY * cosA;
      _checkCenterHit(rDx, rDy, 7.0, damage: 1); // shorter range
    }
  }

  void _checkCenterHit(double rayDirX, double rayDirY, double maxRange, {int damage = 1}) {
    double bestDist = maxRange;
    _Enemy? target;
    for (final e in _enemies) {
      if (!e.alive) continue;
      final dx = e.x - _posX, dy = e.y - _posY;
      final dot = dx * rayDirX + dy * rayDirY;
      if (dot <= 0 || dot > bestDist) continue;
      final perp = (dx * rayDirY - dy * rayDirX).abs();
      if (perp < 0.60) { bestDist = dot; target = e; }
    }
    if (target != null) {
      target.hp -= damage;
      target.hitFlash = 1.0;
      if (target.hp <= 0) {
        target.alive = false;
        _kills++;
        HapticFeedback.mediumImpact();
        _checkWaveComplete();
      }
    }
  }

  void _checkWaveComplete() {
    if (_enemies.any((e) => e.alive)) return;
    _wave++;
    _ammo += 25;
    _health = (_health + 20).clamp(0, 100.0);

    // Shotgun: unlock at wave 2, grant ammo every even wave (2, 4, 6…)
    if (_wave == 2) {
      _shotgunUnlocked = true;
    }
    if (_wave >= 2 && _wave % 2 == 0) {
      final nextCount = _wave + 3; // enemies that will spawn
      _shotgunAmmo += (nextCount * 0.75).round();
    }

    _saldo += 1;
    widget.onSaldoChanged(_saldo);
    _updateFirestore(_saldo);
    _waveBannerTimer = 2.5;
    HapticFeedback.heavyImpact();
    _spawnWave(_wave);
  }

  void _tick(Timer t) {
    if (_state != _GameState.playing) return;
    final now = DateTime.now();
    final dt = _lastTick == null ? 0.016 : now.difference(_lastTick!).inMicroseconds / 1e6;
    _lastTick = now;
    final dts = dt.clamp(0.001, 0.1);
    _time += dts;
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
    if (c.isHeld(ArcadeButton.left)) _rotate(-_rotSpeed * dt);
    if (c.isHeld(ArcadeButton.right)) _rotate(_rotSpeed * dt);
  }

  void _rotate(double angle) {
    final cosA = cos(angle), sinA = sin(angle);
    final ndx = _dirX * cosA - _dirY * sinA;
    final ndy = _dirX * sinA + _dirY * cosA;
    _dirX = ndx; _dirY = ndy;
    final npx = _planeX * cosA - _planeY * sinA;
    final npy = _planeX * sinA + _planeY * cosA;
    _planeX = npx; _planeY = npy;
  }

  void _updateEnemies(double dt) {
    final eBaseSpeed = 0.7 + _wave * 0.15;
    for (final e in _enemies) {
      if (!e.alive) continue;
      final dx = _posX - e.x, dy = _posY - e.y;
      final dist = sqrt(dx * dx + dy * dy);
      if (dist < 0.5) {
        // Accumulate fractional damage — no rounding so it always applies
        _health -= e.damage * dt;
        _hitFlash = (_hitFlash + dt * 3).clamp(0, 1);
        if (_damageCooldown <= 0) {
          HapticFeedback.lightImpact();
          _damageCooldown = 0.35;
        }
        if (_health <= 0) { _health = 0; _gameOver(); return; }
        continue;
      }
      final spd = eBaseSpeed * e.speed;
      final nx = e.x + (dx / dist) * spd * dt;
      final ny = e.y + (dy / dist) * spd * dt;
      if (_kMap[e.y.floor()][nx.floor()] == 0) e.x = nx;
      if (_kMap[ny.floor()][e.x.floor()] == 0) e.y = ny;
    }
  }

  void _updateTimers(double dt) {
    if (_damageCooldown > 0) _damageCooldown -= dt;
    if (_fireTimer > 0) _fireTimer -= dt;
    if (_hitFlash > 0) _hitFlash = (_hitFlash - dt * 2.5).clamp(0, 1);
    if (_shootFlash > 0) _shootFlash = (_shootFlash - dt * 10.0).clamp(0, 1);
    if (_waveBannerTimer > 0) _waveBannerTimer -= dt;
    if (_dimFlash > 0) _dimFlash = (_dimFlash - dt * 1.8).clamp(0, 1);
    // Atmospheric dim: random darkness pulses every 4-10 seconds
    _dimTimer -= dt;
    if (_dimTimer <= 0) {
      _dimFlash = 0.55 + _rng.nextDouble() * 0.35; // 55-90% darkness
      _dimTimer = 4.0 + _rng.nextDouble() * 6.0;   // next event in 4-10 s
    }
    for (final e in _enemies) {
      if (e.hitFlash > 0) e.hitFlash = (e.hitFlash - dt * 7.0).clamp(0, 1);
    }
  }

  void _gameOver() {
    _gameTimer?.cancel();
    _state = _GameState.dead;
    HapticFeedback.heavyImpact();
    HighScoreService.submit('raycaster', _kills);
    HighScoreService.load('raycaster').then((v) => setState(() => _hiScore = v));
  }

  Future<void> _updateFirestore(double newSaldo) async {
    try {
      final userCardRef = FirebaseFirestore.instance
          .collection('users').doc(widget.userId)
          .collection('rewardsCard').doc('cardInfo');
      final batch = FirebaseFirestore.instance.batch();
      batch.update(userCardRef, {'saldo': newSaldo});
      batch.update(widget.rewardsDocRef, {'saldo': newSaldo});
      await batch.commit();
    } catch (e) { debugPrint('MazmorraInfernal Firestore: $e'); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        SizedBox.expand(
          child: CustomPaint(
            painter: _RaycasterPainter(
              posX: _posX, posY: _posY,
              dirX: _dirX, dirY: _dirY,
              planeX: _planeX, planeY: _planeY,
              enemies: _enemies,
              zBuf: _zBuf,
              health: _health.round().clamp(0, 100),
              kills: _kills,
              ammo: _ammo,
              shotgunAmmo: _shotgunAmmo,
              shotgunUnlocked: _shotgunUnlocked,
              weapon: _weapon,
              wave: _wave,
              hitFlash: _hitFlash,
              shootFlash: _shootFlash,
              dimFlash: _dimFlash,
              isFiring: _fireTimer > 0,
              showHud: _state == _GameState.playing || _state == _GameState.dead,
              time: _time,
            ),
          ),
        ),
        if (_state == _GameState.playing && _waveBannerTimer > 0) _buildWaveBanner(),
        if (_state == _GameState.start) _buildStartOverlay(),
        if (_state == _GameState.dead) _buildDeathOverlay(),
      ]),
    );
  }

  Widget _buildWaveBanner() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.80),
          border: Border.all(color: const Color(0xFFCC2200), width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text('¡OLEADA $_wave!',
          style: const TextStyle(color: Colors.white, fontSize: 36,
            fontWeight: FontWeight.bold, fontFamily: 'monospace', letterSpacing: 4)),
      ),
    );
  }

  Widget _buildStartOverlay() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xF0100000), Color(0xF0200000)],
        ),
      ),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('🔥', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 8),
          const Text('INFRAMUNDO 2D',
            style: TextStyle(
              color: Color(0xFFCC2200),
              fontSize: 26,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              letterSpacing: 3,
            )),
          const SizedBox(height: 4),
          const Text('Demonios acechan en la oscuridad…',
            style: TextStyle(color: Color(0xFF882200), fontSize: 11, fontFamily: 'monospace')),
          const SizedBox(height: 22),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF660000), width: 1),
              color: const Color(0x33110000),
            ),
            child: const Column(children: [
              Text('↑↓ mover   ←→ girar   A disparar',
                style: TextStyle(color: Color(0xFF44FF00), fontSize: 12, fontFamily: 'monospace')),
              SizedBox(height: 6),
              Text('X: escopeta (¡cuando la desbloquees!)',
                style: TextStyle(color: Color(0xFF888888), fontSize: 10, fontFamily: 'monospace')),
              SizedBox(height: 8),
              Text('BAJAS × OLEADA = PUNTUACIÓN',
                style: TextStyle(color: Color(0xFFCC8800), fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
              Text('+1 PTO CADA 5 OLEADAS',
                style: TextStyle(color: Color(0xFFFF4400), fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
            ]),
          ),
          const SizedBox(height: 22),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: SizedBox(width: double.infinity,
              child: ElevatedButton(
                onPressed: _startGame,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7B0000),
                  foregroundColor: Colors.white,
                  shape: const StadiumBorder()),
                child: const Text('⚔  Entrar a la Mazmorra',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              )),
          ),
        ]),
      ),
    );
  }

  Widget _buildDeathOverlay() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xF0200000), Color(0xF0050000)],
        ),
      ),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('💀', style: TextStyle(fontSize: 52)),
          const SizedBox(height: 8),
          const Text('HAS CAÍDO',
            style: TextStyle(
              color: Color(0xFFFF2200),
              fontSize: 30,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              letterSpacing: 3,
            )),
          const SizedBox(height: 4),
          const Text('Los demonios han terminado contigo',
            style: TextStyle(color: Color(0xFF882200), fontSize: 11, fontFamily: 'monospace')),
          const SizedBox(height: 20),
          Text('Bajas: $_kills',
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
          Text('Oleada alcanzada: $_wave',
            style: const TextStyle(color: Color(0xFFFF8800), fontSize: 14, fontFamily: 'monospace')),
          Text('Récord: $_hiScore bajas',
            style: const TextStyle(color: Color(0xFFFFDD00), fontSize: 12, fontFamily: 'monospace')),
          const SizedBox(height: 26),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: SizedBox(width: double.infinity,
              child: ElevatedButton(
                onPressed: _restart,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7B0000),
                  foregroundColor: Colors.white,
                  shape: const StadiumBorder()),
                child: const Text('⚔  Nueva Batalla',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              )),
          ),
        ]),
      ),
    );
  }
}

// ─── Painter ──────────────────────────────────────────────────────────────────

class _RaycasterPainter extends CustomPainter {
  final double posX, posY, dirX, dirY, planeX, planeY;
  final List<_Enemy> enemies;
  final List<double> zBuf;
  final int health, kills, ammo, shotgunAmmo, wave;
  final bool shotgunUnlocked;
  final _WeaponType weapon;
  final double hitFlash, shootFlash, dimFlash, time;
  final bool isFiring, showHud;

  const _RaycasterPainter({
    required this.posX, required this.posY,
    required this.dirX, required this.dirY,
    required this.planeX, required this.planeY,
    required this.enemies, required this.zBuf,
    required this.health, required this.kills,
    required this.ammo, required this.shotgunAmmo,
    required this.shotgunUnlocked, required this.weapon,
    required this.wave,
    required this.hitFlash, required this.shootFlash,
    required this.dimFlash,
    required this.isFiring, required this.showHud,
    required this.time,
  });

  @override
  bool shouldRepaint(_RaycasterPainter old) => true;

  @override
  void paint(Canvas canvas, Size size) {
    final pxW = size.width / 120.0;
    final pxH = size.height / 80.0;

    _drawCeilingAndFloor(canvas, size, pxW, pxH);
    _castWalls(canvas, size, pxW, pxH);
    _drawEnemySprites(canvas, size, pxW, pxH);
    _drawScreenFx(canvas, size);
    if (showHud) {
      _drawHud(canvas, size);
      _drawCrosshair(canvas, size);
      _drawWeapon(canvas, size, isFiring);
      _drawRadar(canvas, size);
    }
  }

  // ── Ceiling & lava floor ────────────────────────────────────────────────────

  void _drawCeilingAndFloor(Canvas canvas, Size size, double pxW, double pxH) {
    final p = Paint()..isAntiAlias = false;

    // Ceiling — dark reddish stone
    p.color = const Color(0xFF110808);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height / 2), p);

    // Floor — dark lava ground
    p.color = const Color(0xFF180A00);
    canvas.drawRect(Rect.fromLTWH(0, size.height / 2, size.width, size.height / 2), p);

    // Atmospheric stone floor lines (distance shading)
    p.color = const Color(0xFF200C00);
    for (int i = 0; i < 10; i++) {
      final lineY = size.height * 0.5 + size.height * 0.5 * (i + 0.5) / 10;
      canvas.drawRect(Rect.fromLTWH(0, lineY, size.width, 1.0), p);
    }
    // Blood pools (static dark splotches near ground)
    p.color = const Color(0xFF2A0400);
    canvas.drawRect(Rect.fromLTWH(0, size.height * 0.82, size.width * 0.12, size.height * 0.08), p);
    canvas.drawRect(Rect.fromLTWH(size.width * 0.55, size.height * 0.88, size.width * 0.18, size.height * 0.06), p);
    canvas.drawRect(Rect.fromLTWH(size.width * 0.78, size.height * 0.80, size.width * 0.10, size.height * 0.10), p);

    // Screen-edge infernal glow (vignette)
    final vPaint = Paint()
      ..shader = LinearGradient(
        colors: [const Color(0x44CC1100), Colors.transparent],
      ).createShader(Rect.fromLTWH(0, 0, size.width * 0.18, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width * 0.18, size.height), vPaint);

    final vPaint2 = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerRight,
        end: Alignment.centerLeft,
        colors: [const Color(0x44CC1100), Colors.transparent],
      ).createShader(Rect.fromLTWH(size.width * 0.82, 0, size.width * 0.18, size.height));
    canvas.drawRect(Rect.fromLTWH(size.width * 0.82, 0, size.width * 0.18, size.height), vPaint2);
  }

  // ── Wall raycasting ─────────────────────────────────────────────────────────

  void _castWalls(Canvas canvas, Size size, double pxW, double pxH) {
    final wallPaint = Paint()..isAntiAlias = false;

    for (int x = 0; x < 120; x++) {
      final cameraX = 2 * x / 120.0 - 1.0;
      final rayDirX = dirX + planeX * cameraX;
      final rayDirY = dirY + planeY * cameraX;

      int mapX = posX.floor(), mapY = posY.floor();

      final deltaDistX = rayDirX.abs() < 1e-20 ? 1e30 : 1.0 / rayDirX.abs();
      final deltaDistY = rayDirY.abs() < 1e-20 ? 1e30 : 1.0 / rayDirY.abs();

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
      while (safety++ < 64) {
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

      final lineH = (80 / perpWallDist).round().clamp(1, 80);
      final ds = (40 - lineH ~/ 2).clamp(0, 79);
      final de = (40 + lineH ~/ 2).clamp(0, 79);

      // Dark red brick walls — side walls slightly darker
      final int baseR = side == 0 ? 0x7A : 0x55;
      final int baseG = side == 0 ? 0x18 : 0x10;
      final int baseB = side == 0 ? 0x08 : 0x05;

      final br = (1.0 / (1.0 + perpWallDist * 0.30)).clamp(0.1, 1.0);
      wallPaint.color = Color.fromRGBO(
        (baseR * br).round(), (baseG * br).round(), (baseB * br).round(), 1);
      canvas.drawRect(
        Rect.fromLTWH(x * pxW, ds * pxH, pxW + 0.5, (de - ds) * pxH + 0.5), wallPaint);
    }
  }

  // ── Enemy sprites ───────────────────────────────────────────────────────────

  void _drawEnemySprites(Canvas canvas, Size size, double pxW, double pxH) {
    final alive = enemies.where((e) => e.alive).toList();
    alive.sort((a, b) {
      final da = (a.x - posX) * (a.x - posX) + (a.y - posY) * (a.y - posY);
      final db = (b.x - posX) * (b.x - posX) + (b.y - posY) * (b.y - posY);
      return db.compareTo(da);
    });

    final sp = Paint()..isAntiAlias = false;

    for (final e in alive) {
      final dx = e.x - posX, dy = e.y - posY;
      final invDet = 1.0 / (planeX * dirY - dirX * planeY);
      final transformX = invDet * (dirY * dx - dirX * dy);
      final transformY = invDet * (-planeY * dx + planeX * dy);
      if (transformY <= 0.1) continue;

      final screenX = (60 * (1 + transformX / transformY)).round();
      final baseH = (80 / transformY).abs();

      // Scale: 3/4 height max, type-specific scale
      final spriteH = (baseH * e.spriteScale).round().clamp(2, 60);
      final spriteW = spriteH;

      // Cacodemon floats/bobs vertically
      final bobOffset = e.type == _EnemyType.cacodemon
          ? (sin(time * 2.8 + e.x * 1.3) * 3).round()
          : 0;

      final drawStartX = screenX - spriteW ~/ 2;
      final drawStartY = ((40 - spriteH ~/ 2) + bobOffset).clamp(0, 79);
      final drawEndY = ((40 + spriteH ~/ 2) + bobOffset).clamp(0, 79);

      final by = drawStartY * pxH;
      final sh = (drawEndY - drawStartY) * pxH;
      final v = sh / 20.0; // vertical unit within sprite
      final flash = e.hitFlash;

      for (int sx = drawStartX; sx < drawStartX + spriteW; sx++) {
        if (sx < 0 || sx >= 120) continue;
        if (transformY >= zBuf[sx]) continue;

        final localX = sx - drawStartX;
        final frac = localX / spriteW.toDouble();

        switch (e.type) {
          case _EnemyType.demon:
            _drawDemonColumn(canvas, sp, sx, pxW, by, sh, v, frac, e.hp, flash);
          case _EnemyType.cacodemon:
            _drawCacoDemonColumn(canvas, sp, sx, pxW, by, sh, v, frac, e.hp, flash);
          case _EnemyType.skeleton:
            _drawSkeletonColumn(canvas, sp, sx, pxW, by, sh, v, frac, e.hp, flash);
        }
      }

      // Hit-mark cross
      if (flash > 0.5) {
        final cx = screenX * pxW;
        final cy = (drawStartY + (drawEndY - drawStartY) / 2.0) * pxH;
        sp.color = Colors.white;
        canvas.drawRect(Rect.fromLTWH(cx - 5, cy - 1, 10, 2), sp);
        canvas.drawRect(Rect.fromLTWH(cx - 1, cy - 5, 2, 10), sp);
      }
    }
  }

  // ─── Demon (bipedal humanoid) ───────────────────────────────────────────────

  void _drawDemonColumn(Canvas canvas, Paint sp, int sx, double pxW,
      double by, double sh, double v, double frac, double hp, double flash) {
    final Color body, detail, eye;
    if (hp >= 3) {
      body = Color.fromARGB(255, (0x8B + (255 - 0x8B) * flash).round(), (0x18 * (1 - flash)).round(), (0x18 * (1 - flash)).round());
      detail = const Color(0xFF3A0808);
      eye = const Color(0xFFFF1100);
    } else if (hp >= 2) {
      body = Color.fromARGB(255, (0xBB + (255 - 0xBB) * flash).round(), (0x44 * (1 - flash)).round(), 0);
      detail = const Color(0xFF552200);
      eye = const Color(0xFFFFAA00);
    } else {
      body = Color.fromARGB(255, 255, (0x22 * (1 - flash)).round(), (0x99 * (1 - flash)).round());
      detail = const Color(0xFF770044);
      eye = const Color(0xFFFF00FF);
    }

    final x = sx * pxW;

    // Body center 20-80%
    if (frac >= 0.20 && frac <= 0.80) {
      sp.color = body;
      canvas.drawRect(Rect.fromLTWH(x, by + v * 4, pxW, sh - v * 5), sp);
    }
    // Head 25-75%, rows 1-5
    if (frac >= 0.25 && frac <= 0.75) {
      sp.color = body;
      canvas.drawRect(Rect.fromLTWH(x, by + v * 1, pxW, v * 3.5), sp);
    }
    // Horns 10-30% and 70-90%, rows 0-2
    if ((frac >= 0.10 && frac <= 0.30) || (frac >= 0.70 && frac <= 0.90)) {
      sp.color = detail;
      canvas.drawRect(Rect.fromLTWH(x, by, pxW, v * 2.0), sp);
    }
    // Eyes 32-44% and 56-68%, rows 2-3.5
    if ((frac >= 0.32 && frac <= 0.44) || (frac >= 0.56 && frac <= 0.68)) {
      sp.color = eye;
      canvas.drawRect(Rect.fromLTWH(x, by + v * 2.0, pxW, v * 1.5), sp);
    }
    // Arms 5-20% and 80-95%, rows 5-12
    if ((frac >= 0.05 && frac <= 0.20) || (frac >= 0.80 && frac <= 0.95)) {
      sp.color = detail;
      canvas.drawRect(Rect.fromLTWH(x, by + v * 4.5, pxW, v * 7), sp);
    }
    // Legs 28-44% and 56-72%, rows 15-20
    if ((frac >= 0.28 && frac <= 0.44) || (frac >= 0.56 && frac <= 0.72)) {
      sp.color = body;
      canvas.drawRect(Rect.fromLTWH(x, by + v * 15, pxW, v * 5), sp);
    }
    // Pectoral muscles (light highlight strips, frac 22-38% and 62-78%, rows 4-6)
    if ((frac >= 0.22 && frac <= 0.38) || (frac >= 0.62 && frac <= 0.78)) {
      sp.color = Color.fromARGB(255,
        (body.red * 1.25).clamp(0, 255).round(),
        (body.green * 1.1).clamp(0, 255).round(),
        (body.blue * 1.1).clamp(0, 255).round(),
      );
      canvas.drawRect(Rect.fromLTWH(x, by + v * 4.0, pxW, v * 1.5), sp);
    }
    // Abdominal ridges (alternating strips, frac 30-70%, rows 7-14)
    if (frac >= 0.30 && frac <= 0.70) {
      for (int ab = 0; ab < 4; ab++) {
        final isLight = ab % 2 == 0;
        sp.color = isLight
            ? Color.fromARGB(255,
                (body.red * 1.20).clamp(0, 255).round(),
                (body.green * 1.0).clamp(0, 255).round(),
                (body.blue * 1.0).clamp(0, 255).round())
            : Color.fromARGB(255,
                (body.red * 0.65).clamp(0, 255).round(),
                (body.green * 0.65).clamp(0, 255).round(),
                (body.blue * 0.65).clamp(0, 255).round());
        canvas.drawRect(Rect.fromLTWH(x, by + v * (7.5 + ab * 1.6), pxW, v * 0.9), sp);
      }
    }
    // Bulging arm highlight (outer third of arm column, rows 5-10)
    if ((frac >= 0.05 && frac <= 0.13) || (frac >= 0.87 && frac <= 0.95)) {
      sp.color = Color.fromARGB(255,
        (body.red * 1.15).clamp(0, 255).round(),
        (body.green * 1.0).clamp(0, 255).round(),
        (body.blue * 1.0).clamp(0, 255).round(),
      );
      canvas.drawRect(Rect.fromLTWH(x, by + v * 5.0, pxW, v * 5), sp);
    }
    // Thick neck (frac 40-60%, rows 3-4.5)
    if (frac >= 0.40 && frac <= 0.60) {
      sp.color = body;
      canvas.drawRect(Rect.fromLTWH(x, by + v * 3.0, pxW, v * 1.5), sp);
    }
  }

  // ─── Cacodemon (demonic floating crimson sphere) ───────────────────────────

  void _drawCacoDemonColumn(Canvas canvas, Paint sp, int sx, double pxW,
      double by, double sh, double v, double frac, double hp, double flash) {
    final xFrac = frac - 0.5; // -0.5 to 0.5
    if (xFrac.abs() >= 0.5) return;

    final sphereRadius = sqrt(0.25 - xFrac * xFrac);
    final sphereTop = by + sh * (0.5 - sphereRadius);
    final sphereBot = by + sh * (0.5 + sphereRadius);
    final spriteH = sphereBot - sphereTop;
    final x = sx * pxW;

    // ── Sphere body — crimson/blood-red ───────────────────────────────────────
    // Shading: dark at edges, brighter at center for 3-D illusion
    final edgeFactor = xFrac.abs() * 2.0;     // 0=center, 1=edge
    final shade = (1.0 - edgeFactor * 0.55).clamp(0.35, 1.0);

    // Base colour shifts from deep crimson (full HP) to sickly purple-red (low HP)
    final Color bodyBase;
    if (hp >= 2) {
      // Healthy: dark blood-red, brightens with flash
      bodyBase = Color.fromARGB(255,
          (0xAA + (255 - 0xAA) * flash).round().clamp(0, 255),
          (0x0A * (1 - flash)).round().clamp(0, 255),
          (0x0A * (1 - flash)).round().clamp(0, 255));
    } else {
      // Damaged: sickly dark purple
      bodyBase = Color.fromARGB(255,
          (0x88 + (255 - 0x88) * flash).round().clamp(0, 255),
          (0x04 * (1 - flash)).round().clamp(0, 255),
          (0x22 * (1 - flash)).round().clamp(0, 255));
    }

    sp.color = Color.fromARGB(255,
        (bodyBase.red   * shade).round().clamp(0, 255),
        (bodyBase.green * shade).round().clamp(0, 255),
        (bodyBase.blue  * shade).round().clamp(0, 255));
    canvas.drawRect(Rect.fromLTWH(x, sphereTop, pxW, spriteH), sp);

    // Dark veins / shadow band around equator
    if (xFrac.abs() < 0.45) {
      final veinY = sphereTop + spriteH * 0.60;
      sp.color = const Color(0xFF3A0000).withOpacity(0.50);
      canvas.drawRect(Rect.fromLTWH(x, veinY, pxW, spriteH * 0.06), sp);
    }

    // ── Large angry eye (central, yellow-orange sclera, black slit pupil) ────
    if (xFrac.abs() < 0.32) {
      final eyeXFrac = xFrac / 0.32;
      final eyeHalfH = sqrt(1 - eyeXFrac * eyeXFrac) * 0.26 * spriteH;
      final eyeCenterY = sphereTop + spriteH * 0.38; // slightly above center

      // Sclera — angry yellow-orange
      sp.color = hp >= 2
          ? Color.fromARGB(255, (255 * (1 - flash * 0.3)).round(), (0xCC * (1 - flash * 0.5)).round(), 0)
          : const Color(0xFFFF6600);
      canvas.drawRect(Rect.fromLTWH(x, eyeCenterY - eyeHalfH, pxW, eyeHalfH * 2), sp);

      // Slit pupil (vertical black bar in center third)
      if (xFrac.abs() < 0.10) {
        sp.color = const Color(0xFF080000);
        canvas.drawRect(Rect.fromLTWH(x, eyeCenterY - eyeHalfH * 1.1, pxW, eyeHalfH * 2.2), sp);
      }
      // Blood vessel lines radiating from eye (horizontal red streaks)
      if (xFrac.abs() > 0.12 && xFrac.abs() < 0.28) {
        sp.color = const Color(0xFFCC0000).withOpacity(0.70);
        canvas.drawRect(Rect.fromLTWH(x, eyeCenterY - eyeHalfH * 0.25, pxW, eyeHalfH * 0.15), sp);
        canvas.drawRect(Rect.fromLTWH(x, eyeCenterY + eyeHalfH * 0.18, pxW, eyeHalfH * 0.15), sp);
      }
      // Specular highlight (upper-left of eye)
      if (xFrac < -0.06 && xFrac > -0.20) {
        sp.color = Colors.white.withOpacity(0.65);
        canvas.drawRect(Rect.fromLTWH(x, eyeCenterY - eyeHalfH * 0.85, pxW, eyeHalfH * 0.35), sp);
      }
    }

    // ── Jagged horns (top of sphere) ──────────────────────────────────────────
    // Two curved horns projecting above the sphere at ≈ ±35% width
    if (xFrac > 0.28 && xFrac < 0.44) {
      // Right horn: tapers upward
      final hornH = spriteH * (0.42 - (xFrac - 0.28) * 1.5);
      sp.color = const Color(0xFF220000);
      canvas.drawRect(Rect.fromLTWH(x, sphereTop - hornH, pxW, hornH), sp);
      sp.color = const Color(0xFF550000); // lighter tip
      canvas.drawRect(Rect.fromLTWH(x, sphereTop - hornH, pxW, hornH * 0.3), sp);
    }
    if (xFrac < -0.28 && xFrac > -0.44) {
      final hornH = spriteH * (0.42 - (-xFrac - 0.28) * 1.5);
      sp.color = const Color(0xFF220000);
      canvas.drawRect(Rect.fromLTWH(x, sphereTop - hornH, pxW, hornH), sp);
      sp.color = const Color(0xFF550000);
      canvas.drawRect(Rect.fromLTWH(x, sphereTop - hornH, pxW, hornH * 0.3), sp);
    }

    // ── Jagged teeth (lower half) ─────────────────────────────────────────────
    // Wide gaping maw in the bottom 30% of the sphere
    if (xFrac.abs() < 0.38) {
      final mawY = sphereTop + spriteH * 0.68;
      final mawH = spriteH * 0.28;
      // Dark mouth cavity
      sp.color = const Color(0xFF0A0000);
      canvas.drawRect(Rect.fromLTWH(x, mawY, pxW, mawH), sp);
      // Upper teeth (jagged: alternate tall/short)
      final toothPhase = ((xFrac + 0.38) / 0.76 * 7).floor();
      sp.color = Colors.white.withOpacity(0.88);
      if (toothPhase % 2 == 0) {
        canvas.drawRect(Rect.fromLTWH(x, mawY, pxW, mawH * 0.45), sp);
      } else {
        canvas.drawRect(Rect.fromLTWH(x, mawY, pxW, mawH * 0.25), sp);
      }
      // Lower teeth
      if (toothPhase % 2 == 1) {
        sp.color = Colors.white.withOpacity(0.75);
        canvas.drawRect(Rect.fromLTWH(x, mawY + mawH - mawH * 0.40, pxW, mawH * 0.40), sp);
      }
      // Gum/blood at top and bottom of maw
      sp.color = const Color(0xFF880000).withOpacity(0.60);
      canvas.drawRect(Rect.fromLTWH(x, mawY - 1, pxW, 2), sp);
      canvas.drawRect(Rect.fromLTWH(x, mawY + mawH, pxW, 2), sp);
    }
  }

  // ─── Skeleton ──────────────────────────────────────────────────────────────

  void _drawSkeletonColumn(Canvas canvas, Paint sp, int sx, double pxW,
      double by, double sh, double v, double frac, double hp, double flash) {
    final x = sx * pxW;
    final bone = Color.fromARGB(255, (0xE8 * (1 - flash) + 255 * flash).round(),
        (0xE4 * (1 - flash) + 255 * flash).round(), (0xCC * (1 - flash)).round());
    const dark = Color(0xFF111111);

    // Skull: rows 0.5-4.5, cols 28-72%
    if (frac >= 0.28 && frac <= 0.72) {
      sp.color = bone;
      canvas.drawRect(Rect.fromLTWH(x, by + v * 0.5, pxW, v * 4), sp);
      // Eye sockets
      if ((frac >= 0.32 && frac <= 0.44) || (frac >= 0.56 && frac <= 0.68)) {
        sp.color = dark;
        canvas.drawRect(Rect.fromLTWH(x, by + v * 1.5, pxW, v * 1.8), sp);
      }
      // Nasal cavity
      if (frac >= 0.45 && frac <= 0.55) {
        sp.color = dark;
        canvas.drawRect(Rect.fromLTWH(x, by + v * 2.8, pxW, v * 1.2), sp);
      }
      // Teeth
      if (frac >= 0.34 && frac <= 0.66) {
        sp.color = bone;
        canvas.drawRect(Rect.fromLTWH(x, by + v * 4.0, pxW, v * 0.5), sp);
        if ((frac + 0.04).round() % 2 == 0) {
          sp.color = dark;
          canvas.drawRect(Rect.fromLTWH(x, by + v * 4.0, pxW, v * 0.5), sp);
        }
      }
    }

    // Neck: rows 4.5-5.5, cols 44-56%
    if (frac >= 0.44 && frac <= 0.56) {
      sp.color = bone;
      canvas.drawRect(Rect.fromLTWH(x, by + v * 4.5, pxW, v * 1), sp);
    }

    // Spine (center): rows 5.5-14, cols 47-53%
    if (frac >= 0.47 && frac <= 0.53) {
      sp.color = bone;
      canvas.drawRect(Rect.fromLTWH(x, by + v * 5.5, pxW, v * 8.5), sp);
    }

    // Ribs: rows 6-12, cols 28-72% — alternating bars
    if (frac >= 0.28 && frac <= 0.72) {
      for (int rib = 0; rib < 5; rib++) {
        sp.color = bone;
        canvas.drawRect(Rect.fromLTWH(x, by + v * (6 + rib * 1.4), pxW, v * 0.6), sp);
      }
    }

    // Shoulder collar: rows 5.5-6.5, cols 15-85%
    if (frac >= 0.15 && frac <= 0.85) {
      sp.color = bone;
      canvas.drawRect(Rect.fromLTWH(x, by + v * 5.5, pxW, v * 1), sp);
    }

    // Arms: rows 6-12, cols 12-26% and 74-88%
    if ((frac >= 0.12 && frac <= 0.26) || (frac >= 0.74 && frac <= 0.88)) {
      sp.color = bone;
      canvas.drawRect(Rect.fromLTWH(x, by + v * 6, pxW, v * 6), sp);
    }

    // Pelvis: rows 14-15.5, cols 28-72%
    if (frac >= 0.28 && frac <= 0.72) {
      sp.color = bone;
      canvas.drawRect(Rect.fromLTWH(x, by + v * 14, pxW, v * 1.5), sp);
    }

    // Legs: rows 15.5-20, cols 32-46% and 54-68%
    if ((frac >= 0.32 && frac <= 0.46) || (frac >= 0.54 && frac <= 0.68)) {
      sp.color = bone;
      canvas.drawRect(Rect.fromLTWH(x, by + v * 15.5, pxW, v * 4.5), sp);
    }
  }

  // ── Screen effects ──────────────────────────────────────────────────────────

  void _drawScreenFx(Canvas canvas, Size size) {
    // Atmospheric darkness pulse (scary random dim)
    if (dimFlash > 0) {
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = const Color(0xFF0A0000).withOpacity(dimFlash * 0.82)..isAntiAlias = false);
    }
    if (shootFlash > 0) {
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = Colors.orange.withOpacity(shootFlash * 0.22)..isAntiAlias = false);
    }
    if (hitFlash > 0) {
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = Colors.red.withOpacity(hitFlash * 0.50)..isAntiAlias = false);
    }
  }

  // ── HUD ─────────────────────────────────────────────────────────────────────

  void _drawHud(Canvas canvas, Size size) {
    final p = Paint()..isAntiAlias = false;

    // HUD strip background
    p.color = Colors.black.withOpacity(0.78);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 30), p);

    // ── Health bar ────────────────────────────────────────────────────────────
    const barX = 8.0, barY = 8.0, barW = 90.0, barH = 14.0;
    final hFrac = (health / 100.0).clamp(0.0, 1.0);
    final barFill = health > 60
        ? const Color(0xFF22CC44)
        : health > 30 ? const Color(0xFFFF8800) : const Color(0xFFCC1111);

    p.color = const Color(0xFF222222);
    canvas.drawRect(Rect.fromLTWH(barX, barY, barW, barH), p);
    p.color = barFill;
    canvas.drawRect(Rect.fromLTWH(barX, barY, barW * hFrac, barH), p);
    p.color = Colors.white24;
    p.style = PaintingStyle.stroke;
    p.strokeWidth = 1.0;
    canvas.drawRect(Rect.fromLTWH(barX, barY, barW, barH), p);
    p.style = PaintingStyle.fill;

    _hudText(canvas, '❤  $health%', barX + 4, barY + 2, color: Colors.white, size: 10);

    // ── Kill counter ──────────────────────────────────────────────────────────
    _hudText(canvas, '💀 $kills', 106, barY + 2, color: Colors.white, size: 10);

    // ── Wave indicator ────────────────────────────────────────────────────────
    _hudText(canvas, 'OLA $wave', size.width / 2 - 22, barY + 2,
        color: const Color(0xFFFF8800), size: 10);

    // ── Ammo display (right side) ─────────────────────────────────────────────
    if (!shotgunUnlocked) {
      _hudText(canvas, '🔫 $ammo', size.width - 62, barY + 2,
          color: Colors.white, size: 10);
    } else {
      final pistolColor = weapon == _WeaponType.pistol
          ? const Color(0xFFFFEE44) : Colors.white54;
      final shotgunColor = weapon == _WeaponType.shotgun
          ? const Color(0xFFFFEE44) : Colors.white54;
      _hudText(canvas, '🔫 $ammo', size.width - 78, barY,
          color: pistolColor, size: 9);
      _hudText(canvas, '🟠 $shotgunAmmo', size.width - 78, barY + 13,
          color: shotgunColor, size: 9);
      // Active weapon indicator bar
      final activeY = weapon == _WeaponType.pistol ? barY + 1.5 : barY + 14.5;
      p.color = const Color(0xFFFFEE44);
      canvas.drawRect(Rect.fromLTWH(size.width - 82, activeY, 2, 7), p);
    }
  }

  void _hudText(Canvas canvas, String text, double x, double y,
      {Color color = Colors.white, double size = 10}) {
    final tp = TextPainter(
      text: TextSpan(text: text,
          style: TextStyle(color: color, fontSize: size,
              fontFamily: 'monospace', fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset(x, y));
    tp.dispose();
  }

  void _drawCrosshair(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2;
    final p = Paint()..color = Colors.white..isAntiAlias = false;
    canvas.drawRect(Rect.fromLTWH(cx - 1, cy - 5, 2, 10), p);
    canvas.drawRect(Rect.fromLTWH(cx - 5, cy - 1, 10, 2), p);
    final gap = Paint()..color = Colors.black..isAntiAlias = false;
    canvas.drawRect(Rect.fromLTWH(cx - 1, cy - 1, 2, 2), gap);
  }

  // ── Radar (cone-of-vision mini-map) ─────────────────────────────────────────

  void _drawRadar(Canvas canvas, Size size) {
    const radarR = 44.0;
    const cx = 55.0;
    final cy = size.height - 62.0;
    const scale = radarR / 7.0; // 7 map units → radarR px

    final p = Paint()..isAntiAlias = true;

    // Clip drawing to circle shape
    canvas.save();
    canvas.clipPath(Path()..addOval(
        Rect.fromCircle(center: Offset(cx, cy), radius: radarR)));

    // Background
    p.color = Colors.black.withOpacity(0.72);
    canvas.drawCircle(Offset(cx, cy), radarR, p);

    // FOV cone fill
    final fovHalf = atan(0.66); // camera plane / dir length ≈ 33.4°
    final playerAngle = atan2(-dirY, dirX); // flip Y for screen coords
    final conePath = Path()..moveTo(cx, cy);
    const steps = 12;
    for (int i = 0; i <= steps; i++) {
      final a = (playerAngle - fovHalf) + (fovHalf * 2) * i / steps;
      conePath.lineTo(cx + cos(a) * radarR, cy - sin(a) * radarR);
    }
    conePath.close();
    p.color = const Color(0xFFFF6600).withOpacity(0.20);
    canvas.drawPath(conePath, p);

    // FOV edge lines
    p.color = const Color(0xFFFF8800).withOpacity(0.70);
    p.style = PaintingStyle.stroke;
    p.strokeWidth = 1.0;
    canvas.drawLine(Offset(cx, cy),
        Offset(cx + cos(playerAngle - fovHalf) * radarR,
               cy - sin(playerAngle - fovHalf) * radarR), p);
    canvas.drawLine(Offset(cx, cy),
        Offset(cx + cos(playerAngle + fovHalf) * radarR,
               cy - sin(playerAngle + fovHalf) * radarR), p);
    p.style = PaintingStyle.fill;

    // Enemy icons — type-specific symbols matching enemy colors
    for (final e in enemies) {
      if (!e.alive) continue;
      final dx = e.x - posX, dy = e.y - posY;
      final rx = cx + dx * scale;
      final ry = cy + dy * scale;
      if ((rx - cx) * (rx - cx) + (ry - cy) * (ry - cy) > (radarR - 3) * (radarR - 3)) continue;

      if (e.type == _EnemyType.skeleton) {
        // Skull: white circle + dark eye holes cross
        p.color = Colors.white70;
        canvas.drawCircle(Offset(rx, ry), 3.5, p);
        p.color = Colors.black;
        canvas.drawRect(Rect.fromLTWH(rx - 2, ry - 1, 1.5, 1.5), p); // left eye
        canvas.drawRect(Rect.fromLTWH(rx + 0.5, ry - 1, 1.5, 1.5), p); // right eye
        canvas.drawRect(Rect.fromLTWH(rx - 1, ry + 0.8, 2, 1), p); // nasal
      } else if (e.type == _EnemyType.demon) {
        // Red diamond + horn nubs above
        p.color = const Color(0xFFFF3322);
        // Diamond body
        final path = Path()
          ..moveTo(rx, ry - 4)
          ..lineTo(rx + 3, ry)
          ..lineTo(rx, ry + 3)
          ..lineTo(rx - 3, ry)
          ..close();
        canvas.drawPath(path, p);
        // Horn nubs
        p.color = const Color(0xFFAA1100);
        canvas.drawRect(Rect.fromLTWH(rx - 3.5, ry - 6, 1.5, 2.5), p);
        canvas.drawRect(Rect.fromLTWH(rx + 2, ry - 6, 1.5, 2.5), p);
      } else {
        // Cacodemon: blue filled circle with tiny spike top
        p.color = const Color(0xFF44BBFF);
        canvas.drawCircle(Offset(rx, ry + 0.5), 3.5, p);
        // Horn on top
        final hornPath = Path()
          ..moveTo(rx - 1.5, ry - 3)
          ..lineTo(rx, ry - 6)
          ..lineTo(rx + 1.5, ry - 3)
          ..close();
        canvas.drawPath(hornPath, p);
        p.color = Colors.black38;
        p.style = PaintingStyle.stroke;
        p.strokeWidth = 0.8;
        canvas.drawCircle(Offset(rx, ry + 0.5), 3.5, p);
        p.style = PaintingStyle.fill;
      }
    }

    // Player dot + forward arrow
    p.color = const Color(0xFF44FF88);
    canvas.drawCircle(Offset(cx, cy), 4.0, p);
    p.style = PaintingStyle.stroke;
    p.strokeWidth = 1.5;
    canvas.drawLine(Offset(cx, cy),
        Offset(cx + dirX * 10, cy + dirY * 10), p);
    p.style = PaintingStyle.fill;

    canvas.restore(); // restore clip

    // Border (drawn outside clip so it's always crisp)
    p.color = const Color(0xFF884400);
    p.style = PaintingStyle.stroke;
    p.strokeWidth = 1.5;
    canvas.drawCircle(Offset(cx, cy), radarR, p);
    p.style = PaintingStyle.fill;

    // Label
    _hudText(canvas, 'RADAR', cx - 14, cy + radarR + 3,
        color: const Color(0xFFBB6622), size: 8);
  }

  // ── Weapon dispatcher ────────────────────────────────────────────────────────

  void _drawWeapon(Canvas canvas, Size size, bool firing) {
    if (weapon == _WeaponType.shotgun) {
      _drawShotgun(canvas, size, firing);
    } else {
      _drawPistol(canvas, size, firing);
    }
  }

  // ── Double-barrel shotgun – front-facing, same tilt as pistol ───────────────

  void _drawShotgun(Canvas canvas, Size size, bool firing) {
    canvas.save();
    // Same base position and tilt as pistol so both feel consistent
    canvas.translate(size.width * 0.60, size.height * 0.94);
    canvas.rotate(-0.25); // 5° left tilt – identical to pistol

    final p = Paint()..isAntiAlias = false;

    // ── Dual muzzle flash (above both barrels) ────────────────────────────────
    if (firing) {
      p.isAntiAlias = true;
      p.color = const Color(0xFFFF5500).withOpacity(0.88);
      canvas.drawOval(const Rect.fromLTWH(-26, -120, 30, 24), p);
      canvas.drawOval(const Rect.fromLTWH(2,  -120, 30, 24), p);
      p.color = const Color(0xFFFFDD00);
      canvas.drawOval(const Rect.fromLTWH(-22, -117, 20, 16), p);
      canvas.drawOval(const Rect.fromLTWH(6,  -117, 20, 16), p);
      p.color = Colors.white;
      canvas.drawOval(const Rect.fromLTWH(-18, -114, 12, 11), p);
      canvas.drawOval(const Rect.fromLTWH(10, -114, 12, 11), p);
      p.isAntiAlias = false;
    }

    // ── Left barrel ───────────────────────────────────────────────────────────
    p.color = const Color(0xFF888888); // left highlight
    canvas.drawRect(const Rect.fromLTWH(-24, -108, 2, 62), p);
    p.color = const Color(0xFF606060); // body
    canvas.drawRect(const Rect.fromLTWH(-22, -108, 18, 62), p);
    p.color = const Color(0xFF404040); // right shadow
    canvas.drawRect(const Rect.fromLTWH(-4, -108, 2, 62), p);
    p.color = const Color(0xFF111111); // bore
    canvas.drawRect(const Rect.fromLTWH(-20, -109, 14, 8), p);
    // Muzzle crown ring
    p.color = const Color(0xFF555555);
    canvas.drawRect(const Rect.fromLTWH(-24, -111, 22, 3), p);

    // ── Right barrel ──────────────────────────────────────────────────────────
    p.color = const Color(0xFF888888);
    canvas.drawRect(const Rect.fromLTWH(2, -108, 2, 62), p);
    p.color = const Color(0xFF606060);
    canvas.drawRect(const Rect.fromLTWH(4, -108, 18, 62), p);
    p.color = const Color(0xFF404040);
    canvas.drawRect(const Rect.fromLTWH(22, -108, 2, 62), p);
    p.color = const Color(0xFF111111);
    canvas.drawRect(const Rect.fromLTWH(6, -109, 14, 8), p);
    p.color = const Color(0xFF555555);
    canvas.drawRect(const Rect.fromLTWH(2, -111, 22, 3), p);

    // ── Rib between barrels ───────────────────────────────────────────────────
    p.color = const Color(0xFF777777);
    canvas.drawRect(const Rect.fromLTWH(-2, -108, 4, 62), p);

    // ── Barrel band ───────────────────────────────────────────────────────────
    p.color = const Color(0xFF555555);
    canvas.drawRect(const Rect.fromLTWH(-24, -64, 48, 8), p);
    p.color = const Color(0xFF777777);
    canvas.drawRect(const Rect.fromLTWH(-24, -64, 48, 2), p);

    // ── Wooden forestock ──────────────────────────────────────────────────────
    p.color = const Color(0xFF6B4520);
    canvas.drawRect(const Rect.fromLTWH(-20, -56, 40, 30), p);
    p.color = const Color(0xFF7A5028);
    for (int i = 0; i < 4; i++) {
      canvas.drawRect(Rect.fromLTWH(-18.0 + i * 9, -54, 6, 26), p);
    }

    // ── Metal receiver ────────────────────────────────────────────────────────
    p.color = const Color(0xFF404040);
    canvas.drawRect(const Rect.fromLTWH(-22, -26, 44, 36), p);
    p.color = const Color(0xFF555555); // top highlight
    canvas.drawRect(const Rect.fromLTWH(-22, -26, 44, 3), p);
    p.color = const Color(0xFF333333); // bottom shadow
    canvas.drawRect(const Rect.fromLTWH(-22, 8,  44, 2), p);
    // Ejection port
    p.color = const Color(0xFF1A1A1A);
    canvas.drawRect(const Rect.fromLTWH(10, -22, 8, 20), p);

    // ── Trigger guard ─────────────────────────────────────────────────────────
    p.color = const Color(0xFF444444);
    canvas.drawRect(const Rect.fromLTWH(-18, 8,  36, 3), p);
    canvas.drawRect(const Rect.fromLTWH(-18, 8,  3, 22), p);
    canvas.drawRect(const Rect.fromLTWH(15,  8,  3, 22), p);
    canvas.drawRect(const Rect.fromLTWH(-18, 28, 36, 3), p);
    p.color = const Color(0xFF888888);
    canvas.drawRect(const Rect.fromLTWH(-5, 11, 7, 14), p); // trigger

    // ── Pistol grip (wood) ────────────────────────────────────────────────────
    p.color = const Color(0xFF5C3A12);
    canvas.drawRect(const Rect.fromLTWH(-12, 30, 32, 44), p);
    p.color = const Color(0xFF6A4418);
    for (int r = 0; r < 5; r++) {
      canvas.drawRect(Rect.fromLTWH(-9.0, 34.0 + r * 7, 24, 4), p);
    }
    p.color = const Color(0xFF3A2208);
    canvas.drawRect(const Rect.fromLTWH(-12, 72, 32, 4), p);

    canvas.restore();

    if (shotgunAmmo == 0) {
      final tp = TextPainter(
        text: const TextSpan(text: '— SIN CARTUCHOS —',
            style: TextStyle(color: Colors.orange, fontSize: 10,
                fontFamily: 'monospace', fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(size.width / 2 - tp.width / 2, size.height * 0.60));
      tp.dispose();
    }
  }

  // ── Semi-auto pistol – barrel points up, 5° left tilt ────────────────────────

  void _drawPistol(Canvas canvas, Size size, bool firing) {
    canvas.save();
    canvas.translate(size.width * 0.78, size.height * 0.94);
    canvas.rotate(-0.35); // 5° left tilt – matches shotgun

    final p = Paint()..isAntiAlias = false;

    // ── Muzzle flash ──────────────────────────────────────────────────────────
    if (firing) {
      p.isAntiAlias = true;
      p.color = const Color(0xFFFF8800).withOpacity(0.88);
      canvas.drawOval(const Rect.fromLTWH(-17, -110, 34, 26), p);
      p.color = const Color(0xFFFFEE00);
      canvas.drawOval(const Rect.fromLTWH(-11, -107, 22, 17), p);
      p.color = Colors.white;
      canvas.drawOval(const Rect.fromLTWH(-7, -104, 14, 13), p);
      p.isAntiAlias = false;
    }

    // ── Barrel (vertical, pointing up) ────────────────────────────────────────
    p.color = const Color(0xFF888888); // left highlight
    canvas.drawRect(const Rect.fromLTWH(-7, -98, 2, 52), p);
    p.color = const Color(0xFF606060); // body
    canvas.drawRect(const Rect.fromLTWH(-5, -98, 14, 52), p);
    p.color = const Color(0xFF404040); // right shadow
    canvas.drawRect(const Rect.fromLTWH(9, -98, 3, 52), p);
    p.color = const Color(0xFF111111); // bore
    canvas.drawRect(const Rect.fromLTWH(-3, -99, 8, 6), p);
    // Front sight (wider blade – easier to see)
    p.color = const Color(0xFF666666);
    canvas.drawRect(const Rect.fromLTWH(-9, -102, 24, 4), p);
    p.color = Colors.white.withOpacity(0.30);
    canvas.drawRect(const Rect.fromLTWH(-2, -99, 8, 2), p); // sight dot

    // ── Slide (boxy top half of gun) ──────────────────────────────────────────
    p.color = const Color(0xFF333333);
    canvas.drawRect(const Rect.fromLTWH(-15, -86, 32, 82), p);
    p.color = const Color(0xFF555555); // left highlight
    canvas.drawRect(const Rect.fromLTWH(-15, -86, 3, 82), p);
    p.color = const Color(0xFF484848); // top face
    canvas.drawRect(const Rect.fromLTWH(-15, -86, 32, 3), p);
    // Serrations (lower third of slide)
    p.color = const Color(0xFF282828);
    for (int i = 0; i < 7; i++) {
      canvas.drawRect(Rect.fromLTWH(-13, -34.0 + i * 5, 28, 2), p);
    }
    // Rear sight (two posts with gap)
    p.color = const Color(0xFF555555);
    canvas.drawRect(const Rect.fromLTWH(-14, -90, 7, 5), p); // left post
    canvas.drawRect(const Rect.fromLTWH(7,  -90, 7, 5), p);  // right post
    p.color = const Color(0xFF111111);
    canvas.drawRect(const Rect.fromLTWH(-6, -90, 13, 5), p); // notch gap
    // Ejection port
    p.color = const Color(0xFF1A1A1A);
    canvas.drawRect(const Rect.fromLTWH(11, -70, 5, 22), p);
    p.color = const Color(0xFFB8860B);
    canvas.drawRect(const Rect.fromLTWH(12, -67, 3, 15), p); // brass case

    // ── Frame / dust-cover ────────────────────────────────────────────────────
    p.color = const Color(0xFF2E2E2E);
    canvas.drawRect(const Rect.fromLTWH(-17, -6, 34, 24), p);
    p.color = const Color(0xFF444444);
    canvas.drawRect(const Rect.fromLTWH(-17, -6, 3, 24), p);
    // Rail under frame
    p.color = const Color(0xFF262626);
    canvas.drawRect(const Rect.fromLTWH(-17, 14, 34, 4), p);

    // ── Trigger guard ─────────────────────────────────────────────────────────
    p.color = const Color(0xFF303030);
    canvas.drawRect(const Rect.fromLTWH(-14, 16, 28, 3), p);  // top
    canvas.drawRect(const Rect.fromLTWH(-14, 16, 3, 20), p);  // left
    canvas.drawRect(const Rect.fromLTWH(11,  16, 3, 20), p);  // right
    canvas.drawRect(const Rect.fromLTWH(-14, 33, 28, 3), p);  // bottom
    p.color = const Color(0xFF888888);
    canvas.drawRect(const Rect.fromLTWH(-4, 19, 7, 12), p);   // trigger

    // ── Grip ──────────────────────────────────────────────────────────────────
    p.color = const Color(0xFF222222);
    canvas.drawRect(const Rect.fromLTWH(-15, 25, 34, 46), p);
    // Stippling texture
    p.color = const Color(0xFF333333);
    for (int r = 0; r < 5; r++) {
      for (int c = 0; c < 4; c++) {
        canvas.drawRect(Rect.fromLTWH(-11.0 + c*7, 29.0 + r*7, 4, 3), p);
      }
    }
    p.color = const Color(0xFF1A1A1A); // base
    canvas.drawRect(const Rect.fromLTWH(-15, 69, 34, 5), p);
    p.color = const Color(0xFF404040); // mag plate
    canvas.drawRect(const Rect.fromLTWH(-13, 73, 30, 4), p);

    // ── Exposed hammer ────────────────────────────────────────────────────────
    p.color = const Color(0xFF777777);
    canvas.drawRect(const Rect.fromLTWH(13, -18, 10, 11), p);
    p.color = const Color(0xFF444444);
    canvas.drawRect(const Rect.fromLTWH(15, -16, 6, 8), p);

    canvas.restore();

    if (ammo == 0) {
      final tp = TextPainter(
        text: const TextSpan(text: '— SIN BALAS —',
          style: TextStyle(color: Colors.red, fontSize: 10,
            fontFamily: 'monospace', fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(size.width / 2 - tp.width / 2, size.height * 0.60));
      tp.dispose();
    }
  }
}
