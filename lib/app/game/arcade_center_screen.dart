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

// ─── Settings enums ──────────────────────────────────────────────────────────

enum ConsoleSkin    { gameBoy, psp, gba }
enum ShellColor     { gray, midnight, indigo, crimson, navy, forest, rose }
enum ColorTheme     { greenPhosphor, amberRetro, cyanCrypto, infernalRed }
enum ButtonLayout   { snes, xbox, ps4 }
enum ButtonDisplay  { solid, blackout, clear }
enum AppLanguage   { spanish, english }

// Per-position button definition (label + color + underlying ArcadeButton)
class _BtnDef {
  final String label;
  final Color  color;
  final ArcadeButton btn;
  final double labelSize;
  const _BtnDef(this.label, this.color, this.btn, {this.labelSize = 15});
}

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
  Color(0xFFFF44AA), // Dino Escape       – hot pink
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
  [Color(0xFF180008), Color(0xFF3A0025)],   // Dino Escape       – dark magenta
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

// Games ordered alphabetically by English title (9 playable + 3 locked teasers):
// Block Drop  · Candy Swap  · Crypt Doom ·
// Dino Dash   · Frog Dash   · Ghost Maze ·
// Minefield   · Neon Break  · Neon Snake ·
// Star Blaster · Volt Pong  · Wing Rush
final List<ArcadeGameDef> kArcadeGames = [
  ArcadeGameDef(id: 'tetris',   emoji: '🟦', title: 'Block Drop',
    builder: ({required userId, required rewardsDocRef, required currentSaldo,
        required controller, required onSaldoChanged}) =>
      TetrisScreen(userId: userId, rewardsDocRef: rewardsDocRef,
        currentSaldo: currentSaldo, controller: controller, onSaldoChanged: onSaldoChanged)),
  ArcadeGameDef(id: 'logic',    emoji: '💣', title: 'Minefield',
    builder: ({required userId, required rewardsDocRef, required currentSaldo,
        required controller, required onSaldoChanged}) =>
      LogicGridScreen(userId: userId, rewardsDocRef: rewardsDocRef,
        currentSaldo: currentSaldo, controller: controller, onSaldoChanged: onSaldoChanged)),
  ArcadeGameDef(id: 'match3',   emoji: '🍬', title: 'Candy Swap',
    builder: ({required userId, required rewardsDocRef, required currentSaldo,
        required controller, required onSaldoChanged}) =>
      Match3Screen(userId: userId, rewardsDocRef: rewardsDocRef,
        currentSaldo: currentSaldo, controller: controller, onSaldoChanged: onSaldoChanged)),
  ArcadeGameDef(id: 'shooter',  emoji: '🚀', title: 'Star Blaster', supportsDiagonal: true,
    builder: ({required userId, required rewardsDocRef, required currentSaldo,
        required controller, required onSaldoChanged}) =>
      SpaceShooterScreen(userId: userId, rewardsDocRef: rewardsDocRef,
        currentSaldo: currentSaldo, controller: controller, onSaldoChanged: onSaldoChanged)),
  ArcadeGameDef(id: 'maze',     emoji: '👻', title: 'Ghost Maze',
    builder: ({required userId, required rewardsDocRef, required currentSaldo,
        required controller, required onSaldoChanged}) =>
      MazeChasScreen(userId: userId, rewardsDocRef: rewardsDocRef,
        currentSaldo: currentSaldo, controller: controller, onSaldoChanged: onSaldoChanged)),
  ArcadeGameDef(id: 'raycaster',emoji: '🔥', title: 'Crypt Doom', supportsDiagonal: true,
    builder: ({required userId, required rewardsDocRef, required currentSaldo,
        required controller, required onSaldoChanged}) =>
      RaycasterScreen(userId: userId, rewardsDocRef: rewardsDocRef,
        currentSaldo: currentSaldo, controller: controller, onSaldoChanged: onSaldoChanged)),
  ArcadeGameDef(id: 'hopper',   emoji: '🐸', title: 'Frog Dash',
    builder: ({required userId, required rewardsDocRef, required currentSaldo,
        required controller, required onSaldoChanged}) =>
      TrafficHopperScreen(userId: userId, rewardsDocRef: rewardsDocRef,
        currentSaldo: currentSaldo, controller: controller, onSaldoChanged: onSaldoChanged)),
  ArcadeGameDef(id: 'snake',    emoji: '🐍', title: 'Neon Snake',
    builder: ({required userId, required rewardsDocRef, required currentSaldo,
        required controller, required onSaldoChanged}) =>
      SnakeGameScreen(userId: userId, rewardsDocRef: rewardsDocRef,
        currentSaldo: currentSaldo, controller: controller, onSaldoChanged: onSaldoChanged)),
  ArcadeGameDef(id: 'flappy',   emoji: '🕊️', title: 'Wing Rush',
    builder: ({required userId, required rewardsDocRef, required currentSaldo,
        required controller, required onSaldoChanged}) =>
      FlappyBirdScreen(userId: userId, rewardsDocRef: rewardsDocRef,
        currentSaldo: currentSaldo, controller: controller, onSaldoChanged: onSaldoChanged)),
  ArcadeGameDef(id: 'runner', emoji: '🦕', title: 'Dino Dash',
    builder: ({required userId, required rewardsDocRef, required currentSaldo,
        required controller, required onSaldoChanged}) =>
      EndlessRunnerScreen(userId: userId, rewardsDocRef: rewardsDocRef,
        currentSaldo: currentSaldo, controller: controller, onSaldoChanged: onSaldoChanged)),
  ArcadeGameDef(id: 'breakout', emoji: '🧱', title: 'Neon Break',
    builder: ({required userId, required rewardsDocRef, required currentSaldo,
        required controller, required onSaldoChanged}) =>
      BreakoutScreen(userId: userId, rewardsDocRef: rewardsDocRef,
        currentSaldo: currentSaldo, controller: controller, onSaldoChanged: onSaldoChanged)),
  ArcadeGameDef(id: 'pong', emoji: '🏓', title: 'Volt Pong',
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

class _ArcadeCenterScreenState extends State<ArcadeCenterScreen>
    with TickerProviderStateMixin {
  late final ArcadeInputController _ctrl;
  late double _saldo;
  int _selectedIndex = 0;
  int _hubCategory = 1;   // 0=reciente, 1=biblioteca, 2=perfil, 3=config
  final ScrollController _carouselCtrl = ScrollController();
  final List<GlobalKey> _settingKeys = List.generate(22, (_) => GlobalKey());
  int? _lastPlayedIndex;
  ArcadeGameDef? _activeGame;
  final List<int> _highScores = List.filled(12, 0);
  int? _newRecordIndex;
  Timer? _recordTimer;

  // ── Console customisation ──────────────────────────────────────────────────
  ConsoleSkin  _skin          = ConsoleSkin.gameBoy;
  ShellColor   _shellColor    = ShellColor.gray;
  ColorTheme   _colorTheme    = ColorTheme.greenPhosphor;
  ButtonLayout   _buttonLayout   = ButtonLayout.snes;
  ButtonDisplay  _buttonDisplay  = ButtonDisplay.solid;
  int            _settingsCursor = 0;
  AppLanguage    _language       = AppLanguage.spanish;
  bool _headerFocused = false; // false = d-pad starts on content (game list)

  // Theme accent colour (used everywhere terminal-green currently is)
  Color get _accent {
    switch (_colorTheme) {
      case ColorTheme.greenPhosphor: return const Color(0xFF00FF88);
      case ColorTheme.amberRetro:    return const Color(0xFFFFB347);
      case ColorTheme.cyanCrypto:    return const Color(0xFF00DDFF);
      case ColorTheme.infernalRed:   return const Color(0xFFFF4455);
    }
  }

  String _t(String es, String en) =>
      _language == AppLanguage.spanish ? es : en;

  // SELECT/START button colour — darker tint of the shell
  Color get _metaColor {
    switch (_shellColor) {
      case ShellColor.gray:     return const Color(0xFF909090);
      case ShellColor.midnight: return const Color(0xFF383838);
      case ShellColor.indigo:   return const Color(0xFF3A2A5A);
      case ShellColor.crimson:  return const Color(0xFF5A1212);
      case ShellColor.navy:     return const Color(0xFF1A2438);
      case ShellColor.forest:   return const Color(0xFF1A2E1A);
      case ShellColor.rose:     return const Color(0xFF4A1E2E);
    }
  }

  // Button cluster layout — [top, left, right, bottom]
  List<_BtnDef> get _btnDefs {
    switch (_buttonLayout) {
      case ButtonLayout.snes:
        return const [
          _BtnDef('X', Color(0xFF1E88E5), ArcadeButton.x),
          _BtnDef('Y', Color(0xFF43A047), ArcadeButton.y),
          _BtnDef('A', Color(0xFFE53935), ArcadeButton.a),
          _BtnDef('B', Color(0xFFFFB300), ArcadeButton.b),
        ];
      case ButtonLayout.xbox:
        return const [
          _BtnDef('Y', Color(0xFFFFCC00), ArcadeButton.y),
          _BtnDef('X', Color(0xFF107EC4), ArcadeButton.x),
          _BtnDef('B', Color(0xFFD32F2F), ArcadeButton.b),
          _BtnDef('A', Color(0xFF107C10), ArcadeButton.a),
        ];
      case ButtonLayout.ps4:
        return const [
          _BtnDef('△', Color(0xFF00C896), ArcadeButton.x, labelSize: 20),
          _BtnDef('☐', Color(0xFFCC66AA), ArcadeButton.y, labelSize: 19),
          _BtnDef('○', Color(0xFFDD2222), ArcadeButton.a, labelSize: 21),
          _BtnDef('✕', Color(0xFF4488CC), ArcadeButton.b, labelSize: 19),
        ];
    }
  }

  // Shell body gradient — top/bottom/border colors for the console body
  ({Color top, Color bot, Color bdr}) get _shellGradient {
    switch (_shellColor) {
      case ShellColor.gray:     return (top: const Color(0xFFD4D4D4), bot: const Color(0xFFAAAAAA), bdr: const Color(0xFF888888));
      case ShellColor.midnight: return (top: const Color(0xFF252525), bot: const Color(0xFF151515), bdr: const Color(0xFF3A3A3A));
      case ShellColor.indigo:   return (top: const Color(0xFF4A3A6A), bot: const Color(0xFF2A1A4A), bdr: const Color(0xFF6A5A8A));
      case ShellColor.crimson:  return (top: const Color(0xFF6A1A1A), bot: const Color(0xFF4A0A0A), bdr: const Color(0xFF8A3A3A));
      case ShellColor.navy:     return (top: const Color(0xFF1A2A4A), bot: const Color(0xFF0A1A2A), bdr: const Color(0xFF3A4A6A));
      case ShellColor.forest:   return (top: const Color(0xFF1A3A1A), bot: const Color(0xFF0A2A0A), bdr: const Color(0xFF3A5A3A));
      case ShellColor.rose:     return (top: const Color(0xFF5A2A3A), bot: const Color(0xFF3A1A2A), bdr: const Color(0xFF7A4A5A));
    }
  }

  void _applyOrientation() {
    if (_skin == ConsoleSkin.psp || _skin == ConsoleSkin.gba) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
  }

  // ── Power-off ──────────────────────────────────────────────────────────────
  bool _poweringOff = false;
  int _powerOffStep = 0;
  Timer? _powerOffTimer;

  // ── CRT TV-off animation (plays before Navigator.pop) ─────────────────────
  bool _crtOffAnim = false;
  late final AnimationController _crtOffCtrl;
  late final Animation<double> _crtSquish; // scaleY 1→0
  late final Animation<double> _crtLine;   // white-line brightness 0→1→0
  late final Animation<double> _crtFade;   // black overlay 0→1

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
    // CRT TV-off animation controller
    _crtOffCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1020));
    _crtSquish = Tween<double>(begin: 1.0, end: 0.0).animate(
        CurvedAnimation(parent: _crtOffCtrl,
            curve: const Interval(0.0, 0.58, curve: Curves.easeIn)));
    _crtLine = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 1),
    ]).animate(CurvedAnimation(parent: _crtOffCtrl,
        curve: const Interval(0.44, 0.80)));
    _crtFade = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _crtOffCtrl,
            curve: const Interval(0.65, 1.0, curve: Curves.easeIn)));
    _crtOffCtrl.addStatusListener((s) {
      if (s == AnimationStatus.completed && _crtOffAnim && mounted) {
        Navigator.pop(context);
      }
    });
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _ctrl = ArcadeInputController();
    _saldo = widget.currentSaldo;
    _ctrl.addListener(_handleShellEvent);
    _loadHighScores();
    _fetchUserName();
    _loadPreferences(); // calls _applyOrientation after loading
    // Advance boot lines every 420 ms
    _splashTimer = Timer.periodic(const Duration(milliseconds: 420), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        if (_splashLine < _kBootLines.length + 1) {
          _splashLine++;
        } else {
          t.cancel();
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
    _powerOffTimer?.cancel();
    _crtOffCtrl.dispose();
    _ctrl.removeListener(_handleShellEvent);
    _ctrl.dispose();
    _carouselCtrl.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: [SystemUiOverlay.top]);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  void _triggerPowerOff() {
    if (_poweringOff) return;
    setState(() { _poweringOff = true; _powerOffStep = 0; });
    _powerOffTimer = Timer.periodic(const Duration(milliseconds: 500), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _powerOffStep++);
      if (_powerOffStep >= 6) {
        t.cancel();
        // Short pause, then CRT TV-off animation; Navigator.pop fires on complete
        Future.delayed(const Duration(milliseconds: 220), () {
          if (mounted) {
            setState(() => _crtOffAnim = true);
            _crtOffCtrl.forward();
          }
        });
      }
    });
  }

  void _scrollCarouselToSelected() {
    if (!_carouselCtrl.hasClients) return;
    const itemW = 56.0; // approx carousel item width + margin
    final offset = (_selectedIndex * itemW - 40.0).clamp(0.0, double.infinity);
    _carouselCtrl.animateTo(offset,
        duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  void _ensureSettingVisible(int idx) {
    if (idx < 0 || idx >= _settingKeys.length) return;
    final ctx = _settingKeys[idx].currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          alignment: 0.5);
    }
  }

  Future<void> _loadPreferences() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users').doc(widget.userId)
          .collection('preferences').doc('arcade').get();
      if (!mounted || !doc.exists) { _applyOrientation(); return; }
      final d = doc.data()!;
      setState(() {
        _skin = ConsoleSkin.values.firstWhere(
            (e) => e.name == d['skin'], orElse: () => ConsoleSkin.gameBoy);
        _shellColor = ShellColor.values.firstWhere(
            (e) => e.name == d['shellColor'], orElse: () => ShellColor.gray);
        _colorTheme = ColorTheme.values.firstWhere(
            (e) => e.name == d['colorTheme'], orElse: () => ColorTheme.greenPhosphor);
        _buttonLayout = ButtonLayout.values.firstWhere(
            (e) => e.name == d['buttonLayout'], orElse: () => ButtonLayout.snes);
        // Support old bool field as migration path
        final oldBlackout = d['buttonBlackout'] as bool? ?? false;
        _buttonDisplay = ButtonDisplay.values.firstWhere(
            (e) => e.name == d['buttonDisplay'],
            orElse: () => oldBlackout ? ButtonDisplay.blackout : ButtonDisplay.solid);
        _language = AppLanguage.values.firstWhere(
            (e) => e.name == d['language'], orElse: () => AppLanguage.spanish);
      });
      _applyOrientation();
    } catch (_) { _applyOrientation(); }
  }

  Future<void> _savePreferences() async {
    try {
      await FirebaseFirestore.instance
          .collection('users').doc(widget.userId)
          .collection('preferences').doc('arcade')
          .set({
        'skin': _skin.name,
        'shellColor': _shellColor.name,
        'colorTheme': _colorTheme.name,
        'buttonLayout': _buttonLayout.name,
        'buttonDisplay': _buttonDisplay.name,
        'language': _language.name,
      });
    } catch (_) {}
  }

  void _activateSetting(int idx) {
    setState(() {
      switch (idx) {
        // SKIN (0-2) — PSP/GBA locked as teaser
        case 0: _skin = ConsoleSkin.gameBoy; _applyOrientation();
        case 1: break; // PSP — próximamente
        case 2: break; // GBA — próximamente
        // SHELL COLOR (3-9)
        case 3: _shellColor = ShellColor.gray;
        case 4: _shellColor = ShellColor.midnight;
        case 5: _shellColor = ShellColor.indigo;
        case 6: _shellColor = ShellColor.crimson;
        case 7: _shellColor = ShellColor.navy;
        case 8: _shellColor = ShellColor.forest;
        case 9: _shellColor = ShellColor.rose;
        // ACCENT COLOR THEME (10-13)
        case 10: _colorTheme = ColorTheme.greenPhosphor;
        case 11: _colorTheme = ColorTheme.amberRetro;
        case 12: _colorTheme = ColorTheme.cyanCrypto;
        case 13: _colorTheme = ColorTheme.infernalRed;
        // BUTTON LAYOUT (14-16)
        case 14: _buttonLayout = ButtonLayout.snes;
        case 15: _buttonLayout = ButtonLayout.xbox;
        case 16: _buttonLayout = ButtonLayout.ps4;
        // BUTTON DISPLAY (17-19)
        case 17: _buttonDisplay = ButtonDisplay.solid;
        case 18: _buttonDisplay = ButtonDisplay.blackout;
        case 19: _buttonDisplay = ButtonDisplay.clear;
        // LANGUAGE (20-21)
        case 20: _language = AppLanguage.spanish;
        case 21: _language = AppLanguage.english;
      }
    });
    _savePreferences();
  }

  bool _isCursorOn(int idx) => _settingsCursor == idx;
  // Rows that are locked/coming-soon — skip in D-pad navigation
  bool _isSettingLocked(int idx) => idx == 1 || idx == 2;
  bool _isSettingActive(int idx) {
    switch (idx) {
      case 0: return _skin == ConsoleSkin.gameBoy;
      case 1: return _skin == ConsoleSkin.psp;
      case 2: return _skin == ConsoleSkin.gba;
      case 3: return _shellColor == ShellColor.gray;
      case 4: return _shellColor == ShellColor.midnight;
      case 5: return _shellColor == ShellColor.indigo;
      case 6: return _shellColor == ShellColor.crimson;
      case 7: return _shellColor == ShellColor.navy;
      case 8: return _shellColor == ShellColor.forest;
      case 9: return _shellColor == ShellColor.rose;
      case 10: return _colorTheme == ColorTheme.greenPhosphor;
      case 11: return _colorTheme == ColorTheme.amberRetro;
      case 12: return _colorTheme == ColorTheme.cyanCrypto;
      case 13: return _colorTheme == ColorTheme.infernalRed;
      case 14: return _buttonLayout == ButtonLayout.snes;
      case 15: return _buttonLayout == ButtonLayout.xbox;
      case 16: return _buttonLayout == ButtonLayout.ps4;
      case 17: return _buttonDisplay == ButtonDisplay.solid;
      case 18: return _buttonDisplay == ButtonDisplay.blackout;
      case 19: return _buttonDisplay == ButtonDisplay.clear;
      case 20: return _language == AppLanguage.spanish;
      case 21: return _language == AppLanguage.english;
      default: return false;
    }
  }

  void _handleShellEvent() {
    final event = _ctrl.lastEvent;
    if (event == null || !event.isDown) return;
    final btn = event.button;

    // Splash intercept
    if (!_splashDone) {
      if (btn == ArcadeButton.a || btn == ArcadeButton.start) {
        _splashTimer?.cancel();
        setState(() => _splashDone = true);
      }
      return;
    }

    if (_activeGame == null) {
      const totalOpts = 22; // 3+7+4+3+3+2 = 22 settings rows

      if (_headerFocused) {
        // ── Header level: L/R switches tab, DOWN enters content ─────────────
        switch (btn) {
          case ArcadeButton.left:
            if (_hubCategory > 0) setState(() { _hubCategory -= 1; });
          case ArcadeButton.right:
            if (_hubCategory < 3) setState(() { _hubCategory += 1; });
          case ArcadeButton.down:
            setState(() { _headerFocused = false; _settingsCursor = 0; });
          default: break;
        }
        return;
      }

      // ── Content level ────────────────────────────────────────────────────
      switch (btn) {
        case ArcadeButton.up:
          if (_hubCategory == 3) {
            // Settings: move cursor up; if at top, return to header
            if (_settingsCursor == 0) {
              setState(() => _headerFocused = true);
            } else {
              int next = _settingsCursor - 1;
              while (next > 0 && _isSettingLocked(next)) next--;
              setState(() => _settingsCursor = next);
              _ensureSettingVisible(_settingsCursor);
            }
          } else {
            // Other tabs: return to header on up
            setState(() => _headerFocused = true);
          }
        case ArcadeButton.down:
          if (_hubCategory == 3) {
            int next = (_settingsCursor + 1) % totalOpts;
            while (_isSettingLocked(next)) next = (next + 1) % totalOpts;
            setState(() => _settingsCursor = next);
            _ensureSettingVisible(_settingsCursor);
          }
        case ArcadeButton.left:
          if (_hubCategory == 1) {
            int next = _selectedIndex - 1;
            while (next >= 0 && kArcadeGames[next].locked) next--;
            if (next >= 0) setState(() => _selectedIndex = next);
            _scrollCarouselToSelected();
          }
        case ArcadeButton.right:
          if (_hubCategory == 1) {
            int next = _selectedIndex + 1;
            while (next < kArcadeGames.length && kArcadeGames[next].locked) next++;
            if (next < kArcadeGames.length) setState(() => _selectedIndex = next);
            _scrollCarouselToSelected();
          }
        case ArcadeButton.a:
        case ArcadeButton.start:
          if (_hubCategory == 1) _launchSelected();
          else if (_hubCategory == 0 && _lastPlayedIndex != null) {
            setState(() { _hubCategory = 1; _selectedIndex = _lastPlayedIndex!; _headerFocused = false; });
            _launchSelected();
          } else if (_hubCategory == 3) {
            _activateSetting(_settingsCursor);
          }
        default: break;
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
    setState(() { _saldo = newSaldo; _activeGame = game; _lastPlayedIndex = _selectedIndex; });
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // only the power-off button may exit
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Padding(
          padding: const EdgeInsets.all(4),
          child: _buildConsoleBody(),
        ),
      ),
    );
  }

  Widget _buildConsoleBody() {
    if (_skin == ConsoleSkin.psp) return _buildConsoleBodyPsp();
    if (_skin == ConsoleSkin.gba) return _buildConsoleBodyGba();
    final sg = _shellGradient;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [sg.top, sg.bot],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: sg.bdr, width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.30),
            blurRadius: 20, spreadRadius: 1, offset: const Offset(0, 4))],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Column(children: [
          _buildTopStrip(),
          const SizedBox(height: 8),
          Expanded(child: _buildScreenBezel()),
          const SizedBox(height: 12),
          _buildSelectStartStrip(),
          const SizedBox(height: 10),
          _buildControlsRow(),
          const SizedBox(height: 8),
          _buildSpeakerDots(),
        ]),
      ),
    );
  }

  // PSP skin — landscape layout with shoulder buttons, analog nub, D-pad | screen | ABXY
  Widget _buildConsoleBodyPsp() {
    final sg = _shellGradient;
    final ac = _accent;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [sg.top, sg.bot],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: sg.bdr, width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.40),
            blurRadius: 20, spreadRadius: 1, offset: const Offset(0, 4))],
      ),
      child: Column(children: [
        // ── Shoulder buttons bar ──────────────────────────────────────────────
        _PspShoulderBar(shellGradient: sg, accent: ac),
        // ── Main body ─────────────────────────────────────────────────────────
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left controls: analog nub (top) + D-pad (bottom)
                SizedBox(
                  width: 110,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _PspNub(controller: _ctrl),
                      const SizedBox(height: 4),
                      _ConsoleDPad(controller: _ctrl, joystick: false, size: 100),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                // Center: screen
                Expanded(child: _buildScreenBezel()),
                const SizedBox(width: 6),
                // Right controls: ABXY cluster
                SizedBox(
                  width: 110,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildABXYCluster(size: 36),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // ── Bottom strip: SELECT, home button, START ──────────────────────────
        _PspBottomBar(controller: _ctrl, shellGradient: sg, accent: ac),
      ]),
    );
  }

  // GBA skin — landscape layout with shoulder buttons, D-pad | screen | ABXY
  Widget _buildConsoleBodyGba() {
    final sg = _shellGradient;
    final ac = _accent;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [sg.top, sg.bot],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: sg.bdr, width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.40),
            blurRadius: 20, spreadRadius: 1, offset: const Offset(0, 4))],
      ),
      child: Column(children: [
        // ── Top row: painted L and R shoulder buttons + label ─────────────────
        _GbaShoulderBar(shellGradient: sg, accent: ac),
        // ── Main body ─────────────────────────────────────────────────────────
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Left: D-pad
                SizedBox(
                  width: 110,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _ConsoleDPad(controller: _ctrl, joystick: false, size: 110),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Center: screen
                Expanded(child: _buildScreenBezel()),
                const SizedBox(width: 8),
                // Right: ABXY cluster
                SizedBox(
                  width: 110,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildABXYCluster(size: 40),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // ── Bottom: SELECT, home indicator, START ─────────────────────────────
        _GbaBottomBar(controller: _ctrl, shellGradient: sg, accent: ac),
      ]),
    );
  }

  // ── Top strip ─────────────────────────────────────────────────────────────

  Widget _buildTopStrip() {
    final ac = _accent;
    final sg = _shellGradient;
    final isDark = sg.top.computeLuminance() < 0.3;
    final labelColor = isDark ? ac.withOpacity(0.70) : const Color(0xFF444444);
    final ledColor = ac;
    return Padding(
      padding: const EdgeInsets.only(left: 32),
      child: GestureDetector(
        onTap: _triggerPowerOff,
        child: Row(children: [
      Container(
        width: 7, height: 7,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: ledColor,
          boxShadow: [BoxShadow(color: ledColor.withOpacity(0.8), blurRadius: 6)],
        ),
      ),
      const SizedBox(width: 6),
      Text('T_STY: Arcade -\$',
        style: TextStyle(color: labelColor, fontSize: 8,
            fontWeight: FontWeight.w700, fontFamily: 'monospace', letterSpacing: 0.5)),
    ]),
      ),
    );
  }

  // ── Screen bezel ──────────────────────────────────────────────────────────

  Widget _buildScreenBezel() {
    return Container(
      decoration: BoxDecoration(
        color: _kBezel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black, width: 2),
        boxShadow: const [BoxShadow(color: Colors.black87, blurRadius: 10, offset: Offset(0, 3))],
      ),
      padding: const EdgeInsets.all(8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(children: [
          // CRT TV-off animation wraps game/hub content
          AnimatedBuilder(
            animation: _crtOffCtrl,
            builder: (ctx, child) {
              if (!_crtOffAnim) return child!;
              return Stack(children: [
                Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.diagonal3Values(1.0, _crtSquish.value, 1.0),
                  child: child!,
                ),
                if (_crtLine.value > 0.01)
                  Positioned.fill(child: ColoredBox(
                      color: Colors.white.withOpacity(_crtLine.value * 0.92))),
                if (_crtFade.value > 0.01)
                  Positioned.fill(child: ColoredBox(
                      color: Colors.black.withOpacity(_crtFade.value))),
              ]);
            },
            child: (_activeGame == null || _poweringOff) ? _buildNeonGrid() : _buildActiveGame(),
          ),
          // CRT scanline + vignette overlay
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _CrtOverlayPainter(phosphor: _accent)),
            ),
          ),
        ]),
      ),
    );
  }

  // ── New Hub UI (XMB-style homebrew) ──────────────────────────────────────

  Widget _buildNeonGrid() {
    if (!_splashDone) return _buildSplashScreen();
    if (_poweringOff) return _buildPowerOffScreen();
    return Stack(children: [
      Positioned.fill(child: _buildHubBackground()),
      Column(children: [
        _buildHubCategoryBar(),
        Expanded(child: _buildHubContent()),
        _buildHubHintBar(),
      ]),
    ]);
  }

  Widget _buildHubBackground() {
    final grad = (_hubCategory == 1 && kArcadeGames.isNotEmpty)
        ? _kCardGradients[_selectedIndex.clamp(0, _kCardGradients.length - 1)]
        : [const Color(0xFF060614), const Color(0xFF020208)];
    final neon = (_hubCategory == 1 && kArcadeGames.isNotEmpty)
        ? _kNeonColors[_selectedIndex.clamp(0, _kNeonColors.length - 1)]
        : _accent;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(const Color(0xFF020205), grad[0], 0.55)!,
            const Color(0xFF020205),
            Color.lerp(const Color(0xFF020205), grad[1], 0.30)!,
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
      child: Stack(children: [
        Positioned(right: -24, top: -24,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 450),
            width: 110, height: 110,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                neon.withOpacity(0.08), Colors.transparent]),
            ),
          ),
        ),
        Positioned(left: -30, bottom: -10,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 450),
            width: 130, height: 130,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                grad[1].withOpacity(0.10), Colors.transparent]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildHubCategoryBar() {
    final ac = _accent;
    const icons  = ['🕐', '🎮', '👤', '⚙'];
    final labels = [_t('RECIENTE','RECENT'), _t('JUEGOS','GAMES'), _t('PERFIL','PROFILE'), _t('AJUSTES','SETTINGS')];
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
      child: Row(children: [
        // Pill tabs
        ...List.generate(4, (i) {
          final sel = _hubCategory == i;
          return GestureDetector(
            onTap: () => setState(() => _hubCategory = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 6),
              padding: EdgeInsets.symmetric(
                  horizontal: sel ? 10 : 7, vertical: sel ? 5 : 4),
              decoration: BoxDecoration(
                color: sel
                    ? ac.withOpacity(_headerFocused ? 0.30 : 0.15)
                    : Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: sel
                      ? ac.withOpacity(0.65)
                      : Colors.white.withOpacity(0.10),
                  width: sel ? 1.0 : 0.6,
                ),
                boxShadow: sel
                    ? [BoxShadow(color: ac.withOpacity(_headerFocused ? 0.45 : 0.18),
                        blurRadius: _headerFocused ? 14 : 8, spreadRadius: -2)]
                    : [],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(icons[i], style: TextStyle(fontSize: sel ? 10 : 8)),
                if (sel) ...[
                  const SizedBox(width: 4),
                  Text(labels[i],
                    style: TextStyle(
                      color: ac, fontSize: 6.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      shadows: [Shadow(color: ac, blurRadius: 4)],
                    )),
                ],
              ]),
            ),
          );
        }),
        const Spacer(),
        // Saldo badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.amber.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.amber.withOpacity(0.30), width: 0.7),
          ),
          child: Text('💰 ${_saldo.toStringAsFixed(0)}',
            style: const TextStyle(color: Colors.amber, fontSize: 7.5,
                fontWeight: FontWeight.bold)),
        ),
      ]),
    );
  }

  Widget _buildHubContent() {
    switch (_hubCategory) {
      case 0: return _buildHubRecent();
      case 1: return _buildHubLibrary();
      case 2: return _buildHubProfile();
      case 3: return _buildHubSettings();
      default: return _buildHubLibrary();
    }
  }

  Widget _buildHubHintBar() {
    final ac = _accent;
    final items = _hubCategory == 1
        ? [('◀▶', _t('navegar','browse')), ('A', _t('jugar','play')), ('SEL', _t('salir','exit'))]
        : _hubCategory == 3
        ? [('▲▼', _t('nav','nav')), ('A', _t('confirmar','select')), ('▲', _t('volver','back')), ('SEL', _t('salir','exit'))]
        : [('◀▶', _t('cambiar','switch')), ('SEL', _t('salir','exit'))];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.40),
        border: Border(top: BorderSide(
            color: Colors.white.withOpacity(0.06), width: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: items.expand((h) => [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: ac.withOpacity(0.12),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: ac.withOpacity(0.35), width: 0.5),
              ),
              child: Text(h.$1, style: TextStyle(
                  color: ac, fontSize: 6.5, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 3),
            Text(h.$2, style: TextStyle(
                color: Colors.white.withOpacity(0.30), fontSize: 6.5)),
          ]),
          const SizedBox(width: 12),
        ]).toList()..removeLast(),
      ),
    );
  }

  // ── Hub: Recent ───────────────────────────────────────────────────────────

  Widget _buildHubRecent() {
    if (_lastPlayedIndex == null) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 60, height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
              color: Colors.white.withOpacity(0.04),
            ),
            alignment: Alignment.center,
            child: Text('🕐', style: TextStyle(fontSize: 24,
                color: Colors.white.withOpacity(0.4))),
          ),
          const SizedBox(height: 12),
          Text('No recent games', style: TextStyle(
              color: Colors.white.withOpacity(0.55), fontSize: 11,
              fontWeight: FontWeight.w300, letterSpacing: 0.5)),
          const SizedBox(height: 4),
          Text('Play something to see it here',
              style: TextStyle(color: Colors.white.withOpacity(0.25),
                  fontSize: 8, letterSpacing: 0.3)),
        ]),
      );
    }
    final idx   = _lastPlayedIndex!;
    final game  = kArcadeGames[idx];
    final neon  = _kNeonColors[idx % _kNeonColors.length];
    final grad  = _kCardGradients[idx % _kCardGradients.length];
    final score = _highScores[idx];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('LAST PLAYED',
            style: TextStyle(color: Colors.white.withOpacity(0.35),
                fontSize: 7, letterSpacing: 2.0, fontWeight: FontWeight.w500)),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () { setState(() { _hubCategory = 1; _selectedIndex = idx; }); _launchSelected(); },
          child: Container(
            width: double.infinity, height: 88,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(colors: grad,
                  begin: Alignment.topLeft, end: Alignment.bottomRight),
              border: Border.all(color: Colors.white.withOpacity(0.14), width: 1),
              boxShadow: [
                BoxShadow(color: neon.withOpacity(0.20),
                    blurRadius: 20, spreadRadius: -3, offset: const Offset(0, 4)),
                BoxShadow(color: Colors.black.withOpacity(0.50), blurRadius: 10),
              ],
            ),
            child: Stack(children: [
              // Glass top highlight
              Positioned(top: 0, left: 0, right: 0,
                child: Container(
                  height: 35,
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20)),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: [Colors.white.withOpacity(0.12), Colors.transparent]),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 52, height: 44,
                      child: _HeroDemoGame(
                        key: ValueKey(idx),
                        game: game,
                        userId: widget.userId,
                        rewardsDocRef: widget.rewardsDocRef,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(game.title, style: const TextStyle(color: Colors.white,
                          fontSize: 14, fontWeight: FontWeight.bold,
                          shadows: [Shadow(color: Colors.black54, blurRadius: 4)])),
                      const SizedBox(height: 3),
                      Text(score > 0 ? 'HI  $score pts' : 'No score yet',
                          style: TextStyle(
                              color: score > 0
                                  ? Colors.amber.withOpacity(0.85)
                                  : Colors.white38,
                              fontSize: 8)),
                    ]),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: neon.withOpacity(0.22),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: neon.withOpacity(0.70), width: 1),
                      boxShadow: [BoxShadow(color: neon.withOpacity(0.30),
                          blurRadius: 10)],
                    ),
                    child: Text('▶ PLAY', style: TextStyle(
                        color: neon, fontSize: 9, fontWeight: FontWeight.bold,
                        shadows: [Shadow(color: neon, blurRadius: 5)])),
                  ),
                ]),
              ),
            ]),
          ),
        ),
        if (_newRecordIndex == idx) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.withOpacity(0.35), width: 0.8),
            ),
            child: Row(children: [
              const Text('⚡', style: TextStyle(fontSize: 12)),
              const SizedBox(width: 8),
              Text('NEW RECORD — $score pts',
                  style: const TextStyle(color: Colors.amber, fontSize: 8.5,
                      fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            ]),
          ),
        ],
      ]),
    );
  }

  // ── Hub: Library ──────────────────────────────────────────────────────────

  Widget _buildHubLibrary() {
    return Column(children: [
      Expanded(child: _buildHeroCard()),
      const SizedBox(height: 7),
      _buildGameCarousel(),
      const SizedBox(height: 4),
    ]);
  }

  Widget _buildHeroCard() {
    if (kArcadeGames.isEmpty) return const SizedBox.shrink();
    final idx  = _selectedIndex.clamp(0, kArcadeGames.length - 1);
    final game = kArcadeGames[idx];
    final neon = _kNeonColors[idx % _kNeonColors.length];
    final grad = _kCardGradients[idx % _kCardGradients.length];
    final score = _highScores[idx];

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withOpacity(0.14), width: 1),
          boxShadow: [
            BoxShadow(color: neon.withOpacity(0.22),
                blurRadius: 22, spreadRadius: -4, offset: const Offset(0, 5)),
            BoxShadow(color: Colors.black.withOpacity(0.55),
                blurRadius: 12, offset: const Offset(0, 3)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(children: [
            // Full-bleed live game demo
            Positioned.fill(child: _HeroDemoGame(
              key: ValueKey(idx),
              game: game,
              userId: widget.userId,
              rewardsDocRef: widget.rewardsDocRef,
            )),
            // Dark scrim at bottom for text legibility
            Positioned(bottom: 0, left: 0, right: 0,
              child: Container(
                height: 90,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withOpacity(0.88)],
                  ),
                ),
              ),
            ),
            // Top glass shimmer
            Positioned(top: 0, left: 0, right: 0,
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [Colors.white.withOpacity(0.08), Colors.transparent],
                  ),
                ),
              ),
            ),
            // Number badge — top-left
            Positioned(top: 10, left: 14,
              child: Container(
                width: 26, height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withOpacity(0.55),
                  border: Border.all(color: Colors.white.withOpacity(0.45), width: 1.5),
                ),
                alignment: Alignment.center,
                child: Text('${idx + 1}',
                    style: const TextStyle(color: Colors.white, fontSize: 12,
                        fontWeight: FontWeight.bold, fontFamily: 'monospace')),
              ),
            ),
            // Status badge — top-right
            if (game.locked)
              Positioned(top: 10, right: 14,
                  child: _heroBadge(_t('BLOQUEADO','LOCKED'), Colors.redAccent))
            else if (_newRecordIndex == idx)
              Positioned(top: 10, right: 14,
                  child: _heroBadge('⚡ RECORD', Colors.amber)),
            // Bottom overlay: title + score + play
            Positioned(bottom: 0, left: 0, right: 0,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(game.title,
                      style: const TextStyle(
                        color: Colors.white, fontSize: 17,
                        fontWeight: FontWeight.bold, letterSpacing: 0.3,
                        shadows: [Shadow(color: Colors.black87, blurRadius: 6)],
                      ),
                      overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 5),
                    Row(children: [
                      Text(
                        score > 0 ? 'HI  $score pts' : 'No high score yet',
                        style: TextStyle(
                          color: score > 0
                              ? Colors.amber.withOpacity(0.90)
                              : Colors.white38,
                          fontSize: 8.5,
                        )),
                      const Spacer(),
                      if (!game.locked)
                        GestureDetector(
                          onTap: _launchSelected,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 7),
                            decoration: BoxDecoration(
                              color: neon.withOpacity(0.22),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                  color: neon.withOpacity(0.75), width: 1.2),
                              boxShadow: [BoxShadow(
                                  color: neon.withOpacity(0.35),
                                  blurRadius: 12, spreadRadius: -2)],
                            ),
                            child: Text('▶  PLAY',
                              style: TextStyle(
                                color: neon, fontSize: 10,
                                fontWeight: FontWeight.bold,
                                shadows: [Shadow(color: neon, blurRadius: 5)],
                              )),
                          ),
                        ),
                    ]),
                  ],
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _heroBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.20),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.60), width: 0.8),
      ),
      child: Text(label, style: TextStyle(
          color: color, fontSize: 6.5, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildGameCarousel() {
    return SizedBox(
      height: 58,
      child: ListView.builder(
        controller: _carouselCtrl,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        itemCount: kArcadeGames.length,
        itemBuilder: (_, i) {
          final game = kArcadeGames[i];
          final sel  = _selectedIndex == i;
          final neon = _kNeonColors[i % _kNeonColors.length];
          return GestureDetector(
            onTap: () {
              setState(() => _selectedIndex = i);
              _scrollCarouselToSelected();
            },
            onDoubleTap: (sel && !game.locked) ? _launchSelected : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              width: sel ? 56 : 46,
              margin: EdgeInsets.only(right: 6, top: sel ? 0 : 5, bottom: sel ? 0 : 5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: sel
                      ? neon.withOpacity(0.85)
                      : Colors.white.withOpacity(0.10),
                  width: sel ? 1.5 : 0.8,
                ),
                boxShadow: sel
                    ? [BoxShadow(color: neon.withOpacity(0.35),
                        blurRadius: 10, spreadRadius: -1)]
                    : [],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: Stack(children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _CartridgePainter(
                          index: i, selected: sel, showNumber: false),
                    ),
                  ),
                  if (game.locked)
                    Positioned(right: 2, top: 2,
                      child: Text('🔒',
                          style: TextStyle(fontSize: 8,
                              color: Colors.white.withOpacity(0.6)))),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Hub: Profile ──────────────────────────────────────────────────────────

  Widget _buildHubProfile() {
    final ac = _accent;
    final totalScore  = _highScores.fold(0, (a, b) => a + b);
    final gamesPlayed = _highScores.where((s) => s > 0).length;
    final unlocked    = kArcadeGames.where((g) => !g.locked).length;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // User card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: Colors.white.withOpacity(0.06),
            border: Border.all(color: Colors.white.withOpacity(0.10), width: 0.8),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.35),
                blurRadius: 12, offset: const Offset(0, 3))],
          ),
          child: Row(children: [
            // Avatar circle
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [ac, ac.withOpacity(0.35)]),
                border: Border.all(color: Colors.white.withOpacity(0.25), width: 1),
                boxShadow: [BoxShadow(color: ac.withOpacity(0.25),
                    blurRadius: 10, spreadRadius: -2)],
              ),
              alignment: Alignment.center,
              child: Text(
                _userName.isNotEmpty ? _userName[0].toUpperCase() : '?',
                style: const TextStyle(color: Colors.white, fontSize: 17,
                    fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_userName.isEmpty ? 'Player' : _userName,
                    style: const TextStyle(color: Colors.white, fontSize: 14,
                        fontWeight: FontWeight.bold, letterSpacing: 0.3)),
                Text('Arcade Center',
                    style: TextStyle(color: ac.withOpacity(0.55), fontSize: 8,
                        letterSpacing: 0.5)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('💰 ${_saldo.toStringAsFixed(0)}',
                  style: const TextStyle(color: Colors.amber, fontSize: 10,
                      fontWeight: FontWeight.bold)),
              Text('BALANCE', style: TextStyle(
                  color: Colors.white.withOpacity(0.30), fontSize: 6,
                  letterSpacing: 0.8)),
            ]),
          ]),
        ),
        const SizedBox(height: 10),
        // Stats row
        Row(children: [
          _profileStatCard('TOTAL SCORE', '$totalScore', ac),
          const SizedBox(width: 8),
          _profileStatCard('GAMES PLAYED', '$gamesPlayed / $unlocked', ac),
        ]),
        const SizedBox(height: 10),
        // High scores list
        Text('HIGH SCORES',
            style: TextStyle(color: Colors.white.withOpacity(0.35),
                fontSize: 7, letterSpacing: 2.0, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: Colors.white.withOpacity(0.04),
            border: Border.all(color: Colors.white.withOpacity(0.08), width: 0.6),
          ),
          child: Column(
            children: List.generate(kArcadeGames.length, (i) {
              final g = kArcadeGames[i];
              if (g.locked || _highScores[i] == 0) return const SizedBox.shrink();
              final neon = _kNeonColors[i % _kNeonColors.length];
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(
                      color: Colors.white.withOpacity(0.05), width: 0.5)),
                ),
                child: Row(children: [
                  Container(width: 3, height: 16,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                          color: neon, borderRadius: BorderRadius.circular(2))),
                  Container(
                    width: 20, height: 18,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      gradient: LinearGradient(
                          colors: _kCardGradients[i % _kCardGradients.length],
                          begin: Alignment.topLeft, end: Alignment.bottomRight),
                    ),
                    alignment: Alignment.center,
                    child: Text('${i + 1}', style: const TextStyle(
                        color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold,
                        fontFamily: 'monospace')),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(g.title,
                      style: const TextStyle(color: Colors.white70, fontSize: 8),
                      overflow: TextOverflow.ellipsis)),
                  Text('${_highScores[i]}',
                      style: TextStyle(color: Colors.amber.withOpacity(0.85),
                          fontSize: 8.5, fontWeight: FontWeight.bold)),
                ]),
              );
            }).where((w) => w is! SizedBox || (w as SizedBox).height != null).toList(),
          ),
        ),
        const SizedBox(height: 10),
        // Achievements teaser
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: Colors.white.withOpacity(0.03),
            border: Border.all(color: Colors.white.withOpacity(0.07), width: 0.6),
          ),
          child: Row(children: [
            Text('🏆', style: TextStyle(fontSize: 18,
                color: Colors.white.withOpacity(0.25))),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('ACHIEVEMENTS',
                  style: TextStyle(color: Colors.white.withOpacity(0.35),
                      fontSize: 8, letterSpacing: 1.0, fontWeight: FontWeight.w500)),
              Text('Coming soon...',
                  style: TextStyle(color: Colors.white.withOpacity(0.20),
                      fontSize: 7)),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _profileStatCard(String label, String value, Color ac) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: ac.withOpacity(0.07),
          border: Border.all(color: ac.withOpacity(0.20), width: 0.8),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25),
              blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: TextStyle(color: ac, fontSize: 16,
              fontWeight: FontWeight.bold, letterSpacing: 0.3)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: Colors.white.withOpacity(0.35),
              fontSize: 6, letterSpacing: 0.5)),
        ]),
      ),
    );
  }

  // ── Hub: Settings ─────────────────────────────────────────────────────────

  Widget _buildHubSettings() {
    final ac = _accent;
    int idx = 0;
    Widget opt(String label, {bool locked = false}) {
      final i = idx++;
      if (locked) {
        return _settingsOptRow(label, false, false, null, locked: true, rowKey: _settingKeys[i]);
      }
      return _settingsOptRow(label, _isSettingActive(i), _isCursorOn(i),
          () => _activateSetting(i), rowKey: _settingKeys[i]);
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _settingGroup(_t('APARIENCIA', 'CONSOLE SKIN'), [
          opt(_t('GameBoy Clásico', 'GameBoy Classic')),
          opt(_t('PSP Apaisado', 'PSP Landscape'), locked: true),
          opt(_t('Game Boy Advance', 'Game Boy Advance'), locked: true),
        ]),
        _settingGroup(_t('COLOR DEL CUERPO', 'SHELL COLOR'), [
          opt(_t('Gris Clásico', 'Classic Gray')),
          opt(_t('Negro Medianoche', 'Midnight Black')),
          opt('Índigo'),
          opt(_t('Rojo Carmesí', 'Crimson Red')),
          opt(_t('Azul Marino', 'Navy Blue')),
          opt(_t('Verde Bosque', 'Forest Green')),
          opt(_t('Rosa Oscuro', 'Dark Rose')),
        ]),
        _settingGroup(_t('COLOR ACENTO', 'ACCENT COLOR'), [
          opt(_t('Verde Fósforo', 'Phosphor Green')),
          opt(_t('Ámbar Retro', 'Amber Retro')),
          opt(_t('Cyan Cripto', 'Cyan Crypto')),
          opt(_t('Rojo Infernal', 'Infernal Red')),
        ]),
        _settingGroup(_t('BOTONES', 'BUTTON LAYOUT'), [
          opt('SNES  X/Y/A/B'),
          opt('Xbox  Y/X/B/A'),
          opt('PS4  △/☐/○/✕'),
        ]),
        _settingGroup(_t('DISPLAY BOTONES', 'BUTTON DISPLAY'), [
          opt(_t('Color Sólido', 'Solid Color')),
          opt(_t('Oscuro (brillo neón)', 'Blackout (neon glow)')),
          opt(_t('Cristal transparente', 'Crystal Clear (glass)')),
        ]),
        _settingGroup(_t('IDIOMA', 'LANGUAGE'), [
          opt('Español'),
          opt('English'),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Text('▲▼ ${_t('navegar', 'navigate')}  ', style: TextStyle(
              color: Colors.white.withOpacity(0.30), fontSize: 7)),
          Text('A', style: TextStyle(color: ac.withOpacity(0.60), fontSize: 7,
              fontWeight: FontWeight.bold)),
          Text('  ${_t('confirmar', 'select')}  ▲ ${_t('volver', 'back')}', style: TextStyle(
              color: Colors.white.withOpacity(0.30), fontSize: 7)),
        ]),
      ]),
    );
  }

  Widget _settingGroup(String title, List<Widget> rows) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(
            color: Colors.white.withOpacity(0.35), fontSize: 7,
            letterSpacing: 1.5, fontWeight: FontWeight.w500)),
        const SizedBox(height: 5),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.white.withOpacity(0.04),
            border: Border.all(color: Colors.white.withOpacity(0.07), width: 0.5),
          ),
          child: Column(children: rows),
        ),
      ]),
    );
  }

  Widget _settingsOptRow(String label, bool active, bool cursor,
      VoidCallback? onTap, {bool locked = false, Key? rowKey}) {
    final ac = _accent;
    return GestureDetector(
      key: rowKey,
      onTap: locked ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: cursor
              ? ac.withOpacity(0.12)
              : active
                  ? ac.withOpacity(0.06)
                  : Colors.transparent,
          border: Border(
            bottom: BorderSide(color: Colors.white.withOpacity(0.05), width: 0.4)),
        ),
        child: Row(children: [
          if (active && !locked)
            Container(width: 3, height: 14,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                    color: ac, borderRadius: BorderRadius.circular(2)))
          else
            const SizedBox(width: 11),
          Expanded(child: Text(label, style: TextStyle(
              color: locked
                  ? Colors.white.withOpacity(0.20)
                  : (active || cursor ? Colors.white : Colors.white.withOpacity(0.55)),
              fontSize: 8.5,
              fontWeight: (active || cursor) && !locked
                  ? FontWeight.w500 : FontWeight.normal))),
          if (active && !locked)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: ac.withOpacity(0.18),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: ac.withOpacity(0.50), width: 0.6),
              ),
              child: Text('ON', style: TextStyle(
                  color: ac, fontSize: 7, fontWeight: FontWeight.bold)),
            )
          else if (locked)
            Text('SOON', style: TextStyle(
                color: Colors.white.withOpacity(0.18), fontSize: 6.5,
                letterSpacing: 0.5)),
          if (cursor && !locked)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text('›', style: TextStyle(color: ac, fontSize: 14,
                  fontWeight: FontWeight.bold)),
            ),
        ]),
      ),
    );
  }

  // ── CRT Power-on splash ───────────────────────────────────────────────────

  Widget _buildSplashScreen() {
    final ac = _accent;
    final showWelcome = _splashLine >= _kBootLines.length + 1;
    return SizedBox.expand(child: Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ARCADE CENTER OS  v1.0.0',
            style: TextStyle(color: ac, fontSize: 9,
                fontFamily: 'monospace', fontWeight: FontWeight.bold,
                letterSpacing: 1.5)),
          const SizedBox(height: 2),
          Container(height: 1, color: ac.withOpacity(0.35)),
          const SizedBox(height: 8),
          for (int i = 0; i < _kBootLines.length; i++)
            if (i < _splashLine)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(_kBootLines[i],
                  style: TextStyle(color: ac.withOpacity(0.80), fontSize: 8,
                      fontFamily: 'monospace')),
              ),
          const Spacer(),
          if (showWelcome) ...[
            Container(height: 1, color: ac.withOpacity(0.25)),
            const SizedBox(height: 12),
            Center(
              child: Column(children: [
                Text('¡BIENVENIDO,',
                  style: TextStyle(color: ac, fontSize: 13,
                      fontFamily: 'monospace', fontWeight: FontWeight.bold,
                      letterSpacing: 2)),
                Text(_userName.isEmpty ? '...' : '${_userName.toUpperCase()}!',
                  style: TextStyle(color: Colors.white, fontSize: 22,
                      fontFamily: 'monospace', fontWeight: FontWeight.w900,
                      letterSpacing: 3,
                      shadows: [Shadow(color: ac, blurRadius: 14)])),
              ]),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(_t('[ A ]  Continuar', '[ A ]  Continue'),
                style: TextStyle(
                  color: ac.withOpacity(0.70),
                  fontSize: 8, fontFamily: 'monospace', letterSpacing: 2)),
            ),
          ] else ...[
            Row(children: [
              Text('> ', style: TextStyle(color: ac, fontSize: 8, fontFamily: 'monospace')),
              Container(width: 6, height: 10, color: ac.withOpacity(0.80)),
            ]),
          ],
          const SizedBox(height: 6),
          Container(height: 1, color: ac.withOpacity(0.15)),
          const SizedBox(height: 4),
          Text('ARCADE CENTER OS  ©2025',
            style: TextStyle(color: ac.withOpacity(0.30),
                fontSize: 7, fontFamily: 'monospace')),
        ],
      ),
    ));
  }

  Widget _buildPowerOffScreen() {
    final ac = _accent;
    const messages = [
      '> Guardando partida        [  OK  ]',
      '> Cerrando procesos        [  OK  ]',
      '> Liberando memoria        [  OK  ]',
      '> Apagando pantalla        [  OK  ]',
      '> ¡Hasta pronto!           [  OK  ]',
    ];
    return SizedBox.expand(child: Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('ARCADE CENTER OS  — APAGANDO',
          style: TextStyle(color: ac, fontSize: 9,
              fontFamily: 'monospace', fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        const SizedBox(height: 2),
        Container(height: 1, color: ac.withOpacity(0.35)),
        const SizedBox(height: 8),
        for (int i = 0; i < messages.length; i++)
          if (i < _powerOffStep)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(messages[i],
                style: TextStyle(color: ac.withOpacity(0.80), fontSize: 8,
                    fontFamily: 'monospace')),
            ),
        const Spacer(),
        if (_powerOffStep >= 5) ...[
          Container(height: 1, color: ac.withOpacity(0.25)),
          const SizedBox(height: 12),
          Center(child: Text('😴  ¡NOS VEMOS PRONTO!',
            style: TextStyle(color: Colors.white, fontSize: 14,
                fontFamily: 'monospace', fontWeight: FontWeight.w900,
                letterSpacing: 2,
                shadows: [Shadow(color: ac, blurRadius: 14)]))),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 6),
        Container(height: 1, color: ac.withOpacity(0.15)),
        const SizedBox(height: 4),
        Text('ARCADE CENTER OS  ©2025',
          style: TextStyle(color: ac.withOpacity(0.30), fontSize: 7, fontFamily: 'monospace')),
      ]),
    ));
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
      _ConsoleMetaButton(label: 'SELECT', btn: ArcadeButton.select, controller: _ctrl, shellColor: _metaColor),
      const SizedBox(width: 12),
      GestureDetector(
        onTap: _triggerPowerOff,
        child: Container(
          width: 18, height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black.withOpacity(0.35),
            border: Border.all(color: Colors.white.withOpacity(0.30), width: 1),
          ),
          alignment: Alignment.center,
          child: Icon(Icons.power_settings_new,
              size: 11, color: Colors.white.withOpacity(0.70)),
        ),
      ),
      const SizedBox(width: 12),
      _ConsoleMetaButton(label: 'START', btn: ArcadeButton.start, controller: _ctrl, shellColor: _metaColor),
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
      joystick: _activeGame?.supportsDiagonal ?? false,
      accent: _accent);

  Widget _buildABXYCluster({double size = 48.0}) {
    final btnSize = size;
    const gap = 4.0;
    final total = btnSize * 3 + gap * 2;
    final btns = _btnDefs;
    return SizedBox(
      width: total, height: total,
      child: Stack(alignment: Alignment.center, children: [
        Positioned(top: 0, left: total / 2 - btnSize / 2,
            child: _ConsoleActionButton(label: btns[0].label, btn: btns[0].btn,
                color: btns[0].color, controller: _ctrl, size: btnSize,
                display: _buttonDisplay, labelSize: btns[0].labelSize)),
        Positioned(left: 0, top: total / 2 - btnSize / 2,
            child: _ConsoleActionButton(label: btns[1].label, btn: btns[1].btn,
                color: btns[1].color, controller: _ctrl, size: btnSize,
                display: _buttonDisplay, labelSize: btns[1].labelSize)),
        Positioned(right: 0, top: total / 2 - btnSize / 2,
            child: _ConsoleActionButton(label: btns[2].label, btn: btns[2].btn,
                color: btns[2].color, controller: _ctrl, size: btnSize,
                display: _buttonDisplay, labelSize: btns[2].labelSize)),
        Positioned(bottom: 0, left: total / 2 - btnSize / 2,
            child: _ConsoleActionButton(label: btns[3].label, btn: btns[3].btn,
                color: btns[3].color, controller: _ctrl, size: btnSize,
                display: _buttonDisplay, labelSize: btns[3].labelSize)),
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

// ─── In-card game demo (actual game, bot-driven, no cost / no score impact) ──

class _HeroDemoGame extends StatefulWidget {
  final ArcadeGameDef game;
  final String userId;
  final DocumentReference rewardsDocRef;
  const _HeroDemoGame({super.key, required this.game, required this.userId,
      required this.rewardsDocRef});
  @override State<_HeroDemoGame> createState() => _HeroDemoGameState();
}

class _HeroDemoGameState extends State<_HeroDemoGame> {
  late final ArcadeInputController _bot;
  Timer? _botTimer;
  int _tick = 0;

  @override
  void initState() {
    super.initState();
    HighScoreService.setDemoMode(true);
    _bot = ArcadeInputController();
    _botTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (!mounted) return;
      _tick++;
      _botPlay();
    });
  }

  void _botPlay() {
    for (final b in ArcadeButton.values) _bot.release(b);

    // Phase 0 — press A for the first 10 ticks to get past start screens
    if (_tick <= 10) {
      _bot.press(ArcadeButton.a);
      return;
    }

    final t = _tick - 10; // tick index after startup
    switch (widget.game.id) {
      case 'flappy':
        // Flap every ~7 ticks (840 ms) — steady rhythm keeps bird airborne
        if (t % 7 < 2) _bot.press(ArcadeButton.a);
      case 'tetris':
        // Nudge pieces left/right and rotate; occasional soft-drop
        final phase = t % 14;
        if (phase < 3)       _bot.press(ArcadeButton.left);
        else if (phase < 6)  _bot.press(ArcadeButton.right);
        else if (phase == 7) _bot.press(ArcadeButton.a); // rotate
        if (t % 30 < 2)      _bot.press(ArcadeButton.down);
      case 'snake':
        // Rectangular band — right×14, down×4, left×14, up×4, repeat
        // Keeps snake in a horizontal strip and avoids immediate wall death
        const _snakePattern = [
          ArcadeButton.right, ArcadeButton.right, ArcadeButton.right, ArcadeButton.right,
          ArcadeButton.down, ArcadeButton.down, ArcadeButton.down, ArcadeButton.down,
          ArcadeButton.left, ArcadeButton.left, ArcadeButton.left, ArcadeButton.left,
          ArcadeButton.left, ArcadeButton.left, ArcadeButton.left, ArcadeButton.left,
          ArcadeButton.up, ArcadeButton.up, ArcadeButton.up, ArcadeButton.up,
        ];
        _bot.press(_snakePattern[t % _snakePattern.length]);
      case 'shooter':
        _bot.press(ArcadeButton.a); // always shooting
        final ph = t % 20;
        if (ph < 7)       _bot.press(ArcadeButton.left);
        else if (ph < 14) _bot.press(ArcadeButton.right);
      case 'maze':
        // Hold each direction long enough to traverse a corridor
        const _mazeDirs = [ArcadeButton.right, ArcadeButton.down,
            ArcadeButton.left, ArcadeButton.up];
        _bot.press(_mazeDirs[(t ~/ 20) % _mazeDirs.length]);
      case 'hopper':
        // Hop up frequently; dodge left/right in between
        if (t % 10 < 3)              _bot.press(ArcadeButton.up);
        else if ((t ~/ 10) % 4 == 1) _bot.press(ArcadeButton.left);
        else if ((t ~/ 10) % 4 == 3) _bot.press(ArcadeButton.right);
      case 'breakout':
      case 'pong':
        if ((t ~/ 13) % 2 == 0) _bot.press(ArcadeButton.left);
        else _bot.press(ArcadeButton.right);
      case 'raycaster':
        // Walk forward constantly; sweep right now and then; fire regularly
        _bot.press(ArcadeButton.up);
        if (t % 35 < 10) _bot.press(ArcadeButton.right);
        if (t % 12 < 3)  _bot.press(ArcadeButton.a);
      case 'match3':
        final p2 = t % 22;
        if (p2 < 5)       _bot.press(ArcadeButton.right);
        else if (p2 < 10) _bot.press(ArcadeButton.down);
        else if (p2 < 12) _bot.press(ArcadeButton.a);
      case 'logic':
        final p3 = t % 26;
        if (p3 < 5)       _bot.press(ArcadeButton.right);
        else if (p3 < 10) _bot.press(ArcadeButton.down);
        else if (p3 < 12) _bot.press(ArcadeButton.a);
      default:
        const ds = [ArcadeButton.right, ArcadeButton.down, ArcadeButton.left, ArcadeButton.up];
        _bot.press(ds[(t ~/ 12) % ds.length]);
    }
  }

  @override
  void dispose() {
    _botTimer?.cancel();
    _bot.dispose();
    HighScoreService.setDemoMode(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.game.builder == null || widget.game.locked) {
      return Container(color: Colors.black12);
    }
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: 375, height: 667,
          child: AbsorbPointer(
            child: widget.game.builder!(
              userId: '${widget.userId}_demo',
              // Sink doc: writes go to a harmless throwaway path, not the user's real doc
              rewardsDocRef: FirebaseFirestore.instance
                  .collection('_demo_sink')
                  .doc('void'),
              currentSaldo: 99999,
              controller: _bot,
              onSaldoChanged: (_) {},
            ),
          ),
        ),
      ),
    );
  }
}


