import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'arcade_input_controller.dart';
import 'flappy_bird_screen.dart';
import 'high_score_service.dart';
import 'logic_grid_screen.dart';
import 'maze_chase_screen.dart';
import 'raycaster_screen.dart';
import 'snake_game_screen.dart';
import 'space_shooter_screen.dart';
import 'tetris_game_screen.dart';
import 'traffic_hopper_screen.dart';

// ─── Palette — classic silver Game Boy (late 90s / early 2000s) ───────────────

const _kBodyTop  = Color(0xFFD4D4D4); // light silver
const _kBodyBot  = Color(0xFFAAAAAA); // medium silver/gray
const _kBezel    = Color(0xFF101010); // near-black screen bezel
const _kBtnA     = Color(0xFFE53935); // red
const _kBtnB     = Color(0xFFFFB300); // amber
const _kBtnX     = Color(0xFF1E88E5); // blue
const _kBtnY     = Color(0xFF43A047); // green
const _kDpad     = Color(0xFF2E2E2E); // dark charcoal D-pad
const _kMeta     = Color(0xFF9E9E9E); // gray meta buttons
const _kBodyBdr  = Color(0xFF888888); // silver border

// ─── Category column definitions ──────────────────────────────────────────────

const _kCategories = ['GRID', 'REFLEX', 'SHOOTER', 'PUZZLE'];

// ─── Game registry ────────────────────────────────────────────────────────────
// Layout: 4 cols × 2 rows, index = col*2 + row
// Col 0 GRID: Snake, Maze Chase
// Col 1 REFLEX: Flappy Bird, Traffic Hopper
// Col 2 SHOOTER: Space Shooter, Raycaster
// Col 3 PUZZLE: Tetris, Logic Grid

typedef ArcadeGameBuilder = Widget Function({
  required String userId,
  required DocumentReference rewardsDocRef,
  required double currentSaldo,
  required ArcadeInputController controller,
  required void Function(double) onSaldoChanged,
});

class ArcadeGameDef {
  final String id;
  final String emoji;
  final String title;
  final String subtitle;
  final ArcadeGameBuilder builder;

  const ArcadeGameDef({
    required this.id,
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.builder,
  });
}

