import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

const String kTstyAppQrPrefix = 'TSTYAPP:';

String buildLoyaltyQrPayload(String phoneDigits) {
  return '$kTstyAppQrPrefix$phoneDigits';
}

class CochinitoCard extends StatefulWidget {
  final double saldo;
  final String phoneDigits;
  final String holder;
  final String nip;
  final bool showNipReveal;

  final bool enableQrFlip;

  final String? qrToken;

  final bool isVip;

  const CochinitoCard({
    super.key,
    required this.saldo,
    required this.phoneDigits,
    required this.holder,
    required this.nip,
    this.showNipReveal = false,
    this.enableQrFlip = false,
    this.qrToken,
    this.isVip = false,
  });

  @override
  State<CochinitoCard> createState() => _CochinitoCardState();
}

class _CochinitoCardState extends State<CochinitoCard>
    with SingleTickerProviderStateMixin {
  static const Duration _flipDuration = Duration(milliseconds: 520);

  late final AnimationController _flipCtrl;
  late final Animation<double> _flipAnim;

  bool _showBack = false;

  bool _nipRevealed = false;

  @override
  void initState() {
    super.initState();
    _flipCtrl = AnimationController(vsync: this, duration: _flipDuration);
    _flipAnim = CurvedAnimation(
      parent: _flipCtrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void dispose() {
    _flipCtrl.dispose();
    super.dispose();
  }

  void _toggleFlip() {
    if (!widget.enableQrFlip) return;
    setState(() => _showBack = !_showBack);
    if (_showBack) {
      _flipCtrl.forward();
    } else {
      _flipCtrl.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {

    return AnimatedBuilder(
      animation: _flipAnim,
      builder: (context, _) {
        final t = _flipAnim.value;
        final angle = t * math.pi;
        final isFront = angle <= math.pi / 2;

        final lift = math.sin(angle) * 6;
        final scale = 1.0 - math.sin(angle) * 0.04;

        return Transform.translate(
          offset: Offset(0, -lift),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0012)
              ..rotateY(angle)
              ..scaleByDouble(scale, scale, 1.0, 1.0),
            child: isFront
                ? _CardShell(
                    child: _Front(
                      saldo: widget.saldo,
                      phoneDigits: widget.phoneDigits,
                      holder: widget.holder,
                      nip: widget.nip,
                      showNipReveal:
                          widget.showNipReveal && widget.nip.isNotEmpty,
                      nipRevealed: _nipRevealed,
                      onToggleNip: () =>
                          setState(() => _nipRevealed = !_nipRevealed),
                      enableQrFlip: widget.enableQrFlip,
                      onFlip: _toggleFlip,
                    ),
                  )

                : Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()..rotateY(math.pi),
                    child: _CardShell(
                      child: GestureDetector(
                        onTap: _toggleFlip,
                        behavior: HitTestBehavior.opaque,
                        child: _Back(
                          phoneDigits: widget.phoneDigits,
                          qrToken: widget.qrToken,
                          isVip: widget.isVip,
                        ),
                      ),
                    ),
                  ),
          ),
        );
      },
    );
  }
}

class _CardShell extends StatelessWidget {
  final Widget child;
  const _CardShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF141414), Color(0xFF3A3A3A)],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _Front extends StatelessWidget {
  final double saldo;
  final String phoneDigits;
  final String holder;
  final String nip;
  final bool showNipReveal;
  final bool nipRevealed;
  final VoidCallback onToggleNip;
  final bool enableQrFlip;
  final VoidCallback onFlip;

  const _Front({
    required this.saldo,
    required this.phoneDigits,
    required this.holder,
    required this.nip,
    required this.showNipReveal,
    required this.nipRevealed,
    required this.onToggleNip,
    required this.enableQrFlip,
    required this.onFlip,
  });

  String _formatPhone() {
    final d = phoneDigits.replaceAll(RegExp(r'\D'), '');
    if (d.length == 10) {
      return '${d.substring(0, 3)} ${d.substring(3, 6)} ${d.substring(6)}';
    }
    return d.isEmpty ? '••• ••• ••••' : d;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(top: -34, right: -24, child: _decorCircle(130, 0.06)),
        Positioned(bottom: -56, right: 48, child: _decorCircle(150, 0.05)),
        Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.savings,
                            color: Colors.white, size: 18),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Cochinito',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'T_STY',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2.5,

                          height: 1.0,
                        ),
                      ),
                      if (enableQrFlip) ...[
                        const SizedBox(height: 4),
                        _FlipChip(onTap: onFlip),
                      ],
                    ],
                  ),
                ],
              ),
              const Spacer(),
              const Text(
                'Saldo disponible',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
              const SizedBox(height: 2),
              Text(
                '\$${saldo.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _formatPhone(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          (holder.isEmpty ? 'TITULAR' : holder).toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (showNipReveal)
                    GestureDetector(
                      onTap: onToggleNip,
                      behavior: HitTestBehavior.opaque,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'NIP ${nipRevealed ? nip : '••••'}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Icon(
                            nipRevealed
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: Colors.white54,
                            size: 16,
                          ),
                        ],
                      ),
                    )
                  else
                    Text(
                      'NIP ${nip.isEmpty ? '••••' : nip}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _decorCircle(double size, double alpha) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: alpha),
        ),
      );
}

class _FlipChip extends StatelessWidget {
  final VoidCallback onTap;
  const _FlipChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: const Padding(

          padding: EdgeInsets.symmetric(horizontal: 9, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.qr_code_2_rounded,
                  color: Colors.white, size: 12),
              SizedBox(width: 4),
              Text(
                'QR',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Back extends StatelessWidget {
  final String phoneDigits;
  final String? qrToken;
  final bool isVip;
  const _Back({
    required this.phoneDigits,
    this.qrToken,
    this.isVip = false,
  });

  @override
  Widget build(BuildContext context) {

    final payload = (qrToken != null && qrToken!.isNotEmpty)
        ? qrToken!
        : buildLoyaltyQrPayload(phoneDigits);

    return Stack(
      children: [

        Positioned(top: -34, right: -24, child: _ghostCircle(130, 0.06)),
        Positioned(bottom: -56, right: 48, child: _ghostCircle(150, 0.05)),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Row(
            children: [

              Container(
                width: 168,
                height: 168,

                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.22),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: QrImageView(
                  data: payload,
                  version: QrVersions.auto,

                  errorCorrectionLevel: QrErrorCorrectLevel.H,
                  backgroundColor: Colors.white,

                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Color(0xFF141414),
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Color(0xFF141414),
                  ),
                  gapless: true,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [

                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: isVip
                                ? const Color(0xFFFFD54F)
                                    .withValues(alpha: 0.22)
                                : Colors.white.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.workspace_premium_rounded,
                            color: isVip
                                ? const Color(0xFFFFD54F)
                                : Colors.white,
                            size: 14,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Cliente VIP',
                          style: TextStyle(
                            color: isVip
                                ? const Color(0xFFFFD54F)
                                : Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Muestra este código\nen caja para ganar\n+50 % de puntos.',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        height: 1.3,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Toca para volver',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _ghostCircle(double size, double alpha) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: alpha),
        ),
      );
}
