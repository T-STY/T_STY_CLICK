import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'arcade_input_controller.dart';
import 'slot_machine_screen.dart';
import 'snake_game_screen.dart';

// ─── Game registry ────────────────────────────────────────────────────────────

typedef ArcadeGameBuilder = Widget Function({
  required String userId,
  required DocumentReference rewardsDocRef,
  required double currentSaldo,
  required ArcadeInputController controller,
  required VoidCallback onSaldoChanged,
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
  ArcadeGameDef(
    id: 'slot',
    emoji: '🎰',
    title: 'Tragamonedas',
    subtitle: 'Azar',
    builder: ({
      required userId,
      required rewardsDocRef,
      required currentSaldo,
      required controller,
      required onSaldoChanged,
    }) =>
        SlotMachineScreen(
          userId: userId,
          rewardsDocRef: rewardsDocRef,
          currentSaldo: currentSaldo,
          controller: controller,
          onSaldoChanged: onSaldoChanged,
        ),
  ),
  ArcadeGameDef(
    id: 'snake',
    emoji: '🐍',
    title: 'Snake',
    subtitle: 'Habilidad',
    builder: ({
      required userId,
      required rewardsDocRef,
      required currentSaldo,
      required controller,
      required onSaldoChanged,
    }) =>
        SnakeGameScreen(
          userId: userId,
          rewardsDocRef: rewardsDocRef,
          currentSaldo: currentSaldo,
          controller: controller,
          onSaldoChanged: onSaldoChanged,
        ),
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
  late final ArcadeInputController _controller;
  late double _saldo;
  int _selectedIndex = 0;
  ArcadeGameDef? _activeGame;

  @override
  void initState() {
    super.initState();
    _controller = ArcadeInputController();
    _saldo = widget.currentSaldo;
    _controller.addListener(_handleControllerEvent);
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerEvent);
    _controller.dispose();
    super.dispose();
  }

  void _handleControllerEvent() {
    final btn = _controller.lastEvent;
    if (btn == null) return;

    if (_activeGame == null) {
      switch (btn) {
        case ArcadeButton.left:
          setState(() => _selectedIndex =
              (_selectedIndex - 1 + kArcadeGames.length) % kArcadeGames.length);
        case ArcadeButton.right:
          setState(() => _selectedIndex =
              (_selectedIndex + 1) % kArcadeGames.length);
        case ArcadeButton.a:
        case ArcadeButton.start:
          _launchSelected();
        case ArcadeButton.b:
          Navigator.pop(context);
        default:
          break;
      }
    } else {
      if (btn == ArcadeButton.b || btn == ArcadeButton.start) {
        setState(() => _activeGame = null);
      }
    }
  }

  Future<void> _launchSelected() async {
    if (_saldo < 10) return;

    final game = kArcadeGames[_selectedIndex];
    final newSaldo = _saldo - 10.0;

    final userCardRef = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .collection('rewardsCard')
        .doc('cardInfo');
    final batch = FirebaseFirestore.instance.batch();
    batch.update(userCardRef, {'saldo': newSaldo});
    batch.update(widget.rewardsDocRef, {'saldo': newSaldo});
    await batch.commit();

    if (!mounted) return;
    setState(() {
      _saldo = newSaldo;
      _activeGame = game;
    });
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(child: _buildScreenArea()),
            _buildControlsArea(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'ARCADE',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 4,
            ),
          ),
          Text(
            '💰 ${_saldo.toStringAsFixed(0)} pts',
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildScreenArea() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF333340), width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 16, offset: Offset(0, 4))
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: AspectRatio(
          aspectRatio: 10 / 16,
          child: _activeGame == null
              ? _buildGameSelector()
              : _buildActiveGame(),
        ),
      ),
    );
  }

  Widget _buildGameSelector() {
    return Container(
      color: const Color(0xFF0D1117),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'SELECT GAME',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 10,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (int i = 0; i < kArcadeGames.length; i++)
                _buildSelectorCard(kArcadeGames[i], i == _selectedIndex),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            'A / START para jugar  ·  B para salir',
            style: TextStyle(color: Colors.white30, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectorCard(ArcadeGameDef def, bool isSelected) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isSelected ? Colors.white : const Color(0xFF1C2128),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? Colors.white : const Color(0xFF30363D),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(def.emoji, style: const TextStyle(fontSize: 36)),
          const SizedBox(height: 8),
          Text(
            def.title,
            style: TextStyle(
              color: isSelected ? Colors.black : Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            def.subtitle,
            style: TextStyle(
              color: isSelected ? Colors.black54 : Colors.white38,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveGame() {
    return _activeGame!.builder(
      userId: widget.userId,
      rewardsDocRef: widget.rewardsDocRef,
      currentSaldo: _saldo,
      controller: _controller,
      onSaldoChanged: () {},
    );
  }

  // ─── Controls ──────────────────────────────────────────────────────────────

  Widget _buildControlsArea() {
    return Flexible(
      fit: FlexFit.loose,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildDPad(),
            _buildMetaButtons(),
            _buildABButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildDPad() {
    return SizedBox(
      width: 108,
      height: 108,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _DPadButton(
                icon: Icons.keyboard_arrow_up,
                btn: ArcadeButton.up,
                controller: _controller,
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _DPadButton(
                icon: Icons.keyboard_arrow_left,
                btn: ArcadeButton.left,
                controller: _controller,
              ),
              Container(
                width: 36,
                height: 36,
                color: const Color(0xFF222222),
              ),
              _DPadButton(
                icon: Icons.keyboard_arrow_right,
                btn: ArcadeButton.right,
                controller: _controller,
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _DPadButton(
                icon: Icons.keyboard_arrow_down,
                btn: ArcadeButton.down,
                controller: _controller,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetaButtons() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _MetaButton(
              label: 'SELECT',
              btn: ArcadeButton.select,
              controller: _controller,
            ),
            const SizedBox(width: 12),
            _MetaButton(
              label: 'START',
              btn: ArcadeButton.start,
              controller: _controller,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildABButtons() {
    return SizedBox(
      width: 108,
      height: 108,
      child: Stack(
        children: [
          Positioned(
            top: 16,
            right: 0,
            child: _ABButton(
              label: 'A',
              btn: ArcadeButton.a,
              color: const Color(0xFF1565C0),
              controller: _controller,
            ),
          ),
          Positioned(
            bottom: 16,
            left: 0,
            child: _ABButton(
              label: 'B',
              btn: ArcadeButton.b,
              color: const Color(0xFF880E4F),
              controller: _controller,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── D-Pad button ─────────────────────────────────────────────────────────────

class _DPadButton extends StatelessWidget {
  final IconData icon;
  final ArcadeButton btn;
  final ArcadeInputController controller;

  const _DPadButton({
    required this.icon,
    required this.btn,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => controller.press(btn),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: const Color(0xFF2D2D2D),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(icon, color: Colors.white70, size: 20),
      ),
    );
  }
}

// ─── Meta button (SELECT / START) ─────────────────────────────────────────────

class _MetaButton extends StatelessWidget {
  final String label;
  final ArcadeButton btn;
  final ArcadeInputController controller;

  const _MetaButton({
    required this.label,
    required this.btn,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => controller.press(btn),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF2D2D2D),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 9,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
      ),
    );
  }
}

// ─── A/B button ───────────────────────────────────────────────────────────────

class _ABButton extends StatelessWidget {
  final String label;
  final ArcadeButton btn;
  final Color color;
  final ArcadeInputController controller;

  const _ABButton({
    required this.label,
    required this.btn,
    required this.color,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => controller.press(btn),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.4),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}