final List<ArcadeGameDef> kArcadeGames = [
  // Col 0 — GRID
  ArcadeGameDef(
    id: 'snake', emoji: '🐍', title: 'Serpiente', subtitle: 'Col·come',
    builder: ({required userId, required rewardsDocRef, required currentSaldo,
        required controller, required onSaldoChanged}) =>
        SnakeGameScreen(userId: userId, rewardsDocRef: rewardsDocRef,
            currentSaldo: currentSaldo, controller: controller, onSaldoChanged: onSaldoChanged),
  ),
  ArcadeGameDef(
    id: 'maze', emoji: '👻', title: 'Laberinto', subtitle: 'Pac-Man',
    builder: ({required userId, required rewardsDocRef, required currentSaldo,
        required controller, required onSaldoChanged}) =>
        MazeChasScreen(userId: userId, rewardsDocRef: rewardsDocRef,
            currentSaldo: currentSaldo, controller: controller, onSaldoChanged: onSaldoChanged),
  ),
  // Col 1 — REFLEX
  ArcadeGameDef(
    id: 'flappy', emoji: '🐦', title: 'Pájaro', subtitle: 'Esquiva',
    builder: ({required userId, required rewardsDocRef, required currentSaldo,
        required controller, required onSaldoChanged}) =>
        FlappyBirdScreen(userId: userId, rewardsDocRef: rewardsDocRef,
            currentSaldo: currentSaldo, controller: controller, onSaldoChanged: onSaldoChanged),
  ),
  ArcadeGameDef(
    id: 'hopper', emoji: '🐸', title: 'Tráfico', subtitle: 'Frogger',
    builder: ({required userId, required rewardsDocRef, required currentSaldo,
        required controller, required onSaldoChanged}) =>
        TrafficHopperScreen(userId: userId, rewardsDocRef: rewardsDocRef,
            currentSaldo: currentSaldo, controller: controller, onSaldoChanged: onSaldoChanged),
  ),
  // Col 2 — SHOOTER
  ArcadeGameDef(
    id: 'shooter', emoji: '🚀', title: 'Invasores', subtitle: 'Acción',
    builder: ({required userId, required rewardsDocRef, required currentSaldo,
        required controller, required onSaldoChanged}) =>
        SpaceShooterScreen(userId: userId, rewardsDocRef: rewardsDocRef,
            currentSaldo: currentSaldo, controller: controller, onSaldoChanged: onSaldoChanged),
  ),
  ArcadeGameDef(
    id: 'raycaster', emoji: '🔫', title: 'FPV Doom', subtitle: '3D retro',
    builder: ({required userId, required rewardsDocRef, required currentSaldo,
        required controller, required onSaldoChanged}) =>
        RaycasterScreen(userId: userId, rewardsDocRef: rewardsDocRef,
            currentSaldo: currentSaldo, controller: controller, onSaldoChanged: onSaldoChanged),
  ),
  // Col 3 — PUZZLE
  ArcadeGameDef(
    id: 'tetris', emoji: '🟦', title: 'Tetris', subtitle: 'Bloques',
    builder: ({required userId, required rewardsDocRef, required currentSaldo,
        required controller, required onSaldoChanged}) =>
        TetrisScreen(userId: userId, rewardsDocRef: rewardsDocRef,
            currentSaldo: currentSaldo, controller: controller, onSaldoChanged: onSaldoChanged),
  ),
  ArcadeGameDef(
    id: 'logic', emoji: '💣', title: 'Minas', subtitle: 'Lógica',
    builder: ({required userId, required rewardsDocRef, required currentSaldo,
        required controller, required onSaldoChanged}) =>
        LogicGridScreen(userId: userId, rewardsDocRef: rewardsDocRef,
            currentSaldo: currentSaldo, controller: controller, onSaldoChanged: onSaldoChanged),
  ),
];

// ─── Shell ────────────────────────────────────────────────────────────────────

class ArcadeCenterScreen extends StatefulWidget {
  final String userId;
  final DocumentReference rewardsDocRef;
  final double currentSaldo;

  const ArcadeCenterScreen({
    super.key,
    required this.userId,
    required this.rewardsDocRef,
    required this.currentSaldo,
  });

  @override
  State<ArcadeCenterScreen> createState() => _ArcadeCenterScreenState();
}

class _ArcadeCenterScreenState extends State<ArcadeCenterScreen> {
  late final ArcadeInputController _ctrl;
  late double _saldo;

  // Grid selection: 4 cols × 2 rows
  int _selCol = 0;
  int _selRow = 0;

  ArcadeGameDef? _activeGame;

  // Local high scores indexed same as kArcadeGames
  final List<int> _highScores = List.filled(8, 0);

  int get _selectedIndex => _selCol * 2 + _selRow;

  @override
  void initState() {
    super.initState();
    _ctrl = ArcadeInputController();
    _saldo = widget.currentSaldo;
    _ctrl.addListener(_handleShellEvent);
    _loadHighScores();
  }

  Future<void> _loadHighScores() async {
    final scores = await Future.wait(
      kArcadeGames.map((g) => HighScoreService.load(g.id)),
    );
    if (mounted) setState(() {
      for (int i = 0; i < scores.length; i++) _highScores[i] = scores[i];
    });
  }

  @override
  void dispose() {
    _ctrl.removeListener(_handleShellEvent);
    _ctrl.dispose();
    super.dispose();
  }

