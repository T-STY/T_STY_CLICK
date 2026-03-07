import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

// ─── Palette ──────────────────────────────────────────────────────────────────

const _kBodyTop  = Color(0xFFD4D4D4);
const _kBodyBot  = Color(0xFFAAAAAA);
const _kBezel    = Color(0xFF101010);
const _kBtnA     = Color(0xFFE53935);
const _kBtnB     = Color(0xFFFFB300);
const _kBtnX     = Color(0xFF1E88E5);
const _kBtnY     = Color(0xFF43A047);
const _kDpad     = Color(0xFF2E2E2E);
const _kMeta     = Color(0xFF9E9E9E);
const _kBodyBdr  = Color(0xFF888888);

// ─── Card background gradients (per game) ─────────────────────────────────────

const _kCardGradients = <List<Color>>[
  [Color(0xFF0B2B0B), Color(0xFF1B5E20)],   // Víbora Neón    – forest green
  [Color(0xFF140033), Color(0xFF4A148C)],   // Reino Fantasmal – deep purple
  [Color(0xFF0D2137), Color(0xFF01579B)],   // Alas de Cromo   – steel blue
  [Color(0xFF2D1B00), Color(0xFF6D4C00)],   // Cruce Peligroso – amber
  [Color(0xFF0A0A1E), Color(0xFF1A237E)],   // Asalto Estelar  – navy
  [Color(0xFF1A0000), Color(0xFF7B0000)],   // Mazmorra Infernal – blood red
  [Color(0xFF001B2E), Color(0xFF0D47A1)],   // Cascada de Bloques – ocean blue
  [Color(0xFF1A110A), Color(0xFF4E342E)],   // Campo Minado    – dark earth
];

// ─── Category labels (index = gameIndex ~/ 2) ─────────────────────────────────

const _kCategoryLabels = ['REJILLA', 'REFLEJOS', 'DISPAROS', 'PUZLE'];

// ─── Game registry ─────────────────────────────────────────────────────────────

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
  final ArcadeGameBuilder builder;
  const ArcadeGameDef({required this.id, required this.emoji,
      required this.title, required this.builder});
}

final List<ArcadeGameDef> kArcadeGames = [
  // Col 0 — REJILLA
  ArcadeGameDef(id: 'snake',    emoji: '🐍', title: 'Víbora Neón',
    builder: ({required userId, required rewardsDocRef, required currentSaldo,
        required controller, required onSaldoChanged}) =>
      SnakeGameScreen(userId: userId, rewardsDocRef: rewardsDocRef,
        currentSaldo: currentSaldo, controller: controller, onSaldoChanged: onSaldoChanged)),
  ArcadeGameDef(id: 'maze',     emoji: '👻', title: 'Reino Fantasmal',
    builder: ({required userId, required rewardsDocRef, required currentSaldo,
        required controller, required onSaldoChanged}) =>
      MazeChasScreen(userId: userId, rewardsDocRef: rewardsDocRef,
        currentSaldo: currentSaldo, controller: controller, onSaldoChanged: onSaldoChanged)),
  // Col 1 — REFLEJOS
  ArcadeGameDef(id: 'flappy',   emoji: '🕊️', title: 'Alas de Cromo',
    builder: ({required userId, required rewardsDocRef, required currentSaldo,
        required controller, required onSaldoChanged}) =>
      FlappyBirdScreen(userId: userId, rewardsDocRef: rewardsDocRef,
        currentSaldo: currentSaldo, controller: controller, onSaldoChanged: onSaldoChanged)),
  ArcadeGameDef(id: 'hopper',   emoji: '🐸', title: 'Cruce Peligroso',
    builder: ({required userId, required rewardsDocRef, required currentSaldo,
        required controller, required onSaldoChanged}) =>
      TrafficHopperScreen(userId: userId, rewardsDocRef: rewardsDocRef,
        currentSaldo: currentSaldo, controller: controller, onSaldoChanged: onSaldoChanged)),
  // Col 2 — DISPAROS
  ArcadeGameDef(id: 'shooter',  emoji: '🚀', title: 'Asalto Estelar',
    builder: ({required userId, required rewardsDocRef, required currentSaldo,
        required controller, required onSaldoChanged}) =>
      SpaceShooterScreen(userId: userId, rewardsDocRef: rewardsDocRef,
        currentSaldo: currentSaldo, controller: controller, onSaldoChanged: onSaldoChanged)),
  ArcadeGameDef(id: 'raycaster',emoji: '🔥', title: 'Mazmorra Infernal',
    builder: ({required userId, required rewardsDocRef, required currentSaldo,
        required controller, required onSaldoChanged}) =>
      RaycasterScreen(userId: userId, rewardsDocRef: rewardsDocRef,
        currentSaldo: currentSaldo, controller: controller, onSaldoChanged: onSaldoChanged)),
  // Col 3 — PUZLE
  ArcadeGameDef(id: 'tetris',   emoji: '🟦', title: 'Cascada de Bloques',
    builder: ({required userId, required rewardsDocRef, required currentSaldo,
        required controller, required onSaldoChanged}) =>
      TetrisScreen(userId: userId, rewardsDocRef: rewardsDocRef,
        currentSaldo: currentSaldo, controller: controller, onSaldoChanged: onSaldoChanged)),
  ArcadeGameDef(id: 'logic',    emoji: '💣', title: 'Campo Minado',
    builder: ({required userId, required rewardsDocRef, required currentSaldo,
        required controller, required onSaldoChanged}) =>
      LogicGridScreen(userId: userId, rewardsDocRef: rewardsDocRef,
        currentSaldo: currentSaldo, controller: controller, onSaldoChanged: onSaldoChanged)),
];

