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
  static const double kSpawnInterval = 0.50;
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
  bool _paused = false;
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
      return;
    }
    if (btn == ArcadeButton.start && !_betweenWaves) {
      setState(() => _paused = !_paused);
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
    if (_isDead || _paused) return;
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
          top: 6, left: 6, right: 6,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _livesHud(_lives),
              if (_shieldHits > 0) _neonPill('🛡 $_shieldHits', _kCyan),
              _scoreHud(_score),
              if (_specialAmmo > 0) _neonPill('🔥 $_specialAmmo', const Color(0xFFFF9800)),
              _waveHud(_wave),
            ],
          ),
        ),
        // Between-wave banner
        if (_betweenWaves)
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [const Color(0xDD000820), const Color(0xCC001040), const Color(0xDD000820)],
                ),
              ),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '¡OLA $_wave COMPLETADA!  +200 PTS',
                    style: const TextStyle(
                      color: Color(0xFF00FFD4),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                      shadows: [Shadow(color: Color(0xFF00FFD4), blurRadius: 10)],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    'SIGUIENTE OLA EN ${_betweenWaveTimer.ceil()}s…',
                    style: const TextStyle(
                      color: Color(0xFF4488BB),
                      fontSize: 9,
                      letterSpacing: 1,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        if (!_isRunning && !_isDead) _buildStartOverlay(),
        if (_isDead) _buildDeathOverlay(),
        if (_paused && _isRunning) _buildPauseOverlay(),
      ]);
    });
  }

  static const _kCyan = Color(0xFF00E5FF);
  static const _kMagenta = Color(0xFFE040FB);

  Widget _neonPill(String t, Color color, {double fontSize = 10, double letterSpacing = 0, double blurRadius = 6}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          border: Border.all(color: color.withOpacity(0.6), width: 1),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [BoxShadow(color: color.withOpacity(0.25), blurRadius: blurRadius)],
        ),
        child: Text(t,
            style: TextStyle(
                color: color,
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
                letterSpacing: letterSpacing,
                shadows: [Shadow(color: color, blurRadius: blurRadius)])),
      );

  Widget _livesHud(int lives) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(lives, (_) => Padding(
          padding: const EdgeInsets.only(right: 2),
          child: _miniShipIcon(),
        )),
      );

  Widget _miniShipIcon() => CustomPaint(
        size: const Size(14, 14),
        painter: _MiniShipPainter(),
      );

  Widget _scoreHud(int score) => _neonPill('$score', _kCyan, fontSize: 11, letterSpacing: 1, blurRadius: 8);

  Widget _waveHud(int wave) => _neonPill('OLA $wave', _kMagenta, letterSpacing: 1);

  Widget _buildStartOverlay() => Positioned.fill(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF010115), Color(0xFF02022A), Color(0xFF010115)],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Ship icon
            CustomPaint(size: const Size(60, 60), painter: _LargeShipPainter()),
            const SizedBox(height: 12),
            // Title with glow
            const Text('CAZA ESTELAR',
                style: TextStyle(
                    color: Color(0xFF00E5FF),
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 5,
                    shadows: [
                      Shadow(color: Color(0xFF00E5FF), blurRadius: 16),
                      Shadow(color: Color(0xFF0066FF), blurRadius: 30),
                    ])),
            const SizedBox(height: 4),
            const Text('S P A C E   S H O O T E R',
                style: TextStyle(color: Color(0xFF224488), fontSize: 9, letterSpacing: 4)),
            const SizedBox(height: 20),
            // Stat card
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [const Color(0xFF00E5FF).withOpacity(0.05), const Color(0xFF0066FF).withOpacity(0.05)],
                ),
                border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.3), width: 1),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: const Color(0xFF00E5FF).withOpacity(0.1), blurRadius: 12)],
              ),
              child: const Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('D-pad ', style: TextStyle(color: Color(0xFF00E5FF), fontSize: 11, fontWeight: FontWeight.bold)),
                  Text('mover nave', style: TextStyle(color: Colors.white70, fontSize: 11)),
                ]),
                SizedBox(height: 5),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('A ', style: TextStyle(color: Color(0xFF69F0AE), fontSize: 11, fontWeight: FontWeight.bold)),
                  Text('disparar  ', style: TextStyle(color: Colors.white70, fontSize: 11)),
                  Text('X ', style: TextStyle(color: Color(0xFFFF9800), fontSize: 11, fontWeight: FontWeight.bold)),
                  Text('especial', style: TextStyle(color: Colors.white70, fontSize: 11)),
                ]),
                SizedBox(height: 8),
                Text('+1 PTO REAL POR OLA COMPLETADA',
                    style: TextStyle(
                        color: Color(0xFFFFDD00),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                        shadows: [Shadow(color: Color(0xFFFFDD00), blurRadius: 8)])),
              ]),
            ),
            const SizedBox(height: 18),
            // Pill button
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 9),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF0044BB), Color(0xFF0099EE)]),
                borderRadius: BorderRadius.circular(30),
                boxShadow: [BoxShadow(color: const Color(0xFF00AAFF).withOpacity(0.4), blurRadius: 12)],
              ),
              child: const Text('PRESIONA CUALQUIER BOTÓN',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1)),
            ),
            const SizedBox(height: 10),
            const Text('Los enemigos también disparan — ¡esquívalos!',
                style: TextStyle(color: Color(0xFF334466), fontSize: 9)),
            const SizedBox(height: 3),
            const Text('SELECT para volver al menú',
                style: TextStyle(color: Color(0xFF223344), fontSize: 9)),
          ],
        ),
      ),
    );

  Widget _buildDeathOverlay() => Positioned.fill(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xEE0A0018), Color(0xEE200008), Color(0xEE0A0018)],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Explosion burst visual
            CustomPaint(size: const Size(64, 64), painter: _ExplosionIconPainter()),
            const SizedBox(height: 10),
            const Text('NAVE DESTRUIDA',
                style: TextStyle(
                    color: Color(0xFFFF3030),
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 3,
                    shadows: [
                      Shadow(color: Color(0xFFFF3030), blurRadius: 16),
                      Shadow(color: Color(0xFFFF0000), blurRadius: 30),
                    ])),
            const SizedBox(height: 4),
            const Text('Los alienígenas han ganado esta ronda',
                style: TextStyle(color: Color(0xFF663333), fontSize: 10)),
            const SizedBox(height: 18),
            // Stat cards row
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _statCard('PUNTOS', '$_score', const Color(0xFF00E5FF)),
                const SizedBox(width: 10),
                _statCard('OLA', '$_wave', const Color(0xFFE040FB)),
                if (_bestScore > 0) ...[
                  const SizedBox(width: 10),
                  _statCard('RÉCORD', '$_bestScore', const Color(0xFFFFD700)),
                ],
              ],
            ),
            const SizedBox(height: 22),
            // Restart pill button
            GestureDetector(
              onTap: _restart,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF880022), Color(0xFFCC0044)]),
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [BoxShadow(color: const Color(0xFFFF0044).withOpacity(0.4), blurRadius: 14)],
                ),
                child: const Text('RELANZAR NAVE',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2)),
              ),
            ),
            const SizedBox(height: 8),
            const Text('SELECT para volver al menú',
                style: TextStyle(color: Color(0xFF223344), fontSize: 9)),
          ],
        ),
      ),
    );

  Widget _statCard(String label, String value, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          border: Border.all(color: color.withOpacity(0.4), width: 1),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [BoxShadow(color: color.withOpacity(0.2), blurRadius: 8)],
        ),
        child: Column(
          children: [
            Text(label, style: TextStyle(color: color.withOpacity(0.7), fontSize: 8, letterSpacing: 1)),
            Text(value,
                style: TextStyle(
                    color: color,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    shadows: [Shadow(color: color, blurRadius: 8)])),
          ],
        ),
      );

  Widget _buildPauseOverlay() => Positioned.fill(
    child: Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [const Color(0xCC000820), const Color(0xDD000010), const Color(0xCC000820)],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.5), width: 2),
              boxShadow: [BoxShadow(color: const Color(0xFF00E5FF).withOpacity(0.2), blurRadius: 16)],
            ),
            child: const Text('II',
                style: TextStyle(
                    color: Color(0xFF00E5FF),
                    fontSize: 28,
                    fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 14),
          const Text('PAUSA',
              style: TextStyle(
                  color: Color(0xFF00E5FF),
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 8,
                  shadows: [Shadow(color: Color(0xFF00E5FF), blurRadius: 16)])),
          const SizedBox(height: 14),
          const Text('START para continuar',
              style: TextStyle(color: Color(0xFF4488AA), fontSize: 12, letterSpacing: 1)),
        ],
      ),
    ),
  );
}

