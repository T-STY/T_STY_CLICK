import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'arcade_input_controller.dart';
import 'breakout_screen.dart';
import 'endless_runner_screen.dart';
import 'flappy_bird_screen.dart';
import 'high_score_service.dart';
import 'logic_grid_screen.dart';
import 'match3_screen.dart';
import 'maze_chase_screen.dart';
import 'pong_screen.dart';
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
  Color(0xFFFF8800), // INFRAMUNDO 2D   – hellfire orange
  Color(0xFF88FF44), // Rana Saltarina  – lime
  Color(0xFF00FF88), // Víbora Veloz    – green
  Color(0xFF00CCFF), // Vuelo Kamikaze  – sky cyan
  Color(0xFFFF44AA), // Corredor Infinito – hot pink
  Color(0xFF00DDFF), // Muro de Neón      – electric cyan
  Color(0xFFFFAA00), // Contragolpe       – amber
];

// ─── Card background gradients (per game — colours match the actual game) ─────

// Card art gradients — matched to alphabetical title order:
const _kCardGradients = <List<Color>>[
  [Color(0xFF040414), Color(0xFF10104A)],   // Bloques Caídos  – dark navy
  [Color(0xFF040C04), Color(0xFF0C2A0C)],   // Campo Minado    – dark forest
  [Color(0xFF1A0018), Color(0xFF5A0038)],   // Cascada Dulce   – candy pink
  [Color(0xFF02040E), Color(0xFF060E38)],   // Caza Estelar    – deep space
  [Color(0xFF000A28), Color(0xFF001E8A)],   // Comecocos       – royal blue
  [Color(0xFF160000), Color(0xFF4D0000)],   // INFRAMUNDO 2D   – blood red
  [Color(0xFF080C00), Color(0xFF254700)],   // Rana Saltarina  – forest green
  [Color(0xFF001200), Color(0xFF005A00)],   // Víbora Veloz    – neon green
  [Color(0xFF001018), Color(0xFF004D70)],   // Vuelo Kamikaze  – sky blue
  [Color(0xFF180008), Color(0xFF3A0025)],   // Corredor Infinito – dark magenta
  [Color(0xFF001418), Color(0xFF003040)],   // Muro de Neón      – dark teal
  [Color(0xFF141000), Color(0xFF382800)],   // Contragolpe       – dark amber
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
  final bool locked;
  final bool supportsDiagonal; // true → thumbstick; false → cross d-pad
  final ArcadeGameBuilder? builder;
  const ArcadeGameDef({required this.id, required this.emoji,
      required this.title, this.locked = false,
      this.supportsDiagonal = false, this.builder});
}

