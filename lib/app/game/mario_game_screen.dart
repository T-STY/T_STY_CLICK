import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'arcade_center_screen.dart' show AppLanguage;
import 'arcade_input_controller.dart';
import 'game_saldo.dart';

class _Plat {
  final double x, y, w, h;
  final bool isGround;
  const _Plat(this.x, this.y, this.w, this.h, {this.isGround = false});
}

/// Hand-authored level definition. See `kMarioLevels` at the bottom
/// of this file for the curated set of 20 (auto-cycle if `_level`
/// exceeds the list). The auto-generator that used to live in
/// `_generateMap` is gone — all maps are now data, all jumps are
/// verified by design, no more random gaps the player can't clear.
class MarioLevel {
  final String name;
  final double worldW;
  final double flagX;
  final double startX;
  final double startY;
  // [startX, width]
  final List<List<double>> ground;
  // [x, y, w]
  final List<List<double>> platforms;
  // [x, y, vx]
  final List<List<double>> goombas;
  // [cx, baseY, xMin, xMax, vx, phase]
  final List<List<double>> flyers;
  // [x, y, vx]
  final List<List<double>> koopas;
  // [x, y]
  final List<List<double>> coins;
  // [x, blockTopY, typeIndex] (0=bigMario, 1=fireball, 2=life)
  final List<List<double>> powerBlocks;
  // [x, y]
  final List<List<double>> spikes;
  const MarioLevel({
    required this.name,
    required this.worldW,
    required this.flagX,
    required this.platforms,
    required this.ground,
    required this.goombas,
    required this.flyers,
    required this.koopas,
    required this.coins,
    required this.powerBlocks,
    required this.spikes,
    this.startX = 1.0,
    this.startY = 11.4,
  });
}

class _Goomba {
  double x, y, vx;
  bool alive, stomped;
  double stompTimer;
  _Goomba({required this.x, required this.y, this.vx = 1.5})
      : alive = true, stomped = false, stompTimer = 0;
}

/// Flying enemy. Patrols a horizontal segment at a fixed altitude
/// with a small sine-wave bob. Can be stomped (worth +200 score)
/// or fireballed. Doesn't collide with ground platforms — it flies
/// freely between `xMin` and `xMax`. Phase offset randomizes the
/// bob so a row of three flyers doesn't move in lockstep.
class _Flyer {
  double x, y, vx;
  final double baseY;
  final double xMin, xMax;
  final double phase;
  bool alive, stomped;
  double stompTimer;
  _Flyer({
    required this.x,
    required this.baseY,
    required this.xMin,
    required this.xMax,
    required this.vx,
    required this.phase,
  })  : y = baseY,
        alive = true,
        stomped = false,
        stompTimer = 0;
}

/// Stationary spike trap on top of a ground tile. Cannot be
/// stomped — touching it from any direction triggers the hit. The
/// only counter is jumping over it. Worth 0 points (pure
/// avoidance hazard).
class _Spike {
  final double x, y;
  const _Spike(this.x, this.y);
}

enum _KoopaState { walking, shelled }

/// Koopa Troopa — green turtle enemy that hides in its shell when
/// hit rather than dying outright. Behavior matches the classic:
///   * Walking → patrols a platform like a Goomba.
///   * First stomp (from above) OR bonk-from-below on a block
///     they're standing on: state flips to `shelled`. Immobile for
///     `_kShellRevertSec` seconds, then walks again.
///   * Second stomp WHILE shelled: instant kill (+200 score).
///   * Player walking into a shelled Koopa: harmless — they can
///     pass right through it.
///   * Fireball: same as Goomba (instant kill).
class _Koopa {
  double x, y, vx;
  _KoopaState state;
  double shellTimer;
  bool alive;
  bool stomped;
  double stompTimer;
  _Koopa({required this.x, required this.y, this.vx = 1.4})
      : state = _KoopaState.walking,
        shellTimer = 0,
        alive = true,
        stomped = false,
        stompTimer = 0;
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

class MarioGameScreen extends StatefulWidget {
  final String userId;
  final DocumentReference rewardsDocRef;
  final double currentSaldo;
  final ArcadeInputController controller;
  final void Function(double) onSaldoChanged;
  final AppLanguage language;

  const MarioGameScreen({
    super.key,
    required this.userId,
    required this.rewardsDocRef,
    required this.currentSaldo,
    required this.controller,
    required this.onSaldoChanged,
    this.language = AppLanguage.spanish,
  });

  @override
  State<MarioGameScreen> createState() => _MarioGameScreenState();
}

class _MarioGameScreenState extends State<MarioGameScreen> {
  static const double kGravity    = 30.0;
  static const double kLowGravity = 10.0;
  static const double kMaxJumpHold = 0.5;
  static const double kWalkSpeed  = 5.5;
  static const double kRunSpeed   = 9.0;
  // Reduced from -13.5 — at full hold the previous value rose
  // ~6.7 units, which put the player well above where any
  // legitimate platform could spawn. -11.5 caps max apex at ~5.2
  // units, which still clears `kPlatYMin = 8.5` platforms from
  // ground (Y=13) with comfortable margin while feeling closer
  // to the classic Mario hop.
  static const double kJumpVel    = -11.5;
  static const double kMaxFall    = 24.0;
  static const double kPlayerW    = 0.82;
  static const double kPlayerH    = 1.1;
  static const double kEnemyW     = 0.82;
  static const double kEnemyH     = 0.72;
  static const double kPbW        = 0.55;
  static const double kPbH        = 0.55;
  static const int   kCols        = 10;

  // Map-gen safety bounds — these are the ones the previous map
  // generator violated, which is why characters got stuck and gaps
  // were unjumpable. Derived from the physics constants above:
  //   * Player on ground top (y=13) has body Y in [11.9, 13.0].
  //     A floating platform's bottom edge must therefore be at
  //     Y ≤ 11.4 (≥ 0.5 below the player's head) for the player
  //     to walk underneath without clipping. With floating
  //     platform height 0.5, that means platform top Y ≤ 10.9.
  //   * Jump apex with hold (kJumpVel=-13.5 + kLowGravity for
  //     kMaxJumpHold): ~6.7 units of rise. Player's feet can
  //     reach Y=13-6.7=6.3. Platforms at Y<7.0 are unreachable.
  //   * Walking-only jump horizontal distance ~5 units. Capping
  //     ground gaps at 3.5 leaves comfortable margin even for a
  //     tap-only jump.
  static const double kPlatYMin            = 8.5;
  static const double kPlatYMax            = 10.5;
  static const double kPlatHFloating       = 0.5;
  static const double kMinHorizPlatGap     = 1.5;
  static const double kMaxSafeGroundGap    = 3.5;
  static const double kSteppingStoneGapMax = 5.5;
  // How long a Koopa stays in shell form before reverting to a
  // walking turtle. Classic Mario uses ~5s; the user asked for 3s
  // here so the player has to commit to a follow-up stomp quickly.
  static const double kShellRevertSec      = 3.0;
  // Vertical offset from a platform top up to the power-block
  // BOTTOM. At ~1.3× player height the block sits high enough
  // that the player can walk underneath (clearance ≥ 0.3 above
  // head) but low enough to feel like the classic Mario "hop &
  // bonk" rather than a ceiling-stretch — the previous 1.95
  // value pushed blocks so high the player had to use a perfect
  // platform-jump just to graze them.
  static const double kPowerBlockLift      = 1.4;

  double _px = 1.0, _py = 0.0;
  double _pvx = 0.0, _pvy = 0.0;
  bool   _pOnGround = false;
  bool   _pFacingRight = true;
  double _jumpHoldTimer = 0.0;

  bool   _isBig = false;
  bool   _hasFireball = false;
  double _fireballActiveTimer = 0.0;
  double _fireballCooldown = 0.0;
  bool   _invincible = false;
  double _invTimer = 0.0;

  double _camX = 0.0;

  double _worldW = 32.0;
  double _flagX  = 30.0;
  List<_Plat>       _platforms   = [];
  List<_Goomba>     _enemies     = [];
  List<_Flyer>      _flyers      = [];
  List<_Koopa>      _koopas      = [];
  List<_Spike>      _spikes      = [];
  List<_Coin>       _coins       = [];
  List<_PowerBlock> _powerBlocks = [];
  List<_Fireball>   _fireballs   = [];

  // Cumulative tick time for flyer sine-wave bob. Reset per map
  // so a fresh level's flyers don't pick up mid-cycle.
  double _flyerClock = 0.0;

  bool _isRunning = false;
  bool _isDead    = false;
  bool _isLevelComplete = false;
  int  _level  = 1;
  int  _score  = 0;
  int  _lives  = 3;
  late double _saldo;
  late double _lastCommitted;

  Timer?    _ticker;
  DateTime? _lastTick;

  String _t(String es, String en) =>
      widget.language == AppLanguage.spanish ? es : en;