// ─── Star helper ─────────────────────────────────────────────────────────────

class _Star {
  final double x, y, r, opacity;
  final bool isBright; // bright stars get a subtle cross-sparkle
  _Star(Random rng)
      : x = rng.nextDouble() * 10,
        y = rng.nextDouble() * 16,
        r = 0.03 + rng.nextDouble() * 0.10,
        opacity = 0.35 + rng.nextDouble() * 0.65,
        isBright = rng.nextDouble() < 0.15;
}

// ─── Mini ship HUD icon painter ───────────────────────────────────────────────

class _MiniShipPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    // Engine glow
    canvas.drawCircle(
      Offset(w * 0.5, h * 0.85),
      w * 0.22,
      Paint()
        ..color = const Color(0xFFFF6600).withOpacity(0.7)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    // Hull
    final hull = Path()
      ..moveTo(w * 0.5, 0)
      ..lineTo(w * 0.92, h * 0.72)
      ..lineTo(w * 0.68, h)
      ..lineTo(w * 0.32, h)
      ..lineTo(w * 0.08, h * 0.72)
      ..close();
    canvas.drawPath(hull, Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF00AAFF), Color(0xFF003388)],
      ).createShader(Rect.fromLTWH(0, 0, w, h)));
    // Wing accents
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.08, h * 0.72)
        ..lineTo(0, h * 0.9)
        ..lineTo(w * 0.32, h)
        ..close(),
      Paint()..color = const Color(0xFF0055CC),
    );
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.92, h * 0.72)
        ..lineTo(w, h * 0.9)
        ..lineTo(w * 0.68, h)
        ..close(),
      Paint()..color = const Color(0xFF0055CC),
    );
    // Cockpit
    canvas.drawOval(
      Rect.fromLTWH(w * 0.32, h * 0.14, w * 0.36, h * 0.35),
      Paint()..color = const Color(0xFF00E5FF).withOpacity(0.85),
    );
  }

  @override
  bool shouldRepaint(_MiniShipPainter old) => false;
}

// ─── Large ship icon painter (start overlay) ─────────────────────────────────