// ─── Shell ────────────────────────────────────────────────────────────────────

class ArcadeCenterScreen extends StatefulWidget {
  final String userId;
  final DocumentReference rewardsDocRef;
  final double currentSaldo;

  const ArcadeCenterScreen({super.key, required this.userId,
      required this.rewardsDocRef, required this.currentSaldo});

  @override
  State<ArcadeCenterScreen> createState() => _ArcadeCenterScreenState();
}

class _ArcadeCenterScreenState extends State<ArcadeCenterScreen> {
  late final ArcadeInputController _ctrl;
  late double _saldo;
  int _selectedIndex = 0;
  ArcadeGameDef? _activeGame;
  final List<int> _highScores = List.filled(8, 0);

  @override
  void initState() {
    super.initState();
    _ctrl = ArcadeInputController();
    _saldo = widget.currentSaldo;
    _ctrl.addListener(_handleShellEvent);
    _loadHighScores();
  }

  Future<void> _loadHighScores() async {
    final scores = await Future.wait(kArcadeGames.map((g) => HighScoreService.load(g.id)));
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
          setState(() => _selectedIndex = (_selectedIndex - 1 + 8) % 8);
        case ArcadeButton.right:
          setState(() => _selectedIndex = (_selectedIndex + 1) % 8);
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
        setState(() { _activeGame = null; _loadHighScores(); });
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

  // ─── Build ──────────────────────────────────────────────────────────────────

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
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [_kBodyTop, _kBodyBot],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _kBodyBdr, width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.30),
            blurRadius: 20, spreadRadius: 1, offset: const Offset(0, 4))],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Column(children: [
          _buildTopStrip(),
          const SizedBox(height: 8),
          Expanded(child: _buildScreenBezel()),
          const SizedBox(height: 6),
          _buildSelectStartStrip(),
          const SizedBox(height: 10),
          _buildControlsRow(),
          const SizedBox(height: 8),
          _buildSpeakerDots(),
        ]),
      ),
    );
  }

  // ── Top strip ─────────────────────────────────────────────────────────────

  Widget _buildTopStrip() {
    return Row(children: [
      Container(
        width: 7, height: 7,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF69F0AE),
          boxShadow: [BoxShadow(color: const Color(0xFF69F0AE).withOpacity(0.8), blurRadius: 6)],
        ),
      ),
      const SizedBox(width: 8),
      const Text('ARCADE CENTER',
        style: TextStyle(color: Color(0xFF555555), fontSize: 9,
            fontWeight: FontWeight.w700, letterSpacing: 3)),
      const Spacer(),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.black26),
        ),
        child: Text('💰 ${_saldo.toStringAsFixed(0)} pts',
          style: const TextStyle(color: Color(0xFF333333), fontSize: 9, fontWeight: FontWeight.w600)),
      ),
    ]);
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
        child: _activeGame == null ? _buildCarousel() : _buildActiveGame(),
      ),
    );
  }

  // ── Carousel ──────────────────────────────────────────────────────────────

  Widget _buildCarousel() {
    return Container(
      color: const Color(0xFF060A14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          final cardW = (w * 0.78).clamp(160.0, 260.0);
          final cardH = (h * 0.74).clamp(130.0, 210.0);
          final gap = w * 0.05;
          final centerX = (w - cardW) / 2;

          return Column(children: [
            const SizedBox(height: 8),
            // Category badge row
            Text(
              _kCategoryLabels[_selectedIndex ~/ 2],
              style: const TextStyle(color: Colors.white24, fontSize: 8,
                  letterSpacing: 3, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),

            // Cards carousel
            SizedBox(
              height: cardH,
              child: Stack(
                clipBehavior: Clip.none,
                children: List.generate(kArcadeGames.length, (i) {
                  final offset = (i - _selectedIndex) * (cardW + gap);
                  final isSelected = i == _selectedIndex;
                  return AnimatedPositioned(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                    left: centerX + offset,
                    top: isSelected ? 0 : cardH * 0.06,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 280),
                      opacity: (i - _selectedIndex).abs() <= 1 ? 1.0 : 0.0,
                      child: _buildCarouselCard(
                        kArcadeGames[i], i, isSelected, cardW, cardH),
                    ),
                  );
                }),
              ),
            ),

            const SizedBox(height: 8),

            // Navigation dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(8, (i) {
                final sel = i == _selectedIndex;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  width: sel ? 16 : 5,
                  height: 4,
                  decoration: BoxDecoration(
                    color: sel ? Colors.white : Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                );
              }),
            ),

            const SizedBox(height: 6),
            const Text('◄ ► navegar  ·  A jugar  ·  SELECT salir',
              style: TextStyle(color: Colors.white24, fontSize: 7)),
            const Text('−10 pts por partida',
              style: TextStyle(color: Colors.white12, fontSize: 7)),
          ]);
        },
      ),
    );
  }

  Widget _buildCarouselCard(
      ArcadeGameDef def, int index, bool selected, double w, double h) {
    return GestureDetector(
      onTap: selected ? _launchSelected : () => setState(() => _selectedIndex = index),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 280),
        scale: selected ? 1.0 : 0.88,
        child: SizedBox(
          width: w,
          height: h,
          child: Stack(children: [
            // Painted background with pixel art
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: CustomPaint(
                painter: _CardArtPainter(index: index, selected: selected),
                child: const SizedBox.expand(),
              ),
            ),

            // Border glow for selected
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected
                      ? Colors.white.withOpacity(0.50)
                      : Colors.white.withOpacity(0.06),
                  width: selected ? 2 : 1,
                ),
              ),
            ),

            // Content overlay
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category chip
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.45),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      _kCategoryLabels[index ~/ 2],
                      style: const TextStyle(
                        color: Colors.white54, fontSize: 7, letterSpacing: 2,
                        fontWeight: FontWeight.w700),
                    ),
                  ),
                  const Spacer(),
                  // Emoji
                  Text(def.emoji, style: const TextStyle(fontSize: 40)),
                  const SizedBox(height: 6),
                  // Title
                  Text(def.title,
                    style: const TextStyle(color: Colors.white, fontSize: 15,
                        fontWeight: FontWeight.bold, letterSpacing: 0.3),
                    maxLines: 2,
                  ),
                  // High score
                  if (_highScores[index] > 0) ...[
                    const SizedBox(height: 4),
                    Text('⭐ Récord: ${_highScores[index]}',
                      style: const TextStyle(color: Colors.white54, fontSize: 9)),
                  ],
                ],
              ),
            ),

            // "JUGAR" badge bottom-right when selected
            if (selected)
              Positioned(
                right: 12, bottom: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white38),
                  ),
                  child: const Text('A → JUGAR',
                    style: TextStyle(color: Colors.white, fontSize: 7,
                        fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                ),
              ),
          ]),
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
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      _ConsoleMetaButton(label: 'SELECT', btn: ArcadeButton.select, controller: _ctrl),
      const SizedBox(width: 16),
      Container(width: 8, height: 8,
        decoration: BoxDecoration(shape: BoxShape.circle,
            color: Colors.white12, border: Border.all(color: Colors.white24))),
      const SizedBox(width: 16),
      _ConsoleMetaButton(label: 'START', btn: ArcadeButton.start, controller: _ctrl),
    ]);
  }

  // ── Controls row ──────────────────────────────────────────────────────────

  Widget _buildControlsRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [_buildDPad(), _buildABXYCluster()],
    );
  }

  Widget _buildDPad() {
    return SizedBox(
      width: 144, height: 144,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _ConsoleDPadArm(icon: Icons.keyboard_arrow_up_rounded, btn: ArcadeButton.up,
              controller: _ctrl, radius: const BorderRadius.vertical(top: Radius.circular(6))),
        ]),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _ConsoleDPadArm(icon: Icons.keyboard_arrow_left_rounded, btn: ArcadeButton.left,
              controller: _ctrl, radius: const BorderRadius.horizontal(left: Radius.circular(6))),
          Container(width: 48, height: 48, decoration: const BoxDecoration(color: _kDpad)),
          _ConsoleDPadArm(icon: Icons.keyboard_arrow_right_rounded, btn: ArcadeButton.right,
              controller: _ctrl, radius: const BorderRadius.horizontal(right: Radius.circular(6))),
        ]),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _ConsoleDPadArm(icon: Icons.keyboard_arrow_down_rounded, btn: ArcadeButton.down,
              controller: _ctrl, radius: const BorderRadius.vertical(bottom: Radius.circular(6))),
        ]),
      ]),
    );
  }

  Widget _buildABXYCluster() {
    const btnSize = 48.0;
    const gap     = 4.0;
    const total   = btnSize * 3 + gap * 2;
    return SizedBox(
      width: total, height: total,
      child: Stack(alignment: Alignment.center, children: [
        Positioned(top: 0, left: total / 2 - btnSize / 2,
            child: _ConsoleActionButton(label: 'X', btn: ArcadeButton.x,
                color: _kBtnX, controller: _ctrl, size: btnSize)),
        Positioned(left: 0, top: total / 2 - btnSize / 2,
            child: _ConsoleActionButton(label: 'Y', btn: ArcadeButton.y,
                color: _kBtnY, controller: _ctrl, size: btnSize)),
        Positioned(right: 0, top: total / 2 - btnSize / 2,
            child: _ConsoleActionButton(label: 'A', btn: ArcadeButton.a,
                color: _kBtnA, controller: _ctrl, size: btnSize)),
        Positioned(bottom: 0, left: total / 2 - btnSize / 2,
            child: _ConsoleActionButton(label: 'B', btn: ArcadeButton.b,
                color: _kBtnB, controller: _ctrl, size: btnSize)),
      ]),
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

// ─── Card Art Painter ─────────────────────────────────────────────────────────

class _CardArtPainter extends CustomPainter {
  final int index;
  final bool selected;
  const _CardArtPainter({required this.index, required this.selected});

  @override
  bool shouldRepaint(_CardArtPainter old) => old.selected != selected || old.index != index;

  @override
  void paint(Canvas canvas, Size size) {
    final g = _kCardGradients[index];
    // Background gradient
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size.width, size.height), const Radius.circular(14)),
      Paint()..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: g).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    final p = Paint()..isAntiAlias = false;
    final w = size.width, h = size.height;

    switch (index) {
      // ── Víbora Neón ──────────────────────────────────────────────────────
      case 0:
        // Snake body — winding dot trail
        p.color = const Color(0xFF4CAF50).withOpacity(0.30);
        final pts = [
          Offset(w*0.62, h*0.20), Offset(w*0.82, h*0.28), Offset(w*0.88, h*0.42),
          Offset(w*0.82, h*0.58), Offset(w*0.65, h*0.64), Offset(w*0.50, h*0.58),
        ];
        for (int i = 0; i < pts.length - 1; i++) {
          canvas.drawLine(pts[i], pts[i + 1], p..strokeWidth = 10);
        }
        p.color = const Color(0xFF76FF03).withOpacity(0.55);
        canvas.drawCircle(pts[0], 8, p); // head
        p.color = const Color(0xFF00E676).withOpacity(0.20);
        canvas.drawRect(Rect.fromLTWH(w*0.45, h*0.08, w*0.48, h*0.78), p); // field glow

      // ── Reino Fantasmal ──────────────────────────────────────────────────
      case 1:
        // Maze grid
        p.color = Colors.deepPurple.withOpacity(0.18);
        for (int r = 0; r < 5; r++) {
          for (int c = 0; c < 7; c++) {
            if ((r + c) % 3 != 0) canvas.drawRect(Rect.fromLTWH(w*0.42 + c*13, h*0.08 + r*14, 12, 13), p);
          }
        }
        // Ghost
        p.color = Colors.white.withOpacity(0.18);
        canvas.drawOval(Rect.fromLTWH(w*0.60, h*0.55, 40, 32), p);
        canvas.drawRect(Rect.fromLTWH(w*0.60, h*0.55+16, 40, 20), p);
        // Eyes
        p.color = const Color(0xFF1A0A4A).withOpacity(0.80);
        canvas.drawCircle(Offset(w*0.66, h*0.62), 5, p);
        canvas.drawCircle(Offset(w*0.78, h*0.62), 5, p);

      // ── Alas de Cromo ────────────────────────────────────────────────────
      case 2:
        // Pipes
        p.color = Colors.cyan.withOpacity(0.18);
        canvas.drawRect(Rect.fromLTWH(w*0.52, 0, 22, h*0.36), p);
        canvas.drawRect(Rect.fromLTWH(w*0.52, h*0.60, 22, h*0.40), p);
        canvas.drawRect(Rect.fromLTWH(w*0.78, 0, 22, h*0.28), p);
        canvas.drawRect(Rect.fromLTWH(w*0.78, h*0.66, 22, h*0.34), p);
        // Bird
        p.color = Colors.amberAccent.withOpacity(0.45);
        canvas.drawOval(Rect.fromLTWH(w*0.35, h*0.44, 28, 18), p);
        canvas.drawOval(Rect.fromLTWH(w*0.28, h*0.42, 12, 8), p); // wing

      // ── Cruce Peligroso ──────────────────────────────────────────────────
      case 3:
        // Road lanes
        p.color = Colors.white.withOpacity(0.06);
        for (int i = 0; i < 4; i++) canvas.drawRect(Rect.fromLTWH(0, h*(0.20 + i*0.16), w, h*0.10), p);
        // Dashed center lines
        p.color = Colors.yellow.withOpacity(0.12);
        for (int i = 0; i < 6; i++) canvas.drawRect(Rect.fromLTWH(w*0.42 + i*14, h*0.24, 8, h*0.07), p);
        // Cars
        p.color = Colors.red.withOpacity(0.30);
        canvas.drawRect(Rect.fromLTWH(w*0.52, h*0.21, 32, 14), p);
        p.color = Colors.blue.withOpacity(0.25);
        canvas.drawRect(Rect.fromLTWH(w*0.70, h*0.37, 28, 13), p);
        // Frog
        p.color = Colors.green.withOpacity(0.45);
        canvas.drawOval(Rect.fromLTWH(w*0.60, h*0.66, 20, 16), p);
        p.color = Colors.white.withOpacity(0.60);
        canvas.drawCircle(Offset(w*0.63, h*0.65), 3, p);
        canvas.drawCircle(Offset(w*0.69, h*0.65), 3, p);

      // ── Asalto Estelar ────────────────────────────────────────────────────
      case 4:
        // Stars
        p.color = Colors.white.withOpacity(0.35);
        final stars = [Offset(w*0.50,h*0.10),Offset(w*0.65,h*0.18),Offset(w*0.80,h*0.12),
          Offset(w*0.55,h*0.32),Offset(w*0.72,h*0.40),Offset(w*0.88,h*0.28),
          Offset(w*0.48,h*0.52),Offset(w*0.78,h*0.58),Offset(w*0.92,h*0.48)];
        for (final s in stars) canvas.drawRect(Rect.fromLTWH(s.dx-1,s.dy-1,3,3), p);
        // Ship
        p.color = Colors.cyanAccent.withOpacity(0.35);
        final path = Path()
          ..moveTo(w*0.68, h*0.70)..lineTo(w*0.60, h*0.84)..lineTo(w*0.76, h*0.84)..close();
        canvas.drawPath(path, p..isAntiAlias = true);
        p.isAntiAlias = false;
        // Exhaust
        p.color = Colors.orange.withOpacity(0.35);
        canvas.drawRect(Rect.fromLTWH(w*0.65, h*0.84, 6, 8), p);
        // Enemy row
        p.color = Colors.redAccent.withOpacity(0.28);
        for (int i = 0; i < 4; i++) canvas.drawRect(Rect.fromLTWH(w*0.50+i*15, h*0.14, 11, 8), p);

      // ── Mazmorra Infernal ────────────────────────────────────────────────
      case 5:
        // Brick pattern
        p.color = Colors.red.withOpacity(0.10);
        for (int r = 0; r < 7; r++) {
          for (int c = 0; c < 5; c++) {
            final ox = (r % 2) * 12.0;
            canvas.drawRect(Rect.fromLTWH(w*0.40 + c*22 + ox, h*0.04 + r*12, 20, 10), p);
          }
        }
        // Demon eye (large)
        p.color = const Color(0xFFCC1100).withOpacity(0.50);
        canvas.drawCircle(Offset(w*0.72, h*0.62), 24, p..isAntiAlias = true);
        p.color = const Color(0xFF110000).withOpacity(0.60);
        canvas.drawCircle(Offset(w*0.72, h*0.62), 11, p);
        p.color = const Color(0xFFFF2200).withOpacity(0.85);
        canvas.drawCircle(Offset(w*0.72, h*0.62), 5, p);
        p.isAntiAlias = false;
        // Flames
        p.color = Colors.orange.withOpacity(0.22);
        canvas.drawOval(Rect.fromLTWH(w*0.53, h*0.76, 14, 22), p);
        canvas.drawOval(Rect.fromLTWH(w*0.62, h*0.78, 12, 18), p);
        canvas.drawOval(Rect.fromLTWH(w*0.80, h*0.75, 14, 22), p);
        p.color = Colors.yellow.withOpacity(0.15);
        canvas.drawOval(Rect.fromLTWH(w*0.55, h*0.80, 8, 14), p);
        canvas.drawOval(Rect.fromLTWH(w*0.82, h*0.79, 8, 14), p);

      // ── Cascada de Bloques ────────────────────────────────────────────────
      case 6:
        // I-piece (cyan)
        p.color = Colors.cyanAccent.withOpacity(0.28);
        for (int i = 0; i < 4; i++) canvas.drawRect(Rect.fromLTWH(w*0.48+i*14, h*0.12, 13, 13), p);
        // L-piece (orange)
        p.color = Colors.orange.withOpacity(0.28);
        for (int i = 0; i < 3; i++) canvas.drawRect(Rect.fromLTWH(w*0.48, h*0.28+i*14, 13, 13), p);
        canvas.drawRect(Rect.fromLTWH(w*0.62, h*0.28+2*14, 13, 13), p);
        // S-piece (green)
        p.color = Colors.greenAccent.withOpacity(0.25);
        canvas.drawRect(Rect.fromLTWH(w*0.62, h*0.52, 13, 13), p);
        canvas.drawRect(Rect.fromLTWH(w*0.76, h*0.52, 13, 13), p);
        canvas.drawRect(Rect.fromLTWH(w*0.48, h*0.66, 13, 13), p);
        canvas.drawRect(Rect.fromLTWH(w*0.62, h*0.66, 13, 13), p);
        // T-piece (purple)
        p.color = Colors.purpleAccent.withOpacity(0.25);
        for (int i = 0; i < 3; i++) canvas.drawRect(Rect.fromLTWH(w*0.48+i*14, h*0.80, 13, 13), p);
        canvas.drawRect(Rect.fromLTWH(w*0.62, h*0.66, 13, 13), p);

      // ── Campo Minado ──────────────────────────────────────────────────────
      case 7:
        // Grid cells
        p.color = Colors.white.withOpacity(0.07);
        for (int r = 0; r < 6; r++) {
          for (int c = 0; c < 6; c++) canvas.drawRect(Rect.fromLTWH(w*0.42+c*15, h*0.12+r*15, 14, 14), p);
        }
        // A few revealed cells
        p.color = Colors.white.withOpacity(0.18);
        canvas.drawRect(Rect.fromLTWH(w*0.42, h*0.12, 14, 14), p);
        canvas.drawRect(Rect.fromLTWH(w*0.57, h*0.12, 14, 14), p);
        canvas.drawRect(Rect.fromLTWH(w*0.42, h*0.27, 14, 14), p);
        // Mine/bomb
        p.color = Colors.orangeAccent.withOpacity(0.50);
        canvas.drawCircle(Offset(w*0.74, h*0.62), 16, p..isAntiAlias = true);
        p.color = Colors.red.withOpacity(0.50);
        canvas.drawRect(Rect.fromLTWH(w*0.74-2, h*0.62-24, 4, 10), p..isAntiAlias = false);
        // Spikes
        p.color = Colors.orangeAccent.withOpacity(0.40);
        for (int i = 0; i < 4; i++) {
          final angle = i * 3.14159 / 2;
          canvas.drawRect(Rect.fromLTWH(
            w*0.74 + cos(angle) * 16 - 2, h*0.62 + sin(angle) * 16 - 2, 4, 4), p);
        }
        break;
    }
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
  @override State<_ConsoleDPadArm> createState() => _ConsoleDPadArmState();
}