// ─── TCG-style Card Painter ───────────────────────────────────────────────────

class _CartridgePainter extends CustomPainter {
  final int index;
  final bool selected;
  final bool showNumber;
  const _CartridgePainter({required this.index, required this.selected, this.showNumber = true});

  @override
  bool shouldRepaint(_CartridgePainter old) =>
      old.selected != selected || old.index != index || old.showNumber != showNumber;

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
    const refW = 120.0, refH = 150.0;
    canvas.scale(w / refW, h / refH);
    _drawGameArt(canvas, refW, refH);

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

    // ── Number badge (top centre) — only when showNumber is true ───────────────
    if (showNumber) {
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
    }

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

      // ── Dino Escape (Endless Runner) ─────────────────────────────────────
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
  final double size;
  final Color accent;
  const _ConsoleDPad({required this.controller, this.joystick = false,
      this.size = 144, this.accent = const Color(0xFF00FF88)});
  @override State<_ConsoleDPad> createState() => _ConsoleDPadState();
}

class _ConsoleDPadState extends State<_ConsoleDPad> {
  Set<ArcadeButton> _active = const {};

  // Larger dead zone (24 px) reduces accidental triggers on touch
  static const _dead = 24.0;

  List<ArcadeButton> _buttonsFor(Offset local) {
    final cx = widget.size / 2, cy = widget.size / 2;
    final dx = local.dx - cx, dy = local.dy - cy;
    if (dx * dx + dy * dy < _dead * _dead) return const [];
    if (widget.joystick) {
      // 8-direction for diagonal-capable games (shooter / raycaster)
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

  void _applyButtons(List<ArcadeButton> next, Offset local) {
    final newSet = next.toSet();
    for (final b in _active.difference(newSet)) widget.controller.release(b);
    for (final b in newSet.difference(_active)) {
      widget.controller.press(b);
      HapticFeedback.lightImpact();
    }
    setState(() { _active = newSet; });
  }

  void _release() {
    for (final b in _active) widget.controller.release(b);
    setState(() { _active = const {}; });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown:   (e) => _applyButtons(_buttonsFor(e.localPosition), e.localPosition),
      onPointerMove:   (e) => _applyButtons(_buttonsFor(e.localPosition), e.localPosition),
      onPointerUp:     (_) => _release(),
      onPointerCancel: (_) => _release(),
      // Always render the one-piece cross d-pad; joystick flag only affects
      // input detection (8-dir vs 4-dir) in _buttonsFor, not appearance.
      child: CustomPaint(
        size: Size(widget.size, widget.size),
        painter: _CrossDPadPainter(active: _active, accent: widget.accent),
      ),
    );
  }
}

// ─── Modern Cross D-pad painter ───────────────────────────────────────────────

class _CrossDPadPainter extends CustomPainter {
  final Set<ArcadeButton> active;
  final Color accent;
  const _CrossDPadPainter({required this.active, this.accent = const Color(0xFF00FF88)});