// Games ordered alphabetically by new Spanish title (9 playable + 3 locked teasers):
// Bloques Caídos · Campo Minado · Cascada Dulce ·
// Caza Estelar   · Comecocos    · INFRAMUNDO 2D ·
// Rana Saltarina · Víbora Veloz · Vuelo Kamikaze ·
// [3 locked future games]
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
  ArcadeGameDef(id: 'shooter',  emoji: '🚀', title: 'Caza Estelar', supportsDiagonal: true,
    builder: ({required userId, required rewardsDocRef, required currentSaldo,
        required controller, required onSaldoChanged}) =>
      SpaceShooterScreen(userId: userId, rewardsDocRef: rewardsDocRef,
        currentSaldo: currentSaldo, controller: controller, onSaldoChanged: onSaldoChanged)),
  ArcadeGameDef(id: 'maze',     emoji: '👻', title: 'Comecocos',
    builder: ({required userId, required rewardsDocRef, required currentSaldo,
        required controller, required onSaldoChanged}) =>
      MazeChasScreen(userId: userId, rewardsDocRef: rewardsDocRef,
        currentSaldo: currentSaldo, controller: controller, onSaldoChanged: onSaldoChanged)),
  ArcadeGameDef(id: 'raycaster',emoji: '🔥', title: 'INFRAMUNDO 2D', supportsDiagonal: true,
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
  ArcadeGameDef(id: 'runner', emoji: '🏃', title: 'Corredor Infinito',
    builder: ({required userId, required rewardsDocRef, required currentSaldo,
        required controller, required onSaldoChanged}) =>
      EndlessRunnerScreen(userId: userId, rewardsDocRef: rewardsDocRef,
        currentSaldo: currentSaldo, controller: controller, onSaldoChanged: onSaldoChanged)),
  ArcadeGameDef(id: 'breakout', emoji: '🧱', title: 'Muro de Neón',
    builder: ({required userId, required rewardsDocRef, required currentSaldo,
        required controller, required onSaldoChanged}) =>
      BreakoutScreen(userId: userId, rewardsDocRef: rewardsDocRef,
        currentSaldo: currentSaldo, controller: controller, onSaldoChanged: onSaldoChanged)),
  ArcadeGameDef(id: 'pong', emoji: '🏓', title: 'Contragolpe',
    builder: ({required userId, required rewardsDocRef, required currentSaldo,
        required controller, required onSaldoChanged}) =>
      PongScreen(userId: userId, rewardsDocRef: rewardsDocRef,
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
  final List<int> _highScores = List.filled(12, 0);
  int? _newRecordIndex;
  Timer? _recordTimer;

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
    final scores = await Future.wait(
      kArcadeGames.map((g) => g.locked ? Future.value(0) : HighScoreService.load(g.id)));
    if (mounted) setState(() {
      for (int i = 0; i < scores.length; i++) _highScores[i] = scores[i];
    });
  }

  @override
  void dispose() {
    _splashTimer?.cancel();
    _recordTimer?.cancel();
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
      final n = kArcadeGames.length;
      switch (btn) {
        case ArcadeButton.left:
          setState(() => _selectedIndex = (_selectedIndex - 1 + n) % n);
        case ArcadeButton.right:
          setState(() => _selectedIndex = (_selectedIndex + 1) % n);
        case ArcadeButton.up:
          setState(() => _selectedIndex = (_selectedIndex - cols + n) % n);
        case ArcadeButton.down:
          setState(() => _selectedIndex = (_selectedIndex + cols) % n);
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
        final prevScore = _highScores[_selectedIndex];
        final gameIdx = _selectedIndex;
        setState(() => _activeGame = null);
        _loadHighScores().then((_) {
          if (!mounted) return;
          if (_highScores[gameIdx] > prevScore) {
            _recordTimer?.cancel();
            setState(() => _newRecordIndex = gameIdx);
            _recordTimer = Timer(const Duration(seconds: 6), () {
              if (mounted) setState(() => _newRecordIndex = null);
            });
          }
        });
      }
    }
  }

  Future<void> _launchSelected() async {
    final game = kArcadeGames[_selectedIndex];
    if (game.locked || game.builder == null) return;
    if (_saldo < 10) return;
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
        Expanded(child: _buildGameGrid()),
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
        final cellH = constraints.maxHeight / 4;

        return GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(6),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
          ),
          itemCount: kArcadeGames.length,
          itemBuilder: (_, i) {
            final game = kArcadeGames[i];
            if (game.locked) return _buildLockedCard(game, i, i == _selectedIndex);
            return _buildNeonCard(game, i, i == _selectedIndex, cellW - 6, cellH - 6);
          },
        );
      },
    );
  }

  Widget _buildNeonCard(ArcadeGameDef def, int index, bool selected, double w, double h) {
    const phosphor = Color(0xFF00FF88);
    final neon = _kNeonColors[index];
    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = index),
      onDoubleTap: selected ? _launchSelected : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: (_newRecordIndex == index)
                ? Colors.amber
                : selected ? phosphor : neon.withOpacity(0.22),
            width: selected ? 1.5 : 1.0,
          ),
          boxShadow: selected ? [
            BoxShadow(color: phosphor.withOpacity(0.28), blurRadius: 10),
            BoxShadow(color: phosphor.withOpacity(0.10), blurRadius: 22, spreadRadius: 1),
          ] : [],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: Stack(children: [
            // Card art background
            Positioned.fill(
              child: CustomPaint(
                painter: _CartridgePainter(index: index, selected: selected),
              ),
            ),
            // Terminal dark overlay — dimmer when unselected
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(selected ? 0.36 : 0.52),
                ),
              ),
            ),
            // New record celebration banner
            if (_newRecordIndex == index)
              Positioned(
                top: 5,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(
                    '⚡ NUEVO RECORD ⚡',
                    style: TextStyle(
                      color: Colors.amber,
                      fontSize: 5.5,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      shadows: [Shadow(color: Colors.amber, blurRadius: 8)],
                    ),
                  ),
                ),
              ),
            // Content
            Positioned.fill(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(def.emoji, style: TextStyle(fontSize: selected ? 20 : 16)),
                  const SizedBox(height: 2),
                  Text(def.title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? phosphor : Colors.white54,
                      fontSize: 7,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                      letterSpacing: 0.4,
                      shadows: selected ? [Shadow(color: phosphor, blurRadius: 8)] : null,
                    ),
                  ),
                  if (_highScores[index] > 0)
                    Text('★ ${_highScores[index]}',
                      style: TextStyle(
                        color: selected ? Colors.amber : Colors.amber.withOpacity(0.45),
                        fontSize: 6.5, fontFamily: 'monospace',
                      )),
                  if (selected)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(6, 3, 6, 5),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        decoration: BoxDecoration(
                          border: Border.all(color: phosphor.withOpacity(0.55), width: 1),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: const Text('[▶ JUGAR]',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: phosphor, fontSize: 6.5, fontFamily: 'monospace',
                            shadows: [Shadow(color: phosphor, blurRadius: 5)])),
                      ),
                    )
                  else
                    const SizedBox(height: 5),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildLockedCard(ArcadeGameDef def, int index, bool selected) {
    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: const Color(0xFF050505),
          border: Border.all(
            color: selected
                ? const Color(0xFF550000)
                : Colors.white.withOpacity(0.07),
            width: 1.0,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(def.emoji,
              style: TextStyle(fontSize: 18, color: Colors.white.withOpacity(0.10))),
            const SizedBox(height: 4),
            const Text('🔒', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 3),
            Text('PRÓXIMAMENTE',
              style: TextStyle(
                color: const Color(0xFF550000).withOpacity(selected ? 0.65 : 0.35),
                fontSize: 6, fontFamily: 'monospace', letterSpacing: 0.5)),
          ],
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
    return _activeGame!.builder!(
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

  Widget _buildDPad() => _ConsoleDPad(
      controller: _ctrl,
      joystick: _activeGame?.supportsDiagonal ?? false);

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
      // ── Bloques Caídos (Tetris) ───────────────────────────────────────────
      case 0:
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

      // ── Campo Minado (Minesweeper) ────────────────────────────────────────
      case 1:
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

      // ── Cascada Dulce (Match3) ─────────────────────────────────────────────
      case 2:
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
          p.color = Colors.white.withOpacity(0.50);
          canvas.drawOval(Rect.fromLTWH(cx-cs*0.28, cy-cs*0.36, cs*0.28, cs*0.18), p);
          p.color = color.withOpacity(0.38);
          canvas.drawOval(Rect.fromLTWH(cx-cs*0.22, cy+cs*0.10, cs*0.44, cs*0.18), p);
        }
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

      // ── Caza Estelar (Space Shooter) ──────────────────────────────────────
      case 3:
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
        canvas.drawOval(Rect.fromLTWH(w*0.46, h*0.74, 8, 10), p);
        p.color = const Color(0xFFFF8800).withOpacity(0.75);
        canvas.drawOval(Rect.fromLTWH(w*0.45, h*0.86, 10, 8), p);
        p.color = Colors.white.withOpacity(0.60);
        canvas.drawOval(Rect.fromLTWH(w*0.47, h*0.87, 6, 5), p);
        p.color = const Color(0xFF88FFFF).withOpacity(0.70);
        canvas.drawRect(Rect.fromLTWH(w*0.49, h*0.42, 3, h*0.30), p);
        p.isAntiAlias = false;
        break;

      // ── Comecocos (Pac-Man) ───────────────────────────────────────────────
      case 4:
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
        p.color = const Color(0xFFFFFF88).withOpacity(0.65);
        for (int i = 0; i < 5; i++) canvas.drawRect(Rect.fromLTWH(w*0.38 + i*11, h*0.62, 5, 5), p);
        p.color = const Color(0xFFFFDD00).withOpacity(0.95);
        p.isAntiAlias = true;
        final pac = Path()
          ..moveTo(w*0.33, h*0.63)
          ..arcTo(Rect.fromCenter(center: Offset(w*0.33, h*0.63), width: 28, height: 28), 0.5, 5.4, false)
          ..close();
        canvas.drawPath(pac, p);
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

      // ── INFRAMUNDO 2D (FPS) ───────────────────────────────────────────────
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

      // ── Rana Saltarina (Frogger) ──────────────────────────────────────────
      case 6:
        // Road strips
        p.color = Colors.white.withOpacity(0.05);
        for (int i = 0; i < 3; i++) canvas.drawRect(Rect.fromLTWH(0, h*(0.06+i*0.13), w, h*0.10), p);
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
        canvas.drawOval(Rect.fromLTWH(w*0.28, h*0.59, 18, 14), p);
        canvas.drawOval(Rect.fromLTWH(w*0.54, h*0.59, 18, 14), p);
        p.color = const Color(0xFF33EE33).withOpacity(0.90);
        canvas.drawCircle(Offset(w*0.38, h*0.61), 7, p);
        canvas.drawCircle(Offset(w*0.56, h*0.61), 7, p);
        p.color = Colors.black;
        canvas.drawCircle(Offset(w*0.38, h*0.61), 3, p);
        canvas.drawCircle(Offset(w*0.56, h*0.61), 3, p);
        p.isAntiAlias = false;
        break;

      // ── Víbora Veloz (Snake) ──────────────────────────────────────────────
      case 7:
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
        segP.color = const Color(0xFF22EE22);
        canvas.drawCircle(segs[0], 10, segP..style = PaintingStyle.fill);
        p.color = Colors.black;
        canvas.drawRect(Rect.fromLTWH(segs[0].dx - 5, segs[0].dy - 3, 3, 3), p);
        canvas.drawRect(Rect.fromLTWH(segs[0].dx + 2, segs[0].dy - 3, 3, 3), p);
        p.isAntiAlias = true;
        p.color = const Color(0xFFFF2222).withOpacity(0.90);
        canvas.drawCircle(Offset(w*0.22, h*0.33), 8, p);
        p.color = Colors.white.withOpacity(0.65);
        canvas.drawCircle(Offset(w*0.20, h*0.31), 3, p);
        p.isAntiAlias = false;
        break;

      // ── Vuelo Kamikaze (Flappy) ───────────────────────────────────────────
      case 8:
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
        // Clouds
        p.color = Colors.white.withOpacity(0.20);
        canvas.drawOval(Rect.fromLTWH(w*0.35, h*0.10, 44, 18), p);
        canvas.drawOval(Rect.fromLTWH(w*0.52, h*0.08, 30, 14), p);
        canvas.drawOval(Rect.fromLTWH(w*0.54, h*0.74, 36, 16), p);
        // Bird
        p.color = const Color(0xFFFFCC00).withOpacity(0.95);
        p.isAntiAlias = true;
        canvas.drawOval(Rect.fromLTWH(w*0.38, h*0.36, 36, 28), p);
        p.color = const Color(0xFFFFAA00).withOpacity(0.85);
        canvas.drawOval(Rect.fromLTWH(w*0.40, h*0.42, 18, 10), p);
        p.color = Colors.white;
        canvas.drawCircle(Offset(w*0.52, h*0.38), 7, p);
        p.color = Colors.black;
        canvas.drawCircle(Offset(w*0.54, h*0.38), 3, p);
        p.color = const Color(0xFFFF6600);
        canvas.drawRect(Rect.fromLTWH(w*0.57, h*0.41, 9, 5), p);
        p.isAntiAlias = false;
        break;

      // ── Corredor Infinito (Endless Runner) ────────────────────────────────
      case 9:
        // City silhouette
        p.color = const Color(0xFF1A0030).withOpacity(0.70);
        canvas.drawRect(Rect.fromLTWH(w*0.00, h*0.28, w*0.18, h*0.40), p);
        canvas.drawRect(Rect.fromLTWH(w*0.22, h*0.18, w*0.14, h*0.50), p);
        canvas.drawRect(Rect.fromLTWH(w*0.40, h*0.32, w*0.10, h*0.36), p);
        canvas.drawRect(Rect.fromLTWH(w*0.55, h*0.22, w*0.16, h*0.46), p);
        canvas.drawRect(Rect.fromLTWH(w*0.75, h*0.30, w*0.25, h*0.38), p);
        // Ground neon line
        p.color = const Color(0xFF44FF44).withOpacity(0.80);
        canvas.drawRect(Rect.fromLTWH(0, h*0.68, w, 2.5), p);
        p.color = const Color(0xFF44FF44).withOpacity(0.18);
        canvas.drawRect(Rect.fromLTWH(0, h*0.68, w, h*0.32), p);
        // Runner figure
        p.color = const Color(0xFFFFAA00).withOpacity(0.90);
        p.isAntiAlias = true;
        canvas.drawOval(Rect.fromLTWH(w*0.18, h*0.42, 14, 14), p); // head
        canvas.drawRect(Rect.fromLTWH(w*0.20, h*0.52, 10, 16), p); // torso
        p.color = const Color(0xFFFFCC44).withOpacity(0.75);
        canvas.drawRect(Rect.fromLTWH(w*0.20, h*0.66, 7, 3), p); // leg1
        canvas.drawRect(Rect.fromLTWH(w*0.26, h*0.64, 7, 3), p); // leg2
        // Obstacle ahead
        p.color = const Color(0xFFFF4422).withOpacity(0.80);
        canvas.drawRect(Rect.fromLTWH(w*0.58, h*0.57, 14, 14), p);
        p.color = const Color(0xFFFF4422).withOpacity(0.50);
        canvas.drawRect(Rect.fromLTWH(w*0.56, h*0.55, 18, 3), p);
        p.isAntiAlias = false;
        break;

      // ── Muro de Neón (Breakout) ───────────────────────────────────────────
      case 10:
        // Brick grid (5 rows × 4 visible cols)
        final brickColors10 = [
          const Color(0xFFFF2222), const Color(0xFFFF8800),
          const Color(0xFFFFDD00), const Color(0xFF44FF44), const Color(0xFF00DDFF),
        ];
        for (int row = 0; row < 5; row++) {
          for (int col = 0; col < 4; col++) {
            final bx = w * (0.05 + col * 0.24);
            final by = h * (0.05 + row * 0.13);
            p.color = brickColors10[row].withOpacity(0.70);
            canvas.drawRect(Rect.fromLTWH(bx, by, w*0.22, h*0.11), p);
            p.color = brickColors10[row].withOpacity(0.25);
            p.style = PaintingStyle.stroke;
            p.strokeWidth = 0.8;
            canvas.drawRect(Rect.fromLTWH(bx, by, w*0.22, h*0.11), p);
            p.style = PaintingStyle.fill;
          }
        }
        // Paddle
        p.color = const Color(0xFF00DDFF).withOpacity(0.85);
        canvas.drawRect(Rect.fromLTWH(w*0.24, h*0.83, w*0.52, h*0.05), p);
        // Ball
        p.isAntiAlias = true;
        p.color = Colors.white.withOpacity(0.90);
        canvas.drawCircle(Offset(w*0.52, h*0.72), 6, p);
        p.isAntiAlias = false;
        break;

      // ── Contragolpe (Pong) ────────────────────────────────────────────────
      case 11:
        // Centre dashes
        p.color = Colors.white.withOpacity(0.15);
        for (int i = 0; i < 8; i++) {
          if (i.isEven) canvas.drawRect(Rect.fromLTWH(w*0.49, h*(0.05 + i*0.12), 3, h*0.08), p);
        }
        // Player paddle (left)
        p.color = const Color(0xFF00DDFF).withOpacity(0.85);
        canvas.drawRect(Rect.fromLTWH(w*0.08, h*0.32, w*0.06, h*0.36), p);
        // AI paddle (right)
        p.color = Colors.redAccent.withOpacity(0.75);
        canvas.drawRect(Rect.fromLTWH(w*0.86, h*0.24, w*0.06, h*0.36), p);
        // Ball
        p.isAntiAlias = true;
        p.color = Colors.white.withOpacity(0.90);
        canvas.drawCircle(Offset(w*0.55, h*0.46), 7, p);
        p.isAntiAlias = false;
        break;
    }
  }
}