  void _handleShellEvent() {
    final event = _ctrl.lastEvent;
    if (event == null || !event.isDown) return;
    final btn = event.button;

    if (_activeGame == null) {
      switch (btn) {
        case ArcadeButton.left:
          setState(() => _selCol = (_selCol - 1 + 4) % 4);
        case ArcadeButton.right:
          setState(() => _selCol = (_selCol + 1) % 4);
        case ArcadeButton.up:
          setState(() => _selRow = (_selRow - 1 + 2) % 2);
        case ArcadeButton.down:
          setState(() => _selRow = (_selRow + 1) % 2);
        case ArcadeButton.a:
        case ArcadeButton.start:
          _launchSelected();
        case ArcadeButton.select:
          Navigator.pop(context);
        default:
          break;
      }
    } else {
      if (btn == ArcadeButton.select) {
        setState(() {
          _activeGame = null;
          _loadHighScores(); // refresh after playing
        });
      }
    }
  }

  Future<void> _launchSelected() async {
    if (_saldo < 10) return;
    final game = kArcadeGames[_selectedIndex];
    final newSaldo = _saldo - 10.0;
    try {
      final userCardRef = FirebaseFirestore.instance
          .collection('users').doc(widget.userId)
          .collection('rewardsCard').doc('cardInfo');
      final batch = FirebaseFirestore.instance.batch();
      batch.update(userCardRef, {'saldo': newSaldo});
      batch.update(widget.rewardsDocRef, {'saldo': newSaldo});
      await batch.commit();
    } catch (_) {}
    if (!mounted) return;
    setState(() { _saldo = newSaldo; _activeGame = game; });
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: _buildConsoleBody(),
        ),
      ),
    );
  }

  Widget _buildConsoleBody() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_kBodyTop, _kBodyBot],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _kBodyBdr, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.30),
            blurRadius: 20,
            spreadRadius: 1,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Column(
          children: [
            _buildTopStrip(),
            const SizedBox(height: 8),
            Expanded(child: _buildScreenBezel()),
            const SizedBox(height: 6),
            _buildSelectStartStrip(),
            const SizedBox(height: 10),
            _buildControlsRow(),
            const SizedBox(height: 8),
            _buildSpeakerDots(),
          ],
        ),
      ),
    );
  }

  // ── Top strip ─────────────────────────────────────────────────────────────

  Widget _buildTopStrip() {
    return Row(
      children: [
        Container(
          width: 7, height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF69F0AE),
            boxShadow: [BoxShadow(color: const Color(0xFF69F0AE).withOpacity(0.8), blurRadius: 6)],
          ),
        ),
        const SizedBox(width: 8),
        const Text(
          'ARCADE CENTER',
          style: TextStyle(color: Color(0xFF555555), fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 3),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.black26),
          ),
          child: Text(
            '💰 ${_saldo.toStringAsFixed(0)} pts',
            style: const TextStyle(color: Color(0xFF333333), fontSize: 9, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  // ── Screen bezel ──────────────────────────────────────────────────────────

  Widget _buildScreenBezel() {
    return Container(
      decoration: BoxDecoration(
        color: _kBezel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1A0840), width: 2),
        boxShadow: const [BoxShadow(color: Colors.black87, blurRadius: 10, offset: Offset(0, 3))],
      ),
      padding: const EdgeInsets.all(8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: _activeGame == null ? _buildGameSelector() : _buildActiveGame(),
      ),
    );
  }

  // ── 4×2 Game selector grid ────────────────────────────────────────────────

  Widget _buildGameSelector() {
    return Container(
      color: const Color(0xFF080D1A),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'ELIGE TU JUEGO',
            style: TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 3),
          ),
          const SizedBox(height: 10),
          // Category headers row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (int col = 0; col < 4; col++) ...[
                SizedBox(
                  width: 62,
                  child: Text(
                    _kCategories[col],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: col == _selCol ? Colors.white70 : Colors.white24,
                      fontSize: 7,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                if (col < 3) const SizedBox(width: 4),
              ],
            ],
          ),
          const SizedBox(height: 6),
          // 2 rows of cards
          for (int row = 0; row < 2; row++) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (int col = 0; col < 4; col++) ...[
                  _buildSelectorCard(
                    kArcadeGames[col * 2 + row],
                    col * 2 + row,
                    col == _selCol && row == _selRow,
                  ),
                  if (col < 3) const SizedBox(width: 4),
                ],
              ],
            ),
            if (row == 0) const SizedBox(height: 4),
          ],
          const SizedBox(height: 10),
          const Text(
            '◄ ► col  ·  ▲ ▼ fila  ·  A jugar  ·  SELECT salir',
            style: TextStyle(color: Colors.white24, fontSize: 7),
          ),
          const Text(
            '−10 pts por partida',
            style: TextStyle(color: Colors.white24, fontSize: 7),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectorCard(ArcadeGameDef def, int index, bool isSelected) {
    final hs = _highScores[index];
    return SizedBox(
      width: 62,
      height: 82,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : const Color(0xFF111827),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Colors.white : const Color(0xFF2D3748),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(def.emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 4),
            Text(
              def.title,
              style: TextStyle(
                color: isSelected ? Colors.black : Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (hs > 0) ...[
              const SizedBox(height: 2),
              Text(
                '⭐$hs',
                style: TextStyle(
                  color: isSelected ? Colors.black54 : const Color(0xFFFFB300),
                  fontSize: 8,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActiveGame() {
    return _activeGame!.builder(
      userId: widget.userId,
      rewardsDocRef: widget.rewardsDocRef,
      currentSaldo: _saldo,
      controller: _ctrl,
      onSaldoChanged: (newSaldo) => setState(() => _saldo = newSaldo),
    );
  }

  // ── SELECT / START strip ──────────────────────────────────────────────────

  Widget _buildSelectStartStrip() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _ConsoleMetaButton(label: 'SELECT', btn: ArcadeButton.select, controller: _ctrl),
        const SizedBox(width: 16),
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white12,
            border: Border.all(color: Colors.white24),
          ),
        ),
        const SizedBox(width: 16),
        _ConsoleMetaButton(label: 'START', btn: ArcadeButton.start, controller: _ctrl),
      ],
    );
  }

  // ── Controls row ──────────────────────────────────────────────────────────

  Widget _buildControlsRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildDPad(),
        _buildABXYCluster(),
      ],
    );
  }

  Widget _buildDPad() {
    return SizedBox(
      width: 144,
      height: 144,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _ConsoleDPadArm(icon: Icons.keyboard_arrow_up_rounded, btn: ArcadeButton.up, controller: _ctrl,
                radius: const BorderRadius.vertical(top: Radius.circular(6))),
          ]),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _ConsoleDPadArm(icon: Icons.keyboard_arrow_left_rounded, btn: ArcadeButton.left, controller: _ctrl,
                radius: const BorderRadius.horizontal(left: Radius.circular(6))),
            Container(width: 48, height: 48, decoration: const BoxDecoration(color: _kDpad)),
            _ConsoleDPadArm(icon: Icons.keyboard_arrow_right_rounded, btn: ArcadeButton.right, controller: _ctrl,
                radius: const BorderRadius.horizontal(right: Radius.circular(6))),
          ]),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _ConsoleDPadArm(icon: Icons.keyboard_arrow_down_rounded, btn: ArcadeButton.down, controller: _ctrl,
                radius: const BorderRadius.vertical(bottom: Radius.circular(6))),
          ]),
        ],
      ),
    );
  }

  // ABXY diamond: X top, Y left, A right, B bottom
  Widget _buildABXYCluster() {
    const btnSize = 48.0;
    const gap     = 4.0;
    const total   = btnSize * 3 + gap * 2;
    return SizedBox(
      width: total,
      height: total,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(top: 0, left: total / 2 - btnSize / 2,
              child: _ConsoleActionButton(label: 'X', btn: ArcadeButton.x, color: _kBtnX, controller: _ctrl, size: btnSize)),
          Positioned(left: 0, top: total / 2 - btnSize / 2,
              child: _ConsoleActionButton(label: 'Y', btn: ArcadeButton.y, color: _kBtnY, controller: _ctrl, size: btnSize)),
          Positioned(right: 0, top: total / 2 - btnSize / 2,
              child: _ConsoleActionButton(label: 'A', btn: ArcadeButton.a, color: _kBtnA, controller: _ctrl, size: btnSize)),
          Positioned(bottom: 0, left: total / 2 - btnSize / 2,
              child: _ConsoleActionButton(label: 'B', btn: ArcadeButton.b, color: _kBtnB, controller: _ctrl, size: btnSize)),
        ],
      ),
    );
  }

  Widget _buildSpeakerDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        for (int i = 0; i < 6; i++)
          Container(
            margin: const EdgeInsets.only(left: 4),
            width: 4, height: 4,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withOpacity(0.22),
            ),
          ),
      ],
    );
  }
}