  @override
  bool shouldRepaint(_CrossDPadPainter o) =>
      o.active.length != active.length || !o.active.containsAll(active) || o.accent != accent;

  bool _lit(ArcadeButton b) => active.contains(b);

  // Build one-piece cross via union of two rounded rectangles.
  // The rounded corners of each bar create natural concave junctions — exactly
  // how a real injection-moulded d-pad looks.
  Path _crossPath(Size size) {
    final cx = size.width / 2, cy = size.height / 2;
    final arm = size.width * 0.36;
    final half = arm / 2;
    const r = 9.0;
    final horiz = Path()..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(0, cy - half, size.width, arm), Radius.circular(r)));
    final vert  = Path()..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - half, 0, arm, size.height), Radius.circular(r)));
    return Path.combine(PathOperation.union, horiz, vert);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2;
    final arm = size.width * 0.36;
    final half = arm / 2;
    final p = Paint()..isAntiAlias = true;
    final cross = _crossPath(size);

    // Outer accent glow when any button active
    if (active.isNotEmpty) {
      p..color = accent.withOpacity(0.13)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
      canvas.drawPath(cross, p);
      p.maskFilter = null;
    }

    // Drop shadow
    p..color = Colors.black.withOpacity(0.55)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.save();
    canvas.translate(0, 2);
    canvas.drawPath(cross, p);
    canvas.restore();
    p.maskFilter = null;

    // Base fill — single gradient across the whole cross (one piece)
    p.shader = const LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight,
      colors: [Color(0xFF2E2E2E), Color(0xFF171717)],
    ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(cross, p);
    p.shader = null;


    // Thin surface rim
    p..color = Colors.white.withOpacity(0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawPath(cross, p);
    p.style = PaintingStyle.fill;

    // ── Chevron arrows ─────────────────────────────────────────────────────────
    void drawChevron(List<Offset> pts, ArcadeButton btn) {
      p.color = Colors.white.withOpacity(0.45);
      final path = Path()..moveTo(pts[0].dx, pts[0].dy);
      for (int i = 1; i < pts.length; i++) path.lineTo(pts[i].dx, pts[i].dy);
      path.close();
      canvas.drawPath(path, p);
    }

    // Up chevron
    drawChevron([Offset(cx, 10), Offset(cx - 8, 26), Offset(cx - 3, 26),
        Offset(cx - 3, 30), Offset(cx + 3, 30), Offset(cx + 3, 26), Offset(cx + 8, 26)],
        ArcadeButton.up);
    // Down chevron
    drawChevron([Offset(cx, size.height - 10), Offset(cx - 8, size.height - 26),
        Offset(cx - 3, size.height - 26), Offset(cx - 3, size.height - 30),
        Offset(cx + 3, size.height - 30), Offset(cx + 3, size.height - 26),
        Offset(cx + 8, size.height - 26)],
        ArcadeButton.down);
    // Left chevron
    drawChevron([Offset(10, cy), Offset(26, cy - 8), Offset(26, cy - 3),
        Offset(30, cy - 3), Offset(30, cy + 3), Offset(26, cy + 3), Offset(26, cy + 8)],
        ArcadeButton.left);
    // Right chevron
    drawChevron([Offset(size.width - 10, cy), Offset(size.width - 26, cy - 8),
        Offset(size.width - 26, cy - 3), Offset(size.width - 30, cy - 3),
        Offset(size.width - 30, cy + 3), Offset(size.width - 26, cy + 3),
        Offset(size.width - 26, cy + 8)],
        ArcadeButton.right);
  }
}

