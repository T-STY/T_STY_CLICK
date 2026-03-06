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
      : alive = true,
        stomped = false,
        stompTimer = 0;
}

class _Coin {
  final double x, y;
  bool collected;
  _Coin(this.x, this.y) : collected = false;
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
  // Physics (cells/s)
  static const double kGravity = 30.0;
  static const double kLowGravity = 12.0; // when holding A while rising
  static const double kWalkSpeed = 5.5;
  static const double kRunSpeed = 9.0;
  static const double kJumpVel = -13.5;
  static const double kMaxFall = 24.0;
  static const double kPlayerW = 0.82;
  static const double kPlayerH = 1.1;
  static const double kEnemyW = 0.82;
  static const double kEnemyH = 0.72;
  static const int kCols = 10;

  // Player
  double _px = 1.0, _py = 0.0;
  double _pvx = 0.0, _pvy = 0.0;
  bool _pOnGround = false;
  bool _pFacingRight = true;

  // Camera
  double _camX = 0.0;

  // World
  double _worldW = 32.0;
  double _flagX = 30.0;
  List<_Plat> _platforms = [];
  List<_Goomba> _enemies = [];
  List<_Coin> _coins = [];

  // State
  bool _isRunning = false;
  bool _isDead = false;
  bool _isLevelComplete = false;
  int _level = 1;
  int _score = 0;
  int _lives = 3;
  late double _saldo;

  Timer? _ticker;
  DateTime? _lastTick;

