import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'arcade_input_controller.dart';
import 'high_score_service.dart';

// ─── Enums ────────────────────────────────────────────────────────────────────

enum _AlienType { basic, burst, scatter, missile }

enum _PickupType { shield, specialAmmo, heart }

// ─── Data ─────────────────────────────────────────────────────────────────────

class _Bullet {
  double x, y, vx, vy;
  final bool isPlayer;
  final bool isMissile;
  bool alive;
  _Bullet(this.x, this.y,
      {required this.isPlayer, this.vx = 0, this.vy = 0, this.isMissile = false})
      : alive = true;
}

class _Alien {
  double x, y, vx, vy, dirChangeTimer, fireTimer, burstTimer;
  int hp, burstCount;
  _AlienType type;
  bool alive;

  _Alien(this.x, this.y, {required this.type})
      : alive = true,
        hp = type == _AlienType.scatter
            ? 3
            : (type == _AlienType.burst ? 2 : 1),
        fireTimer = 0.3 + Random().nextDouble() * 0.8,
        burstCount = 0,
        burstTimer = 0,
        vx = (Random().nextDouble() - 0.5) * 2.5,
        vy = 0.3 + Random().nextDouble() * 0.6,
        dirChangeTimer = 1.5 + Random().nextDouble() * 2.0;
}

class _Asteroid {
  double x, y, vy, rot, rotV, radius;
  bool alive;
  _Asteroid(this.x, this.y, this.vy, this.radius)
      : alive = true,
        rot = 0,
        rotV = (Random().nextDouble() - 0.5) * 4;
}

class _Pickup {
  double x, y, vy;
  _PickupType type;
  bool alive;
  _Pickup(this.x, this.y, {required this.type}) : alive = true, vy = 1.8;
}

// ─── Screen ──────────────────────────────────────────────────────────────────

class SpaceShooterScreen extends StatefulWidget {
  final String userId;
  final DocumentReference rewardsDocRef;
  final double currentSaldo;
  final ArcadeInputController controller;
  final void Function(double) onSaldoChanged;

  const SpaceShooterScreen({
    super.key,
    required this.userId,
    required this.rewardsDocRef,
    required this.currentSaldo,
    required this.controller,
    required this.onSaldoChanged,
  });

  @override
  State<SpaceShooterScreen> createState() => _SpaceShooterScreenState();
}

class _SpaceShooterScreenState extends State<SpaceShooterScreen> {
  static const int kW = 10;
  static const int kH = 16;
  static const double kShipW = 1.2;
  static const double kShipH = 1.0;
  static const double kShipSpeed = 7.0;
  static const double kBulletSpeed = 18.0;
  static const double kEnemyBulletSpeed = 7.0;
  static const double kMissileSpeed = 5.0;
  static const double kShipMinY = 9.0;
  static const double kFireCooldown = 0.25;
  static const double kSpecialCooldown = 0.5;
  static const double kSpawnInterval = 0.65;
  // Auto-advance to next wave after all aliens cleared
  static const double kBetweenWaveDuration = 2.5;

  final _rng = Random();

  // Ship state
  double _sx = 4.4, _sy = 13.5;
  int _lives = 3;
  bool _invincible = false;
  double _invTimer = 0;
  int _shieldHits = 0;
  int _specialAmmo = 0;
  double _fireCooldown = 0;
  double _specialCooldown = 0;

  // Saldo
  late double _saldo;
  bool _awardingPoints = false;

  // Entities
  List<_Bullet> _bullets = [];
  List<_Alien> _aliens = [];
  List<_Asteroid> _asteroids = [];
  List<_Pickup> _pickups = [];

  // Spawn queue — aliens appear gradually, not all at once
  final List<_Alien> _spawnQueue = [];
  double _spawnTimer = 0;

  // Between-wave auto-transition (no pause/button press needed)
  bool _betweenWaves = false;
  double _betweenWaveTimer = 0;

  // Asteroid timer
  double _asteroidSpawnTimer = 3.0;

  // Game state
  bool _isRunning = false;
  bool _isDead = false;
  int _score = 0;
  int _wave = 1;
  int _bestScore = 0;

  Timer? _ticker;
  DateTime? _lastTick;
  late final List<_Star> _stars;