  @override
  void initState() {
    super.initState();
    _saldo = widget.currentSaldo;
    _lastCommitted = widget.currentSaldo;
    _generateMap();
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

  void _update(double dt) {
    final left  = widget.controller.isHeld(ArcadeButton.left);
    final right = widget.controller.isHeld(ArcadeButton.right);
    final run   = widget.controller.isHeld(ArcadeButton.b) ||
                  widget.controller.isHeld(ArcadeButton.y);
    final holdJump = widget.controller.isHeld(ArcadeButton.a) ||
                     widget.controller.isHeld(ArcadeButton.up);

    if (_fireballCooldown > 0) _fireballCooldown -= dt;
    if (_fireballActiveTimer > 0) {
      _fireballActiveTimer -= dt;
      if (_fireballActiveTimer <= 0) _hasFireball = false;
    }
    if (_invincible) { _invTimer -= dt; if (_invTimer <= 0) _invincible = false; }

    final spd = run ? kRunSpeed : kWalkSpeed;
    if (left)       { _pvx = -spd; _pFacingRight = false; }
    else if (right) { _pvx =  spd; _pFacingRight = true;  }
    else              _pvx = 0;

    _px += _pvx * dt;
    _px  = _px.clamp(0, _worldW - kPlayerW);

    for (final p in _platforms) {
      if (_py + kPlayerH <= p.y + 0.05 || _py >= p.y + p.h - 0.05) continue;
      if (_px + kPlayerW > p.x && _px < p.x + p.w) {
        if (_pvx > 0) _px = p.x - kPlayerW;
        else if (_pvx < 0) _px = p.x + p.w;
        _pvx = 0;
      }
    }

    if (holdJump && _pvy < 0 && _jumpHoldTimer < kMaxJumpHold) {
      _pvy += kLowGravity * dt;
      _jumpHoldTimer += dt;
    } else {
      _pvy += kGravity * dt;
    }
    _pvy = _pvy.clamp(-40.0, kMaxFall);

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

    for (final pb in _powerBlocks) {
      if (pb.hit) continue;
      if (_pvy >= 0) continue;
      if (_px + kPlayerW <= pb.x || _px >= pb.x + kPbW) continue;
      if (_py < pb.y + kPbH && _py + kPlayerH > pb.y) {
        pb.hit = true;
        _py  = pb.y + kPbH;
        _pvy = 2.0;
        _activatePower(pb.type);

        // Classic Mario "bonk from below" — any enemy sitting on
        // top of this block when it gets hit takes damage. Goombas
        // and Flyers die outright; Koopas hide in their shell
        // (still alive, follow-up stomp finishes them). The check
        // is an "is enemy's bottom roughly at the block's top, AND
        // do their x-spans overlap" test.
        _bonkEnemiesAbove(pb.x, pb.x + kPbW, pb.y);
      }
    }

    _camX = (_px - kCols / 2.0 + kPlayerW / 2).clamp(0, _worldW - kCols);

    if (_py > 20) { _triggerDeath(); return; }

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

    // ── Flyer update + collision ────────────────────────────
    _flyerClock += dt;
    for (final f in _flyers) {
      if (!f.alive) continue;
      if (f.stomped) {
        f.stompTimer -= dt;
        if (f.stompTimer <= 0) f.alive = false;
        continue;
      }
      // Horizontal patrol — turn around at xMin/xMax.
      f.x += f.vx * dt;
      if (f.x < f.xMin) { f.x = f.xMin; f.vx = f.vx.abs(); }
      if (f.x > f.xMax) { f.x = f.xMax; f.vx = -f.vx.abs(); }
      // Vertical bob — phase per-flyer so a cluster looks alive.
      f.y = f.baseY + sin(_flyerClock * 3.0 + f.phase) * 0.45;

      if (!_invincible) {
        final overX = _px + kPlayerW > f.x && _px < f.x + kEnemyW;
        final overY = _py + kPlayerH > f.y && _py < f.y + kEnemyH;
        if (overX && overY) {
          // Same stomp test as Goomba: descending onto the top
          // half of the flyer.
          if (_pvy > 0 && _py + kPlayerH < f.y + kEnemyH * 0.6) {
            f.stomped = true; f.stompTimer = 0.35;
            _pvy = -9.0; _score += 200;
            HapticFeedback.mediumImpact();
          } else {
            _handlePlayerHit(); return;
          }
        }
      }
    }

    // ── Koopa update + collision ────────────────────────────
    for (final k in _koopas) {
      if (!k.alive) continue;
      if (k.stomped) {
        k.stompTimer -= dt;
        if (k.stompTimer <= 0) k.alive = false;
        continue;
      }
      if (k.state == _KoopaState.shelled) {
        // Inert: no movement, no damage to player, count down to
        // revert. Player walking THROUGH a shell is harmless —
        // matches classic Mario where a still shell is touchable.
        k.shellTimer -= dt;
        if (k.shellTimer <= 0) {
          k.state = _KoopaState.walking;
        }
        continue;
      }
      // Walking — same as Goomba (platform edge bouncing).
      k.x += k.vx * dt;
      for (final p in _platforms) {
        final kBottom = k.y + kEnemyH;
        if ((kBottom - p.y).abs() < 0.15 &&
            k.x + kEnemyW > p.x && k.x < p.x + p.w) {
          if (k.x < p.x) { k.x = p.x; k.vx = k.vx.abs(); }
          if (k.x + kEnemyW > p.x + p.w) {
            k.x = p.x + p.w - kEnemyW; k.vx = -k.vx.abs();
          }
        }
      }
      if (!_invincible) {
        final overX = _px + kPlayerW > k.x && _px < k.x + kEnemyW;
        final overY = _py + kPlayerH > k.y && _py < k.y + kEnemyH;
        if (overX && overY) {
          if (_pvy > 0 && _py + kPlayerH < k.y + kEnemyH * 0.6) {
            // Stomp from above → hide in shell.
            k.state = _KoopaState.shelled;
            k.shellTimer = kShellRevertSec;
            _pvy = -9.0; _score += 100;
            HapticFeedback.mediumImpact();
          } else {
            _handlePlayerHit(); return;
          }
        }
      }
    }

    // ── Spike collision (lethal touch) ──────────────────────
    // Spikes are stationary triangles glued to the ground. Any
    // hitbox overlap triggers `_handlePlayerHit` — they cannot
    // be stomped, the player must jump over them. The hitbox is
    // generously tight (0.55w × 0.4h) so the player can land
    // immediately adjacent without dying.
    if (!_invincible) {
      const spkW = 0.6;
      const spkH = 0.4;
      for (final s in _spikes) {
        if (_px + kPlayerW > s.x &&
            _px < s.x + spkW &&
            _py + kPlayerH > s.y &&
            _py < s.y + spkH) {
          _handlePlayerHit();
          return;
        }
      }
    }

    for (final c in _coins) {
      if (c.collected) continue;
      if ((_px + kPlayerW / 2 - (c.x + 0.25)).abs() < 0.55 &&
          (_py + kPlayerH / 2 - (c.y + 0.25)).abs() < 0.55) {
        c.collected = true; _score += 50;
      }
    }

    _updateFireballs(dt);

    if ((_px + kPlayerW / 2 - (_flagX + 0.3)).abs() < 1.0 && _py + kPlayerH > 6) {
      _levelComplete();
    }
  }

  /// Kills (or shells) any enemy currently standing on top of a
  /// block whose top edge is at `blockTop` and whose horizontal
  /// span is `[blockLeft, blockRight)`. Called immediately after
  /// the player bonks a power block from below.
  ///
  /// Behavior:
  ///   * Goomba — dies (sets stomped → fades out after the
  ///     existing 0.35s animation timer).
  ///   * Flyer — dies the same way.
  ///   * Koopa — first hit puts it in shell; if it's already
  ///     shelled, this counts as the follow-up that kills it.
  ///
  /// The "is the enemy sitting on top" test uses a generous 0.18
  /// vertical tolerance so an enemy mid-platform-step still
  /// registers, and the x-spans must overlap by any amount.
  void _bonkEnemiesAbove(
    double blockLeft, double blockRight, double blockTop) {
    const tol = 0.18;
    for (final e in _enemies) {
      if (!e.alive || e.stomped) continue;
      final eBottom = e.y + kEnemyH;
      if ((eBottom - blockTop).abs() < tol &&
          e.x + kEnemyW > blockLeft && e.x < blockRight) {
        e.stomped = true;
        e.stompTimer = 0.35;
        _score += 100;
      }
    }
    for (final f in _flyers) {
      if (!f.alive || f.stomped) continue;
      final fBottom = f.y + kEnemyH;
      if ((fBottom - blockTop).abs() < tol &&
          f.x + kEnemyW > blockLeft && f.x < blockRight) {
        f.stomped = true;
        f.stompTimer = 0.35;
        _score += 200;
      }
    }
    for (final k in _koopas) {
      if (!k.alive || k.stomped) continue;
      final kBottom = k.y + kEnemyH;
      if ((kBottom - blockTop).abs() < tol &&
          k.x + kEnemyW > blockLeft && k.x < blockRight) {
        if (k.state == _KoopaState.shelled) {
          // Follow-up bonk on the shell finishes it.
          k.stomped = true;
          k.stompTimer = 0.35;
          _score += 200;
        } else {
          // First bonk hides it in the shell.
          k.state = _KoopaState.shelled;
          k.shellTimer = kShellRevertSec;
          _score += 100;
        }
      }
    }
  }

  void _activatePower(_PowerType type) {
    // Explicit `break;` on every case — the previous version
    // relied on Dart 3's implicit-end-of-case behavior, but
    // certain analyser configurations + the way the haptic call
    // was the last statement caused fireball/life to silently
    // chain into bigMario. Result on screen: every power-up
    // looked like bigMario. Explicit breaks fix it.
    switch (type) {
      case _PowerType.fireball:
        _hasFireball = true;
        _fireballActiveTimer = 25.0;
        HapticFeedback.heavyImpact();
        break;
      case _PowerType.life:
        _lives++;
        HapticFeedback.heavyImpact();
        break;
      case _PowerType.bigMario:
        _isBig = true;
        HapticFeedback.heavyImpact();
        break;
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

      if (fb.x < -1 || fb.x > _worldW + 1 || fb.y > 20) fb.alive = false;

      for (final e in _enemies) {
        if (!e.alive || e.stomped) continue;
        if (fb.x > e.x && fb.x < e.x + kEnemyW && fb.y > e.y && fb.y < e.y + kEnemyH) {
          e.stomped = true; e.stompTimer = 0.3;
          fb.alive = false; _score += 150;
          break;
        }
      }
      // Flyers also vulnerable to fireball — same hitbox shape.
      if (!fb.alive) continue;
      for (final f in _flyers) {
        if (!f.alive || f.stomped) continue;
        if (fb.x > f.x && fb.x < f.x + kEnemyW && fb.y > f.y && fb.y < f.y + kEnemyH) {
          f.stomped = true; f.stompTimer = 0.3;
          fb.alive = false; _score += 250;
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
    // Award +1 saldo on level-complete — parity with maze_chase,
    // breakout, etc. which already award per cleared level. Was
    // a long-standing dead path on this game; harmless to fire
    // optimistically because applyArcadeDelta tolerates retries.
    final newSaldo = _saldo + 1;
    _saldo = newSaldo;
    widget.onSaldoChanged(newSaldo);
    _updateFirestore(newSaldo);
    if (mounted) setState(() { _isLevelComplete = true; _isRunning = false; });
  }

  Future<void> _tryRestart() async {
    if (_lives <= 0) {
      final ns = await chargeForReplay(
          userId: widget.userId,
          rewardsDocRef: widget.rewardsDocRef,
          currentSaldo: _saldo);
      if (ns == null) return;
      if (!mounted) return;
      // Resync the ledger: the replay charge was already committed
      // server-side, so _lastCommitted has to follow _saldo. Without
      // this the next credit's delta is computed against the
      // pre-charge value and debits the player instead.
      _lastCommitted = ns;
      setState(() => _saldo = ns);
      widget.onSaldoChanged(ns);
      _lives = 3;
      _score = 0;
      _level = 1;
    }
    _generateMap();
    _startGame();
  }

  void _nextLevel() {
    _level++;
    _generateMap();
    _startGame();
  }

  /// Replaces the old auto-generator entirely. Loads a hand-
  /// authored `MarioLevel` from `kMarioLevels`, cycling once the
  /// player completes all 20. Every entity coordinate is data;
  /// the physics envelope is enforced at design time, so there's
  /// no risk of the auto-gen's "platforms too low to fit under"
  /// class of bugs.
  void _generateMap() => _loadLevel();

  void _loadLevel() {
    _ticker?.cancel();
    _isRunning = false; _isDead = false; _isLevelComplete = false;
    _pvx = 0; _pvy = 0; _pOnGround = false; _camX = 0;
    _isBig = false; _hasFireball = false; _fireballActiveTimer = 0;
    _fireballCooldown = 0; _invincible = false; _invTimer = 0;
    _fireballs = [];
    _flyerClock = 0.0;

    _platforms   = [];
    _enemies     = [];
    _flyers      = [];
    _koopas      = [];
    _spikes      = [];
    _coins       = [];
    _powerBlocks = [];

    if (kMarioLevels.isEmpty) {
      // Should never happen — keeps the State alive if someone
      // ever ships an empty registry.
      _worldW = 24.0;
      _flagX = 22.0;
      _px = 1.0; _py = 11.4;
      _platforms.add(_Plat(0.0, 13.0, _worldW, 3.0, isGround: true));
      return;
    }

    final lvl = kMarioLevels[(_level - 1) % kMarioLevels.length];

    _worldW = lvl.worldW;
    _flagX  = lvl.flagX;
    _px = lvl.startX;
    _py = lvl.startY;

    for (final g in lvl.ground) {
      _platforms.add(_Plat(g[0], 13.0, g[1], 3.0, isGround: true));
    }
    for (final p in lvl.platforms) {
      _platforms.add(_Plat(p[0], p[1], p[2], kPlatHFloating));
    }
    for (final g in lvl.goombas) {
      _enemies.add(_Goomba(x: g[0], y: g[1], vx: g[2]));
    }
    for (final f in lvl.flyers) {
      _flyers.add(_Flyer(
        x: f[0],
        baseY: f[1],
        xMin: f[2],
        xMax: f[3],
        vx: f[4],
        phase: f[5],
      ));
    }
    for (final k in lvl.koopas) {
      _koopas.add(_Koopa(x: k[0], y: k[1], vx: k[2]));
    }
    for (final c in lvl.coins) {
      _coins.add(_Coin(c[0], c[1]));
    }
    for (final pb in lvl.powerBlocks) {
      final t = pb[2].toInt();
      final type = t == 1
          ? _PowerType.fireball
          : t == 2
              ? _PowerType.life
              : _PowerType.bigMario;
      _powerBlocks.add(_PowerBlock(pb[0], pb[1], type));
    }
    for (final s in lvl.spikes) {
      _spikes.add(_Spike(s[0], s[1]));
    }
    return;
  }

  // ─── DEAD CODE BELOW (kept temporarily; the old auto-gen is
  // now never invoked but I'm leaving the body in this branch so
  // the diff is easier to review. Safe to delete in a follow-up.)
  // ignore: dead_code
  void _generateMapLegacy() {
    final rng  = Random();
    final diff = (_level - 1).clamp(0, 5);

    _worldW = 28.0 + diff * 2.0 + rng.nextDouble() * 4.0;
    _flagX  = _worldW - 2.5;
    _px = 1.0; _py = 11.4;

    _platforms   = [];
    _enemies     = [];
    _flyers      = [];
    _koopas      = [];
    _spikes      = [];
    _coins       = [];
    _powerBlocks = [];

    // ── Ground gaps ─────────────────────────────────────────────
    // Cap each gap at kMaxSafeGroundGap (3.5 units) so a tap-only
    // walking jump always clears it with margin. Higher levels can
    // try a gap up to kSteppingStoneGapMax (5.5) but those MUST get
    // a floating stepping-stone platform in the middle — physics
    // guarantee one is reachable from each side.
    final gapCount   = 1 + (diff ~/ 2).clamp(0, 2);
    final gaps       = <(double, double)>[];
    double safeStart = 6.0;
    for (int i = 0; i < gapCount; i++) {
      final gapStart = safeStart + 3.0 + rng.nextDouble() * 3.0;
      final maxGap   = diff >= 2
          ? kSteppingStoneGapMax
          : kMaxSafeGroundGap;
      final gapW = 1.4 + rng.nextDouble() * (maxGap - 1.4);
      if (gapStart + gapW > _worldW - 5.0) break;
      gaps.add((gapStart, gapStart + gapW));
      safeStart = gapStart + gapW + 4.0;
    }

    double prevEnd = 0.0;
    for (final (gs, ge) in gaps) {
      if (gs > prevEnd + 0.5) {
        _platforms.add(_Plat(prevEnd, 13.0, gs - prevEnd, 3.0, isGround: true));
      }
      // Wide gap → drop a stepping-stone in the middle at a
      // reachable Y. Top must be at Y ≤ ~10.5 so a running jump
      // from ground (Y=13) can land on it.
      if (ge - gs > kMaxSafeGroundGap) {
        final stoneX = gs + (ge - gs) / 2 - 0.85;
        _platforms.add(_Plat(stoneX, 10.5, 1.7, kPlatHFloating));
      }
      prevEnd = ge;
    }
    _platforms.add(_Plat(prevEnd, 13.0, _worldW - prevEnd, 3.0, isGround: true));

    // ── Floating platforms (jump targets) ───────────────────────
    // Y bounds enforced so the player can always walk underneath
    // them on the ground. X spacing enforced so two platforms never
    // overlap, and never sit too close together to walk between.
    double x = 2.8;
    while (x < _worldW - 4.5) {
      final platW = 1.5 + rng.nextDouble() * 1.8;
      final platY = kPlatYMin + rng.nextDouble() * (kPlatYMax - kPlatYMin);

      // Skip if this would overlap an existing platform (the
      // stepping-stone we may have placed above).
      final overlapsExisting = _platforms.any((p) =>
          !p.isGround &&
          x < p.x + p.w + kMinHorizPlatGap &&
          x + platW + kMinHorizPlatGap > p.x);
      if (overlapsExisting) {
        x += platW + 1.5;
        continue;
      }

      _platforms.add(_Plat(x, platY, platW, kPlatHFloating));

      // Mix in enemies. Goomba walking on this platform, OR a
      // flying enemy patrolling above it, OR (higher levels)
      // both. Spike traps only appear directly on ground tiles
      // below — see the dedicated ground-decoration pass.
      final enemyRoll = rng.nextDouble();
      if (enemyRoll < 0.30 + diff * 0.04) {
        final baseSpeed = 0.8 + rng.nextDouble() * (1.0 + diff * 0.3);
        _enemies.add(_Goomba(
            x: x + 0.1, y: platY - kEnemyH, vx: baseSpeed));
      }
      if (diff >= 1 && enemyRoll > 0.55 && rng.nextDouble() < 0.40) {
        // Flyer hovers a bit above the platform top, patrolling a
        // ±1.2-unit segment centered on the platform's middle.
        final cx = x + platW / 2;
        final flyY = (platY - 1.8).clamp(kPlatYMin - 1.5, kPlatYMax - 0.5);
        _flyers.add(_Flyer(
          x: cx,
          baseY: flyY,
          xMin: cx - 1.2,
          xMax: cx + 1.2,
          vx: (rng.nextBool() ? 1.0 : -1.0) *
              (1.2 + rng.nextDouble() * (0.6 + diff * 0.2)),
          phase: rng.nextDouble() * pi * 2,
        ));
      }

      final coinCount = 1 + rng.nextInt(3);
      for (int i = 0; i < coinCount; i++) {
        final cx = x + (i - (coinCount - 1) / 2.0) * 0.65 + platW / 2;
        _coins.add(_Coin(cx, platY - 1.1));
      }

      if (rng.nextDouble() < 0.12) {
        final typeRoll = rng.nextDouble();
        final type = typeRoll < 0.45
            ? _PowerType.bigMario
            : typeRoll < 0.75
                ? _PowerType.fireball
                : _PowerType.life;
        // Lifted higher than before — `kPowerBlockLift` puts the
        // block bottom ~1.95 above the platform top, so the player
        // can stand under, jump straight up to bonk it from below,
        // AND the block reads as a deliberate goal in the air
        // rather than something at head height the player keeps
        // bumping into walking past.
        _powerBlocks.add(_PowerBlock(
          x + platW / 2 - kPbW / 2,
          platY - kPowerBlockLift - kPbH,
          type,
        ));
      }

      x += platW + 1.8 + rng.nextDouble() * 1.6;
    }

    // ── Ground decorations: Goombas + Spike traps ──────────────
    // Spike traps are tied to ground tiles (never over a gap) and
    // spawn farther into the world so the player isn't surprised
    // at level start. Density scales with difficulty.
    for (final p in _platforms.where((p) => p.isGround)) {
      if (p.w > 3.5 && rng.nextDouble() < 0.45) {
        final ex = p.x + 2.0 + rng.nextDouble() * (p.w - 2.5);
        _enemies.add(_Goomba(
            x: ex,
            y: 13.0 - kEnemyH,
            vx: 0.9 + rng.nextDouble() * (0.8 + diff * 0.25)));
      }
      // Koopas — 20% chance on wide ground at diff ≥ 1, scaling
      // a bit with level. Placed in the second half of the
      // segment so they're not the very first enemy the player
      // sees on the level.
      if (diff >= 1 && p.w > 4.5 && p.x > 6.0) {
        final koopaChance = 0.20 + diff * 0.04;
        if (rng.nextDouble() < koopaChance) {
          final kx = p.x + p.w / 2 +
              rng.nextDouble() * (p.w / 2 - 1.5);
          _koopas.add(_Koopa(
            x: kx,
            y: 13.0 - kEnemyH,
            vx: (rng.nextBool() ? 1.0 : -1.0) *
                (1.2 + rng.nextDouble() * (0.4 + diff * 0.2)),
          ));
        }
      }
      if (diff >= 1 && p.w > 4.0 && p.x > 5.0) {
        final spikeChance = 0.18 + diff * 0.05;
        if (rng.nextDouble() < spikeChance) {
          // Spike sits on top of the ground (its top at y=13.0
          // means its hitbox occupies y=13.0..13.6, immediately
          // above the ground surface). Keep at least 1.5 units
          // away from the platform edges so the player has
          // landing room on either side.
          final sx = p.x + 1.5 + rng.nextDouble() * (p.w - 3.0);
          _spikes.add(_Spike(sx, 12.4));
        }
      }
    }
  }

  Future<void> _updateFirestore(double newSaldo) async {
    // Routes through the server-side `updateRewardsSaldo`
    // callable instead of writing rewards/{docId} directly
    // (admin-only collection — direct writes failed silently
    // for every non-admin user). The CF resolves the wallet,
    // applies the delta in a transaction, and mirrors the
    // result to the owner-readable card cache.
    final delta = newSaldo - _lastCommitted;
    if (delta == 0) return;
    final result = await applyArcadeDelta(
      delta: delta,
      reason: 'mario',
    );
    if (result != null) {
      _lastCommitted = result;
      if (mounted && _saldo != result) {
        setState(() => _saldo = result);
      }
    }
  }

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
            flyers: _flyers, spikes: _spikes, koopas: _koopas,
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
        Positioned(
          top: 4, left: 4, right: 4,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _chip('❤️ $_lives'),
              if (_isBig) _chip(_t('🍄 Grande', '🍄 Big'), Colors.orange.shade700),
              if (_hasFireball) _chip('🔥 ${_fireballActiveTimer.toInt()}s', Colors.red.shade700),
              _chip('⭐ $_score'),
              _chip(_t('Niv $_level', 'Lvl $_level')),
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
        Text(_t('Nivel $_level — Mapa nuevo', 'Level $_level — New map'), style: const TextStyle(color: Colors.yellow, fontSize: 12)),
        const SizedBox(height: 18),
        Text(_t('Pulsa cualquier botón para empezar', 'Press any button to start'), style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 4),
        Text(_t('D-pad mover  ·  A saltar  ·  B correr', 'D-pad move  ·  A jump  ·  B run'), style: const TextStyle(color: Colors.white54, fontSize: 11)),
        Text(_t('X disparar bola de fuego  ·  Pisa los Goombas', 'X shoot fireball  ·  Stomp the Goombas'), style: const TextStyle(color: Colors.white38, fontSize: 10)),
        const SizedBox(height: 4),
        Text(_t('Bloques amarillos: poderes', 'Yellow blocks: power-ups'), style: const TextStyle(color: Colors.yellow, fontSize: 10)),
      ]),
    ),
  );

  Widget _buildDeathOverlay() => Positioned.fill(
    child: Container(
      color: Colors.black87,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(
            _lives <= 0
                // Left untranslated: idiomatic in Spanish arcades.
                ? '💀 GAME OVER'
                : _t('😵 ¡Perdiste una vida!', '😵 You lost a life!'),
            style: const TextStyle(color: Colors.red, fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(_t('Puntuación: $_score', 'Score: $_score'), style: const TextStyle(color: Colors.white, fontSize: 16)),
        if (_lives > 0) Text(_t('Vidas restantes: $_lives', 'Lives left: $_lives'), style: const TextStyle(color: Colors.yellow, fontSize: 13)),
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _tryRestart,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white, shape: const StadiumBorder()),
              child: Text(_lives <= 0
                  ? _t('Nueva partida', 'New game')
                  : _t('Continuar', 'Continue')),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(_t('SELECT para volver al menú', 'SELECT to return to the menu'), style: const TextStyle(color: Colors.white38, fontSize: 10)),
      ]),
    ),
  );