// ─── Modern Round D-pad painter (8-dir: shooter / raycaster) ─────────────────

class _RoundDPadPainter extends CustomPainter {
  final Set<ArcadeButton> active;
  final Color accent;
  const _RoundDPadPainter({required this.active, this.accent = const Color(0xFF00FF88)});

  @override
  bool shouldRepaint(_RoundDPadPainter o) =>
      o.active.length != active.length || !o.active.containsAll(active) || o.accent != accent;

  bool _lit(ArcadeButton b) => active.contains(b);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2;
    final R = size.width / 2 - 4;
    final p = Paint()..isAntiAlias = true;

    // Base disc shadow
    p.color = Colors.black.withOpacity(0.45);
    canvas.drawCircle(Offset(cx + 1, cy + 2), R, p);

    // Base disc gradient
    p.shader = const RadialGradient(
      center: Alignment(-0.3, -0.4),
      colors: [Color(0xFF2C2C2C), Color(0xFF141414)],
    ).createShader(Rect.fromCircle(center: Offset(72, 72), radius: 68));
    canvas.drawCircle(Offset(cx, cy), R, p);
    p.shader = null;

    // Outer rim highlight
    p..color = Colors.white.withOpacity(0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawCircle(Offset(cx, cy), R, p);
    p.style = PaintingStyle.fill;

    // 8 sector dividers (very subtle)
    p..color = Colors.black.withOpacity(0.35)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    for (int i = 0; i < 8; i++) {
      final angle = i * pi / 4;
      canvas.drawLine(Offset(cx, cy),
          Offset(cx + cos(angle) * R, cy + sin(angle) * R), p);
    }
    p.style = PaintingStyle.fill;

    // Inner disc / hub
    p.color = const Color(0xFF101010);
    canvas.drawCircle(Offset(cx, cy), R * 0.26, p);
    p..color = Colors.white.withOpacity(0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(Offset(cx, cy), R * 0.26, p);
    p.style = PaintingStyle.fill;

    // Cardinal direction arrows
    final arrR = R * 0.72;
    void drawArrow(double angle, ArcadeButton btn) {
      canvas.save();
      canvas.translate(cx + cos(angle) * arrR, cy + sin(angle) * arrR);
      canvas.rotate(angle + pi / 2);
      p.color = Colors.white.withOpacity(0.40);
      const s = 6.0;
      canvas.drawPath(Path()
          ..moveTo(0, -s)..lineTo(-s, s * 0.4)..lineTo(0, 0)..lineTo(s, s * 0.4)..close(), p);
      canvas.restore();
    }
    drawArrow(-pi / 2, ArcadeButton.up);
    drawArrow(pi / 2, ArcadeButton.down);
    drawArrow(pi, ArcadeButton.left);
    drawArrow(0, ArcadeButton.right);
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
  final ButtonDisplay display;
  final double labelSize;
  const _ConsoleActionButton({required this.label, required this.btn,
      required this.color, required this.controller, required this.size,
      this.display = ButtonDisplay.solid, this.labelSize = 15});
  @override State<_ConsoleActionButton> createState() => _ConsoleActionButtonState();
}

class _ConsoleActionButtonState extends State<_ConsoleActionButton> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final c = widget.color;
    final d = widget.display;
    final isBlackout = d == ButtonDisplay.blackout;
    final isClear    = d == ButtonDisplay.clear;
    return GestureDetector(
      onTapDown: (_) { setState(() => _pressed = true); HapticFeedback.selectionClick(); widget.controller.press(widget.btn); },
      onTapUp:   (_) { setState(() => _pressed = false); widget.controller.release(widget.btn); },
      onTapCancel: () { setState(() => _pressed = false); widget.controller.release(widget.btn); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 40),
        width: widget.size, height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isClear
              ? Colors.white.withOpacity(_pressed ? 0.22 : 0.09)
              : isBlackout
                  ? (_pressed ? const Color(0xFF1A1A1A) : Colors.black)
                  : (_pressed ? c.withOpacity(0.55) : c),
          border: (isClear || isBlackout)
              ? Border.all(
                  color: isClear
                      ? c.withOpacity(_pressed ? 1.0 : 0.75)
                      : c.withOpacity(_pressed ? 0.55 : 0.30),
                  width: isClear ? 2.0 : 1.2)
              : null,
          boxShadow: _pressed ? [] : [
            BoxShadow(
              color: c.withOpacity(isClear ? 0.35 : isBlackout ? 0.75 : 0.50),
              blurRadius: isClear ? 10 : isBlackout ? 14 : 8,
              offset: const Offset(0, 3)),
            if (!isClear)
              BoxShadow(color: Colors.black54, blurRadius: 4, offset: const Offset(0, 2)),
          ],
        ),
        alignment: Alignment.center,
        child: Text(widget.label,
          style: TextStyle(
            color: (isBlackout || isClear) ? c : (_pressed ? Colors.white70 : Colors.white),
            fontWeight: FontWeight.bold,
            fontSize: widget.labelSize,
            shadows: (isBlackout || isClear)
                ? [Shadow(color: c, blurRadius: _pressed ? 20 : (isClear ? 16 : 12))]
                : null)),
      ),
    );
  }
}