  @override
  void initState() {
    super.initState();
    _saldo = widget.currentSaldo;
    _stars = List.generate(40, (_) => _Star(_rng));
    _buildSpawnQueue(_wave);
    widget.controller.addListener(_onControllerEvent);
    HighScoreService.load('shooter').then((v) { if (mounted) setState(() => _bestScore = v); });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    widget.controller.removeListener(_onControllerEvent);
    super.dispose();
  }

  void _onControllerEvent() {
    final event = widget.controller.lastEvent;
    if (event == null || !event.isDown) return;
    final btn = event.button;

    if (_isDead) {
      if (btn == ArcadeButton.a || btn == ArcadeButton.start) _restart();
      return;
    }
    if (!_isRunning) {
      _startGame();
    }
  }

  void _startGame() {
    if (_isRunning) return;
    setState(() => _isRunning = true);
    _lastTick = DateTime.now();
    _ticker = Timer.periodic(const Duration(milliseconds: 16), _tick);
  }

  void _tick(Timer t) {
    if (!mounted) return;
    final now = DateTime.now();
    final dt =
        (now.difference(_lastTick!).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _lastTick = now;
    if (_isDead) return;
    _update(dt);
    if (mounted) setState(() {});
  }

  void _update(double dt) {
    // ── Between-wave countdown (auto-transition, no player input needed) ──────
    if (_betweenWaves) {
      _betweenWaveTimer -= dt;
      if (_betweenWaveTimer <= 0) {
        _betweenWaves = false;
        _startNextWave();
      }
      return; // pause gameplay during transition
    }

    // ── Ship movement ──────────────────────────────────────────────────────────
    if (widget.controller.isHeld(ArcadeButton.left)) _sx -= kShipSpeed * dt;
    if (widget.controller.isHeld(ArcadeButton.right)) _sx += kShipSpeed * dt;
    if (widget.controller.isHeld(ArcadeButton.up)) _sy -= kShipSpeed * dt;
    if (widget.controller.isHeld(ArcadeButton.down)) _sy += kShipSpeed * dt;
    _sx = _sx.clamp(0, kW - kShipW);
    _sy = _sy.clamp(kShipMinY, kH - kShipH - 0.2);

    // ── Firing ──────────────────────────────────────────────────────────────────
    _fireCooldown -= dt;
    _specialCooldown -= dt;
    if (_fireCooldown < 0) _fireCooldown = 0;
    if (_specialCooldown < 0) _specialCooldown = 0;

    if (widget.controller.isHeld(ArcadeButton.a) && _fireCooldown <= 0) {
      _fireNormal();
    }
    if (widget.controller.isHeld(ArcadeButton.x) &&
        _specialAmmo > 0 &&
        _specialCooldown <= 0) {
      _fireSpecial();
    }

    // ── Spawn queue ─────────────────────────────────────────────────────────────
    _spawnTimer -= dt;
    if (_spawnTimer <= 0 && _spawnQueue.isNotEmpty) {
      _spawnTimer = kSpawnInterval;
      _aliens.add(_spawnQueue.removeAt(0));
    }

    // ── Bullet movement ─────────────────────────────────────────────────────────
    for (final b in _bullets) {
      if (!b.alive) continue;
      if (b.isMissile) {
        final dx = (_sx + kShipW / 2) - b.x;
        final dy = (_sy + kShipH / 2) - b.y;
        final dist = sqrt(dx * dx + dy * dy);
        if (dist > 0.1) {
          b.vx += (dx / dist) * kMissileSpeed * dt * 4;
          b.vy += (dy / dist) * kMissileSpeed * dt * 4;
          final spd = sqrt(b.vx * b.vx + b.vy * b.vy);
          if (spd > kMissileSpeed) {
            b.vx = b.vx / spd * kMissileSpeed;
            b.vy = b.vy / spd * kMissileSpeed;
          }
        }
        b.x += b.vx * dt;
        b.y += b.vy * dt;
        if (b.x < -2 || b.x > kW + 2 || b.y < -2 || b.y > kH + 2) {
          b.alive = false;
        }
      } else if (b.isPlayer) {
        b.x += b.vx * dt;
        b.y -= kBulletSpeed * dt;
        if (b.y < -1 || b.x < -1 || b.x > kW + 1) b.alive = false;
      } else {
        b.x += b.vx * dt;
        b.y += (b.vy > 0 ? b.vy : kEnemyBulletSpeed) * dt;
        if (b.y > kH + 1 || b.x < -1 || b.x > kW + 1) b.alive = false;
      }
    }
    _bullets.removeWhere((b) => !b.alive);

    // ── Alien movement (each alien moves independently) ─────────────────────────
    for (final a in _aliens) {
      if (!a.alive) continue;

      a.dirChangeTimer -= dt;
      if (a.dirChangeTimer <= 0) {
        a.dirChangeTimer = 1.0 + _rng.nextDouble() * 2.0;
        a.vx = (_rng.nextDouble() - 0.5) * 3.5;
        a.vy = 0.15 + _rng.nextDouble() * 0.7;
      }

      a.x += a.vx * dt;
      a.y += a.vy * dt;

      if (a.x < 0) {
        a.x = 0;
        a.vx = a.vx.abs();
      }
      if (a.x > kW - 1.0) {
        a.x = kW - 1.0;
        a.vx = -a.vx.abs();
      }
      if (a.y < 0.2) a.y = 0.2;

      // Alien breaches the player zone → costs a life (not instant game-over)
      if (a.y > kShipMinY - 0.3) {
        a.alive = false;
        HapticFeedback.heavyImpact();
        _hitShip(); // handles invincibility, life deduction, and game-over when lives = 0
        if (_isDead) return;
        continue;
      }

      // Burst sub-shots
      if (a.burstCount > 0) {
        a.burstTimer -= dt;
        if (a.burstTimer <= 0) {
          a.burstTimer = 0.15;
          a.burstCount--;
          _bullets.add(_Bullet(a.x + 0.5, a.y + 0.8, isPlayer: false));
        }
        continue;
      }

      a.fireTimer -= dt;
      if (a.fireTimer <= 0) {
        a.fireTimer = _fireRateForWave();
        _alienFire(a);
      }
    }

    // ── Asteroids ───────────────────────────────────────────────────────────────
    _asteroidSpawnTimer -= dt;
    if (_asteroidSpawnTimer <= 0) {
      _asteroidSpawnTimer = 2.0 + _rng.nextDouble() * 3.0;
      final r = 0.3 + _rng.nextDouble() * 0.4;
      _asteroids.add(_Asteroid(
          _rng.nextDouble() * (kW - r * 2) + r,
          -r,
          2.0 + _rng.nextDouble() * 2.0,
          r));
    }
    for (final ast in _asteroids) {
      if (!ast.alive) continue;
      ast.y += ast.vy * dt;
      ast.rot += ast.rotV * dt;
      if (ast.y > kH + 1) ast.alive = false;
    }
    _asteroids.removeWhere((a) => !a.alive);

    // ── Pickups ─────────────────────────────────────────────────────────────────
    for (final p in _pickups) {
      if (!p.alive) continue;
      p.y += p.vy * dt;
      if (p.y > kH + 1) p.alive = false;
    }

    // ── Invincibility ───────────────────────────────────────────────────────────
    if (_invincible) {
      _invTimer -= dt;
      if (_invTimer <= 0) _invincible = false;
    }

    // ── Collisions: player bullets → aliens ─────────────────────────────────────
    for (final b in _bullets.where((b) => b.alive && b.isPlayer)) {
      for (final a in _aliens.where((a) => a.alive)) {
        if (b.x > a.x &&
            b.x < a.x + 1.0 &&
            b.y > a.y &&
            b.y < a.y + 0.8) {
          a.hp--;
          b.alive = false;
          if (a.hp <= 0) {
            a.alive = false;
            _score += _scoreForType(a.type);
            HapticFeedback.lightImpact();
            _maybeDropPickup(a);
          }
          break;
        }
      }
    }

    // ── Collisions: player bullets → asteroids ───────────────────────────────────
    for (final b in _bullets.where((b) => b.alive && b.isPlayer)) {
      for (final ast in _asteroids.where((ast) => ast.alive)) {
        final dx = b.x - ast.x, dy = b.y - ast.y;
        if (sqrt(dx * dx + dy * dy) < ast.radius + 0.15) {
          ast.alive = false;
          b.alive = false;
          _score += 25;
          break;
        }
      }
    }

    // ── Collisions: enemy projectiles → ship ────────────────────────────────────
    if (!_invincible) {
      for (final b in _bullets.where((b) => b.alive && !b.isPlayer)) {
        if (b.x > _sx &&
            b.x < _sx + kShipW &&
            b.y > _sy &&
            b.y < _sy + kShipH) {
          b.alive = false;
          _hitShip(bypassShield: b.isMissile);
          if (_isDead) return;
        }
      }
      for (final ast in _asteroids.where((ast) => ast.alive)) {
        final dx = ast.x - (_sx + kShipW / 2), dy = ast.y - (_sy + kShipH / 2);
        if (sqrt(dx * dx + dy * dy) < ast.radius + 0.4) {
          ast.alive = false;
          _hitShip();
          if (_isDead) return;
        }
      }
    }

    // ── Pickup collection ────────────────────────────────────────────────────────
    for (final p in _pickups.where((p) => p.alive)) {
      if (p.x + 0.6 > _sx &&
          p.x - 0.1 < _sx + kShipW &&
          p.y + 0.6 > _sy &&
          p.y - 0.1 < _sy + kShipH) {
        p.alive = false;
        _collectPickup(p.type);
      }
    }
    _pickups.removeWhere((p) => !p.alive);

    // ── Wave complete? → auto-advance, no pause required ─────────────────────────
    // Guard: _aliens must be non-empty (vacuous true for empty list would false-trigger)
    if (_spawnQueue.isEmpty &&
        _aliens.isNotEmpty &&
        _aliens.every((a) => !a.alive)) {
      _waveComplete();
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  // All enemy types now fire a burst of 3 every ~1 s, decreasing with wave
  double _fireRateForWave() => (1.2 - _wave * 0.08).clamp(0.38, 1.2);

  void _alienFire(_Alien a) {
    switch (a.type) {
      case _AlienType.basic:
        // Basic: 50% single shot, 50% burst of 3
        _bullets.add(_Bullet(a.x + 0.5, a.y + 0.8, isPlayer: false));
        a.burstCount = _rng.nextDouble() < 0.5 ? 0 : 2;
        a.burstTimer = 0.12;
        break;
      case _AlienType.burst:
        // Burst: 30% single shot, 70% burst of 3
        _bullets.add(_Bullet(a.x + 0.5, a.y + 0.8, isPlayer: false));
        a.burstCount = _rng.nextDouble() < 0.3 ? 0 : 2;
        a.burstTimer = 0.10;
        break;
      case _AlienType.scatter:
        for (int i = -2; i <= 2; i++) {
          final angle = pi / 2 + i * 0.28;
          _bullets.add(_Bullet(
            a.x + 0.5, a.y + 0.8,
            isPlayer: false,
            vx: cos(angle) * kEnemyBulletSpeed * 0.45,
            vy: sin(angle) * kEnemyBulletSpeed * 0.55,
          ));
        }
        break;
      case _AlienType.missile:
        _bullets.add(_Bullet(a.x + 0.5, a.y + 0.8,
            isPlayer: false, isMissile: true, vx: 0, vy: kMissileSpeed));
        break;
    }
  }

  void _fireNormal() {
    _fireCooldown = kFireCooldown;
    _bullets.add(_Bullet(_sx + kShipW / 2, _sy, isPlayer: true));
    HapticFeedback.selectionClick();
  }

  void _fireSpecial() {
    _specialCooldown = kSpecialCooldown;
    _specialAmmo--;
    for (int i = -1; i <= 1; i++) {
      _bullets.add(_Bullet(_sx + kShipW / 2, _sy,
          isPlayer: true, vx: i * 2.8, vy: 0));
    }
    HapticFeedback.mediumImpact();
  }

  void _hitShip({bool bypassShield = false}) {
    if (!bypassShield && _shieldHits > 0) {
      _shieldHits--;
      HapticFeedback.mediumImpact();
      _invincible = true;
      _invTimer = 0.5;
      return;
    }
    _lives--;
    HapticFeedback.heavyImpact();
    if (_lives <= 0) {
      _triggerDeath();
    } else {
      _invincible = true;
      _invTimer = 2.0;
    }
  }

  void _triggerDeath() {
    _ticker?.cancel();
    HighScoreService.submit('shooter', _score).then((isNew) {
      if (isNew && mounted) setState(() => _bestScore = _score);
    });
    if (mounted) setState(() { _isDead = true; _isRunning = false; });
  }

  /// Called when all aliens in the current wave are defeated.
  /// Awards saldo, then auto-starts the next wave after a short delay.
  void _waveComplete() {
    _score += 200;
    _betweenWaves = true;
    _betweenWaveTimer = kBetweenWaveDuration;
    _awardWaveSaldo();
  }

  Future<void> _awardWaveSaldo() async {
    if (_awardingPoints) return;
    _awardingPoints = true;
    final newSaldo = _saldo + 1.0;
    await _updateFirestore(newSaldo);
    if (mounted) {
      setState(() => _saldo = newSaldo);
      widget.onSaldoChanged(newSaldo);
    }
    _awardingPoints = false;
  }

  void _startNextWave() {
    _wave++;
    _buildSpawnQueue(_wave);
    _bullets.clear();
    _pickups.clear();
    if (_wave == 3) _specialAmmo += 5;
    else if (_wave > 3) _specialAmmo += 2;
  }

  void _maybeDropPickup(_Alien a) {
    final roll = _rng.nextDouble();
    if (_wave % 10 == 0 && roll < 0.22) {
      _pickups.add(_Pickup(a.x + 0.3, a.y, type: _PickupType.heart));
    } else if (roll < 0.09) {
      _pickups.add(_Pickup(a.x + 0.3, a.y, type: _PickupType.shield));
    } else if (roll < 0.17 && _wave >= 2) {
      _pickups.add(_Pickup(a.x + 0.3, a.y, type: _PickupType.specialAmmo));
    }
  }

  void _collectPickup(_PickupType type) {
    switch (type) {
      case _PickupType.shield:
        _shieldHits = (_shieldHits + 2).clamp(0, 4);
        break;
      case _PickupType.specialAmmo:
        _specialAmmo += 3;
        break;
      case _PickupType.heart:
        _lives++;
        break;
    }
    HapticFeedback.lightImpact();
  }

  int _scoreForType(_AlienType type) {
    switch (type) {
      case _AlienType.basic: return 100;
      case _AlienType.burst: return 150;
      case _AlienType.scatter: return 200;
      case _AlienType.missile: return 300;
    }
  }

  void _buildSpawnQueue(int wave) {
    _spawnQueue.clear();
    _aliens.clear();
    final count = 5 + wave * 2;
    for (int i = 0; i < count; i++) {
      final x = _rng.nextDouble() * (kW - 1.5) + 0.25;
      final y = 0.5 + _rng.nextDouble() * 3.5;
      _AlienType type;
      final r = _rng.nextDouble();
      if (wave >= 5 && r < 0.15) {
        type = _AlienType.missile;
      } else if (wave >= 3 && r < 0.30) {
        type = _AlienType.scatter;
      } else if (wave >= 2 && r < 0.55) {
        type = _AlienType.burst;
      } else {
        type = _AlienType.basic;
      }
      _spawnQueue.add(_Alien(x, y, type: type));
    }
    _spawnTimer = 0;
  }

  void _restart() {
    _wave = 1;
    _score = 0;
    _lives = 3;
    _shieldHits = 0;
    _specialAmmo = 0;
    _sx = 4.4; _sy = 13.5;
    _bullets.clear();
    _asteroids.clear();
    _pickups.clear();
    _invincible = false;
    _betweenWaves = false;
    _buildSpawnQueue(1);
    setState(() { _isDead = false; _isRunning = false; });
    _startGame();
  }

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
      debugPrint('Shooter Firestore error: $e');
    }
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, cons) {
      return Stack(children: [
        CustomPaint(
          painter: _ShooterPainter(
            stars: _stars,
            aliens: _aliens,
            asteroids: _asteroids,
            bullets: _bullets,
            pickups: _pickups,
            sx: _sx, sy: _sy,
            invincible: _invincible,
            shieldHits: _shieldHits,
            kW: kW, kH: kH,
          ),
          child: SizedBox(width: cons.maxWidth, height: cons.maxHeight),
        ),
        // HUD
        Positioned(
          top: 4, left: 4, right: 4,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _chip('❤️ $_lives'),
              if (_shieldHits > 0) _chip('🛡 $_shieldHits'),
              _chip('⭐ $_score'),
              if (_specialAmmo > 0) _chip('🔥 $_specialAmmo'),
              _chip('Ola $_wave'),
            ],
          ),
        ),
        // Between-wave banner (non-blocking — game continues behind it)
        if (_betweenWaves)
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              color: Colors.black54,
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                '✨ ¡Ola $_wave completada! +200 pts  •  Siguiente en ${_betweenWaveTimer.ceil()}s…',
                style: const TextStyle(
                  color: Colors.cyanAccent,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        if (!_isRunning && !_isDead) _buildStartOverlay(),
        if (_isDead) _buildDeathOverlay(),
      ]);
    });
  }

  Widget _chip(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
            color: Colors.black54, borderRadius: BorderRadius.circular(8)),
        child: Text(t,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold)),
      );

  Widget _buildStartOverlay() => Positioned.fill(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF020218), Color(0xFF04042A)],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🚀', style: TextStyle(fontSize: 60)),
            const SizedBox(height: 8),
            const Text('CAZA ESTELAR',
                style: TextStyle(
                    color: Color(0xFF44EEFF),
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 6,
                    shadows: [Shadow(color: Color(0xFF0088FF), blurRadius: 12)])),
            const SizedBox(height: 4),
            const Text('★ ★ ★ ★ ★',
                style: TextStyle(color: Color(0xFF224488), fontSize: 10, letterSpacing: 6)),
            const SizedBox(height: 22),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 28),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                border: Border.all(color: const Color(0xFF224488), width: 1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Column(children: [
                Text('D-pad: mover nave',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
                SizedBox(height: 4),
                Text('A: disparar  •  X: disparo especial',
                    style: TextStyle(color: Colors.white54, fontSize: 11)),
                SizedBox(height: 6),
                Text('+1 PTO REAL POR OLA COMPLETADA',
                    style: TextStyle(
                        color: Color(0xFFFFDD44),
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ]),
            ),
            const SizedBox(height: 20),
            const Text('Los enemigos también disparan — ¡esquívalos!',
                style: TextStyle(color: Color(0xFF445577), fontSize: 10)),
            const SizedBox(height: 4),
            const Text('SELECT para volver al menú',
                style: TextStyle(color: Color(0xFF223344), fontSize: 10)),
          ],
        ),
      ),
    );

  Widget _buildDeathOverlay() => Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [const Color(0xDD020218), Colors.black.withOpacity(0.92)],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('💥', style: TextStyle(fontSize: 56)),
            const Text('NAVE DESTRUIDA',
                style: TextStyle(
                    color: Color(0xFFFF4400),
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 3)),
            const SizedBox(height: 4),
            const Text('Los alienígenas han ganado esta ronda',
                style: TextStyle(color: Color(0xFF664422), fontSize: 10)),
            const SizedBox(height: 16),
            Text('Puntuación: $_score',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            Text('Ola alcanzada: $_wave',
                style: const TextStyle(color: Color(0xFF44EEFF), fontSize: 13)),
            if (_bestScore > 0)
              Text('Récord: $_bestScore',
                  style: const TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 13,
                      fontWeight: FontWeight.bold)),
            const SizedBox(height: 22),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _restart,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0066AA),
                      foregroundColor: Colors.white,
                      shape: const StadiumBorder()),
                  child: const Text('Relanzar nave',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ),
            const SizedBox(height: 6),
            const Text('SELECT para volver al menú',
                style: TextStyle(color: Color(0xFF223344), fontSize: 10)),
          ],
        ),
      ),
    );
}