  Widget _buildCompleteOverlay() => Positioned.fill(
    child: Container(
      color: Colors.black.withOpacity(0.8),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('🏁', style: TextStyle(fontSize: 52)),
        Text(_t('¡NIVEL COMPLETADO!', 'LEVEL COMPLETE!'), style: const TextStyle(color: Colors.yellow, fontSize: 18, fontWeight: FontWeight.bold)),
        Text(_t('+500 puntos  ·  Total: $_score', '+500 points  ·  Total: $_score'), style: const TextStyle(color: Colors.white, fontSize: 14)),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _nextLevel,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white, shape: const StadiumBorder()),
              child: Text(_t('Siguiente nivel →', 'Next level →')),
            ),
          ),
        ),
      ]),
    ),
  );
}

class _MarioPainter extends CustomPainter {
  final List<_Plat>       platforms;
  final List<_Goomba>     enemies;
  final List<_Flyer>      flyers;
  final List<_Spike>      spikes;
  final List<_Koopa>      koopas;
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
    required this.flyers,    required this.spikes, required this.koopas,
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

    for (final pb in powerBlocks) {
      final pbsx = sx(pb.x, cs);
      if (pbsx + kPbW * cs < 0 || pbsx > size.width) continue;
      final pbsy = sy(pb.y, cs);
      final pbw = kPbW * cs, pbh = kPbH * cs;
      if (pb.hit) {
        canvas.drawRect(Rect.fromLTWH(pbsx, pbsy, pbw, pbh),
            Paint()..color = const Color(0xFF8B6914));
      } else {
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
        final tp = TextPainter(
          text: TextSpan(text: '?', style: TextStyle(color: Colors.white, fontSize: pbh * 0.7, fontWeight: FontWeight.bold)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(pbsx + (pbw - tp.width) / 2, pbsy + (pbh - tp.height) / 2));
      }
    }

    for (final c in coins) {
      if (c.collected) continue;
      final cx = sx(c.x + 0.25, cs), cy = sy(c.y + 0.25, cs);
      if (cx < -cs || cx > size.width + cs) continue;
      canvas.drawCircle(Offset(cx, cy), cs * 0.2, Paint()..color = const Color(0xFFFFD700));
      canvas.drawCircle(Offset(cx, cy), cs * 0.12, Paint()..color = const Color(0xFFFFA000));
    }

    for (final fb in fireballs) {
      final fbsx = sx(fb.x, cs), fbsy = sy(fb.y, cs);
      canvas.drawCircle(Offset(fbsx, fbsy), cs * 0.18, Paint()..color = const Color(0xFFFF6D00));
      canvas.drawCircle(Offset(fbsx, fbsy), cs * 0.10, Paint()..color = Colors.yellow);
    }

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

    // Spike traps — fixed-position red triangles sitting on the
    // ground. Drawn before enemies so a Goomba walking over one
    // visually occludes its tip (slightly).
    for (final s in spikes) {
      final ssx = sx(s.x, cs);
      if (ssx + 0.6 * cs < 0 || ssx > size.width) continue;
      final ssy = sy(s.y, cs);
      final spkW = 0.6 * cs;
      final spkH = 0.6 * cs;
      final spikePaint = Paint()..color = const Color(0xFFB71C1C);
      final shadePaint = Paint()..color = const Color(0xFF7F0000);
      for (int i = 0; i < 3; i++) {
        final left = ssx + i * spkW / 3;
        final tipX = left + spkW / 6;
        final tipY = ssy;
        final baseLY = ssy + spkH;
        final baseRX = left + spkW / 3;
        final path = Path()
          ..moveTo(tipX, tipY)
          ..lineTo(left, baseLY)
          ..lineTo(baseRX, baseLY)
          ..close();
        canvas.drawPath(path, spikePaint);
        // Subtle bottom shading line so it reads as 3D.
        canvas.drawLine(
            Offset(left, baseLY),
            Offset(baseRX, baseLY),
            shadePaint..strokeWidth = 1.5);
      }
    }

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

    // Koopas — green turtles. Walking pose draws head + shell;
    // shelled pose draws JUST the shell (lower, no head, with a
    // band texture). Shell pulses when about to revert so the
    // player knows the 3-second window is closing.
    for (final k in koopas) {
      if (!k.alive) continue;
      final ksx = sx(k.x, cs);
      if (ksx + kEnemyW * cs < 0 || ksx > size.width) continue;
      final ksy = sy(k.y, cs);
      final kw = kEnemyW * cs;
      final kh = k.stomped ? kEnemyH * cs * 0.3 : kEnemyH * cs;
      final isShelled = k.state == _KoopaState.shelled;

      final shellColor = const Color(0xFF2E7D32);
      final shellShade = const Color(0xFF1B5E20);
      final headColor  = const Color(0xFFAED581);

      if (isShelled || k.stomped) {
        // Pulse hint: ramps up as shellTimer approaches 0 — only
        // when about to revert (last second).
        final aboutToRevert =
            !k.stomped && k.shellTimer > 0 && k.shellTimer < 1.0;
        final pulse = aboutToRevert
            ? 0.7 + 0.3 * sin(DateTime.now().millisecondsSinceEpoch / 60.0)
            : 1.0;
        final shellPaint = Paint()..color = shellColor.withOpacity(pulse);
        final shellOval = Rect.fromLTWH(
            ksx, ksy + (kEnemyH * cs - kh), kw, kh);
        canvas.drawOval(shellOval, shellPaint);
        // Shell rim
        canvas.drawOval(
            shellOval,
            Paint()
              ..color = shellShade
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.6);
        // Spotted band (3 dots across)
        if (!k.stomped) {
          final spotPaint = Paint()..color = shellShade;
          for (int i = 0; i < 3; i++) {
            final cx = ksx + kw * (0.25 + i * 0.25);
            final cy = ksy + (kEnemyH * cs - kh) + kh * 0.55;
            canvas.drawCircle(Offset(cx, cy), cs * 0.07, spotPaint);
          }
        }
      } else {
        // Walking: shell on top, head poking out (left or right
        // based on movement direction).
        final shellPaint = Paint()..color = shellColor;
        final bodyR = Rect.fromLTWH(ksx, ksy + kh * 0.15, kw, kh * 0.85);
        canvas.drawOval(bodyR, shellPaint);
        canvas.drawOval(
            bodyR,
            Paint()
              ..color = shellShade
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.4);
        // Head
        final facingRight = k.vx > 0;
        final headCx = facingRight
            ? ksx + kw * 0.85
            : ksx + kw * 0.15;
        canvas.drawCircle(
            Offset(headCx, ksy + kh * 0.25),
            cs * 0.18,
            Paint()..color = headColor);
        // Eye
        final eyeOff = facingRight ? cs * 0.06 : -cs * 0.06;
        canvas.drawCircle(
            Offset(headCx + eyeOff, ksy + kh * 0.22),
            cs * 0.045,
            Paint()..color = Colors.black);
        // Feet
        canvas.drawOval(
            Rect.fromLTWH(ksx + kw * 0.05,
                ksy + kh - cs * 0.13, kw * 0.4, cs * 0.18),
            Paint()..color = const Color(0xFFFFA000));
        canvas.drawOval(
            Rect.fromLTWH(ksx + kw * 0.55,
                ksy + kh - cs * 0.13, kw * 0.4, cs * 0.18),
            Paint()..color = const Color(0xFFFFA000));
      }
    }

    // Flyers — winged, purple-bodied enemies bobbing in the air.
    // Wings flap on a 120ms timer so each flyer reads as alive,
    // and squash flat when stomped (same convention as Goomba).
    final wingsUp =
        (DateTime.now().millisecondsSinceEpoch ~/ 120).isEven;
    for (final f in flyers) {
      if (!f.alive) continue;
      final fsx = sx(f.x, cs);
      if (fsx + kEnemyW * cs < 0 || fsx > size.width) continue;
      final fsy = sy(f.y, cs);
      final fw  = kEnemyW * cs;
      final fh  = f.stomped ? kEnemyH * cs * 0.3 : kEnemyH * cs;
      final bodyR = Rect.fromLTWH(fsx, fsy + (kEnemyH * cs - fh), fw, fh);

      if (!f.stomped) {
        // Wings — two trapezoids that flap.
        final wingPaint = Paint()..color = const Color(0xFFE1BEE7);
        final wingShade = Paint()..color = const Color(0xFFAB47BC);
        final wingOffsetY = wingsUp ? -fh * 0.15 : 0.0;
        final leftWing = Path()
          ..moveTo(fsx, fsy + fh * 0.4 + wingOffsetY)
          ..lineTo(fsx - fw * 0.45, fsy + fh * 0.15 + wingOffsetY)
          ..lineTo(fsx - fw * 0.35, fsy + fh * 0.55 + wingOffsetY)
          ..close();
        final rightWing = Path()
          ..moveTo(fsx + fw, fsy + fh * 0.4 + wingOffsetY)
          ..lineTo(fsx + fw + fw * 0.45, fsy + fh * 0.15 + wingOffsetY)
          ..lineTo(fsx + fw + fw * 0.35, fsy + fh * 0.55 + wingOffsetY)
          ..close();
        canvas.drawPath(leftWing, wingPaint);
        canvas.drawPath(rightWing, wingPaint);
        canvas.drawPath(leftWing, wingShade..style = PaintingStyle.stroke..strokeWidth = 1.2);
        canvas.drawPath(rightWing, wingShade);
      }

      // Body (purple) — distinguishes from Goomba's brown.
      canvas.drawOval(
          bodyR, Paint()..color = const Color(0xFF6A1B9A));
      if (!f.stomped) {
        canvas.drawCircle(
            Offset(fsx + fw * 0.3, fsy + fh * 0.3),
            cs * 0.09, Paint()..color = Colors.white);
        canvas.drawCircle(
            Offset(fsx + fw * 0.7, fsy + fh * 0.3),
            cs * 0.09, Paint()..color = Colors.white);
        canvas.drawCircle(
            Offset(fsx + fw * 0.32, fsy + fh * 0.32),
            cs * 0.055, Paint()..color = Colors.black);
        canvas.drawCircle(
            Offset(fsx + fw * 0.72, fsy + fh * 0.32),
            cs * 0.055, Paint()..color = Colors.black);
      }
    }

    if (!invincible || (DateTime.now().millisecondsSinceEpoch ~/ 120).isEven) {
      _drawPlayer(canvas, cs);
    }
  }