// ─── Meta button (SELECT / START) ─────────────────────────────────────────────

class _ConsoleMetaButton extends StatefulWidget {
  final String label;
  final ArcadeButton btn;
  final ArcadeInputController controller;
  final Color? shellColor;
  const _ConsoleMetaButton({required this.label, required this.btn, required this.controller, this.shellColor});
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
          color: _pressed
              ? (widget.shellColor?.withOpacity(0.55) ?? const Color(0xFF707070))
              : (widget.shellColor ?? _kMeta),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.black.withOpacity(0.22)),
          boxShadow: _pressed ? [] : [
            BoxShadow(color: Colors.black.withOpacity(0.30), blurRadius: 5, offset: const Offset(0, 2)),
          ],
        ),
        child: Text(widget.label,
          style: TextStyle(
            color: _pressed ? Colors.white : (widget.shellColor != null && widget.shellColor!.computeLuminance() < 0.3 ? Colors.white70 : const Color(0xFF222222)),
            fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
      ),
    );
  }
}

// ─── PSP Analog Nub ───────────────────────────────────────────────────────────

class _PspNub extends StatefulWidget {
  final ArcadeInputController controller;
  const _PspNub({required this.controller});
  @override State<_PspNub> createState() => _PspNubState();
}

class _PspNubState extends State<_PspNub> {
  Set<ArcadeButton> _active = const {};
  static const _dead = 8.0;
  static const _sz = 72.0;
  static const _cx = _sz / 2, _cy = _sz / 2;