class _ConsoleDPadArmState extends State<_ConsoleDPadArm> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) { setState(() => _pressed = true); HapticFeedback.lightImpact(); widget.controller.press(widget.btn); },
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

// ─── Action button ────────────────────────────────────────────────────────────

class _ConsoleActionButton extends StatefulWidget {
  final String label;
  final ArcadeButton btn;
  final Color color;
  final ArcadeInputController controller;
  final double size;
  const _ConsoleActionButton({required this.label, required this.btn,
      required this.color, required this.controller, required this.size});
  @override State<_ConsoleActionButton> createState() => _ConsoleActionButtonState();
}

class _ConsoleActionButtonState extends State<_ConsoleActionButton> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) { setState(() => _pressed = true); HapticFeedback.selectionClick(); widget.controller.press(widget.btn); },
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
        child: Text(widget.label,
          style: TextStyle(color: _pressed ? Colors.white70 : Colors.white,
              fontWeight: FontWeight.bold, fontSize: 15)),
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
  @override State<_ConsoleMetaButton> createState() => _ConsoleMetaButtonState();
}

class _ConsoleMetaButtonState extends State<_ConsoleMetaButton> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) { setState(() => _pressed = true); HapticFeedback.selectionClick(); widget.controller.press(widget.btn); },
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
        child: Text(widget.label,
          style: TextStyle(
            color: _pressed ? Colors.white : const Color(0xFF222222),
            fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
      ),
    );
  }
}