// ─── Star helper ─────────────────────────────────────────────────────────────

class _Star {
  final double x, y, r, opacity;
  _Star(Random rng)
      : x = rng.nextDouble() * 10,
        y = rng.nextDouble() * 16,
        r = 0.04 + rng.nextDouble() * 0.08,
        opacity = 0.4 + rng.nextDouble() * 0.6;
}

// ─── Painter ─────────────────────────────────────────────────────────────────

class _ShooterPainter extends CustomPainter {
  final List<_Star> stars;
  final List<_Alien> aliens;
  final List<_Asteroid> asteroids;
  final List<_Bullet> bullets;
  final List<_Pickup> pickups;
  final double sx, sy;
  final bool invincible;
  final int shieldHits;
  final int kW, kH;

  static const double kShipW = 1.2;
  static const double kShipH = 1.0;

  const _ShooterPainter({
    required this.stars,
    required this.aliens,
    required this.asteroids,
    required this.bullets,
    required this.pickups,
    required this.sx,
    required this.sy,
    required this.invincible,
    required this.shieldHits,
    required this.kW,
    required this.kH,
  });

  double wx(double x, double cs) => x * cs;
  double wy(double y, double cs) => y * cs;

  @override
  void paint(Canvas canvas, Size size) {
    final cs = size.width / kW;

    // Background
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = const Color(0xFF020818));
    canvas.drawCircle(
      Offset(size.width * 0.3, size.height * 0.4),
      size.width * 0.5,
      Paint()
        ..color = const Color(0xFF0D1B4B).withOpacity(0.6)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30),
    );

    // Stars
    for (final s in stars) {
      canvas.drawCircle(Offset(wx(s.x, cs), wy(s.y, cs)), s.r * cs,
          Paint()..color = Colors.white.withOpacity(s.opacity));
    }

    // Pickups
    for (final p in pickups.where((p) => p.alive)) {
      _drawPickup(canvas, cs, p);
    }

    // Player bullets
    final pBulletPaint = Paint()..color = const Color(0xFF00E5FF);
    for (final b in bullets.where((b) => b.alive && b.isPlayer)) {
      canvas.drawRect(
          Rect.fromLTWH(
              wx(b.x - 0.07, cs), wy(b.y - 0.25, cs), cs * 0.14, cs * 0.5),
          pBulletPaint);
      canvas.drawCircle(
        Offset(wx(b.x, cs), wy(b.y, cs)), cs * 0.12,
        Paint()
          ..color = const Color(0xFF00E5FF).withOpacity(0.4)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }

    // Enemy bullets / missiles
    for (final b in bullets.where((b) => b.alive && !b.isPlayer)) {
      if (b.isMissile) {
        canvas.drawOval(
            Rect.fromLTWH(wx(b.x - 0.12, cs), wy(b.y - 0.2, cs),
                cs * 0.24, cs * 0.45),
            Paint()..color = const Color(0xFFFF6D00));
        canvas.drawCircle(
          Offset(wx(b.x, cs), wy(b.y, cs)), cs * 0.18,
          Paint()
            ..color = const Color(0xFFFF6D00).withOpacity(0.4)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
      } else {
        canvas.drawOval(
            Rect.fromLTWH(wx(b.x - 0.1, cs), wy(b.y - 0.15, cs),
                cs * 0.2, cs * 0.35),
            Paint()..color = const Color(0xFFFF4444));
      }
    }

    // Asteroids
    for (final ast in asteroids.where((a) => a.alive)) {
      canvas.save();
      canvas.translate(wx(ast.x, cs), wy(ast.y, cs));
      canvas.rotate(ast.rot);
      _drawAsteroid(canvas, cs, ast.radius);
      canvas.restore();
    }

    // Aliens
    for (final a in aliens.where((a) => a.alive)) {
      _drawAlien(canvas, cs, a);
    }

    // Ship (blinks when invincible)
    if (!invincible || (DateTime.now().millisecondsSinceEpoch ~/ 100).isEven) {
      _drawShip(canvas, cs);
    }

    // Shield ring
    if (shieldHits > 0) {
      canvas.drawCircle(
        Offset(wx(sx + kShipW / 2, cs), wy(sy + kShipH / 2, cs)), cs * 0.85,
        Paint()
          ..color = Colors.cyanAccent.withOpacity(0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      canvas.drawCircle(
        Offset(wx(sx + kShipW / 2, cs), wy(sy + kShipH / 2, cs)), cs * 0.85,
        Paint()
          ..color = Colors.cyanAccent.withOpacity(0.1)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }

    // Player zone separator
    canvas.drawRect(Rect.fromLTWH(0, wy(8.8, cs), size.width, 1),
        Paint()..color = Colors.white12);
  }

  void _drawPickup(Canvas canvas, double cs, _Pickup p) {
    final px = wx(p.x, cs);
    final py = wy(p.y, cs);
    final sz = cs * 0.55;
    Color glowColor;
    String symbol;
    switch (p.type) {
      case _PickupType.shield:
        glowColor = Colors.cyanAccent;
        symbol = '🛡';
        break;
      case _PickupType.specialAmmo:
        glowColor = Colors.orange;
        symbol = '🔥';
        break;
      case _PickupType.heart:
        glowColor = Colors.pinkAccent;
        symbol = '❤';
        break;
    }
    canvas.drawCircle(
      Offset(px + sz / 2, py + sz / 2), sz * 0.7,
      Paint()
        ..color = glowColor.withOpacity(0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    final tp = TextPainter(
      text: TextSpan(text: symbol, style: TextStyle(fontSize: sz * 1.1)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(px, py));
  }

  void _drawShip(Canvas canvas, double cs) {
    final shipX = wx(sx, cs);
    final shipY = wy(sy, cs);
    final sw = kShipW * cs;
    final sh = kShipH * cs;

    canvas.drawCircle(
      Offset(shipX + sw / 2, shipY + sh), cs * 0.28,
      Paint()
        ..color = const Color(0xFFFF8C00).withOpacity(0.7)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    final hull = Path()
      ..moveTo(shipX + sw / 2, shipY)
      ..lineTo(shipX + sw, shipY + sh * 0.7)
      ..lineTo(shipX + sw * 0.65, shipY + sh)
      ..lineTo(shipX + sw * 0.35, shipY + sh)
      ..lineTo(shipX, shipY + sh * 0.7)
      ..close();
    canvas.drawPath(hull, Paint()..color = const Color(0xFF1565C0));
    canvas.drawOval(
        Rect.fromLTWH(shipX + sw * 0.3, shipY + sh * 0.15, sw * 0.4, sh * 0.4),
        Paint()..color = const Color(0xFF00E5FF).withOpacity(0.8));
    canvas.drawRect(
        Rect.fromLTWH(shipX, shipY + sh * 0.6, sw * 0.3, sh * 0.15),
        Paint()..color = const Color(0xFF42A5F5));
    canvas.drawRect(
        Rect.fromLTWH(shipX + sw * 0.7, shipY + sh * 0.6, sw * 0.3, sh * 0.15),
        Paint()..color = const Color(0xFF42A5F5));
  }

  void _drawAlien(Canvas canvas, double cs, _Alien a) {
    final ax = wx(a.x, cs);
    final ay = wy(a.y, cs);
    final aw = cs * 1.0;
    final ah = cs * 0.8;

    Color color;
    switch (a.type) {
      case _AlienType.basic:   color = const Color(0xFF69F0AE); break;
      case _AlienType.burst:   color = const Color(0xFFE040FB); break;
      case _AlienType.scatter: color = const Color(0xFFFF6D00); break;
      case _AlienType.missile: color = const Color(0xFFFF1744); break;
    }

    canvas.drawOval(
        Rect.fromLTWH(ax, ay + ah * 0.3, aw, ah * 0.7), Paint()..color = color);
    canvas.drawOval(Rect.fromLTWH(ax + aw * 0.2, ay, aw * 0.6, ah * 0.6),
        Paint()..color = color.withOpacity(0.6));
    canvas.drawCircle(Offset(ax + aw * 0.35, ay + ah * 0.55), cs * 0.07,
        Paint()..color = Colors.black);
    canvas.drawCircle(Offset(ax + aw * 0.65, ay + ah * 0.55), cs * 0.07,
        Paint()..color = Colors.black);
    canvas.drawOval(
      Rect.fromLTWH(ax - 1, ay + ah * 0.3 - 1, aw + 2, ah * 0.7 + 2),
      Paint()
        ..color = color.withOpacity(0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    if (a.hp > 1) {
      for (int i = 0; i < a.hp; i++) {
        canvas.drawCircle(
          Offset(ax + aw * (0.25 + i * 0.25), ay - cs * 0.1),
          cs * 0.065,
          Paint()..color = color,
        );
      }
    }
  }

  void _drawAsteroid(Canvas canvas, double cs, double radius) {
    final r = radius * cs;
    final path = Path();
    const sides = 8;
    for (int i = 0; i < sides; i++) {
      final angle = i * 2 * pi / sides;
      final jitter = 0.7 + (i * 37 % 7) * 0.05;
      final x = cos(angle) * r * jitter;
      final y = sin(angle) * r * jitter;
      if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = const Color(0xFF78909C));
    canvas.drawPath(path,
        Paint()
          ..color = const Color(0xFF90A4AE)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(_ShooterPainter old) => true;
}