  List<ArcadeButton> _buttonsFor(Offset local) {
    final dx = local.dx - _cx, dy = local.dy - _cy;
    if (dx * dx + dy * dy < _dead * _dead) return const [];
    final angle = (atan2(dy, dx) * 180 / pi + 450) % 360;
    if (angle < 22.5 || angle >= 337.5) return [ArcadeButton.up];
    if (angle < 67.5)  return [ArcadeButton.up, ArcadeButton.right];
    if (angle < 112.5) return [ArcadeButton.right];
    if (angle < 157.5) return [ArcadeButton.down, ArcadeButton.right];
    if (angle < 202.5) return [ArcadeButton.down];
    if (angle < 247.5) return [ArcadeButton.down, ArcadeButton.left];
    if (angle < 292.5) return [ArcadeButton.left];
    return [ArcadeButton.up, ArcadeButton.left];
  }

  void _apply(List<ArcadeButton> next) {
    final newSet = next.toSet();
    for (final b in _active.difference(newSet)) widget.controller.release(b);
    for (final b in newSet.difference(_active)) {
      widget.controller.press(b);
      HapticFeedback.lightImpact();
    }
    setState(() => _active = newSet);
  }

  void _release() {
    for (final b in _active) widget.controller.release(b);
    setState(() => _active = const {});
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown:   (e) => _apply(_buttonsFor(e.localPosition)),
      onPointerMove:   (e) => _apply(_buttonsFor(e.localPosition)),
      onPointerUp:     (_) => _release(),
      onPointerCancel: (_) => _release(),
      child: CustomPaint(
        size: const Size(_sz, _sz * 0.55),
        painter: _PspNubPainter(active: _active),
      ),
    );
  }
}