// ─── D-pad widget ─────────────────────────────────────────────────────────────
//
// joystick=false → classic cross/plus pad (cardinal-only, for grid games)
// joystick=true  → faceted thumbstick (8-dir, for shooter / raycaster)

class _ConsoleDPad extends StatefulWidget {
  final ArcadeInputController controller;
  final bool joystick;
  const _ConsoleDPad({required this.controller, this.joystick = false});
  @override State<_ConsoleDPad> createState() => _ConsoleDPadState();
}

class _ConsoleDPadState extends State<_ConsoleDPad> {
  Set<ArcadeButton> _active = const {};
  Offset _nudge = Offset.zero; // thumbstick hub offset

  static const _dead = 16.0;

  List<ArcadeButton> _buttonsFor(Offset local) {
    const cx = 72.0, cy = 72.0;
    final dx = local.dx - cx, dy = local.dy - cy;
    if (dx * dx + dy * dy < _dead * _dead) return const [];
    if (widget.joystick) {
      // 8-direction for thumbstick
      final angle = (atan2(dy, dx) * 180 / pi + 450) % 360;
      if (angle < 22.5 || angle >= 337.5) return [ArcadeButton.up];
      if (angle < 67.5)  return [ArcadeButton.up, ArcadeButton.right];
      if (angle < 112.5) return [ArcadeButton.right];
      if (angle < 157.5) return [ArcadeButton.down, ArcadeButton.right];
      if (angle < 202.5) return [ArcadeButton.down];
      if (angle < 247.5) return [ArcadeButton.down, ArcadeButton.left];
      if (angle < 292.5) return [ArcadeButton.left];
      return [ArcadeButton.up, ArcadeButton.left];
    } else {
      // Cardinal-only: snap to dominant axis
      if (dx.abs() >= dy.abs()) {
        return [dx > 0 ? ArcadeButton.right : ArcadeButton.left];
      } else {
        return [dy > 0 ? ArcadeButton.down : ArcadeButton.up];
      }
    }
  }