// ─── D-Pad arm ────────────────────────────────────────────────────────────────

class _ConsoleDPadArm extends StatefulWidget {
  final IconData icon;
  final ArcadeButton btn;
  final ArcadeInputController controller;
  final BorderRadius radius;

  const _ConsoleDPadArm({required this.icon, required this.btn,
      required this.controller, required this.radius});

  @override
  State<_ConsoleDPadArm> createState() => _ConsoleDPadArmState();
}

class _ConsoleDPadArmState extends State<_ConsoleDPadArm> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) { setState(() => _pressed = true);  widget.controller.press(widget.btn); },
      onTapUp:   (_) { setState(() => _pressed = false); widget.controller.release(widget.btn); },
      onTapCancel: () { setState(() => _pressed = false); widget.controller.release(widget.btn); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 40),
        width: 48, height: 48,
        decoration: BoxDecoration(
          color: _pressed ? const Color(0xFF555555) : _kDpad,
          borderRadius: widget.radius,
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Icon(widget.icon, color: _pressed ? Colors.white : Colors.white70, size: 26),
      ),
    );
  }
}

// ─── Action button (A / B / X / Y) ───────────────────────────────────────────

class _ConsoleActionButton extends StatefulWidget {
  final String label;
  final ArcadeButton btn;
  final Color color;
  final ArcadeInputController controller;
  final double size;