class _PspNubPainter extends CustomPainter {
  final Set<ArcadeButton> active;
  const _PspNubPainter({required this.active});
  @override bool shouldRepaint(_PspNubPainter o) => o.active != active;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2;
    final p = Paint()..isAntiAlias = true;
    final pressed = active.isNotEmpty;

    // Shadow
    p.color = Colors.black.withOpacity(0.5);
    canvas.drawOval(Rect.fromCenter(center: Offset(cx + 1, cy + 3),
        width: size.width * 0.85, height: size.height * 0.80), p);

    // Base oval
    p.shader = LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight,
      colors: pressed
          ? [const Color(0xFF2A2A2A), const Color(0xFF1A1A1A)]
          : [const Color(0xFF3A3A3A), const Color(0xFF252525)],
    ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawOval(Rect.fromCenter(center: Offset(cx, cy),
        width: size.width * 0.85, height: size.height * 0.78), p);
    p.shader = null;

    // Texture lines
    p..color = Colors.white.withOpacity(0.07)
     ..style = PaintingStyle.stroke
     ..strokeWidth = 0.8;
    for (double y = cy - size.height * 0.22; y < cy + size.height * 0.22; y += 3.5) {
      final halfW = size.width * 0.38 * (1 - ((y - cy).abs() / (size.height * 0.40)));
      canvas.drawLine(Offset(cx - halfW, y), Offset(cx + halfW, y), p);
    }

