import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─── Symbols ────────────────────────────────────────────────────────────────

enum _Sym { cherry, lemon, orange, grape, watermelon, star, bar, seven }

const _symLabel = {
  _Sym.cherry: '🍒',
  _Sym.lemon: '🍋',
  _Sym.orange: '🍊',
  _Sym.grape: '🍇',
  _Sym.watermelon: '🍉',
  _Sym.star: '⭐',
  _Sym.bar: 'BAR',
  _Sym.seven: '7',
};

const _symIsEmoji = {
  _Sym.cherry: true,
  _Sym.lemon: true,
  _Sym.orange: true,
  _Sym.grape: true,
  _Sym.watermelon: true,
  _Sym.star: true,
  _Sym.bar: false,
  _Sym.seven: false,
};

const _symTextColor = {
  _Sym.bar: Color(0xFFFFD700),
  _Sym.seven: Color(0xFFFF4444),
};

// ─── Win table: cost = 10 pts ────────────────────────────────────────────────
// 70/30 house edge: 30% of spins win, avg return ≈ 3.1 pts per 10 spent
const Map<_Sym, double> _winTable = {
  _Sym.cherry: 10.0, // 18% — break-even
  _Sym.lemon: 10.0, // 8%  — break-even
  _Sym.orange: 11.0, // 2.5% — net +1
  _Sym.watermelon: 12.0, // 0.8% — net +2
  _Sym.star: 15.0, // 0.4% — net +5
  _Sym.bar: 20.0, // 0.2% — net +10
  _Sym.seven: 30.0, // 0.1% — jackpot! net +20
};

// ─── Visual strip (20 positions, used for animation cycling) ─────────────────
// cherry=4, lemon=4, orange=3, grape=3, watermelon=2, star=2, bar=1, seven=1
const List<_Sym> _strip = [
  _Sym.cherry,
  _Sym.lemon,
  _Sym.orange,
  _Sym.grape,
  _Sym.cherry,
  _Sym.watermelon,
  _Sym.lemon,
  _Sym.star,
  _Sym.orange,
  _Sym.grape,
  _Sym.cherry,
  _Sym.lemon,
  _Sym.bar,
  _Sym.grape,
  _Sym.cherry,
  _Sym.watermelon,
  _Sym.lemon,
  _Sym.star,
  _Sym.orange,
  _Sym.seven,
];

const int _stripLen = 20;
const double _spinCost = 10.0;

// ─── Screen ──────────────────────────────────────────────────────────────────

class SlotMachineScreen extends StatefulWidget {
  final String userId;
  final DocumentReference rewardsDocRef;
  final double currentSaldo;

  const SlotMachineScreen({
    super.key,
    required this.userId,
    required this.rewardsDocRef,
    required this.currentSaldo,
  });

  @override
  State<SlotMachineScreen> createState() => _SlotMachineScreenState();
}

class _SlotMachineScreenState extends State<SlotMachineScreen> {
  final _rng = Random();

  // Reel positions (center = payline)
  int _pos1 = 0, _pos2 = 6, _pos3 = 13;

  // Spinning state
  bool _isSpinning = false;
  bool _reel1Done = false, _reel2Done = false, _reel3Done = false;

  // Predetermined outcome
  int _target1 = 0, _target2 = 0, _target3 = 0;
  _Sym? _winSymbol; // null = loss

  // Result display
  double? _lastWinAmount; // null = no spin yet
  bool _showWinFlash = false;

  // Timers
  Timer? _ticker;
  Timer? _stop1Timer, _stop2Timer, _stop3Timer, _winFlashTimer;

  // Saldo (local shadow of Firestore value)
  late double _saldo;

  @override
  void initState() {
    super.initState();
    _saldo = widget.currentSaldo;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _stop1Timer?.cancel();
    _stop2Timer?.cancel();
    _stop3Timer?.cancel();
    _winFlashTimer?.cancel();
    super.dispose();
  }

  // ─── Outcome engine ──────────────────────────────────────────────────────

