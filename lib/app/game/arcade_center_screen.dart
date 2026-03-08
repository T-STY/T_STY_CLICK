import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'arcade_input_controller.dart';
import 'flappy_bird_screen.dart';
import 'high_score_service.dart';
import 'logic_grid_screen.dart';
import 'match3_screen.dart';
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

// ─── Neon accent colours (one per game, used for border glow in grid) ────────

// Neon border colours — one per game, in alphabetical title order:
const _kNeonColors = <Color>[
  Color(0xFFBB44FF), // Bloques Caídos  – purple
  Color(0xFFFFEE00), // Campo Minado    – yellow (caution)
  Color(0xFFFF44BB), // Cascada Dulce   – pink
  Color(0xFFFF4422), // Caza Estelar    – red-orange
  Color(0xFF4488FF), // Comecocos       – blue
  Color(0xFFFF8800), // Cripta Maldita  – hellfire orange
  Color(0xFF88FF44), // Rana Saltarina  – lime
  Color(0xFF00FF88), // Víbora Veloz    – green
  Color(0xFF00CCFF), // Vuelo Kamikaze  – sky cyan
];

// ─── Card background gradients (per game — colours match the actual game) ─────

// Card art gradients — matched to alphabetical title order:
const _kCardGradients = <List<Color>>[
  [Color(0xFF040414), Color(0xFF10104A)],   // Bloques Caídos  – dark navy
  [Color(0xFF040C04), Color(0xFF0C2A0C)],   // Campo Minado    – dark forest
  [Color(0xFF1A0018), Color(0xFF5A0038)],   // Cascada Dulce   – candy pink
  [Color(0xFF02040E), Color(0xFF060E38)],   // Caza Estelar    – deep space
  [Color(0xFF000A28), Color(0xFF001E8A)],   // Comecocos       – royal blue
  [Color(0xFF160000), Color(0xFF4D0000)],   // Cripta Maldita  – blood red
  [Color(0xFF080C00), Color(0xFF254700)],   // Rana Saltarina  – forest green
  [Color(0xFF001200), Color(0xFF005A00)],   // Víbora Veloz    – neon green
  [Color(0xFF001018), Color(0xFF004D70)],   // Vuelo Kamikaze  – sky blue
];

// ─── Category labels ──────────────────────────────────────────────────────────

// Category labels removed — hub now uses alphabetical order with neon colour coding

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