  void _drawPlayer(Canvas canvas, double cs) {
    final scale = isBig ? 1.45 : 1.0;
    final psx = sx(px, cs);
    // Anchor the visual to the COLLISION FEET so a bigger Mario
    // grows UPWARD from the platform rather than sinking down
    // through it. The collision box stays kPlayerH=1.1 tall
    // regardless of `isBig`; without this offset the rendered
    // sprite extended (1.45-1.0)*1.1=0.495 units below collision
    // feet, which read on screen as "Mario is half-inside the
    // floor".
    final extraH = kPlayerH * cs * (scale - 1.0);
    final psy = sy(py, cs) - extraH;
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


const List<MarioLevel> kMarioLevels = [
  const MarioLevel(
  name: '1-1: La Llanura',
  worldW: 60.0,
  flagX: 57.0,
  ground: [[0.0, 22.0], [24.5, 14.0], [40.0, 20.0]],
  platforms: [[10.0, 10.0, 2.0], [18.0, 9.5, 2.5], [30.0, 10.0, 2.0], [44.0, 10.0, 2.5]],
  goombas: [[14.0, 12.4, -1.2], [27.0, 12.4, -1.0], [46.0, 12.4, -1.2]],
  flyers: [],
  koopas: [],
  coins: [[10.5, 9.0], [11.5, 9.0], [18.5, 8.5], [19.5, 8.5], [20.5, 8.5], [26.0, 11.5], [27.0, 11.5], [30.5, 9.0], [31.5, 9.0], [44.5, 9.0], [45.5, 9.0], [50.0, 12.0], [52.0, 12.0]],
  powerBlocks: [[8.0, 9.5, 0], [42.0, 9.5, 0]],
  spikes: [],
  startX: 1.0,
  startY: 11.4,
),
  const MarioLevel(
  name: '1-2: El Sendero Verde',
  worldW: 65.0,
  flagX: 62.0,
  ground: [[0.0, 18.0], [20.5, 12.0], [34.5, 10.0], [46.0, 19.0]],
  platforms: [[8.0, 10.0, 2.0], [15.0, 9.5, 2.0], [22.0, 10.0, 2.5], [29.5, 9.5, 2.5], [38.0, 10.0, 2.0], [48.0, 9.5, 2.5], [55.0, 10.0, 2.5]],
  goombas: [[12.0, 12.4, -1.0], [24.0, 12.4, -1.2], [37.0, 12.4, -1.0], [49.0, 12.4, -1.2], [56.0, 12.4, -1.0]],
  flyers: [],
  koopas: [],
  coins: [[8.5, 9.0], [9.5, 9.0], [15.5, 8.5], [16.5, 8.5], [19.0, 11.5], [19.5, 10.5], [22.5, 9.0], [23.5, 9.0], [30.0, 8.5], [31.0, 8.5], [33.0, 11.0], [38.5, 9.0], [39.5, 9.0], [48.5, 8.5], [49.5, 8.5], [55.5, 9.0], [56.5, 9.0]],
  powerBlocks: [[6.0, 9.5, 0], [44.0, 9.5, 1]],
  spikes: [],
  startX: 1.0,
  startY: 11.4,
),
  const MarioLevel(
  name: '1-3: Jardin de Monedas',
  worldW: 68.0,
  flagX: 65.0,
  ground: [[0.0, 16.0], [19.0, 8.0], [29.5, 9.0], [41.0, 7.0], [50.0, 18.0]],
  platforms: [[7.0, 10.5, 2.0], [12.0, 9.5, 2.0], [17.0, 8.5, 2.5], [23.0, 9.5, 2.5], [31.0, 10.0, 2.5], [38.0, 9.0, 2.5], [44.0, 10.0, 2.0], [52.0, 9.5, 2.5], [58.0, 9.0, 2.5]],
  goombas: [[10.0, 12.4, -1.0], [21.0, 12.4, -1.2], [32.0, 12.4, -1.0], [43.0, 12.4, -1.2], [55.0, 12.4, -1.0], [60.0, 12.4, -1.2]],
  flyers: [],
  koopas: [],
  coins: [[7.5, 9.5], [12.5, 8.5], [13.0, 8.5], [17.5, 7.5], [18.5, 7.5], [19.5, 7.5], [23.5, 8.5], [24.5, 8.5], [27.0, 11.0], [27.5, 10.0], [31.5, 9.0], [32.5, 9.0], [38.5, 8.0], [39.5, 8.0], [44.5, 9.0], [45.5, 9.0], [52.5, 8.5], [53.5, 8.5], [58.5, 8.0], [59.5, 8.0]],
  powerBlocks: [[5.0, 9.5, 0], [25.0, 8.5, 0], [48.0, 9.5, 2]],
  spikes: [],
  startX: 1.0,
  startY: 11.4,
),
  const MarioLevel(
  name: '1-4: Colinas Suaves',
  worldW: 70.0,
  flagX: 67.0,
  ground: [[0.0, 14.0], [17.0, 10.0], [30.0, 8.0], [41.0, 11.0], [54.0, 16.0]],
  platforms: [[6.0, 10.0, 2.0], [11.0, 9.0, 2.0], [18.0, 9.5, 2.5], [24.0, 8.5, 2.5], [32.0, 9.5, 2.0], [37.0, 9.0, 2.5], [44.0, 10.0, 2.5], [50.0, 9.0, 2.5], [56.0, 10.0, 2.0], [62.0, 9.5, 2.0]],
  goombas: [[8.0, 12.4, -1.0], [13.0, 12.4, -1.2], [22.0, 12.4, -1.0], [33.0, 12.4, -1.2], [45.0, 12.4, -1.0], [57.0, 12.4, -1.2], [63.0, 12.4, -1.0]],
  flyers: [],
  koopas: [],
  coins: [[6.5, 9.0], [11.5, 8.0], [12.0, 8.0], [15.5, 11.5], [16.5, 11.5], [18.5, 8.5], [19.5, 8.5], [24.5, 7.5], [25.5, 7.5], [28.0, 11.0], [29.0, 11.0], [32.5, 8.5], [37.5, 8.0], [38.5, 8.0], [44.5, 9.0], [45.5, 9.0], [50.5, 8.0], [51.5, 8.0], [56.5, 9.0], [62.5, 8.5], [63.5, 8.5]],
  powerBlocks: [[4.0, 9.5, 0], [27.0, 9.5, 1], [52.0, 9.5, 0]],
  spikes: [[35.0, 12.4]],
  startX: 1.0,
  startY: 11.4,
),
  const MarioLevel(
  name: '1-5: Pradera del Caparazon',
  worldW: 72.0,
  flagX: 69.0,
  ground: [[0.0, 15.0], [18.0, 11.0], [32.0, 9.0], [44.0, 10.0], [56.0, 16.0]],
  platforms: [[7.0, 10.0, 2.0], [12.0, 9.0, 2.0], [19.0, 10.0, 2.5], [25.0, 9.0, 2.5], [33.0, 9.5, 2.5], [40.0, 10.0, 2.0], [46.0, 9.0, 2.5], [52.0, 10.0, 2.0], [58.0, 9.5, 2.5], [64.0, 9.0, 2.5]],
  goombas: [[9.0, 12.4, -1.0], [14.0, 12.4, -1.2], [23.0, 12.4, -1.0], [35.0, 12.4, -1.2], [47.0, 12.4, -1.0], [59.0, 12.4, -1.2]],
  flyers: [],
  koopas: [[42.0, 12.4, -1.0], [65.0, 12.4, -1.2]],
  coins: [[7.5, 9.0], [12.5, 8.0], [13.0, 8.0], [16.0, 11.5], [17.0, 11.5], [19.5, 9.0], [20.5, 9.0], [25.5, 8.0], [26.5, 8.0], [30.0, 11.0], [31.0, 11.0], [33.5, 8.5], [34.5, 8.5], [40.5, 9.0], [41.5, 9.0], [46.5, 8.0], [47.5, 8.0], [52.5, 9.0], [53.5, 9.0], [58.5, 8.5], [59.5, 8.5], [64.5, 8.0], [65.5, 8.0]],
  powerBlocks: [[4.0, 9.5, 0], [28.0, 9.5, 1], [38.0, 9.5, 0], [62.0, 9.5, 2]],
  spikes: [[37.0, 12.4], [55.0, 12.4]],
  startX: 1.0,
  startY: 11.4,
),
  const MarioLevel(
  name: '6-1: Cuevas Goteantes',
  worldW: 60.0,
  flagX: 57.0,
  ground: [
    [0.0, 18.0],
    [21.5, 12.0],
    [37.0, 23.0],
  ],
  platforms: [
    [6.0, 9.5, 2.0],
    [11.0, 10.0, 2.0],
    [19.5, 10.5, 2.5],
    [27.0, 9.0, 3.0],
    [33.5, 10.0, 2.5],
    [42.0, 9.5, 2.0],
    [48.0, 10.0, 2.5],
  ],
  goombas: [
    [9.0, 12.4, -1.0],
    [24.5, 12.4, -1.2],
    [44.0, 12.4, -1.0],
  ],
  flyers: [
    [14.0, 8.5, 12.0, 17.0, 1.6, 0.0],
    [40.0, 8.8, 38.0, 46.0, 1.8, 1.5],
  ],
  koopas: [
    [30.0, 12.4, -1.0],
    [50.0, 12.4, -1.1],
  ],
  coins: [
    [6.5, 9.0],
    [7.0, 9.0],
    [11.5, 9.5],
    [12.0, 9.5],
    [19.5, 10.0],
    [20.5, 10.0],
    [27.5, 8.5],
    [28.5, 8.5],
    [34.0, 9.5],
    [42.5, 9.0],
    [48.5, 9.5],
    [49.5, 9.5],
  ],
  powerBlocks: [
    [4.0, 9.5, 0.0],
    [33.5, 9.0, 1.0],
  ],
  spikes: [
    [17.0, 12.4],
    [46.5, 12.4],
  ],
),
  const MarioLevel(
  name: '6-2: Lago Sereno',
  worldW: 62.0,
  flagX: 59.0,
  ground: [
    [0.0, 14.0],
    [17.5, 10.0],
    [29.5, 14.0],
    [46.5, 15.0],
  ],
  platforms: [
    [14.5, 10.0, 2.0],
    [22.0, 9.5, 2.5],
    [26.5, 10.0, 2.0],
    [33.0, 10.5, 2.5],
    [38.5, 9.0, 2.0],
    [43.0, 10.0, 2.5],
    [50.0, 9.5, 2.0],
    [54.5, 10.0, 2.0],
  ],
  goombas: [
    [11.0, 12.4, -1.0],
    [22.0, 12.4, -1.1],
    [34.0, 12.4, 1.0],
    [52.0, 12.4, -1.0]
  ],
  flyers: [
    [16.0, 8.7, 14.0, 18.0, 1.5, 0.0],
    [31.5, 8.6, 29.0, 34.0, 1.7, 1.0],
    [48.0, 8.8, 46.0, 52.0, 2.0, 2.0],
  ],
  koopas: [
    [20.5, 12.4, -0.9],
    [40.0, 12.4, -1.0],
  ],
  coins: [
    [5.0, 11.0],
    [6.0, 10.5],
    [7.0, 10.5],
    [8.0, 11.0],
    [15.0, 9.5],
    [22.5, 9.0],
    [23.5, 9.0],
    [27.0, 9.5],
    [33.5, 10.0],
    [34.5, 10.0],
    [39.0, 8.5],
    [43.5, 9.5],
    [50.5, 9.0],
    [55.0, 9.5],
  ],
  powerBlocks: [
    [3.0, 9.5, 0.0],
    [38.5, 8.5, 1.0],
  ],
  spikes: [
    [25.0, 12.4],
  ],
),
  const MarioLevel(
  name: '6-3: Gruta del Eco',
  worldW: 64.0,
  flagX: 61.0,
  ground: [
    [0.0, 16.0],
    [19.5, 8.0],
    [29.0, 7.0],
    [38.5, 25.0],
  ],
  platforms: [
    [8.0, 10.0, 2.5],
    [13.0, 9.5, 2.0],
    [21.5, 10.0, 2.5],
    [26.5, 9.0, 2.0],
    [31.0, 10.0, 2.5],
    [42.0, 10.5, 2.5],
    [47.0, 9.5, 2.0],
    [52.5, 10.0, 2.5],
    [57.5, 9.0, 2.0],
  ],
  goombas: [
    [10.0, 12.4, -1.0],
    [22.0, 12.4, -1.0],
    [44.0, 12.4, -1.2],
  ],
  flyers: [
    [17.5, 8.5, 16.0, 19.0, 1.6, 0.0],
    [35.0, 8.6, 33.0, 37.0, 1.8, 1.2],
    [55.0, 8.7, 52.0, 58.0, 2.0, 2.5],
  ],
  koopas: [
    [30.5, 12.4, -1.0],
    [40.0, 12.4, -1.0],
    [50.0, 12.4, 1.0],
  ],
  coins: [
    [8.5, 9.5],
    [9.5, 9.5],
    [13.5, 9.0],
    [21.5, 9.5],
    [22.5, 9.5],
    [26.5, 8.5],
    [27.5, 8.5],
    [31.5, 9.5],
    [32.5, 9.5],
    [42.5, 10.0],
    [47.5, 9.0],
    [53.0, 9.5],
    [54.0, 9.5],
    [58.0, 8.5],
  ],
  powerBlocks: [
    [4.0, 9.5, 0.0],
    [26.5, 8.5, 1.0],
    [47.0, 9.0, 2.0],
  ],
  spikes: [
    [12.0, 12.4],
    [35.0, 12.4],
    [35.5, 12.4],
    [56.0, 12.4],
  ],
),
  const MarioLevel(
  name: '6-4: Orilla del Lago',
  worldW: 63.0,
  flagX: 60.0,
  ground: [
    [0.0, 12.0],
    [15.0, 6.0],
    [24.0, 6.0],
    [33.0, 8.0],
    [44.0, 20.0],
  ],
  platforms: [
    [12.5, 10.0, 2.0],
    [17.0, 9.5, 2.0],
    [21.5, 10.0, 2.0],
    [26.0, 9.0, 2.5],
    [30.5, 10.0, 2.0],
    [35.5, 10.5, 2.5],
    [41.0, 9.5, 2.0],
    [47.5, 9.0, 2.0],
    [52.0, 10.0, 2.5],
    [57.5, 9.5, 2.0],
  ],
  goombas: [
    [8.0, 12.4, -1.0],
    [27.0, 12.4, -1.0],
    [46.0, 12.4, -1.1],
    [55.0, 12.4, 1.0],
  ],
  flyers: [
    [19.0, 8.6, 17.0, 22.0, 1.7, 0.0],
    [37.0, 8.7, 34.0, 40.0, 1.9, 1.3],
  ],
  koopas: [
    [16.5, 12.4, -1.0],
    [50.0, 12.4, -1.0],
  ],
  coins: [
    [12.5, 9.5],
    [13.5, 9.5],
    [17.5, 9.0],
    [21.5, 9.5],
    [26.5, 8.5],
    [27.5, 8.5],
    [30.5, 9.5],
    [36.0, 10.0],
    [37.0, 10.0],
    [41.5, 9.0],
    [48.0, 8.5],
    [52.5, 9.5],
    [58.0, 9.0],
  ],
  powerBlocks: [
    [5.0, 9.5, 0.0],
    [41.0, 9.0, 1.0],
  ],
  spikes: [
    [10.5, 12.4],
    [38.5, 12.4],
    [56.5, 12.4],
  ],
),
  const MarioLevel(
  name: '6-5: Catacumbas Oscuras',
  worldW: 68.0,
  flagX: 65.0,
  ground: [
    [0.0, 14.0],
    [16.5, 9.0],
    [28.0, 8.0],
    [38.5, 7.0],
    [48.0, 20.0],
  ],
  platforms: [
    [7.0, 9.5, 2.0],
    [11.5, 10.0, 2.0],
    [18.5, 9.5, 2.5],
    [23.5, 9.0, 2.0],
    [30.0, 10.0, 2.5],
    [34.5, 9.5, 2.0],
    [40.0, 10.5, 2.0],
    [44.0, 9.5, 2.0],
    [50.5, 10.0, 2.5],
    [55.0, 9.0, 2.0],
    [59.5, 10.0, 2.5],
  ],
  goombas: [
    [9.0, 12.4, -1.0],
    [19.0, 12.4, -1.1],
    [42.0, 12.4, -1.0],
    [57.0, 12.4, 1.0],
  ],
  flyers: [
    [14.0, 8.5, 12.0, 16.0, 1.7, 0.0],
    [32.0, 8.6, 29.0, 35.0, 1.9, 1.2],
    [52.0, 8.7, 49.0, 55.0, 2.0, 2.4],
  ],
  koopas: [
    [20.0, 12.4, -1.0],
    [33.0, 12.4, -1.1],
    [55.0, 12.4, -1.0],
  ],
  coins: [
    [7.5, 9.0],
    [8.5, 9.0],
    [11.5, 9.5],
    [18.5, 9.0],
    [19.5, 9.0],
    [23.5, 8.5],
    [24.5, 8.5],
    [30.5, 9.5],
    [31.5, 9.5],
    [34.5, 9.0],
    [40.5, 10.0],
    [44.5, 9.0],
    [50.5, 9.5],
    [55.5, 8.5],
    [60.0, 9.5],
    [61.0, 9.5],
  ],
  powerBlocks: [
    [4.0, 9.5, 0.0],
    [23.5, 8.5, 1.0],
    [44.0, 9.0, 2.0],
  ],
  spikes: [
    [27.0, 12.4],
    [37.0, 12.4],
  ],
),
  const MarioLevel(
  name: '11-1: Murallas del Castillo',
  worldW: 64.0,
  flagX: 61.0,
  ground: [[0.0, 14.0], [17.0, 6.0], [26.0, 5.0], [34.0, 7.0], [44.0, 4.0], [50.0, 14.0]],
  platforms: [[10.0, 10.0, 2.5], [15.0, 8.5, 2.0], [22.5, 9.5, 2.5], [30.5, 10.0, 2.5], [38.0, 8.5, 3.0], [46.5, 9.5, 2.0], [54.0, 10.0, 3.0], [58.0, 8.5, 2.5]],
  goombas: [[12.0, 12.4, -1.2], [19.0, 12.4, 1.0], [35.0, 12.4, -1.3], [52.0, 12.4, 1.1]],
  flyers: [[28.0, 7.5, 25.0, 33.0, 1.6, 0.0], [55.0, 7.0, 51.0, 60.0, 1.8, 1.2]],
  koopas: [[27.5, 12.4, -0.9], [45.5, 12.4, 1.0]],
  coins: [[10.5, 9.0], [11.5, 9.0], [15.5, 7.5], [16.5, 7.5], [22.5, 8.5], [23.5, 8.5], [30.5, 9.0], [31.5, 9.0], [38.5, 7.5], [39.5, 7.5], [40.5, 7.5], [46.5, 8.5], [54.0, 9.0], [55.0, 9.0], [58.5, 7.5]],
  powerBlocks: [[15.5, 8.5, 0.0], [38.5, 8.5, 1.0], [58.5, 8.5, 2.0]],
  spikes: [[24.5, 12.4], [36.0, 12.4], [46.0, 12.4], [47.5, 12.4]],
),
  const MarioLevel(
  name: '11-2: Torres del Cielo',
  worldW: 66.0,
  flagX: 63.0,
  ground: [[0.0, 10.0], [14.0, 4.0], [21.0, 3.0], [28.0, 4.0], [35.0, 3.0], [42.0, 5.0], [50.0, 16.0]],
  platforms: [[7.5, 9.5, 2.0], [11.5, 8.5, 2.0], [17.0, 9.5, 2.0], [23.5, 8.5, 2.5], [30.0, 9.5, 2.0], [36.5, 9.5, 2.5], [43.0, 9.5, 2.0], [47.0, 8.5, 2.0], [53.0, 9.5, 3.0], [58.0, 8.5, 2.5]],
  goombas: [[15.5, 12.4, -1.0], [29.5, 12.4, 1.2], [44.0, 12.4, -1.1]],
  flyers: [[19.0, 7.0, 16.0, 23.0, 2.0, 0.5], [33.5, 7.0, 30.0, 36.0, 2.2, 1.8], [55.0, 7.0, 51.0, 60.0, 2.0, 0.0]],
  koopas: [[8.0, 12.4, 1.0], [42.5, 12.4, 1.0], [54.5, 12.4, -1.1]],
  coins: [[8.0, 9.0], [9.0, 9.0], [12.0, 8.0], [13.0, 8.0], [17.5, 9.0], [18.5, 9.0], [24.0, 8.0], [25.0, 8.0], [30.5, 9.0], [31.5, 9.0], [37.0, 8.0], [38.0, 8.0], [43.5, 9.0], [47.5, 8.0], [53.5, 9.0], [58.5, 8.0]],
  powerBlocks: [[10.0, 8.5, 0.0], [24.0, 8.5, 1.0], [37.0, 8.5, 2.0]],
  spikes: [[18.5, 12.4], [25.5, 12.4], [32.5, 12.4], [33.5, 12.4], [40.0, 12.4]],
),
  const MarioLevel(
  name: '11-3: Cripta del Foso',
  worldW: 62.0,
  flagX: 59.0,
  ground: [[0.0, 12.0], [15.5, 3.0], [21.0, 3.5], [27.5, 4.0], [34.5, 3.0], [40.0, 4.0], [46.5, 13.5]],
  platforms: [[10.0, 9.5, 2.5], [16.0, 10.0, 2.5], [22.5, 9.5, 2.5], [28.5, 10.0, 2.5], [35.0, 9.5, 2.5], [41.5, 10.0, 2.5], [48.0, 8.5, 2.0], [53.0, 9.5, 2.5], [57.0, 8.5, 2.5]],
  goombas: [[13.0, 12.4, -1.2], [22.0, 12.4, 1.0], [29.0, 12.4, -1.1], [42.0, 12.4, 1.2], [50.0, 12.4, -1.0]],
  flyers: [[19.0, 7.5, 15.0, 24.0, 2.0, 0.0], [37.0, 7.5, 33.0, 43.0, 2.1, 1.5]],
  koopas: [[10.5, 12.4, 1.0], [55.0, 12.4, -1.0]],
  coins: [[10.5, 9.0], [11.5, 9.0], [16.5, 9.5], [17.5, 9.5], [23.0, 9.0], [24.0, 9.0], [29.0, 9.5], [30.0, 9.5], [35.5, 9.0], [36.5, 9.0], [42.0, 9.5], [48.5, 8.0], [53.5, 9.0], [57.5, 8.0]],
  powerBlocks: [[19.5, 9.5, 0.0], [38.5, 9.5, 1.0], [57.5, 8.5, 2.0]],
  spikes: [[18.5, 12.4], [24.5, 12.4], [25.5, 12.4], [31.5, 12.4], [38.0, 12.4], [44.0, 12.4]],
),
  const MarioLevel(
  name: '11-4: Almenas Voladoras',
  worldW: 68.0,
  flagX: 65.0,
  ground: [[0.0, 9.0], [13.0, 3.0], [19.0, 3.0], [25.5, 3.5], [32.5, 3.0], [38.5, 3.5], [45.0, 4.0], [52.0, 16.0]],
  platforms: [[7.0, 10.0, 2.5], [11.0, 8.5, 2.0], [16.5, 9.5, 2.5], [22.5, 8.5, 2.0], [28.0, 9.5, 2.5], [34.5, 8.5, 2.0], [40.0, 9.5, 2.5], [46.5, 8.5, 2.5], [54.5, 9.5, 3.0], [60.0, 8.5, 2.5]],
  goombas: [[14.0, 12.4, -1.1], [26.5, 12.4, 1.0], [40.0, 12.4, -1.2]],
  flyers: [[20.0, 7.0, 16.0, 25.0, 2.2, 0.0], [36.0, 7.0, 32.0, 42.0, 2.3, 1.0], [49.0, 6.5, 46.0, 55.0, 2.4, 2.5], [62.0, 7.0, 58.0, 66.0, 2.0, 0.8]],
  koopas: [[7.5, 12.4, 1.0], [46.0, 12.4, -1.0], [56.0, 12.4, 1.1]],
  coins: [[7.5, 9.5], [8.5, 9.5], [11.5, 8.0], [12.5, 8.0], [17.0, 9.0], [18.0, 9.0], [23.0, 8.0], [28.5, 9.0], [29.5, 9.0], [35.0, 8.0], [40.5, 9.0], [41.5, 9.0], [47.0, 8.0], [48.0, 8.0], [55.0, 9.0], [60.5, 8.0], [61.5, 8.0]],
  powerBlocks: [[9.0, 8.5, 0.0], [37.5, 8.5, 1.0], [63.0, 8.5, 2.0]],
  spikes: [[16.5, 12.4], [22.5, 12.4], [29.0, 12.4], [36.0, 12.4], [37.0, 12.4], [42.0, 12.4], [49.0, 12.4]],
),
  const MarioLevel(
  name: '11-5: Bastión Final',
  worldW: 70.0,
  flagX: 67.0,
  ground: [[0.0, 11.0], [14.5, 4.0], [21.5, 3.0], [27.5, 4.0], [34.5, 3.5], [41.0, 4.5], [48.5, 3.0], [54.0, 16.0]],
  platforms: [[8.5, 9.5, 2.5], [13.0, 8.5, 2.0], [18.5, 9.5, 2.5], [24.0, 8.5, 2.0], [29.5, 9.5, 2.5], [35.5, 8.5, 2.0], [41.5, 9.5, 2.5], [46.5, 8.5, 2.0], [52.0, 9.5, 2.5], [57.0, 8.5, 2.5], [62.0, 9.5, 3.0]],
  goombas: [[16.0, 12.4, -1.2], [28.5, 12.4, 1.1], [42.0, 12.4, -1.2], [55.5, 12.4, 1.0]],
  flyers: [[22.0, 7.0, 18.0, 27.0, 2.3, 0.0], [38.0, 7.0, 34.0, 44.0, 2.4, 1.5], [50.0, 6.5, 46.0, 54.0, 2.2, 2.8], [60.0, 7.5, 56.0, 66.0, 2.1, 0.5]],
  koopas: [[15.0, 12.4, 1.0], [35.0, 12.4, -1.0], [49.0, 12.4, 1.1], [58.0, 12.4, -1.0]],
  coins: [[9.0, 9.0], [10.0, 9.0], [13.5, 8.0], [14.5, 8.0], [19.0, 9.0], [20.0, 9.0], [24.5, 8.0], [25.5, 8.0], [30.0, 9.0], [31.0, 9.0], [36.0, 8.0], [37.0, 8.0], [42.0, 9.0], [43.0, 9.0], [47.0, 8.0], [52.5, 9.0], [57.5, 8.0], [62.5, 9.0], [63.5, 9.0]],
  powerBlocks: [[11.0, 8.5, 0.0], [38.5, 8.5, 1.0], [49.5, 8.5, 1.0], [65.0, 8.5, 2.0]],
  spikes: [[17.5, 12.4], [18.5, 12.4], [25.5, 12.4], [32.0, 12.4], [33.0, 12.4], [38.5, 12.4], [45.0, 12.4], [51.0, 12.4], [52.0, 12.4]],
),
  const MarioLevel(
  name: '16-1: Ruinas del Olvido',
  worldW: 92.0,
  flagX: 89.0,
  ground: [
    [0.0, 14.0],
    [17.5, 6.0],
    [27.0, 5.0],
    [35.5, 8.0],
    [47.0, 4.0],
    [54.5, 6.0],
    [63.0, 7.0],
    [73.5, 18.5],
  ],
  platforms: [
    [6.0, 10.0, 1.5],
    [9.5, 8.8, 1.5],
    [13.0, 9.6, 1.5],
    [23.5, 9.2, 2.0],
    [31.0, 9.8, 1.5],
    [40.0, 8.7, 1.5],
    [43.5, 10.2, 1.5],
    [51.5, 9.4, 1.5],
    [59.5, 9.0, 1.5],
    [67.0, 8.8, 2.0],
    [70.5, 10.1, 1.5],
    [78.0, 9.5, 2.0],
    [83.0, 8.7, 1.5],
  ],
  goombas: [
    [10.0, 12.4, 1.4],
    [18.5, 12.4, -1.3],
    [37.0, 12.4, 1.5],
    [42.0, 12.4, -1.2],
    [55.5, 12.4, 1.4],
    [76.0, 12.4, -1.5],
    [82.0, 12.4, 1.3],
  ],
  flyers: [
    [21.0, 8.5, 18.5, 24.5, 1.8, 0.0],
    [49.0, 8.0, 46.5, 51.5, 2.0, 1.2],
    [86.0, 8.3, 83.0, 89.0, 1.7, 0.5],
  ],
  koopas: [
    [29.0, 12.4, -1.3],
    [65.0, 12.4, 1.4],
  ],
  coins: [
    [6.5, 9.2],
    [9.8, 8.0],
    [13.3, 8.8],
    [16.0, 8.5],
    [20.5, 9.0],
    [24.0, 8.4],
    [31.5, 9.0],
    [40.5, 7.9],
    [44.0, 9.4],
    [52.0, 8.6],
    [60.0, 8.2],
    [67.5, 8.0],
    [71.0, 9.3],
    [78.5, 8.7],
    [83.5, 7.9],
  ],
  powerBlocks: [
    [23.5, 9.0, 1],
    [67.0, 9.0, 0],
    [83.0, 9.0, 2],
  ],
  spikes: [
    [22.0, 12.4],
    [32.5, 12.4],
    [33.5, 12.4],
    [50.5, 12.4],
    [60.5, 12.4],
    [80.0, 12.4],
  ],
),
  const MarioLevel(
  name: '16-2: Tunel de las Sombras',
  worldW: 90.0,
  flagX: 87.5,
  ground: [
    [0.0, 12.0],
    [14.5, 4.0],
    [20.5, 3.0],
    [25.5, 5.0],
    [33.0, 4.0],
    [39.5, 6.0],
    [47.5, 3.0],
    [53.0, 5.0],
    [60.5, 4.0],
    [66.5, 7.0],
    [76.0, 14.0],
  ],
  platforms: [
    [5.0, 9.5, 1.5],
    [8.5, 8.8, 1.5],
    [12.0, 9.8, 1.5],
    [16.5, 9.0, 1.5],
    [22.0, 8.7, 1.5],
    [27.5, 9.4, 1.5],
    [35.0, 8.9, 1.5],
    [41.5, 9.6, 2.0],
    [49.0, 8.8, 1.5],
    [55.0, 9.5, 1.5],
    [62.0, 8.7, 1.5],
    [69.0, 9.3, 2.0],
    [80.0, 9.0, 2.0],
    [84.5, 8.5, 1.5],
  ],
  goombas: [
    [10.0, 12.4, -1.4],
    [26.5, 12.4, 1.3],
    [40.5, 12.4, -1.3],
    [54.0, 12.4, 1.4],
    [78.0, 12.4, -1.3],
    [82.5, 12.4, 1.2],
  ],
  flyers: [
    [18.0, 8.2, 14.5, 21.0, 2.1, 0.0],
    [36.0, 8.0, 32.0, 39.0, 2.2, 0.8],
    [58.0, 8.3, 54.0, 62.5, 1.9, 1.5],
  ],
  koopas: [
    [17.0, 12.4, 1.3],
    [42.5, 12.4, -1.4],
    [68.5, 12.4, 1.3],
  ],
  coins: [
    [5.5, 8.7],
    [8.8, 8.0],
    [12.3, 9.0],
    [16.8, 8.2],
    [22.3, 7.9],
    [27.8, 8.6],
    [35.3, 8.1],
    [42.0, 8.8],
    [49.3, 8.0],
    [55.3, 8.7],
    [62.3, 7.9],
    [69.5, 8.5],
    [80.5, 8.2],
    [85.0, 7.7],
  ],
  powerBlocks: [
    [12.0, 8.5, 0],
    [41.5, 8.5, 1],
    [80.0, 8.5, 2],
  ],
  spikes: [
    [11.5, 12.4],
    [24.5, 12.4],
    [37.0, 12.4],
    [46.5, 12.4],
    [51.0, 12.4],
    [65.0, 12.4],
    [73.0, 12.4],
  ],
),
  const MarioLevel(
  name: '16-3: Cripta Profunda',
  worldW: 94.0,
  flagX: 91.0,
  ground: [
    [0.0, 11.0],
    [13.0, 3.5],
    [18.5, 3.0],
    [23.5, 4.0],
    [30.0, 3.0],
    [35.5, 5.0],
    [42.5, 3.0],
    [48.0, 4.0],
    [54.5, 3.5],
    [60.5, 5.0],
    [68.0, 4.0],
    [74.5, 3.5],
    [80.0, 14.0],
  ],
  platforms: [
    [5.5, 9.8, 1.5],
    [9.0, 8.9, 1.5],
    [14.5, 9.4, 1.5],
    [20.0, 8.7, 1.5],
    [25.5, 9.6, 1.5],
    [31.0, 8.8, 1.5],
    [37.0, 9.7, 1.5],
    [44.0, 8.9, 1.5],
    [49.5, 9.5, 1.5],
    [56.0, 8.8, 1.5],
    [62.0, 9.4, 2.0],
    [69.5, 8.7, 1.5],
    [76.0, 9.5, 1.5],
    [83.5, 9.0, 2.0],
    [87.5, 8.7, 1.5],
  ],
  goombas: [
    [9.5, 12.4, 1.4],
    [25.0, 12.4, -1.3],
    [37.0, 12.4, 1.4],
    [49.5, 12.4, -1.5],
    [62.0, 12.4, 1.3],
    [84.0, 12.4, -1.4],
  ],
  flyers: [
    [16.0, 8.0, 13.0, 19.0, 2.3, 0.2],
    [33.0, 8.2, 29.5, 36.5, 2.0, 1.0],
    [52.0, 7.9, 48.0, 56.5, 2.2, 0.7],
    [72.0, 8.1, 68.0, 75.5, 2.1, 1.4],
  ],
  koopas: [
    [14.0, 12.4, -1.3],
    [36.5, 12.4, 1.4],
    [61.5, 12.4, -1.4],
    [75.0, 12.4, 1.3],
  ],
  coins: [
    [6.0, 9.0],
    [9.3, 8.1],
    [14.8, 8.6],
    [20.3, 7.9],
    [25.8, 8.8],
    [31.3, 8.0],
    [37.3, 8.9],
    [44.3, 8.1],
    [49.8, 8.7],
    [56.3, 8.0],
    [62.5, 8.6],
    [69.8, 7.9],
    [76.3, 8.7],
    [84.0, 8.2],
    [88.0, 7.9],
  ],
  powerBlocks: [
    [20.0, 8.7, 1],
    [44.0, 8.8, 0],
    [83.5, 8.8, 2],
  ],
  spikes: [
    [12.5, 12.4],
    [22.5, 12.4],
    [28.5, 12.4],
    [33.5, 12.4],
    [40.0, 12.4],
    [46.0, 12.4],
    [52.5, 12.4],
    [58.5, 12.4],
    [66.0, 12.4],
    [78.0, 12.4],
  ],
),
  const MarioLevel(
  name: '16-4: Catacumbas Ardientes',
  worldW: 96.0,
  flagX: 93.0,
  ground: [
    [0.0, 12.5],
    [15.0, 5.0],
    [22.0, 3.5],
    [27.5, 4.0],
    [34.0, 5.0],
    [42.0, 3.5],
    [48.0, 4.5],
    [55.0, 6.0],
    [63.5, 4.0],
    [70.0, 5.0],
    [78.0, 16.0],
  ],
  platforms: [
    [5.5, 10.0, 1.5],
    [9.0, 9.2, 1.5],
    [12.5, 8.6, 1.5],
    [18.0, 9.5, 1.5],
    [24.0, 8.8, 1.5],
    [29.5, 9.6, 1.5],
    [36.5, 8.7, 2.0],
    [44.0, 9.4, 1.5],
    [50.0, 8.6, 1.5],
    [57.0, 9.7, 2.0],
    [65.5, 8.8, 1.5],
    [72.0, 9.5, 1.5],
    [80.0, 8.7, 2.0],
    [85.0, 9.5, 1.5],
    [89.5, 8.8, 1.5],
  ],
  goombas: [
    [10.5, 12.4, 1.4],
    [16.5, 12.4, -1.3],
    [29.0, 12.4, 1.3],
    [43.5, 12.4, -1.4],
    [57.0, 12.4, 1.5],
    [72.0, 12.4, -1.4],
    [85.0, 12.4, 1.3],
    [89.0, 12.4, -1.2],
  ],
  flyers: [
    [20.0, 8.0, 15.0, 22.5, 2.2, 0.0],
    [40.0, 8.1, 36.0, 44.0, 2.4, 0.9],
    [60.0, 8.3, 55.0, 63.5, 2.0, 1.6],
    [82.0, 8.0, 78.0, 86.0, 2.1, 0.4],
  ],
  koopas: [
    [17.5, 12.4, -1.3],
    [35.0, 12.4, 1.4],
    [50.0, 12.4, -1.4],
    [70.5, 12.4, 1.3],
  ],
  coins: [
    [6.0, 9.3],
    [9.3, 8.4],
    [12.8, 7.8],
    [18.3, 8.7],
    [24.3, 8.0],
    [29.8, 8.8],
    [37.0, 7.9],
    [44.3, 8.6],
    [50.3, 7.8],
    [57.5, 8.9],
    [65.8, 8.0],
    [72.3, 8.7],
    [80.5, 7.9],
    [85.3, 8.7],
    [89.8, 8.0],
  ],
  powerBlocks: [
    [12.5, 8.6, 0],
    [36.5, 8.7, 1],
    [80.0, 8.7, 2],
  ],
  spikes: [
    [13.5, 12.4],
    [20.5, 12.4],
    [25.5, 12.4],
    [32.0, 12.4],
    [40.0, 12.4],
    [46.5, 12.4],
    [53.0, 12.4],
    [62.0, 12.4],
    [68.5, 12.4],
    [75.0, 12.4],
  ],
),
  const MarioLevel(
  name: '16-5: Ruinas del Rey Caido',
  worldW: 100.0,
  flagX: 97.0,
  ground: [
    [0.0, 13.0],
    [16.0, 4.0],
    [22.5, 3.5],
    [28.5, 4.0],
    [35.0, 3.5],
    [41.0, 5.0],
    [49.0, 3.5],
    [55.0, 4.0],
    [62.0, 5.5],
    [70.5, 4.0],
    [77.0, 3.5],
    [82.5, 4.0],
    [88.0, 12.0],
  ],
  platforms: [
    [5.5, 10.0, 1.5],
    [9.0, 9.0, 1.5],
    [12.5, 8.6, 1.5],
    [18.5, 9.5, 1.5],
    [25.0, 8.8, 1.5],
    [31.0, 9.6, 1.5],
    [37.0, 8.7, 1.5],
    [43.5, 9.7, 2.0],
    [51.0, 8.9, 1.5],
    [57.5, 9.5, 1.5],
    [64.5, 8.7, 2.0],
    [73.0, 9.4, 1.5],
    [79.0, 8.8, 1.5],
    [85.0, 9.5, 1.5],
    [90.5, 8.7, 2.0],
    [95.0, 9.0, 1.5],
  ],
  goombas: [
    [11.0, 12.4, 1.4],
    [18.0, 12.4, -1.3],
    [29.0, 12.4, 1.3],
    [42.0, 12.4, -1.4],
    [56.0, 12.4, 1.4],
    [63.5, 12.4, -1.3],
    [78.5, 12.4, 1.5],
    [91.0, 12.4, -1.4],
    [95.0, 12.4, 1.3],
  ],
  flyers: [
    [20.0, 8.0, 16.0, 24.0, 2.3, 0.0],
    [38.0, 8.1, 34.0, 42.5, 2.4, 0.8],
    [54.0, 7.9, 49.0, 57.5, 2.2, 1.5],
    [68.0, 8.2, 63.0, 71.5, 2.0, 0.6],
    [83.0, 8.0, 78.5, 87.0, 2.3, 1.1],
  ],
  koopas: [
    [16.5, 12.4, 1.3],
    [35.5, 12.4, -1.4],
    [49.5, 12.4, 1.4],
    [70.0, 12.4, -1.3],
    [82.5, 12.4, 1.3],
  ],
  coins: [
    [6.0, 9.3],
    [9.3, 8.2],
    [12.8, 7.8],
    [18.8, 8.7],
    [25.3, 8.0],
    [31.3, 8.8],
    [37.3, 7.9],
    [43.8, 8.9],
    [51.3, 8.1],
    [57.8, 8.7],
    [64.8, 7.9],
    [73.3, 8.6],
    [79.3, 8.0],
    [85.3, 8.7],
    [90.8, 7.9],
    [95.3, 8.2],
  ],
  powerBlocks: [
    [12.5, 8.6, 1],
    [43.5, 8.7, 0],
    [64.5, 8.7, 0],
    [90.5, 8.7, 2],
  ],
  spikes: [
    [14.0, 12.4],
    [20.5, 12.4],
    [26.5, 12.4],
    [33.0, 12.4],
    [39.0, 12.4],
    [46.5, 12.4],
    [53.5, 12.4],
    [60.0, 12.4],
    [68.0, 12.4],
    [75.0, 12.4],
    [81.0, 12.4],
    [86.0, 12.4],
  ],
),
];