class _LargeShipPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    // Engine trail glow
    for (int i = 0; i < 3; i++) {
      canvas.drawOval(
        Rect.fromLTWH(w * 0.35 + i * 2, h * 0.82, w * 0.30 - i * 4, h * 0.22),
        Paint()
          ..color = const Color(0xFFFF6600).withOpacity(0.4 - i * 0.12)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4.0 + i * 3),
      );
    }
    // Outer glow
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.5, 0)
        ..lineTo(w, h * 0.72)
        ..lineTo(w * 0.68, h)
        ..lineTo(w * 0.32, h)
        ..lineTo(0, h * 0.72)
        ..close(),
      Paint()
        ..color = const Color(0xFF00AAFF).withOpacity(0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    // Hull gradient
    final hull = Path()
      ..moveTo(w * 0.5, 0)
      ..lineTo(w * 0.94, h * 0.7)
      ..lineTo(w * 0.68, h * 0.98)
      ..lineTo(w * 0.32, h * 0.98)
      ..lineTo(w * 0.06, h * 0.7)
      ..close();
    canvas.drawPath(hull, Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [const Color(0xFF00CCFF), const Color(0xFF004499)],
      ).createShader(Rect.fromLTWH(0, 0, w, h)));
    // Wing fins
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.06, h * 0.7)
        ..lineTo(0, h * 0.92)
        ..lineTo(w * 0.3, h * 0.98)
        ..close(),
      Paint()..color = const Color(0xFF0044BB),
    );
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.94, h * 0.7)
        ..lineTo(w, h * 0.92)
        ..lineTo(w * 0.7, h * 0.98)
        ..close(),
      Paint()..color = const Color(0xFF0044BB),
    );
    // Center stripe
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.5, h * 0.04)
        ..lineTo(w * 0.56, h * 0.7)
        ..lineTo(w * 0.44, h * 0.7)
        ..close(),
      Paint()..color = const Color(0xFF80DDFF).withOpacity(0.5),
    );
    // Cockpit glow
    canvas.drawOval(
      Rect.fromLTWH(w * 0.3, h * 0.12, w * 0.4, h * 0.38),
      Paint()
        ..color = const Color(0xFF00E5FF).withOpacity(0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawOval(
      Rect.fromLTWH(w * 0.33, h * 0.15, w * 0.34, h * 0.30),
      Paint()..color = const Color(0xFF00E5FF).withOpacity(0.85),
    );
    // Engine nozzles
    for (final nx in [0.38, 0.62]) {
      canvas.drawRect(
        Rect.fromLTWH(w * nx - w * 0.05, h * 0.88, w * 0.10, h * 0.10),
        Paint()..color = const Color(0xFF112244),
      );
      canvas.drawCircle(
        Offset(w * nx, h * 0.92),
        w * 0.06,
        Paint()
          ..color = const Color(0xFFFF8800).withOpacity(0.9)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }
  }

  @override
  bool shouldRepaint(_LargeShipPainter old) => false;
}

// ─── Explosion icon painter (death overlay) ──────────────────────────────────

class _ExplosionIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2;
    final r = size.width * 0.5;
    // Outer burst rays
    final rayColors = [
      const Color(0xFFFF6600), const Color(0xFFFFDD00), const Color(0xFFFF3300),
      const Color(0xFFFFAA00), const Color(0xFFFF0044),
    ];
    for (int i = 0; i < 8; i++) {
      final angle = i * pi / 4;
      final color = rayColors[i % rayColors.length];
      canvas.drawLine(
        Offset(cx, cy),
        Offset(cx + cos(angle) * r, cy + sin(angle) * r),
        Paint()
          ..color = color.withOpacity(0.7)
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
    }
    // Core glow
    canvas.drawCircle(
      Offset(cx, cy), r * 0.45,
      Paint()
        ..color = const Color(0xFFFF6600).withOpacity(0.6)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    // White hot core
    canvas.drawCircle(
      Offset(cx, cy), r * 0.22,
      Paint()..color = const Color(0xFFFFFFCC),
    );
  }

  @override
  bool shouldRepaint(_ExplosionIconPainter old) => false;
}

// ─── Main Painter ─────────────────────────────────────────────────────────────

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

  // Cached gradient definitions — createShader() is called per frame but the
  // gradient object itself is only allocated once.
  static const _shipGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF00CCFF), Color(0xFF0033AA)],
  );
  static const _alienBurstGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFDD88FF), Color(0xFF660099)],
  );
  static const _alienMissileGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFF6666), Color(0xFF880011)],
  );
  static const _alienBasicGradient = RadialGradient(
    center: Alignment(-0.3, -0.4),
    colors: [Color(0xFF44FF99), Color(0xFF006633)],
  );
  static const _alienScatterGradient = RadialGradient(
    center: Alignment(-0.2, -0.3),
    colors: [Color(0xFFFFAA00), Color(0xFF883300)],
  );
  static const _asteroidGradient = RadialGradient(
    center: Alignment(-0.3, -0.4),
    colors: [Color(0xFF9999BB), Color(0xFF33334A)],
  );
  static const _ammoPickupGradient = RadialGradient(
    colors: [Color(0xFFFFDD44), Color(0xFFFF6600)],
  );
  static const _heartPickupGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFF88AA), Color(0xFFCC0044)],
  );
  static const _miniShipGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF00AAFF), Color(0xFF003388)],
  );

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

    // ── Deep space gradient background ────────────────────────────────────────
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF010112), Color(0xFF020825), Color(0xFF030620)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    // Nebula clouds — large soft blobs of color
    _drawNebula(canvas, size.width * 0.15, size.height * 0.25, size.width * 0.55,
        const Color(0xFF1A0066), 0.18);
    _drawNebula(canvas, size.width * 0.65, size.height * 0.55, size.width * 0.50,
        const Color(0xFF002244), 0.22);
    _drawNebula(canvas, size.width * 0.45, size.height * 0.12, size.width * 0.40,
        const Color(0xFF001133), 0.15);

    // ── Animated starfield ────────────────────────────────────────────────────
    final starPaint = Paint();
    final sparkPaint = Paint()..strokeCap = StrokeCap.round;
    for (final s in stars) {
      final sx2 = wx(s.x, cs), sy2 = wy(s.y, cs);
      canvas.drawCircle(Offset(sx2, sy2), s.r * cs,
          starPaint..color = Colors.white.withOpacity(s.opacity));
      // Bright stars get a subtle cross sparkle
      if (s.isBright) {
        sparkPaint
          ..color = Colors.white.withOpacity(s.opacity * 0.6)
          ..strokeWidth = s.r * cs * 0.7;
        final sparkLen = s.r * cs * 3.5;
        canvas.drawLine(Offset(sx2 - sparkLen, sy2), Offset(sx2 + sparkLen, sy2), sparkPaint);
        canvas.drawLine(Offset(sx2, sy2 - sparkLen), Offset(sx2, sy2 + sparkLen), sparkPaint);
      }
    }

    // ── Player zone separator (subtle horizon line) ───────────────────────────
    canvas.drawLine(
      Offset(0, wy(8.8, cs)),
      Offset(size.width, wy(8.8, cs)),
      Paint()
        ..color = const Color(0xFF00AAFF).withOpacity(0.12)
        ..strokeWidth = 1,
    );

    // ── Pickups ───────────────────────────────────────────────────────────────
    for (final p in pickups.where((p) => p.alive)) {
      _drawPickup(canvas, cs, p);
    }

    // ── Player bullets — neon cyan beams with glow ────────────────────────────
    for (final b in bullets.where((b) => b.alive && b.isPlayer)) {
      final bx = wx(b.x, cs), by = wy(b.y, cs);
      // Outer glow beam
      canvas.drawLine(
        Offset(bx, by + cs * 0.5),
        Offset(bx, by - cs * 0.15),
        Paint()
          ..color = const Color(0xFF00E5FF).withOpacity(0.35)
          ..strokeWidth = cs * 0.25
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      // Mid beam
      canvas.drawLine(
        Offset(bx, by + cs * 0.45),
        Offset(bx, by - cs * 0.1),
        Paint()
          ..color = const Color(0xFF80F0FF)
          ..strokeWidth = cs * 0.10
          ..strokeCap = StrokeCap.round,
      );
      // Bright core
      canvas.drawLine(
        Offset(bx, by + cs * 0.38),
        Offset(bx, by - cs * 0.05),
        Paint()
          ..color = Colors.white
          ..strokeWidth = cs * 0.04
          ..strokeCap = StrokeCap.round,
      );
      // Leading tip flare
      canvas.drawCircle(
        Offset(bx, by - cs * 0.06), cs * 0.08,
        Paint()..color = Colors.white,
      );
    }

    // ── Enemy bullets / missiles — hot red/orange beams ───────────────────────
    for (final b in bullets.where((b) => b.alive && !b.isPlayer)) {
      final bx = wx(b.x, cs), by = wy(b.y, cs);
      if (b.isMissile) {
        // Missile: teardrop shape with trail glow
        canvas.drawOval(
          Rect.fromLTWH(bx - cs * 0.14, by - cs * 0.22, cs * 0.28, cs * 0.48),
          Paint()
            ..color = const Color(0xFFFF6D00).withOpacity(0.4)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
        canvas.drawOval(
          Rect.fromLTWH(bx - cs * 0.09, by - cs * 0.16, cs * 0.18, cs * 0.36),
          Paint()..color = const Color(0xFFFF8C00),
        );
        canvas.drawOval(
          Rect.fromLTWH(bx - cs * 0.05, by - cs * 0.12, cs * 0.10, cs * 0.22),
          Paint()..color = const Color(0xFFFFDD44),
        );
        // Exhaust trail
        canvas.drawLine(
          Offset(bx, by + cs * 0.2),
          Offset(bx, by + cs * 0.55),
          Paint()
            ..color = const Color(0xFFFF4400).withOpacity(0.5)
            ..strokeWidth = cs * 0.12
            ..strokeCap = StrokeCap.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
      } else {
        // Standard enemy shot — magenta/red plasma bolt
        canvas.drawLine(
          Offset(bx, by - cs * 0.12),
          Offset(bx, by + cs * 0.35),
          Paint()
            ..color = const Color(0xFFFF2266).withOpacity(0.4)
            ..strokeWidth = cs * 0.22
            ..strokeCap = StrokeCap.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
        canvas.drawLine(
          Offset(bx, by - cs * 0.10),
          Offset(bx, by + cs * 0.30),
          Paint()
            ..color = const Color(0xFFFF4488)
            ..strokeWidth = cs * 0.10
            ..strokeCap = StrokeCap.round,
        );
        canvas.drawCircle(
          Offset(bx, by + cs * 0.28), cs * 0.08,
          Paint()..color = Colors.white.withOpacity(0.7),
        );
      }
    }

    // ── Asteroids ─────────────────────────────────────────────────────────────
    for (final ast in asteroids.where((a) => a.alive)) {
      canvas.save();
      canvas.translate(wx(ast.x, cs), wy(ast.y, cs));
      canvas.rotate(ast.rot);
      _drawAsteroid(canvas, cs, ast.radius);
      canvas.restore();
    }

    // ── Aliens ────────────────────────────────────────────────────────────────
    for (final a in aliens.where((a) => a.alive)) {
      _drawAlien(canvas, cs, a);
    }

    // ── Player ship (blinks when invincible) ──────────────────────────────────
    if (!invincible || (DateTime.now().millisecondsSinceEpoch ~/ 100).isEven) {
      _drawShip(canvas, cs);
    }

    // ── Shield ring ───────────────────────────────────────────────────────────
    if (shieldHits > 0) {
      final scx = wx(sx + kShipW / 2, cs), scy = wy(sy + kShipH / 2, cs);
      // Outer blur ring
      canvas.drawCircle(
        Offset(scx, scy), cs * 0.9,
        Paint()
          ..color = const Color(0xFF00E5FF).withOpacity(0.15)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
      // Solid ring
      canvas.drawCircle(
        Offset(scx, scy), cs * 0.88,
        Paint()
          ..color = const Color(0xFF00E5FF).withOpacity(0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
      // Inner thin ring
      canvas.drawCircle(
        Offset(scx, scy), cs * 0.82,
        Paint()
          ..color = const Color(0xFF00E5FF).withOpacity(0.2)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }

  void _drawNebula(Canvas canvas, double cx, double cy, double r, Color color, double opacity) {
    canvas.drawCircle(
      Offset(cx, cy), r,
      Paint()
        ..color = color.withOpacity(opacity)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.7),
    );
  }

  void _drawPickup(Canvas canvas, double cs, _Pickup p) {
    final px = wx(p.x + 0.3, cs), py = wy(p.y + 0.3, cs);
    final sz = cs * 0.45;

    Color glowColor;
    switch (p.type) {
      case _PickupType.shield:
        glowColor = const Color(0xFF00E5FF);
        _drawShieldPickup(canvas, px, py, sz);
        break;
      case _PickupType.specialAmmo:
        glowColor = const Color(0xFFFF9800);
        _drawAmmoPickup(canvas, px, py, sz);
        break;
      case _PickupType.heart:
        glowColor = const Color(0xFFFF4488);
        _drawHeartPickup(canvas, px, py, sz);
        break;
    }

    // Outer glow aura
    canvas.drawCircle(
      Offset(px, py), sz * 1.2,
      Paint()
        ..color = glowColor.withOpacity(0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
  }

  void _drawShieldPickup(Canvas canvas, double cx, double cy, double sz) {
    // Hexagonal shield shape
    final path = Path();
    for (int i = 0; i < 6; i++) {
      final angle = i * pi / 3 - pi / 6;
      final x = cx + cos(angle) * sz;
      final y = cy + sin(angle) * sz;
      if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
    }
    path.close();
    canvas.drawPath(path, Paint()
      ..color = const Color(0xFF00E5FF).withOpacity(0.25));
    canvas.drawPath(path, Paint()
      ..color = const Color(0xFF00E5FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
    // Inner cross
    canvas.drawLine(Offset(cx, cy - sz * 0.55), Offset(cx, cy + sz * 0.55),
        Paint()..color = const Color(0xFF80F0FF)..strokeWidth = 2);
    canvas.drawLine(Offset(cx - sz * 0.4, cy), Offset(cx + sz * 0.4, cy),
        Paint()..color = const Color(0xFF80F0FF)..strokeWidth = 2);
  }

  void _drawAmmoPickup(Canvas canvas, double cx, double cy, double sz) {
    // Star shape
    final path = Path();
    for (int i = 0; i < 5; i++) {
      final outerAngle = i * 2 * pi / 5 - pi / 2;
      final innerAngle = outerAngle + pi / 5;
      final ox = cx + cos(outerAngle) * sz;
      final oy = cy + sin(outerAngle) * sz;
      final ix = cx + cos(innerAngle) * sz * 0.45;
      final iy = cy + sin(innerAngle) * sz * 0.45;
      if (i == 0) { path.moveTo(ox, oy); } else { path.lineTo(ox, oy); }
      path.lineTo(ix, iy);
    }
    path.close();
    canvas.drawPath(path, Paint()
      ..color = const Color(0xFFFF9800)
      ..shader = _ammoPickupGradient.createShader(Rect.fromCircle(center: Offset(cx, cy), radius: sz)));
    canvas.drawPath(path, Paint()
      ..color = Colors.white.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1);
  }

  void _drawHeartPickup(Canvas canvas, double cx, double cy, double sz) {
    // Heart shape
    final path = Path();
    path.moveTo(cx, cy + sz * 0.4);
    path.cubicTo(cx - sz * 1.2, cy - sz * 0.3, cx - sz * 1.2, cy - sz * 1.1, cx, cy - sz * 0.4);
    path.cubicTo(cx + sz * 1.2, cy - sz * 1.1, cx + sz * 1.2, cy - sz * 0.3, cx, cy + sz * 0.4);
    canvas.drawPath(path, Paint()
      ..color = const Color(0xFFFF3377)
      ..shader = _heartPickupGradient.createShader(Rect.fromLTWH(cx - sz, cy - sz, sz * 2, sz * 2)));
    canvas.drawPath(path, Paint()
      ..color = Colors.white.withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1);
  }

  void _drawShip(Canvas canvas, double cs) {
    final shipX = wx(sx, cs);
    final shipY = wy(sy, cs);
    final sw = kShipW * cs;
    final sh = kShipH * cs;
    final cx = shipX + sw / 2;

    // Engine exhaust trails
    for (int i = 0; i < 3; i++) {
      final fade = 1.0 - i * 0.3;
      canvas.drawOval(
        Rect.fromLTWH(cx - sw * 0.12 - i, shipY + sh + i * cs * 0.08,
            sw * 0.24 + i * 2, sh * 0.28 + i * cs * 0.1),
        Paint()
          ..color = const Color(0xFFFF7700).withOpacity(0.6 * fade)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4.0 + i * 3),
      );
    }
    // Left engine nozzle
    canvas.drawOval(
      Rect.fromLTWH(shipX + sw * 0.06, shipY + sh * 0.88, sw * 0.18, sh * 0.18),
      Paint()
        ..color = const Color(0xFFFF8800).withOpacity(0.8)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    // Right engine nozzle
    canvas.drawOval(
      Rect.fromLTWH(shipX + sw * 0.76, shipY + sh * 0.88, sw * 0.18, sh * 0.18),
      Paint()
        ..color = const Color(0xFFFF8800).withOpacity(0.8)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // Outer hull glow
    canvas.drawPath(
      Path()
        ..moveTo(cx, shipY - sh * 0.05)
        ..lineTo(shipX + sw, shipY + sh * 0.72)
        ..lineTo(shipX + sw * 0.67, shipY + sh + sh * 0.05)
        ..lineTo(shipX + sw * 0.33, shipY + sh + sh * 0.05)
        ..lineTo(shipX, shipY + sh * 0.72)
        ..close(),
      Paint()
        ..color = const Color(0xFF0088FF).withOpacity(0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // Main hull (gradient)
    final hull = Path()
      ..moveTo(cx, shipY)
      ..lineTo(shipX + sw * 0.96, shipY + sh * 0.70)
      ..lineTo(shipX + sw * 0.66, shipY + sh)
      ..lineTo(shipX + sw * 0.34, shipY + sh)
      ..lineTo(shipX + sw * 0.04, shipY + sh * 0.70)
      ..close();
    canvas.drawPath(hull, Paint()
      ..shader = _shipGradient.createShader(Rect.fromLTWH(shipX, shipY, sw, sh)));

    // Wing insets (dark panels)
    canvas.drawPath(
      Path()
        ..moveTo(shipX + sw * 0.04, shipY + sh * 0.70)
        ..lineTo(shipX + sw * 0.22, shipY + sh * 0.55)
        ..lineTo(shipX + sw * 0.34, shipY + sh)
        ..close(),
      Paint()..color = const Color(0xFF001155),
    );
    canvas.drawPath(
      Path()
        ..moveTo(shipX + sw * 0.96, shipY + sh * 0.70)
        ..lineTo(shipX + sw * 0.78, shipY + sh * 0.55)
        ..lineTo(shipX + sw * 0.66, shipY + sh)
        ..close(),
      Paint()..color = const Color(0xFF001155),
    );

    // Center spine highlight
    canvas.drawPath(
      Path()
        ..moveTo(cx, shipY + sh * 0.02)
        ..lineTo(cx + sw * 0.04, shipY + sh * 0.65)
        ..lineTo(cx - sw * 0.04, shipY + sh * 0.65)
        ..close(),
      Paint()..color = const Color(0xFF80DDFF).withOpacity(0.45),
    );

    // Cannon tip
    canvas.drawRect(
      Rect.fromLTWH(cx - cs * 0.07, shipY - sh * 0.12, cs * 0.14, sh * 0.15),
      Paint()..color = const Color(0xFFAAEEFF),
    );
    // Cannon muzzle glow
    canvas.drawCircle(
      Offset(cx, shipY - sh * 0.1), cs * 0.1,
      Paint()
        ..color = const Color(0xFF00E5FF).withOpacity(0.6)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // Cockpit
    canvas.drawOval(
      Rect.fromLTWH(cx - sw * 0.175, shipY + sh * 0.12, sw * 0.35, sh * 0.36),
      Paint()
        ..color = const Color(0xFF00E5FF).withOpacity(0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawOval(
      Rect.fromLTWH(cx - sw * 0.14, shipY + sh * 0.14, sw * 0.28, sh * 0.30),
      Paint()..color = const Color(0xFF00E5FF).withOpacity(0.85),
    );
    // Cockpit glare
    canvas.drawOval(
      Rect.fromLTWH(cx - sw * 0.08, shipY + sh * 0.16, sw * 0.10, sh * 0.10),
      Paint()..color = Colors.white.withOpacity(0.6),
    );

    // Side thrusters
    for (final tx in [shipX, shipX + sw * 0.7]) {
      canvas.drawRect(
        Rect.fromLTWH(tx, shipY + sh * 0.56, sw * 0.30, sh * 0.15),
        Paint()..color = const Color(0xFF0055BB),
      );
    }
  }

  void _drawAlien(Canvas canvas, double cs, _Alien a) {
    final ax = wx(a.x, cs);
    final ay = wy(a.y, cs);
    final aw = cs * 1.0;
    final ah = cs * 0.82;

    switch (a.type) {
      case _AlienType.basic:
        _drawAlienBasic(canvas, ax, ay, aw, ah, cs, a.hp);
        break;
      case _AlienType.burst:
        _drawAlienBurst(canvas, ax, ay, aw, ah, cs, a.hp);
        break;
      case _AlienType.scatter:
        _drawAlienScatter(canvas, ax, ay, aw, ah, cs, a.hp);
        break;
      case _AlienType.missile:
        _drawAlienMissile(canvas, ax, ay, aw, ah, cs, a.hp);
        break;
    }
  }

  // Basic alien — green saucer type
  void _drawAlienBasic(Canvas canvas, double ax, double ay, double aw, double ah, double cs, int hp) {
    const color = Color(0xFF00FF88);
    // Hull glow
    canvas.drawOval(
      Rect.fromLTWH(ax - 2, ay + ah * 0.28 - 2, aw + 4, ah * 0.72 + 4),
      Paint()
        ..color = color.withOpacity(0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    // Body disc
    canvas.drawOval(
      Rect.fromLTWH(ax, ay + ah * 0.30, aw, ah * 0.70),
      Paint()
        ..shader = _alienBasicGradient.createShader(Rect.fromLTWH(ax, ay + ah * 0.30, aw, ah * 0.70)),
    );
    // Dome
    canvas.drawOval(
      Rect.fromLTWH(ax + aw * 0.20, ay, aw * 0.60, ah * 0.65),
      Paint()..color = const Color(0xFF00CC66).withOpacity(0.7),
    );
    canvas.drawOval(
      Rect.fromLTWH(ax + aw * 0.25, ay + ah * 0.04, aw * 0.50, ah * 0.50),
      Paint()..color = const Color(0xFF88FFCC).withOpacity(0.4),
    );
    // Glowing eyes
    for (final eyeX in [ax + aw * 0.31, ax + aw * 0.61]) {
      canvas.drawCircle(Offset(eyeX, ay + ah * 0.52), cs * 0.09,
          Paint()..color = const Color(0xFFFFFF00)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
      canvas.drawCircle(Offset(eyeX, ay + ah * 0.52), cs * 0.055,
          Paint()..color = Colors.white);
    }
    // Rim lights
    canvas.drawOval(
      Rect.fromLTWH(ax, ay + ah * 0.30, aw, ah * 0.70),
      Paint()
        ..color = color.withOpacity(0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    _drawHpPips(canvas, ax, ay, aw, cs, hp, color);
  }

  // Burst alien — purple angular fighter
  void _drawAlienBurst(Canvas canvas, double ax, double ay, double aw, double ah, double cs, int hp) {
    const color = Color(0xFFCC44FF);
    // Glow
    canvas.drawOval(
      Rect.fromLTWH(ax - 3, ay - 2, aw + 6, ah + 4),
      Paint()
        ..color = color.withOpacity(0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    // Main body (diamond/angular)
    final body = Path()
      ..moveTo(ax + aw * 0.5, ay)
      ..lineTo(ax + aw, ay + ah * 0.45)
      ..lineTo(ax + aw * 0.7, ay + ah)
      ..lineTo(ax + aw * 0.3, ay + ah)
      ..lineTo(ax, ay + ah * 0.45)
      ..close();
    canvas.drawPath(body, Paint()
      ..shader = _alienBurstGradient.createShader(Rect.fromLTWH(ax, ay, aw, ah)));
    // Wing spikes
    canvas.drawPath(
      Path()
        ..moveTo(ax, ay + ah * 0.45)
        ..lineTo(ax - aw * 0.25, ay + ah * 0.65)
        ..lineTo(ax + aw * 0.25, ay + ah * 0.60),
      Paint()..color = const Color(0xFF9900CC),
    );
    canvas.drawPath(
      Path()
        ..moveTo(ax + aw, ay + ah * 0.45)
        ..lineTo(ax + aw * 1.25, ay + ah * 0.65)
        ..lineTo(ax + aw * 0.75, ay + ah * 0.60),
      Paint()..color = const Color(0xFF9900CC),
    );
    // Glowing eyes
    for (final eyeX in [ax + aw * 0.33, ax + aw * 0.67]) {
      canvas.drawCircle(Offset(eyeX, ay + ah * 0.42), cs * 0.10,
          Paint()..color = const Color(0xFFFF44FF)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
      canvas.drawCircle(Offset(eyeX, ay + ah * 0.42), cs * 0.06,
          Paint()..color = Colors.white);
    }
    // Outline
    canvas.drawPath(body, Paint()
      ..color = color.withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5);
    _drawHpPips(canvas, ax, ay, aw, cs, hp, color);
  }

  // Scatter alien — orange crab/spider type
  void _drawAlienScatter(Canvas canvas, double ax, double ay, double aw, double ah, double cs, int hp) {
    const color = Color(0xFFFF8800);
    // Glow aura
    canvas.drawOval(
      Rect.fromLTWH(ax - 4, ay - 2, aw + 8, ah + 4),
      Paint()
        ..color = color.withOpacity(0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    // Side legs/pincers
    for (final side in [-1.0, 1.0]) {
      final lx = side < 0 ? ax - aw * 0.18 : ax + aw * 1.0;
      canvas.drawLine(
        Offset(ax + aw * (side < 0 ? 0.1 : 0.9), ay + ah * 0.4),
        Offset(lx + side * aw * 0.22, ay + ah * 0.2),
        Paint()..color = const Color(0xFFCC5500)..strokeWidth = cs * 0.08..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(
        Offset(ax + aw * (side < 0 ? 0.1 : 0.9), ay + ah * 0.55),
        Offset(lx + side * aw * 0.18, ay + ah * 0.6),
        Paint()..color = const Color(0xFFCC5500)..strokeWidth = cs * 0.08..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(
        Offset(ax + aw * (side < 0 ? 0.1 : 0.9), ay + ah * 0.70),
        Offset(lx + side * aw * 0.25, ay + ah * 0.9),
        Paint()..color = const Color(0xFFCC5500)..strokeWidth = cs * 0.07..strokeCap = StrokeCap.round,
      );
    }
    // Body
    canvas.drawOval(
      Rect.fromLTWH(ax + aw * 0.08, ay + ah * 0.15, aw * 0.84, ah * 0.80),
      Paint()
        ..shader = _alienScatterGradient.createShader(Rect.fromLTWH(ax, ay, aw, ah)),
    );
    // Carapace stripe
    canvas.drawOval(
      Rect.fromLTWH(ax + aw * 0.25, ay + ah * 0.15, aw * 0.50, ah * 0.40),
      Paint()..color = const Color(0xFFFFCC44).withOpacity(0.4),
    );
    // Eyes (3)
    for (int i = 0; i < 3; i++) {
      final ex = ax + aw * (0.25 + i * 0.25);
      canvas.drawCircle(Offset(ex, ay + ah * 0.42), cs * 0.085,
          Paint()..color = const Color(0xFFFF2200)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
      canvas.drawCircle(Offset(ex, ay + ah * 0.42), cs * 0.05,
          Paint()..color = Colors.white);
    }
    canvas.drawOval(
      Rect.fromLTWH(ax + aw * 0.08, ay + ah * 0.15, aw * 0.84, ah * 0.80),
      Paint()
        ..color = color.withOpacity(0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    _drawHpPips(canvas, ax, ay, aw, cs, hp, color);
  }

  // Missile alien — red angular warship
  void _drawAlienMissile(Canvas canvas, double ax, double ay, double aw, double ah, double cs, int hp) {
    const color = Color(0xFFFF2244);
    // Red danger glow
    canvas.drawOval(
      Rect.fromLTWH(ax - 4, ay - 3, aw + 8, ah + 6),
      Paint()
        ..color = color.withOpacity(0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    // Main angular body
    final body = Path()
      ..moveTo(ax + aw * 0.50, ay)
      ..lineTo(ax + aw * 0.78, ay + ah * 0.35)
      ..lineTo(ax + aw, ay + ah * 0.55)
      ..lineTo(ax + aw * 0.80, ay + ah)
      ..lineTo(ax + aw * 0.20, ay + ah)
      ..lineTo(ax, ay + ah * 0.55)
      ..lineTo(ax + aw * 0.22, ay + ah * 0.35)
      ..close();
    canvas.drawPath(body, Paint()
      ..shader = _alienMissileGradient.createShader(Rect.fromLTWH(ax, ay, aw, ah)));
    // Dark center panel
    canvas.drawOval(
      Rect.fromLTWH(ax + aw * 0.27, ay + ah * 0.20, aw * 0.46, ah * 0.55),
      Paint()..color = const Color(0xFF330008),
    );
    // Glowing eyes — menacing
    for (final eyeX in [ax + aw * 0.33, ax + aw * 0.67]) {
      canvas.drawCircle(Offset(eyeX, ay + ah * 0.40), cs * 0.12,
          Paint()..color = const Color(0xFFFF0000)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
      canvas.drawCircle(Offset(eyeX, ay + ah * 0.40), cs * 0.07,
          Paint()..color = const Color(0xFFFFDD00));
      canvas.drawCircle(Offset(eyeX, ay + ah * 0.40), cs * 0.035,
          Paint()..color = Colors.white);
    }
    // Intake vents at bottom
    canvas.drawRect(
      Rect.fromLTWH(ax + aw * 0.28, ay + ah * 0.78, aw * 0.44, ah * 0.10),
      Paint()..color = const Color(0xFF550011),
    );
    for (int i = 0; i < 4; i++) {
      canvas.drawRect(
        Rect.fromLTWH(ax + aw * (0.30 + i * 0.10), ay + ah * 0.79, aw * 0.06, ah * 0.08),
        Paint()..color = const Color(0xFFFF4400).withOpacity(0.7),
      );
    }
    canvas.drawPath(body, Paint()
      ..color = color.withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5);
    _drawHpPips(canvas, ax, ay, aw, cs, hp, color);
  }

  void _drawHpPips(Canvas canvas, double ax, double ay, double aw, double cs, int hp, Color color) {
    if (hp <= 1) return;
    for (int i = 0; i < hp; i++) {
      final pipX = ax + aw * (0.25 + i * 0.25);
      canvas.drawCircle(
        Offset(pipX, ay - cs * 0.12), cs * 0.075,
        Paint()
          ..color = color
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
      canvas.drawCircle(
        Offset(pipX, ay - cs * 0.12), cs * 0.05,
        Paint()..color = Colors.white,
      );
    }
  }

  void _drawAsteroid(Canvas canvas, double cs, double radius) {
    final r = radius * cs;
    // Base rock shape
    final path = Path();
    const sides = 9;
    for (int i = 0; i < sides; i++) {
      final angle = i * 2 * pi / sides;
      final jitter = 0.65 + (i * 43 % 9) * 0.04;
      final x = cos(angle) * r * jitter;
      final y = sin(angle) * r * jitter;
      if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
    }
    path.close();
    // Glow
    canvas.drawPath(path, Paint()
      ..color = const Color(0xFF8888AA).withOpacity(0.2)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    // Body gradient
    canvas.drawPath(path, Paint()
      ..shader = _asteroidGradient.createShader(Rect.fromCircle(center: Offset.zero, radius: r)));
    // Crater details
    canvas.drawCircle(
      Offset(r * 0.25, -r * 0.3), r * 0.18,
      Paint()
        ..color = const Color(0xFF222233)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    canvas.drawCircle(
      Offset(-r * 0.35, r * 0.2), r * 0.12,
      Paint()
        ..color = const Color(0xFF222233)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
    // Edge highlight
    canvas.drawPath(path, Paint()
      ..color = const Color(0xFF8888BB).withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2);
  }

  @override
  bool shouldRepaint(_ShooterPainter old) => true;
}