// Games ordered alphabetically by new Spanish title:
// Bloques Caídos · Campo Minado · Cascada Dulce ·
// Caza Estelar   · Comecocos    · Cripta Maldita ·
// Rana Saltarina · Víbora Veloz · Vuelo Kamikaze
final List<ArcadeGameDef> kArcadeGames = [
  ArcadeGameDef(id: 'tetris',   emoji: '🟦', title: 'Bloques Caídos',
    builder: ({required userId, required rewardsDocRef, required currentSaldo,
        required controller, required onSaldoChanged}) =>
      TetrisScreen(userId: userId, rewardsDocRef: rewardsDocRef,
        currentSaldo: currentSaldo, controller: controller, onSaldoChanged: onSaldoChanged)),
  ArcadeGameDef(id: 'logic',    emoji: '💣', title: 'Campo Minado',
    builder: ({required userId, required rewardsDocRef, required currentSaldo,
        required controller, required onSaldoChanged}) =>
      LogicGridScreen(userId: userId, rewardsDocRef: rewardsDocRef,
        currentSaldo: currentSaldo, controller: controller, onSaldoChanged: onSaldoChanged)),
  ArcadeGameDef(id: 'match3',   emoji: '🍬', title: 'Cascada Dulce',
    builder: ({required userId, required rewardsDocRef, required currentSaldo,
        required controller, required onSaldoChanged}) =>
      Match3Screen(userId: userId, rewardsDocRef: rewardsDocRef,
        currentSaldo: currentSaldo, controller: controller, onSaldoChanged: onSaldoChanged)),
  ArcadeGameDef(id: 'shooter',  emoji: '🚀', title: 'Caza Estelar',
    builder: ({required userId, required rewardsDocRef, required currentSaldo,
        required controller, required onSaldoChanged}) =>
      SpaceShooterScreen(userId: userId, rewardsDocRef: rewardsDocRef,
        currentSaldo: currentSaldo, controller: controller, onSaldoChanged: onSaldoChanged)),
  ArcadeGameDef(id: 'maze',     emoji: '👻', title: 'Comecocos',
    builder: ({required userId, required rewardsDocRef, required currentSaldo,
        required controller, required onSaldoChanged}) =>
      MazeChasScreen(userId: userId, rewardsDocRef: rewardsDocRef,
        currentSaldo: currentSaldo, controller: controller, onSaldoChanged: onSaldoChanged)),
  ArcadeGameDef(id: 'raycaster',emoji: '🔥', title: 'Cripta Maldita',
    builder: ({required userId, required rewardsDocRef, required currentSaldo,
        required controller, required onSaldoChanged}) =>
      RaycasterScreen(userId: userId, rewardsDocRef: rewardsDocRef,
        currentSaldo: currentSaldo, controller: controller, onSaldoChanged: onSaldoChanged)),
  ArcadeGameDef(id: 'hopper',   emoji: '🐸', title: 'Rana Saltarina',
    builder: ({required userId, required rewardsDocRef, required currentSaldo,
        required controller, required onSaldoChanged}) =>
      TrafficHopperScreen(userId: userId, rewardsDocRef: rewardsDocRef,
        currentSaldo: currentSaldo, controller: controller, onSaldoChanged: onSaldoChanged)),
  ArcadeGameDef(id: 'snake',    emoji: '🐍', title: 'Víbora Veloz',
    builder: ({required userId, required rewardsDocRef, required currentSaldo,
        required controller, required onSaldoChanged}) =>
      SnakeGameScreen(userId: userId, rewardsDocRef: rewardsDocRef,
        currentSaldo: currentSaldo, controller: controller, onSaldoChanged: onSaldoChanged)),
  ArcadeGameDef(id: 'flappy',   emoji: '🕊️', title: 'Vuelo Kamikaze',
    builder: ({required userId, required rewardsDocRef, required currentSaldo,
        required controller, required onSaldoChanged}) =>
      FlappyBirdScreen(userId: userId, rewardsDocRef: rewardsDocRef,
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
  final List<int> _highScores = List.filled(9, 0);

  // ── Splash / power-on ──────────────────────────────────────────────────────
  bool _splashDone = false;
  int _splashLine = 0;          // 0-6: animate boot lines one by one
  String _userName = '';
  Timer? _splashTimer;

  static const _kBootLines = [
    '> Verificando CPU       [  OK  ]',
    '> RAM 64K               [  OK  ]',
    '> Buffer de video       [  OK  ]',
    '> Sintetizador audio    [  OK  ]',
    '> Conexión de red       [  OK  ]',
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = ArcadeInputController();
    _saldo = widget.currentSaldo;
    _ctrl.addListener(_handleShellEvent);
    _loadHighScores();
    _fetchUserName();
    // Advance boot lines every 420 ms
    _splashTimer = Timer.periodic(const Duration(milliseconds: 420), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        if (_splashLine < _kBootLines.length + 1) {
          _splashLine++;
        } else {
          t.cancel(); // wait for A/Start press
        }
      });
    });
  }

  Future<void> _fetchUserName() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users').doc(widget.userId).get();
      if (mounted) {
        setState(() {
          _userName = (doc.data()?['userInfo']?['name'] as String?)?.trim()
              .split(' ').first // first name only
              ?? 'Jugador';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _userName = 'Jugador');
    }
  }

  Future<void> _loadHighScores() async {
    final scores = await Future.wait(kArcadeGames.map((g) => HighScoreService.load(g.id)));
    if (mounted) setState(() {
      for (int i = 0; i < scores.length; i++) _highScores[i] = scores[i];
    });
  }

  @override
  void dispose() {
    _splashTimer?.cancel();
    _ctrl.removeListener(_handleShellEvent);
    _ctrl.dispose();
    super.dispose();
  }

  void _handleShellEvent() {
    final event = _ctrl.lastEvent;
    if (event == null || !event.isDown) return;
    final btn = event.button;

    // Splash intercept — any confirm button dismisses the splash
    if (!_splashDone) {
      if (btn == ArcadeButton.a || btn == ArcadeButton.start) {
        _splashTimer?.cancel();
        setState(() => _splashDone = true);
      }
      return;
    }

    if (_activeGame == null) {
      const cols = 3; // neon grid columns
      switch (btn) {
        case ArcadeButton.left:
          setState(() => _selectedIndex = (_selectedIndex - 1 + 9) % 9);
        case ArcadeButton.right:
          setState(() => _selectedIndex = (_selectedIndex + 1) % 9);
        case ArcadeButton.up:
          setState(() => _selectedIndex = (_selectedIndex - cols + 9) % 9);
        case ArcadeButton.down:
          setState(() => _selectedIndex = (_selectedIndex + cols) % 9);
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
        child: Stack(children: [
          _activeGame == null ? _buildNeonGrid() : _buildActiveGame(),
          // CRT scanline + vignette overlay
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _CrtOverlayPainter()),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Neon Arcade Cabinet Grid ───────────────────────────────────────────────

  Widget _buildNeonGrid() {
    if (!_splashDone) return _buildSplashScreen();
    return Container(
      color: const Color(0xFF07000F),
      child: Column(children: [
        _buildGameGrid(),
        _buildGridHint(),
      ]),
    );
  }

  // ── CRT Power-on splash ───────────────────────────────────────────────────

  Widget _buildSplashScreen() {
    final showWelcome = _splashLine >= _kBootLines.length + 1;
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          const Text('ARCADE CENTER OS  v1.0.0',
            style: TextStyle(color: Color(0xFF00FF88), fontSize: 9,
                fontFamily: 'monospace', fontWeight: FontWeight.bold,
                letterSpacing: 1.5)),
          const SizedBox(height: 2),
          Container(height: 1, color: const Color(0xFF00FF88).withOpacity(0.35)),
          const SizedBox(height: 8),
          // Boot lines (appear one by one)
          for (int i = 0; i < _kBootLines.length; i++)
            if (i < _splashLine)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(_kBootLines[i],
                  style: const TextStyle(color: Color(0xFF44FF88), fontSize: 8,
                      fontFamily: 'monospace')),
              ),
          const Spacer(),
          // Welcome message (appears after all boot lines)
          if (showWelcome) ...[
            Container(height: 1, color: const Color(0xFF00FF88).withOpacity(0.25)),
            const SizedBox(height: 12),
            Center(
              child: Column(children: [
                Text('¡BIENVENIDO,',
                  style: const TextStyle(color: Color(0xFF00FF88), fontSize: 13,
                      fontFamily: 'monospace', fontWeight: FontWeight.bold,
                      letterSpacing: 2)),
                Text(_userName.isEmpty ? '...' : _userName.toUpperCase() + '!',
                  style: const TextStyle(color: Colors.white, fontSize: 22,
                      fontFamily: 'monospace', fontWeight: FontWeight.w900,
                      letterSpacing: 3,
                      shadows: [Shadow(color: Color(0xFF00FF88), blurRadius: 14)])),
              ]),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text('[ A ]  Continuar',
                style: TextStyle(
                  color: const Color(0xFF00FF88).withOpacity(0.70),
                  fontSize: 8, fontFamily: 'monospace', letterSpacing: 2)),
            ),
          ] else ...[
            // Blinking cursor while booting
            Row(children: [
              const Text('> ',
                style: TextStyle(color: Color(0xFF00FF88), fontSize: 8, fontFamily: 'monospace')),
              Container(width: 6, height: 10, color: const Color(0xFF00FF88).withOpacity(0.80)),
            ]),
          ],
          const SizedBox(height: 6),
          Container(height: 1, color: const Color(0xFF00FF88).withOpacity(0.15)),
          const SizedBox(height: 4),
          Text('ARCADE CENTER OS  ©2025',
            style: TextStyle(color: const Color(0xFF00FF88).withOpacity(0.30),
                fontSize: 7, fontFamily: 'monospace')),
        ],
      ),
    );
  }

  Widget _buildGameGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        const cols = 3;
        final cellW = constraints.maxWidth / cols;
        final cellH = constraints.maxHeight / 3;

        return GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(6),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
          ),
          itemCount: kArcadeGames.length,
          itemBuilder: (_, i) => _buildNeonCard(
              kArcadeGames[i], i, i == _selectedIndex, cellW - 6, cellH - 6),
        );
      },
    );
  }

  Widget _buildNeonCard(ArcadeGameDef def, int index, bool selected, double w, double h) {
    final neon = _kNeonColors[index];
    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = index),
      onDoubleTap: selected ? _launchSelected : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? neon : neon.withOpacity(0.35),
            width: selected ? 2.0 : 1.0,
          ),
          boxShadow: selected ? [
            BoxShadow(color: neon.withOpacity(0.55), blurRadius: 12, spreadRadius: 1),
            BoxShadow(color: neon.withOpacity(0.20), blurRadius: 24, spreadRadius: 3),
          ] : [
            BoxShadow(color: neon.withOpacity(0.08), blurRadius: 6),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: Stack(children: [
            // Card art background
            Positioned.fill(
              child: CustomPaint(
                painter: _CartridgePainter(index: index, selected: selected),
              ),
            ),
            // Neon tint overlay on selected
            if (selected)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: neon.withOpacity(0.06),
                  ),
                ),
              ),
            // Content overlay
            Positioned.fill(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Emoji
                  Text(def.emoji,
                    style: TextStyle(fontSize: selected ? 20 : 16)),
                  const SizedBox(height: 2),
                  // Title
                  Text(def.title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? neon : Colors.white70,
                      fontSize: 7.5,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                      letterSpacing: 0.5,
                      shadows: selected ? [Shadow(color: neon, blurRadius: 8)] : null,
                    ),
                  ),
                  // High score
                  if (_highScores[index] > 0)
                    Text('★ ${_highScores[index]}',
                      style: TextStyle(
                        color: Colors.amber.withOpacity(selected ? 1.0 : 0.60),
                        fontSize: 7, fontFamily: 'monospace',
                      )),
                  const SizedBox(height: 5),
                ],
              ),
            ),
            // JUGAR badge on selected
            if (selected)
              Positioned(
                top: 4, right: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: neon.withOpacity(0.20),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: neon.withOpacity(0.70), width: 1),
                  ),
                  child: Text('▶',
                    style: TextStyle(color: neon, fontSize: 8,
                        shadows: [Shadow(color: neon, blurRadius: 6)])),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _buildGridHint() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0020),
        border: Border(top: BorderSide(
            color: const Color(0xFF660099).withOpacity(0.40), width: 1)),
      ),
      child: const Text(
        '◄ ► ▲ ▼ navegar   A jugar   SELECT salir',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white30, fontSize: 7,
            fontFamily: 'monospace', letterSpacing: 1),
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

