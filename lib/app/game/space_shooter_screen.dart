import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'arcade_input_controller.dart';

// ─── Data ─────────────────────────────────────────────────────────────────────

class _Bullet {
  double x, y;
  final bool isPlayer;
  bool alive;
  _Bullet(this.x, this.y, {required this.isPlayer}) : alive = true;
}

class _Alien {
  double x, y;
  bool alive;
  int hp;
  double fireTimer;
  _Alien(this.x, this.y, {this.hp = 1})
      : alive = true,
        fireTimer = 1.0 + Random().nextDouble() * 2.0;
}

class _Asteroid {
  double x, y, vy, rot, rotV, radius;
  bool alive;
  _Asteroid(this.x, this.y, this.vy, this.radius)
      : alive = true,
        rot = 0,
        rotV = (Random().nextDouble() - 0.5) * 4;
}

// ─── Screen ──────────────────────────────────────────────────────────────────

class SpaceShooterScreen extends StatefulWidget {
  final String userId;
  final DocumentReference rewardsDocRef;
  final double currentSaldo;
  final ArcadeInputController controller;
  final VoidCallback onSaldoChanged;

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
  // World units — 10 wide, 16 tall
  static const int kW = 10;
  static const int kH = 16;
  static const double kShipW = 1.2;
  static const double kShipH = 1.0;
  static const double kShipSpeed = 7.0;
  static const double kBulletSpeed = 18.0;
  static const double kEnemyBulletSpeed = 7.0;
  static const double kShipMinY = 9.0; // player can't go above this
  static const double kFireCooldown = 0.25;

  final _rng = Random();

  // Ship
  double _sx = 4.4, _sy = 13.5;
  int _lives = 3;
  bool _invincible = false;
  double _invTimer = 0;

  // Weapons
  double _fireCooldown = 0;
  List<_Bullet> _bullets = [];

  // Enemies
  List<_Alien> _aliens = [];
  double _groupX = 0, _groupVx = 2.5, _groupY = 0;
  int _wave = 1;

  // Asteroids
  List<_Asteroid> _asteroids = [];
  double _asteroidSpawnTimer = 3.0;

  // State
  bool _isRunning = false;
  bool _isDead = false;
  bool _isWaveComplete = false;
  int _score = 0;
  late double _saldo;

  Timer? _ticker;
  DateTime? _lastTick;

  // Stars (static decorations)
  late final List<_Star> _stars;