  const _ConsoleActionButton({required this.label, required this.btn,
      required this.color, required this.controller, required this.size});

  @override
  State<_ConsoleActionButton> createState() => _ConsoleActionButtonState();
}

class _ConsoleActionButtonState extends State<_ConsoleActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) { setState(() => _pressed = true);  widget.controller.press(widget.btn); },
      onTapUp:   (_) { setState(() => _pressed = false); widget.controller.release(widget.btn); },
      onTapCancel: () { setState(() => _pressed = false); widget.controller.release(widget.btn); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 40),
        width: widget.size, height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _pressed ? widget.color.withOpacity(0.55) : widget.color,
          boxShadow: _pressed ? [] : [
            BoxShadow(color: widget.color.withOpacity(0.5), blurRadius: 8, offset: const Offset(0, 3)),
            BoxShadow(color: Colors.black54, blurRadius: 4, offset: const Offset(0, 2)),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          widget.label,
          style: TextStyle(
            color: _pressed ? Colors.white70 : Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}

// ─── Meta button (SELECT / START) ─────────────────────────────────────────────

class _ConsoleMetaButton extends StatefulWidget {
  final String label;
  final ArcadeButton btn;
  final ArcadeInputController controller;

  const _ConsoleMetaButton({required this.label, required this.btn, required this.controller});

  @override
  State<_ConsoleMetaButton> createState() => _ConsoleMetaButtonState();
}

class _ConsoleMetaButtonState extends State<_ConsoleMetaButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) { setState(() => _pressed = true);  widget.controller.press(widget.btn); },
      onTapUp:   (_) { setState(() => _pressed = false); widget.controller.release(widget.btn); },
      onTapCancel: () { setState(() => _pressed = false); widget.controller.release(widget.btn); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 40),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: _pressed ? const Color(0xFF707070) : _kMeta,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.black.withOpacity(0.18)),
          boxShadow: _pressed ? [] : [
            BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 4, offset: const Offset(0, 2)),
          ],
        ),
        child: Text(
          widget.label,
          style: TextStyle(
            color: _pressed ? Colors.white : const Color(0xFF222222),
            fontSize: 9,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
      ),
    );
  }
}