  Offset _nudgeFor(Offset local) {
    const cx = 72.0, cy = 72.0;
    const maxNudge = 20.0;
    final dx = local.dx - cx, dy = local.dy - cy;
    final dist = sqrt(dx * dx + dy * dy);
    if (dist < _dead) return Offset.zero;
    final scale = ((dist.clamp(_dead, 60.0) - _dead) / (60.0 - _dead)) * maxNudge;
    return Offset(dx / dist * scale, dy / dist * scale);
  }

  void _applyButtons(List<ArcadeButton> next, Offset local) {
    final newSet = next.toSet();
    for (final b in _active.difference(newSet)) widget.controller.release(b);
    for (final b in newSet.difference(_active)) {
      widget.controller.press(b);
      HapticFeedback.lightImpact();
    }
    setState(() {
      _active = newSet;
      if (widget.joystick) _nudge = _nudgeFor(local);
    });
  }

  void _release() {
    for (final b in _active) widget.controller.release(b);
    setState(() { _active = const {}; _nudge = Offset.zero; });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown:   (e) => _applyButtons(_buttonsFor(e.localPosition), e.localPosition),
      onPointerMove:   (e) => _applyButtons(_buttonsFor(e.localPosition), e.localPosition),
      onPointerUp:     (_) => _release(),
      onPointerCancel: (_) => _release(),
      child: CustomPaint(
        size: const Size(144, 144),
        painter: widget.joystick
            ? _ThumbstickPainter(active: _active, nudge: _nudge)
            : _CrossDPadPainter(active: _active),
      ),
    );
  }
}