  @override
  void initState() {
    super.initState();
    _saldo = widget.currentSaldo;
    _loadLevel(1);
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
      if (btn == ArcadeButton.a || btn == ArcadeButton.start) _tryRestart();
      return;
    }
    if (_isLevelComplete) {
      if (btn == ArcadeButton.a || btn == ArcadeButton.start) _nextLevel();
      return;
    }
    if (!_isRunning) {
      _startGame();
      return;
    }
    // Jump: only on isDown event
    if ((btn == ArcadeButton.a || btn == ArcadeButton.up) && _pOnGround) {
      _pvy = kJumpVel;
      _pOnGround = false;
      HapticFeedback.lightImpact();
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

  void _update(double dt) {
    final left = widget.controller.isHeld(ArcadeButton.left);
    final right = widget.controller.isHeld(ArcadeButton.right);
    final run = widget.controller.isHeld(ArcadeButton.b) || widget.controller.isHeld(ArcadeButton.y);
    final holdJump = widget.controller.isHeld(ArcadeButton.a) || widget.controller.isHeld(ArcadeButton.up);

    // Horizontal
    final spd = run ? kRunSpeed : kWalkSpeed;
    if (left) { _pvx = -spd; _pFacingRight = false; }
    else if (right) { _pvx = spd; _pFacingRight = true; }
    else _pvx = 0;

    // Horizontal move + resolve
    _px += _pvx * dt;
    _px = _px.clamp(0, _worldW - kPlayerW);
    for (final p in _platforms) {
      if (_py + kPlayerH <= p.y + 0.05 || _py >= p.y + p.h - 0.05) continue;
      if (_px + kPlayerW > p.x && _px < p.x + p.w) {
        if (_pvx > 0 && _px + kPlayerW > p.x) {
          _px = p.x - kPlayerW;
        } else if (_pvx < 0 && _px < p.x + p.w) {
          _px = p.x + p.w;
        }
        _pvx = 0;
      }
    }

    // Gravity (low gravity when holding jump while rising)
    final effectiveG = (holdJump && _pvy < 0) ? kLowGravity : kGravity;
    _pvy = (_pvy + effectiveG * dt).clamp(-40.0, kMaxFall);

    // Vertical move + resolve
    final prevY = _py;
    _py += _pvy * dt;
    _pOnGround = false;

    for (final p in _platforms) {
      final pLeft = _px + 0.05;
      final pRight = _px + kPlayerW - 0.05;
      if (pRight <= p.x || pLeft >= p.x + p.w) continue;

      final prevBottom = prevY + kPlayerH;
      final newBottom = _py + kPlayerH;

      if (_pvy >= 0 && prevBottom <= p.y + 0.08 && newBottom >= p.y) {
        _py = p.y - kPlayerH;
        _pvy = 0;
        _pOnGround = true;
      } else if (_pvy < 0 && prevY >= p.y + p.h - 0.08 && _py < p.y + p.h) {
        _py = p.y + p.h;
        _pvy = 0;
      }
    }

    // Camera
    _camX = (_px - kCols / 2.0 + kPlayerW / 2).clamp(0, _worldW - kCols);

    // Fell off bottom
    if (_py > 20) { _triggerDeath(); return; }

    // Enemy logic
    for (final e in _enemies) {
      if (!e.alive) continue;
      if (e.stomped) {
        e.stompTimer -= dt;
        if (e.stompTimer <= 0) e.alive = false;
        continue;
      }
      // Move
      e.x += e.vx * dt;
      // Bounce at platform edges
      for (final p in _platforms) {
        final eBottom = e.y + kEnemyH;
        final onThisPlat = (eBottom - p.y).abs() < 0.15 &&
            e.x + kEnemyW > p.x && e.x < p.x + p.w;
        if (onThisPlat) {
          if (e.x < p.x) { e.x = p.x; e.vx = e.vx.abs(); }
          if (e.x + kEnemyW > p.x + p.w) { e.x = p.x + p.w - kEnemyW; e.vx = -e.vx.abs(); }
        }
      }
      // Player vs enemy AABB
      final overX = _px + kPlayerW > e.x && _px < e.x + kEnemyW;
      final overY = _py + kPlayerH > e.y && _py < e.y + kEnemyH;
      if (overX && overY) {
        // Stomp if player falling onto top of enemy
        if (_pvy > 0 && _py + kPlayerH < e.y + kEnemyH * 0.6) {
          e.stomped = true;
          e.stompTimer = 0.35;
          _pvy = -9.0;
          _score += 100;
          HapticFeedback.mediumImpact();
        } else {
          _triggerDeath();
          return;
        }
      }
    }

    // Coin collection
    for (final c in _coins) {
      if (c.collected) continue;
      if ((_px + kPlayerW / 2 - (c.x + 0.25)).abs() < 0.5 &&
          (_py + kPlayerH / 2 - (c.y + 0.25)).abs() < 0.5) {
        c.collected = true;
        _score += 50;
      }
    }

    // Flag (goal)
    if ((_px + kPlayerW / 2 - (_flagX + 0.3)).abs() < 1.0 && _py + kPlayerH > 6) {
      _levelComplete();
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
    _loadLevel(_level);
    _startGame();
  }

  void _nextLevel() {
    _level = (_level % 2) + 1;
    _loadLevel(_level);
    _startGame();
  }

  void _loadLevel(int lvl) {
    _ticker?.cancel();
    _isRunning = false;
    _isDead = false;
    _isLevelComplete = false;
    _pvx = 0;
    _pvy = 0;
    _pOnGround = false;
    _camX = 0;

    if (lvl == 1) {
      _worldW = 32.0; _flagX = 30.0;
      _px = 1.0; _py = 11.4;
      _platforms = [
        const _Plat(0, 12.5, 12.0, 3.5, isGround: true),
        const _Plat(14.0, 12.5, 18.0, 3.5, isGround: true),
        const _Plat(2.5, 11.0, 2.5, 0.5),
        const _Plat(5.5, 9.5, 2.5, 0.5),
        const _Plat(9.5, 11.0, 2.5, 0.5),
        const _Plat(16.0, 10.5, 2.5, 0.5),
        const _Plat(20.0, 9.0, 2.5, 0.5),
        const _Plat(23.5, 10.5, 2.5, 0.5),
        const _Plat(27.0, 9.5, 2.5, 0.5),
      ];
      _enemies = [
        _Goomba(x: 3.0, y: 11.0 - kEnemyH, vx: 1.2),
        _Goomba(x: 8.0, y: 12.5 - kEnemyH, vx: 1.4),
        _Goomba(x: 17.0, y: 10.5 - kEnemyH, vx: 1.1),
        _Goomba(x: 22.0, y: 12.5 - kEnemyH, vx: 1.6),
        _Goomba(x: 28.0, y: 9.5 - kEnemyH, vx: 1.3),
      ];
      _coins = [
        for (double x = 3.0; x <= 4.5; x += 0.75) _Coin(x, 9.8),
        for (double x = 6.0; x <= 7.5; x += 0.75) _Coin(x, 8.3),
        for (double x = 10.0; x <= 11.5; x += 0.75) _Coin(x, 9.8),
        _Coin(5.5, 12.0), _Coin(6.5, 12.0), _Coin(8.5, 12.0),
        for (double x = 16.5; x <= 18.0; x += 0.75) _Coin(x, 9.3),
        for (double x = 20.5; x <= 22.0; x += 0.75) _Coin(x, 7.8),
        for (double x = 24.0; x <= 25.5; x += 0.75) _Coin(x, 9.3),
        for (double x = 27.5; x <= 29.0; x += 0.75) _Coin(x, 8.3),
      ];
    } else {
      _worldW = 34.0; _flagX = 32.0;
      _px = 1.0; _py = 11.4;
      _platforms = [
        const _Plat(0, 12.5, 10.0, 3.5, isGround: true),
        const _Plat(12.5, 12.5, 8.0, 3.5, isGround: true),
        const _Plat(23.0, 12.5, 11.0, 3.5, isGround: true),
        const _Plat(2.0, 10.5, 2.0, 0.5),
        const _Plat(5.0, 9.0, 2.0, 0.5),
        const _Plat(7.5, 11.0, 2.0, 0.5),
        const _Plat(13.0, 10.5, 2.0, 0.5),
        const _Plat(16.0, 8.5, 2.0, 0.5),
        const _Plat(18.5, 10.5, 2.0, 0.5),
        const _Plat(23.5, 10.0, 2.0, 0.5),
        const _Plat(26.5, 8.5, 2.5, 0.5),
        const _Plat(29.5, 10.0, 2.5, 0.5),
      ];
      _enemies = [
        _Goomba(x: 2.5, y: 10.5 - kEnemyH, vx: 1.8),
        _Goomba(x: 5.5, y: 9.0 - kEnemyH, vx: 1.5),
        _Goomba(x: 8.0, y: 12.5 - kEnemyH, vx: 2.0),
        _Goomba(x: 13.5, y: 10.5 - kEnemyH, vx: 1.7),
        _Goomba(x: 16.5, y: 8.5 - kEnemyH, vx: 1.9),
        _Goomba(x: 24.0, y: 12.5 - kEnemyH, vx: 2.2),
        _Goomba(x: 27.0, y: 8.5 - kEnemyH, vx: 1.6),
      ];
      _coins = [
        for (double x = 2.5; x <= 3.5; x += 0.6) _Coin(x, 9.3),
        for (double x = 5.5; x <= 6.5; x += 0.6) _Coin(x, 7.8),
        for (double x = 7.5; x <= 8.5; x += 0.6) _Coin(x, 12.0),
        for (double x = 13.5; x <= 14.5; x += 0.6) _Coin(x, 9.3),
        for (double x = 16.5; x <= 17.5; x += 0.6) _Coin(x, 7.3),
        for (double x = 19.0; x <= 20.0; x += 0.6) _Coin(x, 9.3),
        for (double x = 24.0; x <= 25.0; x += 0.6) _Coin(x, 8.8),
        for (double x = 27.0; x <= 28.5; x += 0.6) _Coin(x, 7.3),
        for (double x = 30.0; x <= 31.0; x += 0.6) _Coin(x, 8.8),
      ];
    }
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, cons) {
      final cs = cons.maxWidth / kCols;
      return Stack(children: [
        // Sky gradient background
        Positioned.fill(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF4FC3F7), Color(0xFF81D4FA)],
              ),
            ),
          ),
        ),
        // Game content
        CustomPaint(
          painter: _MarioPainter(
            platforms: _platforms,
            enemies: _enemies,
            coins: _coins,
            px: _px, py: _py,
            pvx: _pvx, pvy: _pvy,
            camX: _camX,
            flagX: _flagX,
            pFacingRight: _pFacingRight,
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
              _chip('⭐ $_score'),
              _chip('Lvl $_level'),
            ],
          ),
        ),
        // Overlays
        if (!_isRunning && !_isDead && !_isLevelComplete)
          _buildStartOverlay(cs),
        if (_isDead) _buildDeathOverlay(),
        if (_isLevelComplete) _buildCompleteOverlay(),
      ]);
    });
  }

  Widget _chip(String t) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
    child: Text(t, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
  );

  Widget _buildStartOverlay(double cs) => Positioned.fill(
    child: Container(
      color: Colors.black54,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('🍄', style: TextStyle(fontSize: 52)),
        const SizedBox(height: 10),
        const Text('SUPER ARCADE', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 3)),
        Text('Nivel $_level', style: const TextStyle(color: Colors.yellow, fontSize: 13)),
        const SizedBox(height: 18),
        const Text('Pulsa cualquier botón', style: TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 4),
        const Text('D-pad moverse · A saltar · B correr', style: TextStyle(color: Colors.white54, fontSize: 11)),
        const Text('Salta encima de los Goombas 👾', style: TextStyle(color: Colors.white38, fontSize: 10)),
      ]),
    ),
  );

  Widget _buildDeathOverlay() => Positioned.fill(
    child: Container(
      color: Colors.black87,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(_lives <= 0 ? '💀 GAME OVER' : '😵 ¡Perdiste una vida!',
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
        const Text('B para volver al menú', style: TextStyle(color: Colors.white38, fontSize: 10)),
      ]),
    ),
  );

  Widget _buildCompleteOverlay() => Positioned.fill(
    child: Container(
      color: Colors.black.withOpacity(0.8),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('🏁', style: TextStyle(fontSize: 52)),
        const Text('¡NIVEL COMPLETO!', style: TextStyle(color: Colors.yellow, fontSize: 18, fontWeight: FontWeight.bold)),
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
  final List<_Plat> platforms;
  final List<_Goomba> enemies;
  final List<_Coin> coins;
  final double px, py, pvx, pvy, camX, flagX;
  final bool pFacingRight;
  final int kCols;

  static const double kPlayerW = 0.82;
  static const double kPlayerH = 1.1;
  static const double kEnemyW = 0.82;
  static const double kEnemyH = 0.72;

  const _MarioPainter({
    required this.platforms,
    required this.enemies,
    required this.coins,
    required this.px, required this.py,
    required this.pvx, required this.pvy,
    required this.camX, required this.flagX,
    required this.pFacingRight,
    required this.kCols,
  });

  double sx(double worldX, double cs) => (worldX - camX) * cs;
  double sy(double worldY, double cs) => worldY * cs;

  @override
  void paint(Canvas canvas, Size size) {
    final cs = size.width / kCols;

    // Clouds (decorative)
    _drawCloud(canvas, cs, 2.0, 2.0);
    _drawCloud(canvas, cs, 7.0, 1.5);
    _drawCloud(canvas, cs, 14.0, 2.5);
    _drawCloud(canvas, cs, 20.0, 1.8);
    _drawCloud(canvas, cs, 27.0, 2.2);

    // Platforms
    for (final p in platforms) {
      final screenX = sx(p.x, cs);
      final screenW = p.w * cs;
      if (screenX + screenW < 0 || screenX > size.width) continue;
      final screenY = sy(p.y, cs);
      final screenH = p.h * cs;

      if (p.isGround) {
        // Ground: brown body
        canvas.drawRect(
          Rect.fromLTWH(screenX, screenY, screenW, screenH),
          Paint()..color = const Color(0xFF8B5E3C),
        );
        // Grass top
        canvas.drawRect(
          Rect.fromLTWH(screenX, screenY, screenW, cs * 0.35),
          Paint()..color = const Color(0xFF4CAF50),
        );
        canvas.drawRect(
          Rect.fromLTWH(screenX, screenY + cs * 0.35, screenW, cs * 0.15),
          Paint()..color = const Color(0xFF388E3C),
        );
      } else {
        // Brick platform
        final brickPaint = Paint()..color = const Color(0xFFCD853F);
        final mortarPaint = Paint()..color = const Color(0xFF8B6914);
        canvas.drawRect(Rect.fromLTWH(screenX, screenY, screenW, screenH), brickPaint);
        // Mortar lines
        canvas.drawRect(Rect.fromLTWH(screenX, screenY, screenW, 1.5), mortarPaint);
        canvas.drawRect(Rect.fromLTWH(screenX, screenY + screenH - 1.5, screenW, 1.5), mortarPaint);
        for (double bx = screenX; bx < screenX + screenW; bx += cs * 0.7) {
          canvas.drawRect(Rect.fromLTWH(bx, screenY, 1.5, screenH), mortarPaint);
        }
      }
    }

    // Coins
    final coinPaint = Paint()..color = const Color(0xFFFFD700);
    final coinInnerPaint = Paint()..color = const Color(0xFFFFA000);
    for (final c in coins) {
      if (c.collected) continue;
      final cx = sx(c.x + 0.25, cs);
      final cy = sy(c.y + 0.25, cs);
      if (cx < -cs || cx > size.width + cs) continue;
      canvas.drawCircle(Offset(cx, cy), cs * 0.2, coinPaint);
      canvas.drawCircle(Offset(cx, cy), cs * 0.12, coinInnerPaint);
    }

    // Flag / goal
    final fsx = sx(flagX + 0.3, cs);
    if (fsx > -cs && fsx < size.width + cs) {
      final poleTop = sy(6.0, cs);
      final poleBot = sy(12.5, cs);
      canvas.drawRect(Rect.fromLTWH(fsx - 2, poleTop, 4, poleBot - poleTop),
          Paint()..color = Colors.grey.shade400);
      final fp = Path()
        ..moveTo(fsx + 2, poleTop)
        ..lineTo(fsx + cs * 0.7 + 2, poleTop + cs * 0.4)
        ..lineTo(fsx + 2, poleTop + cs * 0.8);
      canvas.drawPath(fp, Paint()..color = Colors.red);
    }

    // Enemies (Goombas)
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
        // Eyes
        canvas.drawCircle(Offset(esx + ew * 0.3, esy + eh * 0.25), cs * 0.09, Paint()..color = Colors.white);
        canvas.drawCircle(Offset(esx + ew * 0.7, esy + eh * 0.25), cs * 0.09, Paint()..color = Colors.white);
        canvas.drawCircle(Offset(esx + ew * 0.32, esy + eh * 0.28), cs * 0.055, Paint()..color = Colors.black);
        canvas.drawCircle(Offset(esx + ew * 0.72, esy + eh * 0.28), cs * 0.055, Paint()..color = Colors.black);
        // Feet
        canvas.drawOval(Rect.fromLTWH(esx, esy + eh - cs * 0.15, ew * 0.48, cs * 0.2), Paint()..color = const Color(0xFF5D2E0C));
        canvas.drawOval(Rect.fromLTWH(esx + ew * 0.52, esy + eh - cs * 0.15, ew * 0.48, cs * 0.2), Paint()..color = const Color(0xFF5D2E0C));
      }
    }

    // Player
    _drawPlayer(canvas, cs);
  }

  void _drawPlayer(Canvas canvas, double cs) {
    final psx = sx(px, cs);
    final psy = sy(py, cs);
    final pw = kPlayerW * cs;
    final ph = kPlayerH * cs;
    if (psx + pw < 0 || psx > 99999) return;

    final dirMul = pFacingRight ? 1.0 : -1.0;
    // Mirror helper
    double mx(double local) => pFacingRight ? psx + local * pw : psx + pw - local * pw;

    // Legs / overalls (blue)
    canvas.drawRect(Rect.fromLTWH(psx, psy + ph * 0.55, pw * 0.45, ph * 0.45),
        Paint()..color = const Color(0xFF1565C0));
    canvas.drawRect(Rect.fromLTWH(psx + pw * 0.55, psy + ph * 0.55, pw * 0.45, ph * 0.45),
        Paint()..color = const Color(0xFF1565C0));

    // Shirt (red)
    canvas.drawRect(Rect.fromLTWH(psx, psy + ph * 0.42, pw, ph * 0.2),
        Paint()..color = const Color(0xFFE53935));

    // Head (skin)
    canvas.drawOval(Rect.fromLTWH(psx + pw * 0.05, psy, pw * 0.9, ph * 0.52),
        Paint()..color = const Color(0xFFFFCCBC));

    // Hat (red)
    canvas.drawRect(Rect.fromLTWH(psx, psy + ph * 0.1, pw, ph * 0.2),
        Paint()..color = const Color(0xFFC62828));
    canvas.drawRect(Rect.fromLTWH(psx + pw * 0.1, psy, pw * 0.8, ph * 0.15),
        Paint()..color = const Color(0xFFC62828));

    // Eye
    final eyeOffX = pFacingRight ? pw * 0.65 : pw * 0.2;
    canvas.drawCircle(Offset(psx + eyeOffX, psy + ph * 0.25), cs * 0.07, Paint()..color = Colors.black);

    // Mustache
    final mustX = pFacingRight ? psx + pw * 0.35 : psx + pw * 0.05;
    canvas.drawRect(Rect.fromLTWH(mustX, psy + ph * 0.35, pw * 0.55, ph * 0.07),
        Paint()..color = const Color(0xFF5D2E0C));
  }

  void _drawCloud(Canvas canvas, double cs, double worldX, double scale) {
    final cx = sx(worldX, cs);
    if (cx + cs * 3 < 0 || cx > 99999) return;
    final cy = cs * 1.5;
    final p = Paint()..color = Colors.white.withOpacity(0.85);
    canvas.drawOval(Rect.fromLTWH(cx, cy, cs * 2 * scale, cs * 0.8 * scale), p);
    canvas.drawOval(Rect.fromLTWH(cx + cs * 0.4 * scale, cy - cs * 0.4 * scale, cs * 1.2 * scale, cs * 0.8 * scale), p);
    canvas.drawOval(Rect.fromLTWH(cx + cs * 1.0 * scale, cy - cs * 0.25 * scale, cs * 0.9 * scale, cs * 0.6 * scale), p);
  }

  @override
  bool shouldRepaint(_MarioPainter old) => true;
}
