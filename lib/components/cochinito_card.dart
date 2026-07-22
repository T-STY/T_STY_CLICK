import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// QR-code prefix carried on every app-rendered loyalty QR.
///
/// The PDV scans this exact string and uses it to distinguish:
///   - "TSTYAPP:<10-digit-phone>"  → app user, accrues at the boosted rate
///                                  (1.5%) because they're using the app's
///                                  in-card QR instead of a phone lookup.
///   - bare "<10-digit-phone>"     → walk-in / phone lookup, base rate (1%).
///
/// Keep this constant identical on the PDV side. If we ever need a v2 layout
/// (e.g. extra signing), bump to `TSTYAPP2:` and keep this one understood
/// for back-compat.
const String kTstyAppQrPrefix = 'TSTYAPP:';

/// Build the full payload string the QR encodes. Centralised so both the
/// client (encode) and PDV (decode) sides agree on the exact format.
String buildLoyaltyQrPayload(String phoneDigits) {
  return '$kTstyAppQrPrefix$phoneDigits';
}

/// The dark cochinito "card" used in two screens:
///   1. The active wallet (`rewards.dart`) — tap to flip to the QR on the
///      back. Reads real `saldo`, `nip`, `phone`, `holder` from Firestore.
///   2. The create-wallet preview (`create_new_card.dart`) — live preview of
///      the values the user is typing. No flip, no QR (we have no phone yet
///      to encode).
///
/// `phoneDigits` MUST be ten ASCII digits when [enableQrFlip] is true — that
/// is what the QR payload is built from. If the field is shorter (still
/// being typed in the create-card preview) keep [enableQrFlip] false so the
/// QR side never renders.
class CochinitoCard extends StatefulWidget {
  final double saldo;
  final String phoneDigits;
  final String holder;
  final String nip;
  final bool showNipReveal;

  /// When false the card is static (used as a typing-preview); when true a
  /// tap on the card flips to the QR back face and a second tap flips back.
  final bool enableQrFlip;

  /// VIP wallet token (`TSTYV1.…`) minted by the enrollVip CF. When present
  /// the QR encodes THIS opaque signed token instead of the legacy
  /// `TSTYAPP:<phone>` payload — unguessable and verified server-side by
  /// the PDV.
  final String? qrToken;

  /// Persisted VIP status (rewards doc `isVip`, mirrored on cardInfo) —
  /// drives the gold treatment on the back face.
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

  /// True once the user has tapped to expose the back side. We also expose
  /// the underlying [_flipCtrl] to drive the perspective math directly so
  /// the lift/scale curve sits on the same timeline as the rotation.
  bool _showBack = false;

  // NIP reveal sits on the front face only; safe to keep as private state.
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
    // The outer GestureDetector used to wrap the whole card with
    // `onTap: _toggleFlip`. That ate every tap before child detectors
    // could see it — so the NIP-reveal eye underneath stopped working.
    // The flip is now driven by a dedicated chip on each face, leaving
    // inner detectors (NIP) to claim their own taps cleanly.
    return AnimatedBuilder(
      animation: _flipAnim,
      builder: (context, _) {
        final t = _flipAnim.value;
        final angle = t * math.pi;
        final isFront = angle <= math.pi / 2;

        // Subtle lift + scale during the half-flip so the card feels like
        // it's coming up off the screen rather than just spinning flat.
        final lift = math.sin(angle) * 6;
        final scale = 1.0 - math.sin(angle) * 0.04;

        return Transform.translate(
          offset: Offset(0, -lift),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0012) // perspective
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
                // The back face has to be flipped 180° about Y so the QR
                // reads the right way around once the Matrix rotation
                // brings it forward. Tapping the back flips back to the
                // front (no inner detectors to compete with here).
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

// ---------------------------------------------------------------------------
// Outer shell — same dimensions / gradient / shadow on both faces.
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Front face — title strip + saldo + phone/holder + NIP reveal.
// ---------------------------------------------------------------------------

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
              // Title row
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
                          // Crunch the leading so the chip below has
                          // somewhere to sit without making this column
                          // taller than the original T_STY-only row.
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

/// Small "QR" pill that lives next to the T_STY wordmark in the title row.
/// Tap-to-flip-the-card. The whole flip behaviour now hangs off this widget
/// instead of a card-wide GestureDetector, so the NIP-reveal eye on the
/// bottom-right keeps its own taps.
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
          // Tighter vertical padding so the chip + T_STY column stays
          // close to the original T_STY-only height. The 200 px card has
          // no spare room and this is the only place the new height
          // came from.
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

// ---------------------------------------------------------------------------
// Back face — QR + bunny animation + caption.
// ---------------------------------------------------------------------------

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
    // Enrolled VIPs carry the signed token; everyone else keeps the legacy
    // phone payload the PDV has always understood.
    final payload = (qrToken != null && qrToken!.isNotEmpty)
        ? qrToken!
        : buildLoyaltyQrPayload(phoneDigits);

    return Stack(
      children: [
        // Same decorative circles as the front so the back doesn't feel like
        // a different card.
        Positioned(top: -34, right: -24, child: _ghostCircle(130, 0.06)),
        Positioned(bottom: -56, right: 48, child: _ghostCircle(150, 0.05)),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Row(
            children: [
              // White QR tile — needs a light surface so dark modules read.
              Container(
                width: 168,
                height: 168,
                // Inner padding doubles as the QR "quiet zone". The spec
                // wants ~4 modules of clear margin around the matrix for
                // reliable scanning; 16 px gives roughly that at our
                // module size. The previous 8 px left handheld barcode
                // scanners refusing the code.
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
                  // Higher error correction so partial occlusion or
                  // imperfect focus still resolves.
                  errorCorrectionLevel: QrErrorCorrectLevel.H,
                  backgroundColor: Colors.white,
                  // Square eyes + square modules. The previous circle
                  // style looked nicer but laser/CCD handheld scanners
                  // read by detecting sharp cell-edge transitions, and
                  // circles leave corner gaps that break the cell grid.
                  // The card still feels distinct thanks to the rounded
                  // white tile + decorative ring overlays.
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
                    // VIP badge — small star icon + label. Bunny moved
                    // into the QR centre, so the right column is text-only
                    // now and we keep a tiny glyph here so the heading
                    // doesn't sit bare on the dark background.
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