  @override
  void initState() {
    super.initState();
    _saldo = widget.currentSaldo;
    _stars = List.generate(40, (_) => _Star(_rng));
    _spawnWave(1);
    widget.controller.addListener(_onControllerEvent);
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
    if (_isWaveComplete) {
      if (btn == ArcadeButton.a || btn == ArcadeButton.start) _nextWave();
      return;
    }
    if (!_isRunning) {
      _startGame();
      return;
    }
    if ((btn == ArcadeButton.a || btn == ArcadeButton.x) && _fireCooldown <= 0) {
      _fire();
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
    final dt = (now.difference(_lastTick!).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _lastTick = now;
    if (_isDead || _isWaveComplete) return;
    _update(dt);
    if (mounted) setState(() {});
  }

  void _update(double dt) {
    // Move ship
    final left = widget.controller.isHeld(ArcadeButton.left);
    final right = widget.controller.isHeld(ArcadeButton.right);
    final up = widget.controller.isHeld(ArcadeButton.up);
    final down = widget.controller.isHeld(ArcadeButton.down);

    if (left) _sx -= kShipSpeed * dt;
    if (right) _sx += kShipSpeed * dt;
    if (up) _sy -= kShipSpeed * dt;
    if (down) _sy += kShipSpeed * dt;
    _sx = _sx.clamp(0, kW - kShipW);
    _sy = _sy.clamp(kShipMinY, kH - kShipH - 0.2);

    // Fire via held A/X
    _fireCooldown -= dt;
    if (_fireCooldown < 0) _fireCooldown = 0;
    if ((widget.controller.isHeld(ArcadeButton.a) || widget.controller.isHeld(ArcadeButton.x))
        && _fireCooldown <= 0) {
      _fire();
    }

    // Move player bullets
    for (final b in _bullets) {
      if (!b.alive) continue;
      if (b.isPlayer) {
        b.y -= kBulletSpeed * dt;
        if (b.y < -1) b.alive = false;
      } else {
        b.y += kEnemyBulletSpeed * dt;
        if (b.y > kH + 1) b.alive = false;
      }
    }
    _bullets.removeWhere((b) => !b.alive);

    // Move alien group (Space Invaders style)
    _groupX += _groupVx * dt;
    double minX = double.infinity, maxX = -double.infinity;
    for (final a in _aliens.where((a) => a.alive)) {
      final ax = a.x + _groupX;
      minX = min(minX, ax);
      maxX = max(maxX, ax + 1.0);
    }
    if (maxX >= kW || minX <= 0) {
      _groupVx = -_groupVx * 1.08; // speed up each bounce
      _groupX += _groupVx * dt;
      _groupY += 0.6;
    }

    // Alien fire & check if they reached player zone
    bool aliensTooClose = false;
    for (final a in _aliens) {
      if (!a.alive) continue;
      final ay = a.y + _groupY;
      if (ay + 0.8 >= kShipMinY - 0.5) { aliensTooClose = true; break; }
      a.fireTimer -= dt;
      if (a.fireTimer <= 0) {
        a.fireTimer = 1.5 + _rng.nextDouble() * 2.5;
        _bullets.add(_Bullet(a.x + _groupX + 0.4, ay + 0.8, isPlayer: false));
      }
    }
    if (aliensTooClose) { _triggerDeath(); return; }

    // Asteroid spawning & movement
    _asteroidSpawnTimer -= dt;
    if (_asteroidSpawnTimer <= 0) {
      _asteroidSpawnTimer = 2.0 + _rng.nextDouble() * 3.0;
      final r = 0.3 + _rng.nextDouble() * 0.4;
      _asteroids.add(_Asteroid(_rng.nextDouble() * (kW - r * 2) + r, -r, 2.0 + _rng.nextDouble() * 2.0, r));
    }
    for (final ast in _asteroids) {
      if (!ast.alive) continue;
      ast.y += ast.vy * dt;
      ast.rot += ast.rotV * dt;
      if (ast.y > kH + 1) ast.alive = false;
    }
    _asteroids.removeWhere((a) => !a.alive);

    // Invincibility
    if (_invincible) {
      _invTimer -= dt;
      if (_invTimer <= 0) _invincible = false;
    }

    // Bullet vs alien collision
    for (final b in _bullets.where((b) => b.alive && b.isPlayer)) {
      for (final a in _aliens.where((a) => a.alive)) {
        final ax = a.x + _groupX, ay = a.y + _groupY;
        if (b.x > ax && b.x < ax + 1.0 && b.y > ay && b.y < ay + 0.8) {
          a.hp--;
          b.alive = false;
          if (a.hp <= 0) {
            a.alive = false;
            _score += _wave > 2 ? 150 : 100;
            HapticFeedback.lightImpact();
          }
          break;
        }
      }
    }

    // Bullet vs asteroid collision
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

    // Enemy bullet vs ship
    if (!_invincible) {
      for (final b in _bullets.where((b) => b.alive && !b.isPlayer)) {
        if (b.x > _sx && b.x < _sx + kShipW && b.y > _sy && b.y < _sy + kShipH) {
          b.alive = false;
          _hitShip();
          if (_isDead) return;
        }
      }
      // Asteroid vs ship
      for (final ast in _asteroids.where((ast) => ast.alive)) {
        final dx = ast.x - (_sx + kShipW / 2), dy = ast.y - (_sy + kShipH / 2);
        if (sqrt(dx * dx + dy * dy) < ast.radius + 0.4) {
          ast.alive = false;
          _hitShip();
          if (_isDead) return;
        }
      }
    }

    // Wave complete?
    if (_aliens.every((a) => !a.alive)) {
      _ticker?.cancel();
      if (mounted) setState(() { _isWaveComplete = true; _isRunning = false; });
    }
  }

  void _fire() {
    _fireCooldown = kFireCooldown;
    _bullets.add(_Bullet(_sx + kShipW / 2, _sy, isPlayer: true));
    HapticFeedback.selectionClick();
  }

  void _hitShip() {
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
    if (mounted) setState(() { _isDead = true; _isRunning = false; });
  }

  void _spawnWave(int wave) {
    _groupX = 0;
    _groupY = 0;
    _groupVx = 1.8 + wave * 0.5;
    _aliens = [];
    final rows = wave >= 3 ? 3 : (wave >= 2 ? 2 : 2);
    final cols = wave >= 3 ? 4 : 3;
    final hp = wave >= 3 ? 2 : 1;
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final startX = (kW - cols * 1.8) / 2;
        _aliens.add(_Alien(startX + c * 1.8, 0.5 + r * 1.2, hp: hp));
      }
    }
  }

  void _nextWave() {
    _wave++;
    _score += 200;
    _spawnWave(_wave);
    _bullets.clear();
    setState(() { _isWaveComplete = false; _isRunning = false; });
    _startGame();
  }