    // Top highlight
    p..color = Colors.white.withOpacity(pressed ? 0.05 : 0.18)
     ..style = PaintingStyle.stroke
     ..strokeWidth = 1.5;
    canvas.drawArc(Rect.fromCenter(center: Offset(cx, cy),
        width: size.width * 0.78, height: size.height * 0.68),
        pi * 1.15, pi * 0.70, false, p);
  }
}

// ─── PSP shoulder bar ─────────────────────────────────────────────────────────

class _PspShoulderBar extends StatelessWidget {
  final ({Color top, Color bot, Color bdr}) shellGradient;
  final Color accent;
  const _PspShoulderBar({required this.shellGradient, required this.accent});

  @override
  Widget build(BuildContext context) {
    final sg = shellGradient;
    return Container(
      height: 22,
      decoration: BoxDecoration(
        color: sg.bdr,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
      ),
      child: Row(children: [
        _ShoulderBtn(label: 'L', align: CrossAxisAlignment.start, sg: sg),
        Expanded(child: Center(
          child: Text('PSP-2000',
            style: TextStyle(color: accent.withOpacity(0.55), fontSize: 7,
                letterSpacing: 2, fontFamily: 'monospace')),
        )),
        _ShoulderBtn(label: 'R', align: CrossAxisAlignment.end, sg: sg),
      ]),
    );
  }
}

// ─── PSP bottom bar ───────────────────────────────────────────────────────────

class _PspBottomBar extends StatelessWidget {
  final ArcadeInputController controller;
  final ({Color top, Color bot, Color bdr}) shellGradient;
  final Color accent;
  const _PspBottomBar({required this.controller, required this.shellGradient, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: shellGradient.bdr.withOpacity(0.7),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _ConsoleMetaButton(label: 'SELECT', btn: ArcadeButton.select, controller: controller),
          Container(
            width: 18, height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: shellGradient.bdr,
              border: Border.all(color: accent.withOpacity(0.5), width: 1),
              boxShadow: [BoxShadow(color: accent.withOpacity(0.25), blurRadius: 6)],
            ),
            child: Center(child: Container(
              width: 8, height: 8,
              decoration: BoxDecoration(shape: BoxShape.circle,
                  color: accent.withOpacity(0.6)),
            )),
          ),
          _ConsoleMetaButton(label: 'START', btn: ArcadeButton.start, controller: controller),
        ],
      ),
    );
  }
}

// ─── GBA shoulder bar ─────────────────────────────────────────────────────────

class _GbaShoulderBar extends StatelessWidget {
  final ({Color top, Color bot, Color bdr}) shellGradient;
  final Color accent;
  const _GbaShoulderBar({required this.shellGradient, required this.accent});

  @override
  Widget build(BuildContext context) {
    final sg = shellGradient;
    return Container(
      height: 20,
      decoration: BoxDecoration(
        color: sg.bdr,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
      ),
      child: Row(children: [
        _ShoulderBtn(label: 'L', align: CrossAxisAlignment.start, sg: sg),
        Expanded(child: Center(
          child: Text('GAME BOY ADVANCE',
            style: TextStyle(color: accent.withOpacity(0.55), fontSize: 6,
                letterSpacing: 1.8, fontFamily: 'monospace')),
        )),
        _ShoulderBtn(label: 'R', align: CrossAxisAlignment.end, sg: sg),
      ]),
    );
  }
}

// ─── GBA bottom bar ───────────────────────────────────────────────────────────

class _GbaBottomBar extends StatelessWidget {
  final ArcadeInputController controller;
  final ({Color top, Color bot, Color bdr}) shellGradient;
  final Color accent;
  const _GbaBottomBar({required this.controller, required this.shellGradient, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: shellGradient.bdr.withOpacity(0.7),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _ConsoleMetaButton(label: 'SELECT', btn: ArcadeButton.select, controller: controller),
          Container(
            width: 22, height: 8,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: accent.withOpacity(0.3),
              border: Border.all(color: accent.withOpacity(0.6), width: 0.8),
              boxShadow: [BoxShadow(color: accent.withOpacity(0.4), blurRadius: 6)],
            ),
          ),
          _ConsoleMetaButton(label: 'START', btn: ArcadeButton.start, controller: controller),
        ],
      ),
    );
  }
}

// ─── Shared shoulder button chip ──────────────────────────────────────────────

class _ShoulderBtn extends StatelessWidget {
  final String label;
  final CrossAxisAlignment align;
  final ({Color top, Color bot, Color bdr}) sg;
  const _ShoulderBtn({required this.label, required this.align, required this.sg});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      alignment: align == CrossAxisAlignment.start ? Alignment.centerLeft : Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Container(
        width: 36, height: 16,
        decoration: BoxDecoration(
          color: sg.bot,
          borderRadius: label == 'L'
              ? const BorderRadius.only(topLeft: Radius.circular(6), bottomRight: Radius.circular(4))
              : const BorderRadius.only(topRight: Radius.circular(6), bottomLeft: Radius.circular(4)),
          border: Border.all(color: sg.bdr, width: 0.8),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 3)],
        ),
        alignment: Alignment.center,
        child: Text(label,
          style: const TextStyle(color: Colors.white70, fontSize: 8,
              fontWeight: FontWeight.bold, letterSpacing: 1)),
      ),
    );
  }
}

// ─── CRT scanline + vignette overlay ─────────────────────────────────────────

class _CrtOverlayPainter extends CustomPainter {
  final Color phosphor;
  const _CrtOverlayPainter({this.phosphor = const Color(0xFF00FF88)});

  @override
  bool shouldRepaint(_CrtOverlayPainter old) => old.phosphor != phosphor;

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

    // Subtle phosphor tint (colour matches active theme)
    p.color = phosphor.withOpacity(0.022);
    p.isAntiAlias = true;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), p);
  }
}