// ─── Cross D-pad painter (cardinal-only games) ────────────────────────────────

class _CrossDPadPainter extends CustomPainter {
  final Set<ArcadeButton> active;
  const _CrossDPadPainter({required this.active});

  @override
  bool shouldRepaint(_CrossDPadPainter o) =>
      o.active.length != active.length || !o.active.containsAll(active);

  @override
  void paint(Canvas canvas, Size size) {
    const cx = 72.0, cy = 72.0;
    const arm = 48.0, half = arm / 2;
    const r = 9.0; // outer-tip corner radius

    bool lit(ArcadeButton b) => active.contains(b);
    const base    = Color(0xFF1C1C1C);
    const pressed = Color(0xFF3E3E3E);
    final p = Paint()..isAntiAlias = true;

    // ── Arms ──────────────────────────────────────────────────────────────────
    // Up
    p.color = lit(ArcadeButton.up) ? pressed : base;
    canvas.drawRRect(RRect.fromRectAndCorners(
        Rect.fromLTWH(cx - half, 0, arm, cy - half),
        topLeft: Radius.circular(r), topRight: Radius.circular(r)), p);
    // Down
    p.color = lit(ArcadeButton.down) ? pressed : base;
    canvas.drawRRect(RRect.fromRectAndCorners(
        Rect.fromLTWH(cx - half, cy + half, arm, cy - half),
        bottomLeft: Radius.circular(r), bottomRight: Radius.circular(r)), p);
    // Left
    p.color = lit(ArcadeButton.left) ? pressed : base;
    canvas.drawRRect(RRect.fromRectAndCorners(
        Rect.fromLTWH(0, cy - half, cx - half, arm),
        topLeft: Radius.circular(r), bottomLeft: Radius.circular(r)), p);
    // Right
    p.color = lit(ArcadeButton.right) ? pressed : base;
    canvas.drawRRect(RRect.fromRectAndCorners(
        Rect.fromLTWH(cx + half, cy - half, cx - half, arm),
        topRight: Radius.circular(r), bottomRight: Radius.circular(r)), p);
    // Centre fill (no rounding, fills the gap between arms)
    p.color = base;
    canvas.drawRect(Rect.fromLTWH(cx - half, cy - half, arm, arm), p);

    // ── Outline strokes on cross bars ─────────────────────────────────────────
    p..color = Colors.white.withOpacity(0.07)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRRect(RRect.fromRectAndCorners(          // vertical bar
        Rect.fromLTWH(cx - half, 0, arm, size.height),
        topLeft: Radius.circular(r), topRight: Radius.circular(r),
        bottomLeft: Radius.circular(r), bottomRight: Radius.circular(r)), p);
    canvas.drawRRect(RRect.fromRectAndCorners(          // horizontal bar
        Rect.fromLTWH(0, cy - half, size.width, arm),
        topLeft: Radius.circular(r), topRight: Radius.circular(r),
        bottomLeft: Radius.circular(r), bottomRight: Radius.circular(r)), p);
    p.style = PaintingStyle.fill;

    // ── Bevel highlights (top/left edge = lighter; bottom/right = shadow) ─────
    // Up-arm top highlight
    p.color = Colors.white.withOpacity(lit(ArcadeButton.up) ? 0.14 : 0.07);
    canvas.drawRRect(RRect.fromRectAndCorners(
        Rect.fromLTWH(cx - half + 1, 1, arm - 2, 2),
        topLeft: Radius.circular(r), topRight: Radius.circular(r)), p);
    // Down-arm bottom shadow
    p.color = Colors.black.withOpacity(0.35);
    canvas.drawRRect(RRect.fromRectAndCorners(
        Rect.fromLTWH(cx - half + 1, size.height - 3, arm - 2, 2),
        bottomLeft: Radius.circular(r), bottomRight: Radius.circular(r)), p);
    // Left-arm left highlight
    p.color = Colors.white.withOpacity(lit(ArcadeButton.left) ? 0.14 : 0.07);
    canvas.drawRRect(RRect.fromRectAndCorners(
        Rect.fromLTWH(1, cy - half + 1, 2, arm - 2),
        topLeft: Radius.circular(r), bottomLeft: Radius.circular(r)), p);
    // Right-arm right shadow
    p.color = Colors.black.withOpacity(0.35);
    canvas.drawRRect(RRect.fromRectAndCorners(
        Rect.fromLTWH(size.width - 3, cy - half + 1, 2, arm - 2),
        topRight: Radius.circular(r), bottomRight: Radius.circular(r)), p);

    // ── Arrow triangles ───────────────────────────────────────────────────────
    final ap = Paint()..isAntiAlias = true;
    // Up
    ap.color = Colors.white.withOpacity(lit(ArcadeButton.up)    ? 0.95 : 0.40);
    canvas.drawPath(Path()..moveTo(cx, 14)..lineTo(cx - 9, 33)..lineTo(cx + 9, 33)..close(), ap);
    // Down
    ap.color = Colors.white.withOpacity(lit(ArcadeButton.down)  ? 0.95 : 0.40);
    canvas.drawPath(Path()..moveTo(cx, 130)..lineTo(cx - 9, 111)..lineTo(cx + 9, 111)..close(), ap);
    // Left
    ap.color = Colors.white.withOpacity(lit(ArcadeButton.left)  ? 0.95 : 0.40);
    canvas.drawPath(Path()..moveTo(14, cy)..lineTo(33, cy - 9)..lineTo(33, cy + 9)..close(), ap);
    // Right
    ap.color = Colors.white.withOpacity(lit(ArcadeButton.right) ? 0.95 : 0.40);
    canvas.drawPath(Path()..moveTo(130, cy)..lineTo(111, cy - 9)..lineTo(111, cy + 9)..close(), ap);
  }
}