  void _restart() {
    _wave = 1;
    _score = 0;
    _lives = 3;
    _sx = 4.4; _sy = 13.5;
    _bullets.clear();
    _asteroids.clear();
    _invincible = false;
    _spawnWave(1);
    setState(() { _isDead = false; _isRunning = false; });
    _startGame();
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, cons) {
      final cs = cons.maxWidth / kW;
      return Stack(children: [
        CustomPaint(
          painter: _ShooterPainter(
            stars: _stars,
            aliens: _aliens,
            asteroids: _asteroids,
            bullets: _bullets,
            groupX: _groupX,
            groupY: _groupY,
            sx: _sx, sy: _sy,
            invincible: _invincible,
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
              _chip('⭐ $_score'),
              _chip('Ola $_wave'),
            ],
          ),
        ),
        if (!_isRunning && !_isDead && !_isWaveComplete) _buildStartOverlay(),
        if (_isDead) _buildDeathOverlay(),
        if (_isWaveComplete) _buildWaveCompleteOverlay(),
      ]);
    });
  }

  Widget _chip(String t) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
    child: Text(t, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
  );

  Widget _buildStartOverlay() => Positioned.fill(
    child: Container(
      color: Colors.black.withOpacity(0.75),
      child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text('🚀', style: TextStyle(fontSize: 52)),
        SizedBox(height: 10),
        Text('SPACE SHOOTER', style: TextStyle(color: Colors.cyanAccent, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 3)),
        SizedBox(height: 18),
        Text('Pulsa cualquier botón', style: TextStyle(color: Colors.white70, fontSize: 12)),
        SizedBox(height: 4),
        Text('D-pad para mover', style: TextStyle(color: Colors.white54, fontSize: 11)),
        Text('A / X para disparar', style: TextStyle(color: Colors.white54, fontSize: 11)),
        SizedBox(height: 4),
        Text('¡Destruye todas las naves!', style: TextStyle(color: Colors.white38, fontSize: 10)),
      ]),
    ),
  );

  Widget _buildDeathOverlay() => Positioned.fill(
    child: Container(
      color: Colors.black87,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('💥 GAME OVER', style: TextStyle(color: Colors.red, fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('Puntuación: $_score', style: const TextStyle(color: Colors.white, fontSize: 16)),
        const SizedBox(height: 18),
        ElevatedButton(
          onPressed: _restart,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white, shape: const StadiumBorder()),
          child: const Text('Nueva partida'),
        ),
        const SizedBox(height: 8),
        const Text('B para volver al menú', style: TextStyle(color: Colors.white38, fontSize: 10)),
      ]),
    ),
  );

  Widget _buildWaveCompleteOverlay() => Positioned.fill(
    child: Container(
      color: Colors.black.withOpacity(0.8),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('🌟', style: TextStyle(fontSize: 52)),
        Text('¡OLA $_wave COMPLETADA!', style: const TextStyle(color: Colors.cyanAccent, fontSize: 18, fontWeight: FontWeight.bold)),
        Text('+200 puntos  ·  Total: $_score', style: const TextStyle(color: Colors.white, fontSize: 14)),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _nextWave,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.cyan.shade700, foregroundColor: Colors.white, shape: const StadiumBorder()),
          child: Text('Ola ${_wave + 1} →'),
        ),
      ]),
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
  final double groupX, groupY, sx, sy;
  final bool invincible;
  final int kW, kH;

  static const double kShipW = 1.2;
  static const double kShipH = 1.0;

  const _ShooterPainter({
    required this.stars, required this.aliens,
    required this.asteroids, required this.bullets,
    required this.groupX, required this.groupY,
    required this.sx, required this.sy,
    required this.invincible,
    required this.kW, required this.kH,
  });

  double wx(double x, double cs) => x * cs;
  double wy(double y, double cs) => y * cs;

  @override
  void paint(Canvas canvas, Size size) {
    final cs = size.width / kW;

    // Space background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF020818),
    );
    // Nebula hint
    final nebula = Paint()
      ..color = const Color(0xFF0D1B4B).withOpacity(0.6)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30);
    canvas.drawCircle(Offset(size.width * 0.3, size.height * 0.4), size.width * 0.5, nebula);

    // Stars
    for (final s in stars) {
      canvas.drawCircle(
        Offset(wx(s.x, cs), wy(s.y, cs)),
        s.r * cs,
        Paint()..color = Colors.white.withOpacity(s.opacity),
      );
    }

    // Player bullets
    final pBulletPaint = Paint()..color = const Color(0xFF00E5FF);
    for (final b in bullets.where((b) => b.alive && b.isPlayer)) {
      canvas.drawRect(
        Rect.fromLTWH(wx(b.x - 0.07, cs), wy(b.y - 0.25, cs), cs * 0.14, cs * 0.5),
        pBulletPaint,
      );
      // Glow
      canvas.drawCircle(Offset(wx(b.x, cs), wy(b.y, cs)), cs * 0.12,
          Paint()..color = const Color(0xFF00E5FF).withOpacity(0.4)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    }

    // Enemy bullets
    final eBulletPaint = Paint()..color = const Color(0xFFFF4444);
    for (final b in bullets.where((b) => b.alive && !b.isPlayer)) {
      canvas.drawOval(
        Rect.fromLTWH(wx(b.x - 0.1, cs), wy(b.y - 0.15, cs), cs * 0.2, cs * 0.35),
        eBulletPaint,
      );
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
      _drawAlien(canvas, cs, wx(a.x + groupX, cs), wy(a.y + groupY, cs), a.hp > 1);
    }

    // Ship (blink when invincible)
    if (!invincible || (DateTime.now().millisecondsSinceEpoch ~/ 100).isEven) {
      _drawShip(canvas, cs);
    }

    // Ground line (visual separator for player zone)
    canvas.drawRect(
      Rect.fromLTWH(0, wy(8.8, cs), size.width, 1),
      Paint()..color = Colors.white12,
    );
  }

  void _drawShip(Canvas canvas, double cs) {
    final shipX = wx(sx, cs);
    final shipY = wy(sy, cs);
    final sw = kShipW * cs;
    final sh = kShipH * cs;

    // Engine glow
    canvas.drawCircle(
      Offset(shipX + sw / 2, shipY + sh),
      cs * 0.28,
      Paint()..color = const Color(0xFFFF8C00).withOpacity(0.7)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );

    // Ship body: triangle hull
    final hull = Path()
      ..moveTo(shipX + sw / 2, shipY)
      ..lineTo(shipX + sw, shipY + sh * 0.7)
      ..lineTo(shipX + sw * 0.65, shipY + sh)
      ..lineTo(shipX + sw * 0.35, shipY + sh)
      ..lineTo(shipX, shipY + sh * 0.7)
      ..close();
    canvas.drawPath(hull, Paint()..color = const Color(0xFF1565C0));

    // Cockpit
    canvas.drawOval(
      Rect.fromLTWH(shipX + sw * 0.3, shipY + sh * 0.15, sw * 0.4, sh * 0.4),
      Paint()..color = const Color(0xFF00E5FF).withOpacity(0.8),
    );

    // Wing accents
    canvas.drawRect(
      Rect.fromLTWH(shipX, shipY + sh * 0.6, sw * 0.3, sh * 0.15),
      Paint()..color = const Color(0xFF42A5F5),
    );
    canvas.drawRect(
      Rect.fromLTWH(shipX + sw * 0.7, shipY + sh * 0.6, sw * 0.3, sh * 0.15),
      Paint()..color = const Color(0xFF42A5F5),
    );
  }

  void _drawAlien(Canvas canvas, double cs, double ax, double ay, bool isElite) {
    final aw = cs * 1.0;
    final ah = cs * 0.8;
    final color = isElite ? const Color(0xFFE040FB) : const Color(0xFF69F0AE);

    // UFO body
    canvas.drawOval(Rect.fromLTWH(ax, ay + ah * 0.3, aw, ah * 0.7),
        Paint()..color = color);
    // Dome
    canvas.drawOval(Rect.fromLTWH(ax + aw * 0.2, ay, aw * 0.6, ah * 0.6),
        Paint()..color = color.withOpacity(0.6));
    // Eyes
    canvas.drawCircle(Offset(ax + aw * 0.35, ay + ah * 0.55), cs * 0.07,
        Paint()..color = Colors.black);
    canvas.drawCircle(Offset(ax + aw * 0.65, ay + ah * 0.55), cs * 0.07,
        Paint()..color = Colors.black);
    // Glow outline
    canvas.drawOval(
      Rect.fromLTWH(ax - 1, ay + ah * 0.3 - 1, aw + 2, ah * 0.7 + 2),
      Paint()..color = color.withOpacity(0.3)..style = PaintingStyle.stroke..strokeWidth = 1.5,
    );
    // Antenna legs
    for (int i = 0; i < 3; i++) {
      final legX = ax + aw * (0.2 + i * 0.3);
      canvas.drawLine(
        Offset(legX, ay + ah),
        Offset(legX + cs * (i == 1 ? 0 : (i == 0 ? -0.15 : 0.15)), ay + ah + cs * 0.2),
        Paint()..color = color..strokeWidth = 1.5,
      );
    }
  }

  void _drawAsteroid(Canvas canvas, double cs, double radius) {
    final r = radius * cs;
    final path = Path();
    const sides = 8;
    for (int i = 0; i < sides; i++) {
      final angle = i * 2 * pi / sides;
      final jitter = 0.7 + (i * 37 % 7) * 0.05; // pseudo-random via prime
      final x = cos(angle) * r * jitter;
      final y = sin(angle) * r * jitter;
      if (i == 0) path.moveTo(x, y);
      else path.lineTo(x, y);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = const Color(0xFF78909C));
    canvas.drawPath(
      path,
      Paint()..color = const Color(0xFF90A4AE)..style = PaintingStyle.stroke..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_ShooterPainter old) => true;
}