  /// Predetermined outcome using weighted probability (70% house / 30% player).
  /// Adjusting the `0.30` threshold changes overall win rate.
  void _determineOutcome() {
    final roll = _rng.nextDouble();

    if (roll < 0.18) {
      _winSymbol = _Sym.cherry; // 18%
    } else if (roll < 0.26) {
      _winSymbol = _Sym.lemon; // 8%
    } else if (roll < 0.285) {
      _winSymbol = _Sym.orange; // 2.5%
    } else if (roll < 0.293) {
      _winSymbol = _Sym.watermelon; // 0.8%
    } else if (roll < 0.297) {
      _winSymbol = _Sym.star; // 0.4%
    } else if (roll < 0.299) {
      _winSymbol = _Sym.bar; // 0.2%
    } else if (roll < 0.30) {
      _winSymbol = _Sym.seven; // 0.1%
    } else {
      _winSymbol = null; // 70% loss
    }

    if (_winSymbol != null) {
      // All 3 reels show the winning symbol (each picks a different valid position)
      _target1 = _findSymbolPos(_winSymbol!);
      _target2 = _findSymbolPos(_winSymbol!);
      _target3 = _findSymbolPos(_winSymbol!);
    } else {
      // Loss: guarantee no 3-of-a-kind
      _target1 = _rng.nextInt(_stripLen);
      do {
        _target2 = _rng.nextInt(_stripLen);
      } while (_strip[_target2] == _strip[_target1]);
      _target3 = _rng.nextInt(_stripLen);
      // Safety guard: ensure not accidentally all same
      int guard = 0;
      while (_strip[_target3] == _strip[_target1] &&
          _strip[_target3] == _strip[_target2] &&
          guard++ < 50) {
        _target3 = _rng.nextInt(_stripLen);
      }
    }
  }

  int _findSymbolPos(_Sym sym) {
    final positions = <int>[];
    for (int i = 0; i < _stripLen; i++) {
      if (_strip[i] == sym) positions.add(i);
    }
    return positions[_rng.nextInt(positions.length)];
  }

  // ─── Spin logic ──────────────────────────────────────────────────────────

  void _spin() {
    if (_isSpinning || _saldo < _spinCost) return;

    HapticFeedback.mediumImpact();
    _determineOutcome();

    setState(() {
      _saldo -= _spinCost;
      _isSpinning = true;
      _reel1Done = false;
      _reel2Done = false;
      _reel3Done = false;
      _lastWinAmount = null;
      _showWinFlash = false;
    });

    // Fire-and-forget deduction write
    _updateFirestore(_saldo);

    // Fast tick: cycle reels every 60ms
    _ticker = Timer.periodic(const Duration(milliseconds: 60), (_) {
      if (!mounted) return;
      setState(() {
        if (!_reel1Done) _pos1 = (_pos1 + 1) % _stripLen;
        if (!_reel2Done) _pos2 = (_pos2 + 1) % _stripLen;
        if (!_reel3Done) _pos3 = (_pos3 + 1) % _stripLen;
      });
    });

    _stop1Timer =
        Timer(const Duration(milliseconds: 1200), () => _stopReel(1));
    _stop2Timer =
        Timer(const Duration(milliseconds: 1900), () => _stopReel(2));
    _stop3Timer =
        Timer(const Duration(milliseconds: 2600), () => _stopReel(3));
  }

  void _stopReel(int reel) {
    if (!mounted) return;
    HapticFeedback.lightImpact();
    setState(() {
      if (reel == 1) {
        _pos1 = _target1;
        _reel1Done = true;
      } else if (reel == 2) {
        _pos2 = _target2;
        _reel2Done = true;
      } else {
        _pos3 = _target3;
        _reel3Done = true;
      }
    });

    if (_reel1Done && _reel2Done && _reel3Done) {
      _ticker?.cancel();
      _onAllReelsStopped();
    }
  }

