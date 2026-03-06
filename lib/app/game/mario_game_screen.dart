import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'arcade_input_controller.dart';

// ─── Data classes ─────────────────────────────────────────────────────────────

class _Plat {
  final double x, y, w, h;
  final bool isGround;
  const _Plat(this.x, this.y, this.w, this.h, {this.isGround = false});
}

class _Goomba {
  double x, y, vx;
  bool alive, stomped;
  double stompTimer;
  _Goomba({required this.x, required this.y, this.vx = 1.5})
      : alive = true, stomped = false, stompTimer = 0;
}

class _Coin {
  final double x, y;
  bool collected;
  _Coin(this.x, this.y) : collected = false;
}

enum _PowerType { fireball, life, bigMario }

class _PowerBlock {
  double x, y;
  final _PowerType type;
  bool hit;
  _PowerBlock(this.x, this.y, this.type) : hit = false;
}

class _Fireball {
  double x, y, vx, vy;
  int bounces;
  bool alive;
  static const double kSpeed = 9.0;
  _Fireball(double startX, double startY, bool right)
      : x = startX, y = startY,
        vx = right ? kSpeed : -kSpeed,
        vy = 0,
        bounces = 0,
        alive = true;
}

// ─── Screen ──────────────────────────────────────────────────────────────────

class MarioGameScreen extends StatefulWidget {
  final String userId;
  final DocumentReference rewardsDocRef;
  final double currentSaldo;
  final ArcadeInputController controller;
  final VoidCallback onSaldoChanged;

  const MarioGameScreen({
    super.key,
    required this.userId,
    required this.rewardsDocRef,
    required this.currentSaldo,
    required this.controller,
    required this.onSaldoChanged,
  });

  @override
  State<MarioGameScreen> createState() => _MarioGameScreenState();
}

class _MarioGameScreenState extends State<MarioGameScreen> {
  // Physics
  static const double kGravity    = 30.0;
  static const double kLowGravity = 10.0;
  static const double kMaxJumpHold = 0.5; // seconds
  static const double kWalkSpeed  = 5.5;
  static const double kRunSpeed   = 9.0;
  static const double kJumpVel    = -13.5;
  static const double kMaxFall    = 24.0;
  static const double kPlayerW    = 0.82;
  static const double kPlayerH    = 1.1;
  static const double kEnemyW     = 0.82;
  static const double kEnemyH     = 0.72;
  static const double kPbW        = 0.55; // power block width
  static const double kPbH        = 0.55;
  static const int   kCols        = 10;

  // Player
  double _px = 1.0, _py = 0.0;
  double _pvx = 0.0, _pvy = 0.0;
  bool   _pOnGround = false;
  bool   _pFacingRight = true;
  double _jumpHoldTimer = 0.0;

  // Power-ups
  bool   _isBig = false;
  bool   _hasFireball = false;
  double _fireballActiveTimer = 0.0;
  double _fireballCooldown = 0.0;
  bool   _invincible = false;
  double _invTimer = 0.0;

  // Camera
  double _camX = 0.0;

  // World
  double _worldW = 32.0;
  double _flagX  = 30.0;
  List<_Plat>       _platforms   = [];
  List<_Goomba>     _enemies     = [];
  List<_Coin>       _coins       = [];
  List<_PowerBlock> _powerBlocks = [];
  List<_Fireball>   _fireballs   = [];

  // State
  bool _isRunning = false;
  bool _isDead    = false;
  bool _isLevelComplete = false;
  int  _level  = 1;
  int  _score  = 0;
  int  _lives  = 3;
  late double _saldo;

  Timer?    _ticker;
  DateTime? _lastTick;

  @override
  void initState() {
    super.initState();
    _saldo = widget.currentSaldo;
    _generateMap();
    widget.controller.addListener(_onControllerEvent);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    widget.controller.removeListener(_onControllerEvent);
    super.dispose();
  }

  // ─── Controller ───────────────────────────────────────────────────────────