// ─── Thumbstick painter (diagonal/analog games) ───────────────────────────────

class _ThumbstickPainter extends CustomPainter {
  final Set<ArcadeButton> active;
  final Offset nudge; // hub offset when pressed
  const _ThumbstickPainter({required this.active, required this.nudge});

  @override
  bool shouldRepaint(_ThumbstickPainter o) =>
      o.active != active || o.nudge != nudge;

  @override
  void paint(Canvas canvas, Size size) {
    const cx = 72.0, cy = 72.0;
    const R    = 66.0;  // disc radius
    const hubR = 14.0;  // centre hub radius
    const N    = 20;    // facet count

    final p = Paint()..isAntiAlias = true;

    // Drop shadow beneath disc
    p.color = Colors.black.withOpacity(0.50);
    canvas.drawCircle(const Offset(cx + 2, cy + 4), R, p);

    // Clip everything to the disc boundary
    canvas.save();
    canvas.clipPath(Path()
        ..addOval(Rect.fromCircle(center: const Offset(cx, cy), radius: R)));

    // Compute active direction vector (for facet glow)
    double ax = 0, ay = 0;
    if (active.contains(ArcadeButton.right)) ax += 1;
    if (active.contains(ArcadeButton.left))  ax -= 1;
    if (active.contains(ArcadeButton.down))  ay += 1;
    if (active.contains(ArcadeButton.up))    ay -= 1;
    final hasActive = ax != 0 || ay != 0;
    final targetAngle = hasActive ? atan2(ay, ax) : 0.0;

    // Facets: N triangular wedges, coloured by a top-left diffuse light
    for (int i = 0; i < N; i++) {
      final startA = -pi / 2 + i       * 2 * pi / N;
      final endA   = -pi / 2 + (i + 1) * 2 * pi / N;
      final midA   = (startA + endA) / 2;

      // Diffuse: light from upper-left (angle ~225°)
      const lx = -0.5774, ly = -0.8165;
      final nx = cos(midA), ny = sin(midA);
      final diffuse = ((nx * lx + ny * ly).clamp(-1.0, 1.0) + 1) / 2; // 0..1

      // Base brightness from diffuse
      int v = (0x10 + diffuse * 0x28).round();

      // Glow in active direction
      if (hasActive) {
        var diff = (midA - targetAngle).abs() % (2 * pi);
        if (diff > pi) diff = 2 * pi - diff;
        if (diff < pi * 0.65) {
          v = (v + ((1 - diff / (pi * 0.65)) * 0x2E).round()).clamp(0, 0xFF);
        }
      }

      p.color = Color(0xFF000000 | (v << 16) | (v << 8) | v);
      canvas.drawPath(
        Path()
          ..moveTo(cx, cy)
          ..lineTo(cx + R * cos(startA), cy + R * sin(startA))
          ..arcTo(Rect.fromCircle(center: const Offset(cx, cy), radius: R),
              startA, 2 * pi / N, false)
          ..close(),
        p,
      );
    }

    // Thin divider lines between facets
    p..color = Colors.black.withOpacity(0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.55;
    for (int i = 0; i < N; i++) {
      final a = -pi / 2 + i * 2 * pi / N;
      canvas.drawLine(const Offset(cx, cy),
          Offset(cx + R * cos(a), cy + R * sin(a)), p);
    }
    p.style = PaintingStyle.fill;

    // Specular arc (upper-left rim highlight)
    p..color = Colors.white.withOpacity(0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawArc(
        Rect.fromCircle(center: const Offset(cx, cy), radius: R - 2.5),
        -pi * 1.25, pi * 0.65, false, p);
    p.style = PaintingStyle.fill;

    canvas.restore();

    // Outer border ring
    p..color = Colors.black.withOpacity(0.80)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(const Offset(cx, cy), R, p);
    p.style = PaintingStyle.fill;

    // Hub (moves with nudge to indicate push direction)
    final hx = cx + nudge.dx, hy = cy + nudge.dy;

    // Hub shadow
    p.color = Colors.black.withOpacity(0.55);
    canvas.drawCircle(Offset(hx + 1, hy + 2), hubR, p);
    // Hub base
    p.color = const Color(0xFF0E0E0E);
    canvas.drawCircle(Offset(hx, hy), hubR, p);
    // Hub inner raised disc
    p.color = const Color(0xFF252525);
    canvas.drawCircle(Offset(hx, hy), hubR - 3, p);
    // Hub specular highlight
    p.color = Colors.white.withOpacity(0.22);
    canvas.drawCircle(Offset(hx - 4, hy - 4), 4, p);
    // Hub border
    p..color = Colors.black.withOpacity(0.65)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawCircle(Offset(hx, hy), hubR, p);
    p.style = PaintingStyle.fill;
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