  void _onAllReelsStopped() {
    if (!mounted) return;

    if (_winSymbol != null) {
      final winAmt = _winTable[_winSymbol]!;
      HapticFeedback.heavyImpact();
      setState(() {
        _saldo += winAmt;
        _lastWinAmount = winAmt;
        _showWinFlash = true;
        _isSpinning = false;
      });
      _updateFirestore(_saldo);
      _winFlashTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _showWinFlash = false);
      });
    } else {
      setState(() {
        _lastWinAmount = 0.0;
        _isSpinning = false;
      });
    }
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
      debugPrint('SlotMachine Firestore error: $e');
    }
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A0033),
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          _buildBody(),
          if (_showWinFlash) _buildWinOverlay(),
        ],
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF0D0020),
      title: const Text(
        '🎰  TRAGAMONEDAS  🎰',
        style: TextStyle(
          color: Color(0xFFFFD700),
          fontFamily: 'monospace',
          fontSize: 15,
          letterSpacing: 2,
          fontWeight: FontWeight.bold,
        ),
      ),
      centerTitle: true,
      iconTheme: const IconThemeData(color: Color(0xFFFFD700)),
    );
  }

  Widget _buildBody() {
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              _buildSaldoDisplay(),
              const SizedBox(height: 24),
              _buildReelFrame(),
              const SizedBox(height: 24),
              _buildSpinButton(),
              const SizedBox(height: 12),
              _buildResultText(),
              const SizedBox(height: 20),
              _buildWinTable(),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSaldoDisplay() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0020),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('💰', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Text(
            'SALDO: ${_saldo.toStringAsFixed(0)} pts',
            style: const TextStyle(
              color: Color(0xFFFFD700),
              fontSize: 18,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReelFrame() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0020),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFD700), width: 2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFD700).withOpacity(0.2),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        children: [
          IntrinsicHeight(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildReel(_pos1, _reel1Done),
                _buildReelDivider(),
                _buildReel(_pos2, _reel2Done),
                _buildReelDivider(),
                _buildReel(_pos3, _reel3Done),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text('◄',
                  style: TextStyle(color: Color(0xFFFF4444), fontSize: 11)),
              Expanded(
                child: Container(
                  height: 1,
                  color: const Color(0xFFFF4444).withOpacity(0.5),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  'PAYLINE',
                  style: TextStyle(
                    color: Color(0xFFFF4444),
                    fontSize: 10,
                    letterSpacing: 2,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              Expanded(
                child: Container(
                  height: 1,
                  color: const Color(0xFFFF4444).withOpacity(0.5),
                ),
              ),
              const Text('►',
                  style: TextStyle(color: Color(0xFFFF4444), fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReelDivider() {
    return Container(
      width: 1,
      color: const Color(0xFFFFD700).withOpacity(0.25),
    );
  }

  Widget _buildReel(int centerPos, bool stopped) {
    final topPos = (centerPos - 1 + _stripLen) % _stripLen;
    final botPos = (centerPos + 1) % _stripLen;
    return Expanded(
      child: Column(
        children: [
          _buildSymbolCell(_strip[topPos], dimmed: true),
          _buildSymbolCell(_strip[centerPos], dimmed: false, highlight: stopped),
          _buildSymbolCell(_strip[botPos], dimmed: true),
        ],
      ),
    );
  }

  Widget _buildSymbolCell(_Sym sym,
      {required bool dimmed, bool highlight = false}) {
    final isEmoji = _symIsEmoji[sym]!;
    final textColor = _symTextColor[sym];

    return AnimatedOpacity(
      opacity: dimmed ? 0.3 : 1.0,
      duration: const Duration(milliseconds: 80),
      child: Container(
        height: 64,
        margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 6),
        decoration: highlight && !dimmed
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: const Color(0xFFFFD700).withOpacity(0.5), width: 1),
                color: const Color(0xFF1A0033),
              )
            : null,
        alignment: Alignment.center,
        child: isEmoji
            ? Text(
                _symLabel[sym]!,
                style: const TextStyle(fontSize: 30),
              )
            : Text(
                _symLabel[sym]!,
                style: TextStyle(
                  color: textColor,
                  fontSize: sym == _Sym.bar ? 18 : 34,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'monospace',
                  letterSpacing: 1,
                  shadows: [
                    Shadow(
                      color: (textColor ?? Colors.white).withOpacity(0.8),
                      blurRadius: 10,
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildSpinButton() {
    final canSpin = !_isSpinning && _saldo >= _spinCost;

    return GestureDetector(
      onTap: canSpin ? _spin : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding:
            const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
        decoration: BoxDecoration(
          gradient: canSpin
              ? const LinearGradient(
                  colors: [Color(0xFFFFD700), Color(0xFFFF8C00)],
                )
              : null,
          color: canSpin ? null : Colors.grey.shade800,
          borderRadius: BorderRadius.circular(50),
          boxShadow: canSpin
              ? [
                  BoxShadow(
                    color: const Color(0xFFFFD700).withOpacity(0.4),
                    blurRadius: 15,
                    spreadRadius: 2,
                  ),
                ]
              : [],
        ),
        child: Text(
          _isSpinning
              ? '⏳  GIRANDO...'
              : _saldo < _spinCost
                  ? 'SIN PUNTOS'
                  : '🎰  GIRAR  (−10 pts)',
          style: TextStyle(
            color: canSpin ? Colors.black : Colors.grey.shade500,
            fontWeight: FontWeight.bold,
            fontSize: 15,
            letterSpacing: 1.5,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }

  Widget _buildResultText() {
    if (_lastWinAmount == null) {
      return const Text(
        '¡Toca GIRAR para jugar!',
        style: TextStyle(
          color: Colors.white38,
          fontSize: 13,
          fontFamily: 'monospace',
        ),
      );
    }

    final amt = _lastWinAmount!;
    String msg;
    Color color;

    if (amt == 0) {
      msg = '❌  Sin suerte esta vez...';
      color = Colors.redAccent;
    } else if (amt <= _spinCost) {
      msg = '🟡  ¡Recuperaste ${amt.toStringAsFixed(0)} pts!';
      color = Colors.amber;
    } else {
      msg = '🎉  ¡GANASTE ${amt.toStringAsFixed(0)} pts!';
      color = Colors.greenAccent;
    }

    return Text(
      msg,
      style: TextStyle(
        color: color,
        fontSize: 14,
        fontFamily: 'monospace',
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildWinTable() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0020),
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: const Color(0xFFFFD700).withOpacity(0.2)),
      ),
      child: Column(
        children: [
          const Text(
            'TABLA DE PREMIOS',
            style: TextStyle(
              color: Color(0xFFFFD700),
              fontSize: 11,
              letterSpacing: 2,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          ..._winTable.entries.map((e) {
            final net = e.value - _spinCost;
            final netStr =
                net >= 0 ? '+${net.toStringAsFixed(0)}' : net.toStringAsFixed(0);
            final netColor = net > 0
                ? Colors.greenAccent
                : net == 0
                    ? Colors.amber
                    : Colors.redAccent;
            final isEmoji = _symIsEmoji[e.key]!;
            final label = '${_symLabel[e.key]!} × 3';

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 70,
                    child: Text(
                      label,
                      style: TextStyle(
                        color: isEmoji
                            ? Colors.white
                            : (_symTextColor[e.key] ?? Colors.white),
                        fontSize: 14,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'devuelve ${e.value.toStringAsFixed(0)} pts',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 36,
                    child: Text(
                      '($netStr)',
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        color: netColor,
                        fontSize: 12,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildWinOverlay() {
    final isJackpot = _winSymbol == _Sym.seven;
    final isBigWin =
        _winSymbol == _Sym.bar || _winSymbol == _Sym.star;

    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: Colors.black.withOpacity(0.75),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isJackpot
                    ? '🎊  JACKPOT!  🎊'
                    : isBigWin
                        ? '🌟  ¡GRAN WIN!  🌟'
                        : '🎉  ¡GANASTE!  🎉',
                style: TextStyle(
                  color: isJackpot
                      ? const Color(0xFFFFD700)
                      : isBigWin
                          ? Colors.greenAccent
                          : Colors.white,
                  fontSize: isJackpot ? 38 : 30,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  shadows: [
                    Shadow(
                      color: isJackpot
                          ? const Color(0xFFFFD700)
                          : Colors.greenAccent,
                      blurRadius: 20,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '+${_lastWinAmount?.toStringAsFixed(0) ?? '0'} puntos',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontFamily: 'monospace',
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