  void _onControllerEvent() {
    final event = widget.controller.lastEvent;
    if (event == null || !event.isDown) return;
    final btn = event.button;

    if (_isDead) {
      if (btn == ArcadeButton.a || btn == ArcadeButton.start) _tryRestart();
      return;
    }
    if (_isLevelComplete) {
      if (btn == ArcadeButton.a || btn == ArcadeButton.start) _nextLevel();
      return;
    }
    if (!_isRunning) { _startGame(); return; }

    if ((btn == ArcadeButton.a || btn == ArcadeButton.up) && _pOnGround) {
      _pvy = kJumpVel;
      _pOnGround = false;
      _jumpHoldTimer = 0.0;
      HapticFeedback.lightImpact();
    }
    if (btn == ArcadeButton.x && _hasFireball && _fireballCooldown <= 0) {
      _launchFireball();
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
    if (_isDead || _isLevelComplete) return;
    _update(dt);
    if (mounted) setState(() {});
  }

  // ─── Physics & game logic ─────────────────────────────────────────────────

  void _update(double dt) {
    final left  = widget.controller.isHeld(ArcadeButton.left);
    final right = widget.controller.isHeld(ArcadeButton.right);
    final run   = widget.controller.isHeld(ArcadeButton.b) ||
                  widget.controller.isHeld(ArcadeButton.y);
    final holdJump = widget.controller.isHeld(ArcadeButton.a) ||
                     widget.controller.isHeld(ArcadeButton.up);

    // Timers
    if (_fireballCooldown > 0) _fireballCooldown -= dt;
    if (_fireballActiveTimer > 0) {
      _fireballActiveTimer -= dt;
      if (_fireballActiveTimer <= 0) _hasFireball = false;
    }
    if (_invincible) { _invTimer -= dt; if (_invTimer <= 0) _invincible = false; }

    // Horizontal movement
    final spd = run ? kRunSpeed : kWalkSpeed;
    if (left)       { _pvx = -spd; _pFacingRight = false; }
    else if (right) { _pvx =  spd; _pFacingRight = true;  }
    else              _pvx = 0;

    _px += _pvx * dt;
    _px  = _px.clamp(0, _worldW - kPlayerW);

    // Horizontal platform collision
    for (final p in _platforms) {
      if (_py + kPlayerH <= p.y + 0.05 || _py >= p.y + p.h - 0.05) continue;
      if (_px + kPlayerW > p.x && _px < p.x + p.w) {
        if (_pvx > 0) _px = p.x - kPlayerW;
        else if (_pvx < 0) _px = p.x + p.w;
        _pvx = 0;
      }
    }

    // Jump hold: low gravity for up to kMaxJumpHold seconds
    if (holdJump && _pvy < 0 && _jumpHoldTimer < kMaxJumpHold) {
      _pvy += kLowGravity * dt;
      _jumpHoldTimer += dt;
    } else {
      _pvy += kGravity * dt;
    }
    _pvy = _pvy.clamp(-40.0, kMaxFall);

    // Vertical movement
    final prevY = _py;
    _py += _pvy * dt;
    _pOnGround = false;

    for (final p in _platforms) {
      final pL = _px + 0.05, pR = _px + kPlayerW - 0.05;
      if (pR <= p.x || pL >= p.x + p.w) continue;
      final prevBottom = prevY + kPlayerH;
      final newBottom  = _py  + kPlayerH;
      if (_pvy >= 0 && prevBottom <= p.y + 0.08 && newBottom >= p.y) {
        _py = p.y - kPlayerH; _pvy = 0; _pOnGround = true;
      } else if (_pvy < 0 && prevY >= p.y + p.h - 0.08 && _py < p.y + p.h) {
        _py = p.y + p.h; _pvy = 0;
      }
    }

    // Power block hit (player head rises through block bottom)
    for (final pb in _powerBlocks) {
      if (pb.hit) continue;
      if (_pvy >= 0) continue;
      if (_px + kPlayerW <= pb.x || _px >= pb.x + kPbW) continue;
      if (_py < pb.y + kPbH && _py + kPlayerH > pb.y) {
        pb.hit = true;
        _py  = pb.y + kPbH;
        _pvy = 2.0;
        _activatePower(pb.type);
      }
    }

    // Camera
    _camX = (_px - kCols / 2.0 + kPlayerW / 2).clamp(0, _worldW - kCols);

    // Death by falling
    if (_py > 20) { _triggerDeath(); return; }

    // Enemies
    for (final e in _enemies) {
      if (!e.alive) continue;
      if (e.stomped) {
        e.stompTimer -= dt;
        if (e.stompTimer <= 0) e.alive = false;
        continue;
      }
      e.x += e.vx * dt;
      for (final p in _platforms) {
        final eBottom = e.y + kEnemyH;
        if ((eBottom - p.y).abs() < 0.15 && e.x + kEnemyW > p.x && e.x < p.x + p.w) {
          if (e.x < p.x)              { e.x = p.x;              e.vx =  e.vx.abs(); }
          if (e.x + kEnemyW > p.x + p.w) { e.x = p.x + p.w - kEnemyW; e.vx = -e.vx.abs(); }
        }
      }
      if (!_invincible) {
        final overX = _px + kPlayerW > e.x && _px < e.x + kEnemyW;
        final overY = _py + kPlayerH > e.y && _py < e.y + kEnemyH;
        if (overX && overY) {
          if (_pvy > 0 && _py + kPlayerH < e.y + kEnemyH * 0.6) {
            e.stomped = true; e.stompTimer = 0.35;
            _pvy = -9.0; _score += 100;
            HapticFeedback.mediumImpact();
          } else {
            _handlePlayerHit(); return;
          }
        }
      }
    }

    // Coins
    for (final c in _coins) {
      if (c.collected) continue;
      if ((_px + kPlayerW / 2 - (c.x + 0.25)).abs() < 0.55 &&
          (_py + kPlayerH / 2 - (c.y + 0.25)).abs() < 0.55) {
        c.collected = true; _score += 50;
      }
    }

    // Fireballs
    _updateFireballs(dt);

    // Flag
    if ((_px + kPlayerW / 2 - (_flagX + 0.3)).abs() < 1.0 && _py + kPlayerH > 6) {
      _levelComplete();
    }
  }

  void _activatePower(_PowerType type) {
    switch (type) {
      case _PowerType.fireball:
        _hasFireball = true;
        _fireballActiveTimer = 25.0; // 25 seconds
        HapticFeedback.heavyImpact();
      case _PowerType.life:
        _lives++;
        HapticFeedback.heavyImpact();
      case _PowerType.bigMario:
        _isBig = true;
        HapticFeedback.heavyImpact();
    }
  }

  void _launchFireball() {
    _fireballCooldown = 0.45;
    _fireballs.add(_Fireball(
      _px + (_pFacingRight ? kPlayerW + 0.1 : -0.4),
      _py + kPlayerH * 0.3,
      _pFacingRight,
    ));
  }

  void _updateFireballs(double dt) {
    for (final fb in _fireballs) {
      if (!fb.alive) continue;
      fb.vy += kGravity * dt;
      fb.x  += fb.vx * dt;
      fb.y  += fb.vy * dt;

      // Bounce off platforms
      for (final p in _platforms) {
        final fbL = fb.x - 0.15, fbR = fb.x + 0.15;
        if (fbR <= p.x || fbL >= p.x + p.w) continue;
        if (fb.vy > 0 && fb.y >= p.y && fb.y < p.y + p.h) {
          fb.y  = p.y - 0.01;
          fb.vy = -(fb.vy * 0.6).clamp(2.0, 6.0);
          fb.bounces++;
          if (fb.bounces > 3) fb.alive = false;
        }
      }

      // Off-screen
      if (fb.x < -1 || fb.x > _worldW + 1 || fb.y > 20) fb.alive = false;

      // Hit enemies
      for (final e in _enemies) {
        if (!e.alive || e.stomped) continue;
        if (fb.x > e.x && fb.x < e.x + kEnemyW && fb.y > e.y && fb.y < e.y + kEnemyH) {
          e.stomped = true; e.stompTimer = 0.3;
          fb.alive = false; _score += 150;
          break;
        }
      }
    }
    _fireballs.removeWhere((fb) => !fb.alive);
  }

  void _handlePlayerHit() {
    if (_isBig) {
      _isBig = false;
      _invincible = true;
      _invTimer = 2.0;
    } else if (_invincible) {
      // no-op
    } else {
      _triggerDeath();
    }
  }

  void _triggerDeath() {
    _ticker?.cancel();
    _lives--;
    HapticFeedback.heavyImpact();
    if (mounted) setState(() { _isDead = true; _isRunning = false; });
  }

  void _levelComplete() {
    _ticker?.cancel();
    _score += 500;
    HapticFeedback.heavyImpact();
    if (mounted) setState(() { _isLevelComplete = true; _isRunning = false; });
  }

  void _tryRestart() {
    if (_lives <= 0) { _lives = 3; _score = 0; _level = 1; }
    _generateMap();
    _startGame();
  }

  void _nextLevel() {
    _level++;
    _generateMap();
    _startGame();
  }

  // ─── Procedural map generation ────────────────────────────────────────────

  void _generateMap() {
    _ticker?.cancel();
    _isRunning = false; _isDead = false; _isLevelComplete = false;
    _pvx = 0; _pvy = 0; _pOnGround = false; _camX = 0;
    _isBig = false; _hasFireball = false; _fireballActiveTimer = 0;
    _fireballCooldown = 0; _invincible = false; _invTimer = 0;
    _fireballs = [];

    final rng   = Random();
    final diff  = (_level - 1).clamp(0, 5); // difficulty 0-5

    // World dimensions
    _worldW = 28.0 + diff * 2.0 + rng.nextDouble() * 4.0;
    _flagX  = _worldW - 2.5;
    _px = 1.0; _py = 11.4;

    _platforms   = [];
    _enemies     = [];
    _coins       = [];
    _powerBlocks = [];

    // ── Ground with gaps ─────────────────────────────────────────────────
    final gapCount    = 1 + (diff ~/ 2).clamp(0, 2);
    final gaps        = <(double, double)>[];
    double safeStart  = 6.0;
    for (int i = 0; i < gapCount; i++) {
      final gapStart = safeStart + 3.0 + rng.nextDouble() * 4.0;
      final gapW     = 1.4 + rng.nextDouble() * 0.6;
      if (gapStart + gapW > _worldW - 5.0) break;
      gaps.add((gapStart, gapStart + gapW));
      safeStart = gapStart + gapW + 3.5;
    }

    double prevEnd = 0.0;
    for (final (gs, ge) in gaps) {
      if (gs > prevEnd + 0.5) {
        _platforms.add(_Plat(prevEnd, 13.0, gs - prevEnd, 3.0, isGround: true));
      }
      prevEnd = ge;
    }
    _platforms.add(_Plat(prevEnd, 13.0, _worldW - prevEnd, 3.0, isGround: true));

    // ── Floating platforms ───────────────────────────────────────────────
    double x = 2.5;
    while (x < _worldW - 4.5) {
      final platY = 10.0 + rng.nextDouble() * 2.5; // y 10.0–12.5
      final platW = 1.5 + rng.nextDouble() * 1.8;
      _platforms.add(_Plat(x, platY, platW, 0.5));

      // Enemy (~25% + diff * 5%)
      if (rng.nextDouble() < 0.25 + diff * 0.05) {
        final baseSpeed = 0.8 + rng.nextDouble() * (1.0 + diff * 0.3);
        _enemies.add(_Goomba(x: x + 0.1, y: platY - kEnemyH, vx: baseSpeed));
      }

      // Coins above platform
      final coinCount = 1 + rng.nextInt(3);
      for (int i = 0; i < coinCount; i++) {
        final cx = x + (i - (coinCount - 1) / 2.0) * 0.65 + platW / 2;
        _coins.add(_Coin(cx, platY - 1.1));
      }

      // Power block (~12%, rare)
      if (rng.nextDouble() < 0.12) {
        final typeRoll = rng.nextDouble();
        final type = typeRoll < 0.45
            ? _PowerType.bigMario
            : typeRoll < 0.75
                ? _PowerType.fireball
                : _PowerType.life;
        _powerBlocks.add(_PowerBlock(x + platW / 2 - kPbW / 2, platY - 1.15, type));
      }

      x += 2.4 + rng.nextDouble() * 2.2;
    }

    // ── Ground enemies ───────────────────────────────────────────────────
    for (final p in _platforms.where((p) => p.isGround)) {
      if (p.w > 3.5 && rng.nextDouble() < 0.45) {
        final ex = p.x + 2.0 + rng.nextDouble() * (p.w - 2.5);
        _enemies.add(_Goomba(x: ex, y: 13.0 - kEnemyH,
            vx: 0.9 + rng.nextDouble() * (0.8 + diff * 0.25)));
      }
    }
  }

  // ─── Firestore ───────────────────────────────────────────────────────────

  Future<void> _updateFirestore(double newSaldo) async {
    try {
      final userCardRef = FirebaseFirestore.instance
          .collection('users').doc(widget.userId)
          .collection('rewardsCard').doc('cardInfo');
      final batch = FirebaseFirestore.instance.batch();
      batch.update(userCardRef, {'saldo': newSaldo});
      batch.update(widget.rewardsDocRef, {'saldo': newSaldo});
      await batch.commit();
    } catch (e) { debugPrint('Mario Firestore error: $e'); }
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, cons) {
      return Stack(children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Color(0xFF4FC3F7), Color(0xFF81D4FA)],
              ),
            ),
          ),
        ),
        CustomPaint(
          painter: _MarioPainter(
            platforms: _platforms, enemies: _enemies,
            coins: _coins, powerBlocks: _powerBlocks, fireballs: _fireballs,
            px: _px, py: _py, pvx: _pvx, pvy: _pvy,
            camX: _camX, flagX: _flagX,
            pFacingRight: _pFacingRight,
            isBig: _isBig,
            invincible: _invincible, invTimer: _invTimer,
            kCols: kCols,
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
              if (_isBig) _chip('🍄 Grande', Colors.orange.shade700),
              if (_hasFireball) _chip('🔥 ${_fireballActiveTimer.toInt()}s', Colors.red.shade700),
              _chip('⭐ $_score'),
              _chip('Niv $_level'),
            ],
          ),
        ),
        if (!_isRunning && !_isDead && !_isLevelComplete) _buildStartOverlay(),
        if (_isDead) _buildDeathOverlay(),
        if (_isLevelComplete) _buildCompleteOverlay(),
      ]);
    });
  }

  Widget _chip(String t, [Color? bg]) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: bg ?? Colors.black54,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(t, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
  );

  Widget _buildStartOverlay() => Positioned.fill(
    child: Container(
      color: Colors.black54,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('🍄', style: TextStyle(fontSize: 52)),
        const SizedBox(height: 10),
        const Text('SUPER ARCADE', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 3)),
        Text('Nivel $_level — Mapa nuevo', style: const TextStyle(color: Colors.yellow, fontSize: 12)),
        const SizedBox(height: 18),
        const Text('Pulsa cualquier botón para empezar', style: TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 4),
        const Text('D-pad mover  ·  A saltar  ·  B correr', style: TextStyle(color: Colors.white54, fontSize: 11)),
        const Text('X disparar bola de fuego  ·  Pisa los Goombas', style: TextStyle(color: Colors.white38, fontSize: 10)),
        const SizedBox(height: 4),
        const Text('Bloques amarillos: poderes', style: TextStyle(color: Colors.yellow, fontSize: 10)),
      ]),
    ),
  );

  Widget _buildDeathOverlay() => Positioned.fill(
    child: Container(
      color: Colors.black87,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(_lives <= 0 ? '💀 FIN DEL JUEGO' : '😵 ¡Perdiste una vida!',
            style: const TextStyle(color: Colors.red, fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('Puntuación: $_score', style: const TextStyle(color: Colors.white, fontSize: 16)),
        if (_lives > 0) Text('Vidas restantes: $_lives', style: const TextStyle(color: Colors.yellow, fontSize: 13)),
        const SizedBox(height: 18),
        ElevatedButton(
          onPressed: _tryRestart,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white, shape: const StadiumBorder()),
          child: Text(_lives <= 0 ? 'Nueva partida' : 'Continuar'),
        ),
        const SizedBox(height: 8),
        const Text('SELECT para volver al menú', style: TextStyle(color: Colors.white38, fontSize: 10)),
      ]),
    ),
  );

  Widget _buildCompleteOverlay() => Positioned.fill(
    child: Container(
      color: Colors.black.withOpacity(0.8),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('🏁', style: TextStyle(fontSize: 52)),
        const Text('¡NIVEL COMPLETADO!', style: TextStyle(color: Colors.yellow, fontSize: 18, fontWeight: FontWeight.bold)),
        Text('+500 puntos  ·  Total: $_score', style: const TextStyle(color: Colors.white, fontSize: 14)),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _nextLevel,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white, shape: const StadiumBorder()),
          child: const Text('Siguiente nivel →'),
        ),
      ]),
    ),
  );
}

