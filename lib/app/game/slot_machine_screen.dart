import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'arcade_input_controller.dart';

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

// ─── Win table: cost = 10 pts ────────────────────────────────────────────────
// 60/40 house edge: 40% of spins win, avg return ≈ 4.1 pts per 10 spent
// Per 100 spins: ~584 pts net removed from rewards pool
const Map<_Sym, double> _winTable = {
  _Sym.cherry: 10.0,     // 22% — break-even
  _Sym.lemon: 10.0,      //  8% — break-even
  _Sym.orange: 11.0,     // 4%  — net +1
  _Sym.watermelon: 12.0, // 1%  — net +2
  _Sym.star: 15.0,       // 0.5% — net +5
  _Sym.bar: 20.0,        // 0.3% — net +10
  _Sym.seven: 30.0,      // 0.2% — jackpot! net +20
};

// ─── Visual strip (20 positions, used for animation cycling) ─────────────────
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
  final ArcadeInputController controller;
  final VoidCallback onSaldoChanged;

  const SlotMachineScreen({
    super.key,
    required this.userId,
    required this.rewardsDocRef,
    required this.currentSaldo,
    required this.controller,
    required this.onSaldoChanged,
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
    widget.controller.addListener(_onControllerEvent);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _stop1Timer?.cancel();
    _stop2Timer?.cancel();
    _stop3Timer?.cancel();
    _winFlashTimer?.cancel();
    widget.controller.removeListener(_onControllerEvent);
    super.dispose();
  }

  // ─── Controller input ────────────────────────────────────────────────────

  void _onControllerEvent() {
    final btn = widget.controller.lastEvent;
    if (btn == ArcadeButton.a) {
      _spin();
    }
  }

  // ─── Outcome engine ──────────────────────────────────────────────────────

  /// Predetermined outcome — 60/40 house edge (40% player wins).
  /// Adjust the `0.40` threshold to change overall win rate.
  void _determineOutcome() {
    final roll = _rng.nextDouble();

    if (roll < 0.22) {
      _winSymbol = _Sym.cherry;      // 22%
    } else if (roll < 0.34) {
      _winSymbol = _Sym.lemon;       // 12%
    } else if (roll < 0.38) {
      _winSymbol = _Sym.orange;      // 4%
    } else if (roll < 0.39) {
      _winSymbol = _Sym.watermelon;  // 1%
    } else if (roll < 0.395) {
      _winSymbol = _Sym.star;        // 0.5%
    } else if (roll < 0.398) {
      _winSymbol = _Sym.bar;         // 0.3%
    } else if (roll < 0.40) {
      _winSymbol = _Sym.seven;       // 0.2%
    } else {
      _winSymbol = null;             // 60% loss
    }

    if (_winSymbol != null) {
      _target1 = _findSymbolPos(_winSymbol!);
      _target2 = _findSymbolPos(_winSymbol!);
      _target3 = _findSymbolPos(_winSymbol!);
    } else {
      _target1 = _rng.nextInt(_stripLen);
      do {
        _target2 = _rng.nextInt(_stripLen);
      } while (_strip[_target2] == _strip[_target1]);
      _target3 = _rng.nextInt(_stripLen);
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

    _updateFirestore(_saldo);

    _ticker = Timer.periodic(const Duration(milliseconds: 60), (_) {
      if (!mounted) return;
      setState(() {
        if (!_reel1Done) _pos1 = (_pos1 + 1) % _stripLen;
        if (!_reel2Done) _pos2 = (_pos2 + 1) % _stripLen;
        if (!_reel3Done) _pos3 = (_pos3 + 1) % _stripLen;
      });
    });

    _stop1Timer = Timer(const Duration(milliseconds: 1200), () => _stopReel(1));
    _stop2Timer = Timer(const Duration(milliseconds: 1900), () => _stopReel(2));
    _stop3Timer = Timer(const Duration(milliseconds: 2600), () => _stopReel(3));
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
    return Stack(
      children: [
        _buildBody(),
        if (_showWinFlash) _buildWinOverlay(),
      ],
    );
  }

  Widget _buildBody() {
    return SingleChildScrollView(
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
    );
  }

  Widget _buildSaldoDisplay() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('💰', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Text(
            'SALDO: ${_saldo.toStringAsFixed(0)} pts',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black, width: 1.5),
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
                  style: TextStyle(color: Colors.black45, fontSize: 11)),
              Expanded(
                child: Container(height: 1, color: Colors.black12),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  'PAYLINE',
                  style: TextStyle(
                    color: Colors.black54,
                    fontSize: 10,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: Container(height: 1, color: Colors.black12),
              ),
              const Text('►',
                  style: TextStyle(color: Colors.black45, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReelDivider() {
    return Container(width: 1, color: Colors.black12);
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

    Color? textColor;
    if (!isEmoji) {
      textColor = sym == _Sym.seven ? Colors.red.shade700 : Colors.black;
    }

    return AnimatedOpacity(
      opacity: dimmed ? 0.25 : 1.0,
      duration: const Duration(milliseconds: 80),
      child: Container(
        height: 64,
        margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 6),
        decoration: highlight && !dimmed
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Colors.grey.shade100,
                border: Border.all(color: Colors.black12),
              )
            : null,
        alignment: Alignment.center,
        child: isEmoji
            ? Text(_symLabel[sym]!, style: const TextStyle(fontSize: 30))
            : Text(
                _symLabel[sym]!,
                style: TextStyle(
                  color: textColor,
                  fontSize: sym == _Sym.bar ? 18 : 34,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
      ),
    );
  }

  Widget _buildSpinButton() {
    final canSpin = !_isSpinning && _saldo >= _spinCost;

    return ElevatedButton(
      onPressed: canSpin ? _spin : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        disabledBackgroundColor: Colors.grey.shade300,
        disabledForegroundColor: Colors.grey.shade500,
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
        shape: const StadiumBorder(),
        elevation: 0,
      ),
      child: Text(
        _isSpinning
            ? 'Girando...'
            : _saldo < _spinCost
                ? 'Sin puntos suficientes'
                : '🎰  Girar  (−10 pts)',
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 15,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildResultText() {
    if (_lastWinAmount == null) {
      return const Text(
        'Toca Girar o pulsa A para jugar',
        style: TextStyle(color: Colors.black38, fontSize: 13),
      );
    }

    final amt = _lastWinAmount!;
    String msg;
    Color color;

    if (amt == 0) {
      msg = 'Sin suerte esta vez...';
      color = Colors.red.shade700;
    } else if (amt <= _spinCost) {
      msg = '¡Recuperaste ${amt.toStringAsFixed(0)} pts!';
      color = Colors.orange.shade700;
    } else {
      msg = '¡Ganaste ${amt.toStringAsFixed(0)} pts!';
      color = Colors.green.shade700;
    }

    return Text(
      msg,
      style: TextStyle(
        color: color,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildWinTable() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ExpansionTile(
          title: const Text(
            'Tabla de premios',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Colors.black,
            ),
          ),
          iconColor: Colors.black,
          collapsedIconColor: Colors.black45,
          initiallyExpanded: false,
          childrenPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: _winTable.entries.map((e) {
            final net = e.value - _spinCost;
            final netStr =
                net >= 0 ? '+${net.toStringAsFixed(0)}' : net.toStringAsFixed(0);
            final netColor = net > 0
                ? Colors.green.shade700
                : net == 0
                    ? Colors.orange.shade700
                    : Colors.red.shade700;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 56,
                    child: Text(
                      '${_symLabel[e.key]!} × 3',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'devuelve ${e.value.toStringAsFixed(0)} pts',
                    style: const TextStyle(color: Colors.black54, fontSize: 12),
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
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildWinOverlay() {
    final isJackpot = _winSymbol == _Sym.seven;
    final isBigWin = _winSymbol == _Sym.bar || _winSymbol == _Sym.star;

    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: Colors.white.withOpacity(0.92),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isJackpot
                    ? '🎊  ¡Jackpot!'
                    : isBigWin
                        ? '🌟  ¡Gran premio!'
                        : '🎉  ¡Ganaste!',
                style: TextStyle(
                  color: isJackpot
                      ? Colors.amber.shade700
                      : isBigWin
                          ? Colors.green.shade700
                          : Colors.black,
                  fontSize: isJackpot ? 36 : 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '+${_lastWinAmount?.toStringAsFixed(0) ?? '0'} puntos',
                style: const TextStyle(
                  color: Colors.black87,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