// ─── TCG-style Card Painter ───────────────────────────────────────────────────

class _CartridgePainter extends CustomPainter {
  final int index;
  final bool selected;
  const _CartridgePainter({required this.index, required this.selected});

  @override
  bool shouldRepaint(_CartridgePainter old) => old.selected != selected || old.index != index;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final rr = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), const Radius.circular(18));

    // ── Base gradient ──────────────────────────────────────────────────────────
    final g = _kCardGradients[index];
    canvas.drawRRect(rr, Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [g[0], g[1]],
      ).createShader(Rect.fromLTWH(0, 0, w, h)));

    // ── Game art (full bleed, clipped to card) ─────────────────────────────────
    canvas.save();
    canvas.clipRRect(rr);
    _drawGameArt(canvas, w, h);

    // Top vignette (darkens top so number badge is readable)
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h * 0.22),
      Paint()..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Colors.black.withOpacity(0.60), Colors.black.withOpacity(0.0)],
      ).createShader(Rect.fromLTWH(0, 0, w, h * 0.22)));

    // Bottom vignette (darkens footer for text legibility)
    canvas.drawRect(Rect.fromLTWH(0, h * 0.55, w, h * 0.45),
      Paint()..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Colors.black.withOpacity(0.0), Colors.black.withOpacity(0.90)],
      ).createShader(Rect.fromLTWH(0, h * 0.55, w, h * 0.45)));

    canvas.restore();

    // ── Outer border ───────────────────────────────────────────────────────────
    canvas.drawRRect(rr, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = selected ? 2.5 : 1.5
      ..color = selected ? Colors.white.withOpacity(0.90) : Colors.white.withOpacity(0.25)
      ..isAntiAlias = true);

    // Inner accent border
    canvas.save();
    canvas.clipRRect(rr);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(4, 4, w - 8, h - 8), const Radius.circular(14)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = Colors.white.withOpacity(0.12)
        ..isAntiAlias = true);
    canvas.restore();

    // ── Number badge (top centre) ───────────────────────────────────────────────
    final bx = w / 2, by = 22.0, br = 14.0;
    canvas.drawCircle(Offset(bx, by + 1.5), br,
        Paint()..color = Colors.black.withOpacity(0.45)..isAntiAlias = true);
    canvas.drawCircle(Offset(bx, by), br,
        Paint()..color = g[1].withOpacity(0.92)..isAntiAlias = true);
    canvas.drawCircle(Offset(bx, by), br,
        Paint()..style = PaintingStyle.stroke..strokeWidth = 1.5
          ..color = Colors.white.withOpacity(0.55)..isAntiAlias = true);
    final numTp = TextPainter(
      text: TextSpan(text: '${index + 1}',
        style: const TextStyle(color: Colors.white, fontSize: 13,
            fontWeight: FontWeight.bold, fontFamily: 'monospace')),
      textDirection: TextDirection.ltr,
    )..layout();
    numTp.paint(canvas, Offset(bx - numTp.width / 2, by - numTp.height / 2));
    numTp.dispose();

    // ── Selected shimmer ────────────────────────────────────────────────────────
    if (selected) {
      canvas.save();
      canvas.clipRRect(rr);
      canvas.drawRect(Rect.fromLTWH(0, 0, w, h),
          Paint()..color = Colors.white.withOpacity(0.05));
      canvas.restore();
    }
  }

  // ── Per-game full-bleed art ───────────────────────────────────────────────────

  void _drawGameArt(Canvas canvas, double w, double h) {
    final p = Paint()..isAntiAlias = false;

    switch (index) {
      // ── La Sierpe ─────────────────────────────────────────────────────────
      case 0:
        // Grid dots
        p.color = const Color(0xFF00FF00).withOpacity(0.06);
        for (int r = 0; r < 10; r++) {
          for (int c = 0; c < 7; c++) {
            canvas.drawRect(Rect.fromLTWH(c * (w/7), r * (h/10), w/7 - 1, h/10 - 1), p);
          }
        }
        // Snake body
        final segs = [
          Offset(w*0.50, h*0.45), Offset(w*0.68, h*0.36), Offset(w*0.80, h*0.28),
          Offset(w*0.80, h*0.48), Offset(w*0.65, h*0.58), Offset(w*0.50, h*0.68),
          Offset(w*0.32, h*0.60), Offset(w*0.20, h*0.50),
        ];
        final segP = Paint()..isAntiAlias = true..strokeWidth = 13
          ..strokeCap = StrokeCap.round..color = const Color(0xFF009900).withOpacity(0.80);
        for (int i = 0; i < segs.length - 1; i++) canvas.drawLine(segs[i], segs[i+1], segP);
        // Head
        segP.color = const Color(0xFF22EE22);
        canvas.drawCircle(segs[0], 10, segP..style = PaintingStyle.fill);
        p.color = Colors.black;
        canvas.drawRect(Rect.fromLTWH(segs[0].dx - 5, segs[0].dy - 3, 3, 3), p);
        canvas.drawRect(Rect.fromLTWH(segs[0].dx + 2, segs[0].dy - 3, 3, 3), p);
        // Food
        p.isAntiAlias = true;
        p.color = const Color(0xFFFF2222).withOpacity(0.90);
        canvas.drawCircle(Offset(w*0.22, h*0.33), 8, p);
        p.color = Colors.white.withOpacity(0.65);
        canvas.drawCircle(Offset(w*0.20, h*0.31), 3, p);
        p.isAntiAlias = false;
        break;

      // ── Tragalaberinto ────────────────────────────────────────────────────
      case 1:
        // Maze walls (BLUE)
        p.color = const Color(0xFF1A4AFF).withOpacity(0.60);
        final walls = [
          Rect.fromLTWH(6, 6, w - 12, 10),
          Rect.fromLTWH(6, h - 16, w - 12, 10),
          Rect.fromLTWH(6, 6, 10, h - 12),
          Rect.fromLTWH(w - 16, 6, 10, h - 12),
          Rect.fromLTWH(6, h*0.28, w*0.42, 10),
          Rect.fromLTWH(w*0.58, h*0.28, w*0.34, 10),
          Rect.fromLTWH(w*0.28, h*0.50, 10, h*0.26),
          Rect.fromLTWH(w*0.65, h*0.50, 10, h*0.26),
          Rect.fromLTWH(6, h*0.70, w*0.52, 10),
          Rect.fromLTWH(w*0.42, h*0.42, w*0.30, 10),
        ];
        for (final r in walls) canvas.drawRect(r, p);
        // Dots trail (yellow)
        p.color = const Color(0xFFFFFF88).withOpacity(0.65);
        for (int i = 0; i < 5; i++) canvas.drawRect(Rect.fromLTWH(w*0.38 + i*11, h*0.62, 5, 5), p);
        // Pac-Man (yellow)
        p.color = const Color(0xFFFFDD00).withOpacity(0.95);
        p.isAntiAlias = true;
        final pac = Path()
          ..moveTo(w*0.33, h*0.63)
          ..arcTo(Rect.fromCenter(center: Offset(w*0.33, h*0.63), width: 28, height: 28), 0.5, 5.4, false)
          ..close();
        canvas.drawPath(pac, p);
        // Ghost (blue)
        p.color = const Color(0xFF3366FF).withOpacity(0.85);
        canvas.drawOval(Rect.fromLTWH(w*0.60, h*0.35, 28, 22), p);
        canvas.drawRect(Rect.fromLTWH(w*0.60, h*0.35 + 11, 28, 14), p);
        p.color = Colors.white;
        canvas.drawOval(Rect.fromLTWH(w*0.63, h*0.37, 8, 9), p);
        canvas.drawOval(Rect.fromLTWH(w*0.73, h*0.37, 8, 9), p);
        p.color = const Color(0xFF0000CC);
        canvas.drawCircle(Offset(w*0.67, h*0.40), 3, p);
        canvas.drawCircle(Offset(w*0.77, h*0.40), 3, p);
        p.isAntiAlias = false;
        break;

      // ── Alas Locas ────────────────────────────────────────────────────────
      case 2:
        // Pipes (green)
        p.color = const Color(0xFF228B22).withOpacity(0.80);
        canvas.drawRect(Rect.fromLTWH(w*0.14, 0, 28, h*0.32), p);
        canvas.drawRect(Rect.fromLTWH(w*0.14, h*0.46, 28, h*0.54), p);
        p.color = const Color(0xFF33AA33).withOpacity(0.80);
        canvas.drawRect(Rect.fromLTWH(w*0.10, h*0.29, 36, 10), p);
        canvas.drawRect(Rect.fromLTWH(w*0.10, h*0.43, 36, 10), p);
        p.color = const Color(0xFF228B22).withOpacity(0.55);
        canvas.drawRect(Rect.fromLTWH(w*0.70, 0, 28, h*0.20), p);
        canvas.drawRect(Rect.fromLTWH(w*0.70, h*0.34, 28, h*0.66), p);
        p.color = const Color(0xFF33AA33).withOpacity(0.55);
        canvas.drawRect(Rect.fromLTWH(w*0.66, h*0.17, 36, 10), p);
        canvas.drawRect(Rect.fromLTWH(w*0.66, h*0.31, 36, 10), p);
        // Cloud puffs
        p.color = Colors.white.withOpacity(0.20);
        canvas.drawOval(Rect.fromLTWH(w*0.35, h*0.10, 44, 18), p);
        canvas.drawOval(Rect.fromLTWH(w*0.52, h*0.08, 30, 14), p);
        canvas.drawOval(Rect.fromLTWH(w*0.54, h*0.74, 36, 16), p);
        // Bird body
        p.color = const Color(0xFFFFCC00).withOpacity(0.95);
        p.isAntiAlias = true;
        canvas.drawOval(Rect.fromLTWH(w*0.38, h*0.36, 36, 28), p);
        p.color = const Color(0xFFFFAA00).withOpacity(0.85);
        canvas.drawOval(Rect.fromLTWH(w*0.40, h*0.42, 18, 10), p); // wing
        p.color = Colors.white;
        canvas.drawCircle(Offset(w*0.52, h*0.38), 7, p);
        p.color = Colors.black;
        canvas.drawCircle(Offset(w*0.54, h*0.38), 3, p);
        p.color = const Color(0xFFFF6600);
        canvas.drawRect(Rect.fromLTWH(w*0.57, h*0.41, 9, 5), p);
        p.isAntiAlias = false;
        break;

      // ── Paso a Paso ────────────────────────────────────────────────────────
      case 3:
        // Road strips
        p.color = Colors.white.withOpacity(0.05);
        for (int i = 0; i < 3; i++) canvas.drawRect(Rect.fromLTWH(0, h*(0.06+i*0.13), w, h*0.10), p);
        // Dashed lines
        p.color = Colors.yellow.withOpacity(0.14);
        for (int i = 0; i < 8; i++) canvas.drawRect(Rect.fromLTWH(i*w/7, h*0.12, w/14, h*0.06), p);
        // Cars
        p.color = Colors.red.withOpacity(0.60);
        canvas.drawRect(Rect.fromLTWH(w*0.05, h*0.07, 44, 14), p);
        p.color = Colors.blue.withOpacity(0.50);
        canvas.drawRect(Rect.fromLTWH(w*0.52, h*0.20, 38, 12), p);
        p.color = Colors.orange.withOpacity(0.55);
        canvas.drawRect(Rect.fromLTWH(w*0.20, h*0.32, 42, 13), p);
        // River
        p.color = const Color(0xFF004466).withOpacity(0.60);
        canvas.drawRect(Rect.fromLTWH(0, h*0.44, w, h*0.22), p);
        // Lily pads
        p.isAntiAlias = true;
        p.color = const Color(0xFF006600).withOpacity(0.65);
        canvas.drawOval(Rect.fromLTWH(w*0.06, h*0.46, 34, 14), p);
        canvas.drawOval(Rect.fromLTWH(w*0.48, h*0.49, 30, 12), p);
        canvas.drawOval(Rect.fromLTWH(w*0.74, h*0.45, 26, 12), p);
        // Frog body
        p.color = const Color(0xFF22CC22).withOpacity(0.92);
        canvas.drawOval(Rect.fromLTWH(w*0.34, h*0.63, 32, 24), p);
        canvas.drawOval(Rect.fromLTWH(w*0.28, h*0.59, 18, 14), p); // left leg
        canvas.drawOval(Rect.fromLTWH(w*0.54, h*0.59, 18, 14), p); // right leg
        p.color = const Color(0xFF33EE33).withOpacity(0.90);
        canvas.drawCircle(Offset(w*0.38, h*0.61), 7, p);
        canvas.drawCircle(Offset(w*0.56, h*0.61), 7, p);
        p.color = Colors.black;
        canvas.drawCircle(Offset(w*0.38, h*0.61), 3, p);
        canvas.drawCircle(Offset(w*0.56, h*0.61), 3, p);
        p.isAntiAlias = false;
        break;

      // ── Astrocaza ─────────────────────────────────────────────────────────
      case 4:
        // Star field
        final starPts = [
          Offset(w*0.10,h*0.08), Offset(w*0.32,h*0.14), Offset(w*0.66,h*0.05),
          Offset(w*0.84,h*0.20), Offset(w*0.20,h*0.34), Offset(w*0.88,h*0.38),
          Offset(w*0.50,h*0.26), Offset(w*0.74,h*0.52), Offset(w*0.06,h*0.60),
          Offset(w*0.40,h*0.52), Offset(w*0.60,h*0.70), Offset(w*0.16,h*0.78),
        ];
        for (final s in starPts) {
          p.color = Colors.white.withOpacity(0.40 + (s.dx / w) * 0.40);
          canvas.drawRect(Rect.fromLTWH(s.dx - 1.5, s.dy - 1.5, 3, 3), p);
        }
        // Enemy ships (red alien row)
        p.color = const Color(0xFFCC1100).withOpacity(0.80);
        for (int i = 0; i < 4; i++) {
          final ex = w*0.10 + i * w*0.22;
          final ey = h*0.12 + (i % 2) * h*0.07;
          canvas.drawRect(Rect.fromLTWH(ex, ey, 20, 8), p);
          canvas.drawRect(Rect.fromLTWH(ex - 4, ey + 8, 28, 6), p);
          canvas.drawRect(Rect.fromLTWH(ex + 2, ey - 4, 6, 4), p);
          canvas.drawRect(Rect.fromLTWH(ex + 12, ey - 4, 6, 4), p);
        }
        // Player ship (cyan)
        p.isAntiAlias = true;
        p.color = const Color(0xFF44FFFF).withOpacity(0.88);
        final ship = Path()
          ..moveTo(w*0.50, h*0.72)
          ..lineTo(w*0.38, h*0.88)
          ..lineTo(w*0.44, h*0.84)
          ..lineTo(w*0.56, h*0.84)
          ..lineTo(w*0.62, h*0.88)
          ..close();
        canvas.drawPath(ship, p);
        p.color = Colors.white.withOpacity(0.55);
        canvas.drawOval(Rect.fromLTWH(w*0.46, h*0.74, 8, 10), p); // cockpit
        // Engine glow
        p.color = const Color(0xFFFF8800).withOpacity(0.75);
        canvas.drawOval(Rect.fromLTWH(w*0.45, h*0.86, 10, 8), p);
        p.color = Colors.white.withOpacity(0.60);
        canvas.drawOval(Rect.fromLTWH(w*0.47, h*0.87, 6, 5), p);
        // Laser bolt
        p.color = const Color(0xFF88FFFF).withOpacity(0.70);
        canvas.drawRect(Rect.fromLTWH(w*0.49, h*0.42, 3, h*0.30), p);
        p.isAntiAlias = false;
        break;

      // ── Inframundo 2D ─────────────────────────────────────────────────────
      case 5:
        // Stone bricks
        p.color = const Color(0xFF550000).withOpacity(0.45);
        for (int r = 0; r < 9; r++) {
          final xOff = (r % 2) * 18.0;
          for (int c = 0; c < 4; c++) {
            canvas.drawRect(Rect.fromLTWH(c * 36.0 + xOff, r * 16.0, 34, 14), p);
          }
        }
        // Demon eye
        p.isAntiAlias = true;
        p.color = const Color(0xFFCC0000).withOpacity(0.20);
        canvas.drawCircle(Offset(w*0.50, h*0.46), 52, p);
        p.color = const Color(0xFF880000).withOpacity(0.75);
        canvas.drawCircle(Offset(w*0.50, h*0.46), 36, p);
        p.color = const Color(0xFFDD1100).withOpacity(0.92);
        canvas.drawCircle(Offset(w*0.50, h*0.46), 26, p);
        p.color = Colors.black;
        canvas.drawOval(Rect.fromLTWH(w*0.47, h*0.40, 7, 24), p); // slit pupil
        p.color = const Color(0xFFFF3311).withOpacity(0.90);
        canvas.drawCircle(Offset(w*0.50, h*0.46), 12, p);
        p.color = Colors.white.withOpacity(0.28);
        canvas.drawCircle(Offset(w*0.46, h*0.42), 5, p);
        // Flames
        p.color = const Color(0xFFFF4400).withOpacity(0.60);
        for (int i = 0; i < 5; i++) canvas.drawOval(Rect.fromLTWH(i*w/5, h*0.74, w/5, h*0.28), p);
        p.color = const Color(0xFFFF8800).withOpacity(0.45);
        for (int i = 0; i < 4; i++) canvas.drawOval(Rect.fromLTWH(w*0.10+i*w/4, h*0.80, w/5, h*0.22), p);
        p.color = const Color(0xFFFFCC00).withOpacity(0.28);
        for (int i = 0; i < 3; i++) canvas.drawOval(Rect.fromLTWH(w*0.15+i*w/3, h*0.86, w/4, h*0.14), p);
        p.isAntiAlias = false;
        break;

      // ── Tetromuro ─────────────────────────────────────────────────────────
      case 6:
        const tetC = [
          Color(0xFF00DDDD), Color(0xFFDD8800), Color(0xFF2222DD),
          Color(0xFFDDDD00), Color(0xFF22DD22), Color(0xFFDD22DD), Color(0xFFDD2222),
        ];
        const cell = 15.0;
        final sl = (w - cell * 7) / 2;
        final rowPattern = [[0,1,2,3,4,5,6],[1,2,3,4,5,6],[0,2,3,5],[1,3,6],[0,4]];
        for (int ri = 0; ri < rowPattern.length; ri++) {
          final rowY = h - (ri + 1) * cell - 8;
          for (final ci in rowPattern[ri]) {
            p.color = tetC[(ri + ci) % tetC.length].withOpacity(0.75);
            canvas.drawRect(Rect.fromLTWH(sl + ci*cell, rowY, cell-1, cell-1), p);
            p.color = Colors.white.withOpacity(0.28);
            canvas.drawRect(Rect.fromLTWH(sl + ci*cell, rowY, cell-1, 3), p);
          }
        }
        // Falling T-piece
        p.color = const Color(0xFFDD22DD).withOpacity(0.85);
        final fx = sl + cell * 2, fy = h * 0.22;
        for (int i = 0; i < 3; i++) canvas.drawRect(Rect.fromLTWH(fx+i*cell, fy, cell-1, cell-1), p);
        canvas.drawRect(Rect.fromLTWH(fx+cell, fy+cell, cell-1, cell-1), p);
        p.color = Colors.white.withOpacity(0.25);
        for (int i = 0; i < 3; i++) canvas.drawRect(Rect.fromLTWH(fx+i*cell, fy, cell-1, 3), p);
        // Ghost drop shadow
        p.color = const Color(0xFFDD22DD).withOpacity(0.18);
        final gy2 = h - 6*cell - 9;
        for (int i = 0; i < 3; i++) canvas.drawRect(Rect.fromLTWH(fx+i*cell, gy2, cell-1, cell-1), p);
        canvas.drawRect(Rect.fromLTWH(fx+cell, gy2+cell, cell-1, cell-1), p);
        break;

      // ── Busca-Trampas ─────────────────────────────────────────────────────
      case 7:
        final cw2 = w / 7, ch2 = h / 9;
        for (int r = 0; r < 9; r++) {
          for (int c = 0; c < 7; c++) {
            final state = (r * 7 + c) % 4;
            if (state == 0) {
              p.color = const Color(0xFF1A5C1A).withOpacity(0.55);
              canvas.drawRect(Rect.fromLTWH(c*cw2+1, r*ch2+1, cw2-2, ch2-2), p);
              p.color = const Color(0xFF22AA22).withOpacity(0.28);
              canvas.drawRect(Rect.fromLTWH(c*cw2+1, r*ch2+1, cw2-2, 2), p);
            } else {
              p.color = const Color(0xFF0A2A0A).withOpacity(0.45);
              canvas.drawRect(Rect.fromLTWH(c*cw2+1, r*ch2+1, cw2-2, ch2-2), p);
            }
          }
        }
        p.color = Colors.black.withOpacity(0.25);
        p.style = PaintingStyle.stroke; p.strokeWidth = 0.8;
        for (int c = 0; c <= 7; c++) canvas.drawLine(Offset(c*cw2, 0), Offset(c*cw2, h), p);
        for (int r = 0; r <= 9; r++) canvas.drawLine(Offset(0, r*ch2), Offset(w, r*ch2), p);
        p.style = PaintingStyle.fill;
        // Flag
        p.color = const Color(0xFFFF2222).withOpacity(0.85);
        canvas.drawRect(Rect.fromLTWH(w*0.58, h*0.18, 18, 13), p);
        p.color = const Color(0xFF888888).withOpacity(0.75);
        canvas.drawRect(Rect.fromLTWH(w*0.58+16, h*0.18, 3, 24), p);
        // Mine
        p.isAntiAlias = true;
        p.color = Colors.black.withOpacity(0.88);
        canvas.drawCircle(Offset(w*0.36, h*0.58), 16, p);
        for (int i = 0; i < 8; i++) {
          final angle = i * pi / 4;
          canvas.drawRect(Rect.fromLTWH(
            w*0.36 + cos(angle)*16 - 2, h*0.58 + sin(angle)*16 - 2, 4, 4), p);
        }
        p.color = Colors.white.withOpacity(0.40);
        canvas.drawCircle(Offset(w*0.34, h*0.55), 4, p);
        p.isAntiAlias = false;
        break;

      // ── Dulce Racha ───────────────────────────────────────────────────────
      case 8:
        const cc = [
          Color(0xFFFF3388), Color(0xFFFF8800), Color(0xFFFFDD00),
          Color(0xFF44CC44), Color(0xFF3388FF), Color(0xFFCC44FF),
        ];
        final cs = w / 5.5;
        final gl = (w - cs*4.5) / 2, gt = h * 0.14;
        final pat = [2,0,4,1, 3,5,1,2, 0,2,5,3, 4,1,0,5, 1,3,2,4];
        p.isAntiAlias = true;
        for (int i = 0; i < pat.length; i++) {
          final r = i ~/ 4, c = i % 4;
          final cx = gl + c*cs + cs/2, cy = gt + r*(cs+3) + cs/2;
          final color = cc[pat[i]];
          p.color = color.withOpacity(0.80);
          canvas.drawCircle(Offset(cx, cy), cs*0.42, p);
          // Shine
          p.color = Colors.white.withOpacity(0.50);
          canvas.drawOval(Rect.fromLTWH(cx-cs*0.28, cy-cs*0.36, cs*0.28, cs*0.18), p);
          p.color = color.withOpacity(0.38);
          canvas.drawOval(Rect.fromLTWH(cx-cs*0.22, cy+cs*0.10, cs*0.44, cs*0.18), p);
        }
        // Sparkles
        p.color = Colors.white.withOpacity(0.72);
        p.isAntiAlias = false;
        canvas.drawRect(Rect.fromLTWH(w*0.06, h*0.17, 4, 4), p);
        canvas.drawRect(Rect.fromLTWH(w*0.88, h*0.28, 3, 3), p);
        canvas.drawRect(Rect.fromLTWH(w*0.10, h*0.72, 3, 3), p);
        canvas.drawRect(Rect.fromLTWH(w*0.84, h*0.68, 4, 4), p);
        p.color = Colors.yellow.withOpacity(0.60);
        canvas.drawRect(Rect.fromLTWH(w*0.76, h*0.77, 5, 5), p);
        canvas.drawRect(Rect.fromLTWH(w*0.74, h*0.79, 9, 1), p);
        canvas.drawRect(Rect.fromLTWH(w*0.78, h*0.75, 1, 9), p);
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

// ─── CRT scanline + vignette overlay ─────────────────────────────────────────

class _CrtOverlayPainter extends CustomPainter {
  const _CrtOverlayPainter();

  @override
  bool shouldRepaint(_CrtOverlayPainter _) => false;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..isAntiAlias = false;

    // Horizontal scanlines — one dark line every 2 px for CRT effect
    p.color = Colors.black.withOpacity(0.14);
    for (double y = 0; y < size.height; y += 2) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), p);
    }

    // Very faint vertical grid (pixel grid)
    p.color = Colors.black.withOpacity(0.04);
    for (double x = 0; x < size.width; x += 2) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 1, size.height), p);
    }

    // Radial vignette — darker edges, bright centre
    final vignette = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 0.75,
        colors: [Colors.transparent, Colors.black.withOpacity(0.42)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..isAntiAlias = true;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), vignette);

    // Subtle green phosphor tint
    p.color = const Color(0xFF00FF88).withOpacity(0.022);
    p.isAntiAlias = true;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), p);
  }
}