// ─── Painter ─────────────────────────────────────────────────────────────────

class _MarioPainter extends CustomPainter {
  final List<_Plat>       platforms;
  final List<_Goomba>     enemies;
  final List<_Coin>       coins;
  final List<_PowerBlock> powerBlocks;
  final List<_Fireball>   fireballs;
  final double px, py, pvx, pvy, camX, flagX;
  final bool   pFacingRight, isBig, invincible;
  final double invTimer;
  final int    kCols;

  static const double kPlayerW = 0.82;
  static const double kPlayerH = 1.1;
  static const double kEnemyW  = 0.82;
  static const double kEnemyH  = 0.72;
  static const double kPbW     = 0.55;
  static const double kPbH     = 0.55;

  const _MarioPainter({
    required this.platforms, required this.enemies,
    required this.coins,     required this.powerBlocks, required this.fireballs,
    required this.px,        required this.py,
    required this.pvx,       required this.pvy,
    required this.camX,      required this.flagX,
    required this.pFacingRight, required this.isBig,
    required this.invincible, required this.invTimer,
    required this.kCols,
  });

  double sx(double wx, double cs) => (wx - camX) * cs;
  double sy(double wy, double cs) => wy * cs;

  @override
  void paint(Canvas canvas, Size size) {
    final cs = size.width / kCols;

    _drawClouds(canvas, cs);

    // Platforms
    for (final p in platforms) {
      final scx = sx(p.x, cs);
      final scw = p.w * cs;
      if (scx + scw < 0 || scx > size.width) continue;
      final scy = sy(p.y, cs);
      final sch = p.h * cs;
      if (p.isGround) {
        canvas.drawRect(Rect.fromLTWH(scx, scy, scw, sch), Paint()..color = const Color(0xFF8B5E3C));
        canvas.drawRect(Rect.fromLTWH(scx, scy, scw, cs * 0.35), Paint()..color = const Color(0xFF4CAF50));
        canvas.drawRect(Rect.fromLTWH(scx, scy + cs * 0.35, scw, cs * 0.15), Paint()..color = const Color(0xFF388E3C));
      } else {
        final brick = Paint()..color = const Color(0xFFCD853F);
        final mortar = Paint()..color = const Color(0xFF8B6914);
        canvas.drawRect(Rect.fromLTWH(scx, scy, scw, sch), brick);
        canvas.drawRect(Rect.fromLTWH(scx, scy, scw, 1.5), mortar);
        canvas.drawRect(Rect.fromLTWH(scx, scy + sch - 1.5, scw, 1.5), mortar);
        for (double bx = scx; bx < scx + scw; bx += cs * 0.7) {
          canvas.drawRect(Rect.fromLTWH(bx, scy, 1.5, sch), mortar);
        }
      }
    }

    // Power blocks
    for (final pb in powerBlocks) {
      final pbsx = sx(pb.x, cs);
      if (pbsx + kPbW * cs < 0 || pbsx > size.width) continue;
      final pbsy = sy(pb.y, cs);
      final pbw = kPbW * cs, pbh = kPbH * cs;
      if (pb.hit) {
        canvas.drawRect(Rect.fromLTWH(pbsx, pbsy, pbw, pbh),
            Paint()..color = const Color(0xFF8B6914));
      } else {
        // Yellow ? block
        final blockColor = switch (pb.type) {
          _PowerType.fireball  => const Color(0xFFFF6F00),
          _PowerType.life      => const Color(0xFF2E7D32),
          _PowerType.bigMario  => const Color(0xFFF9A825),
        };
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(pbsx, pbsy, pbw, pbh), Radius.circular(cs * 0.08)),
          Paint()..color = blockColor,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(pbsx, pbsy, pbw, pbh), Radius.circular(cs * 0.08)),
          Paint()..color = Colors.white24..style = PaintingStyle.stroke..strokeWidth = 1.5,
        );
        // "?" symbol
        final tp = TextPainter(
          text: TextSpan(text: '?', style: TextStyle(color: Colors.white, fontSize: pbh * 0.7, fontWeight: FontWeight.bold)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(pbsx + (pbw - tp.width) / 2, pbsy + (pbh - tp.height) / 2));
      }
    }

    // Coins
    for (final c in coins) {
      if (c.collected) continue;
      final cx = sx(c.x + 0.25, cs), cy = sy(c.y + 0.25, cs);
      if (cx < -cs || cx > size.width + cs) continue;
      canvas.drawCircle(Offset(cx, cy), cs * 0.2, Paint()..color = const Color(0xFFFFD700));
      canvas.drawCircle(Offset(cx, cy), cs * 0.12, Paint()..color = const Color(0xFFFFA000));
    }

    // Fireballs
    for (final fb in fireballs) {
      final fbsx = sx(fb.x, cs), fbsy = sy(fb.y, cs);
      canvas.drawCircle(Offset(fbsx, fbsy), cs * 0.18, Paint()..color = const Color(0xFFFF6D00));
      canvas.drawCircle(Offset(fbsx, fbsy), cs * 0.10, Paint()..color = Colors.yellow);
    }

    // Flag / goal
    final fsx = sx(flagX + 0.3, cs);
    if (fsx > -cs && fsx < size.width + cs) {
      final poleTop = sy(6.0, cs), poleBot = sy(13.0, cs);
      canvas.drawRect(Rect.fromLTWH(fsx - 2, poleTop, 4, poleBot - poleTop),
          Paint()..color = Colors.grey.shade400);
      final fp = Path()
        ..moveTo(fsx + 2, poleTop)
        ..lineTo(fsx + cs * 0.7 + 2, poleTop + cs * 0.4)
        ..lineTo(fsx + 2, poleTop + cs * 0.8);
      canvas.drawPath(fp, Paint()..color = Colors.red);
    }

    // Enemies
    for (final e in enemies) {
      if (!e.alive) continue;
      final esx = sx(e.x, cs);
      if (esx + kEnemyW * cs < 0 || esx > size.width) continue;
      final esy = sy(e.y, cs);
      final ew = kEnemyW * cs;
      final eh = e.stomped ? kEnemyH * cs * 0.3 : kEnemyH * cs;
      final bodyR = Rect.fromLTWH(esx, esy + (kEnemyH * cs - eh), ew, eh);
      canvas.drawOval(bodyR, Paint()..color = const Color(0xFF8B4513));
      if (!e.stomped) {
        canvas.drawCircle(Offset(esx + ew * 0.3, esy + eh * 0.25), cs * 0.09, Paint()..color = Colors.white);
        canvas.drawCircle(Offset(esx + ew * 0.7, esy + eh * 0.25), cs * 0.09, Paint()..color = Colors.white);
        canvas.drawCircle(Offset(esx + ew * 0.32, esy + eh * 0.28), cs * 0.055, Paint()..color = Colors.black);
        canvas.drawCircle(Offset(esx + ew * 0.72, esy + eh * 0.28), cs * 0.055, Paint()..color = Colors.black);
        canvas.drawOval(Rect.fromLTWH(esx, esy + eh - cs * 0.15, ew * 0.48, cs * 0.2), Paint()..color = const Color(0xFF5D2E0C));
        canvas.drawOval(Rect.fromLTWH(esx + ew * 0.52, esy + eh - cs * 0.15, ew * 0.48, cs * 0.2), Paint()..color = const Color(0xFF5D2E0C));
      }
    }

    // Player (blink when invincible)
    if (!invincible || (DateTime.now().millisecondsSinceEpoch ~/ 120).isEven) {
      _drawPlayer(canvas, cs);
    }
  }

  void _drawPlayer(Canvas canvas, double cs) {
    final scale = isBig ? 1.45 : 1.0;
    final psx = sx(px, cs);
    final psy = sy(py, cs);
    final pw = kPlayerW * cs * scale;
    final ph = kPlayerH * cs * scale;

    canvas.drawRect(Rect.fromLTWH(psx, psy + ph * 0.55, pw * 0.45, ph * 0.45),
        Paint()..color = const Color(0xFF1565C0));
    canvas.drawRect(Rect.fromLTWH(psx + pw * 0.55, psy + ph * 0.55, pw * 0.45, ph * 0.45),
        Paint()..color = const Color(0xFF1565C0));
    canvas.drawRect(Rect.fromLTWH(psx, psy + ph * 0.42, pw, ph * 0.2),
        Paint()..color = const Color(0xFFE53935));
    canvas.drawOval(Rect.fromLTWH(psx + pw * 0.05, psy, pw * 0.9, ph * 0.52),
        Paint()..color = const Color(0xFFFFCCBC));
    canvas.drawRect(Rect.fromLTWH(psx, psy + ph * 0.1, pw, ph * 0.2),
        Paint()..color = const Color(0xFFC62828));
    canvas.drawRect(Rect.fromLTWH(psx + pw * 0.1, psy, pw * 0.8, ph * 0.15),
        Paint()..color = const Color(0xFFC62828));
    final eyeOffX = pFacingRight ? pw * 0.65 : pw * 0.2;
    canvas.drawCircle(Offset(psx + eyeOffX, psy + ph * 0.25), cs * 0.07 * scale, Paint()..color = Colors.black);
    final mustX = pFacingRight ? psx + pw * 0.35 : psx + pw * 0.05;
    canvas.drawRect(Rect.fromLTWH(mustX, psy + ph * 0.35, pw * 0.55, ph * 0.07),
        Paint()..color = const Color(0xFF5D2E0C));
  }

  void _drawClouds(Canvas canvas, double cs) {
    final positions = [2.0, 7.5, 14.0, 20.5, 27.0];
    final scales    = [2.0, 1.5, 2.2,  1.8,  2.0];
    for (int i = 0; i < positions.length; i++) {
      final cx = sx(positions[i], cs);
      if (cx + cs * 4 < 0 || cx > 99999) continue;
      final cy = cs * (0.8 + (i % 3) * 0.5);
      final sc = scales[i];
      final p  = Paint()..color = Colors.white.withOpacity(0.82);
      canvas.drawOval(Rect.fromLTWH(cx, cy, cs * 2 * sc, cs * 0.8 * sc), p);
      canvas.drawOval(Rect.fromLTWH(cx + cs * 0.4 * sc, cy - cs * 0.4 * sc, cs * 1.2 * sc, cs * 0.8 * sc), p);
      canvas.drawOval(Rect.fromLTWH(cx + cs * 1.0 * sc, cy - cs * 0.25 * sc, cs * 0.9 * sc, cs * 0.6 * sc), p);
    }
  }

  @override
  bool shouldRepaint(_MarioPainter old) => true;
}
