import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../constants/app_images.dart';
import 'apoyo_join_page.dart';
import 'apoyo_status_page.dart';

/// ── APOYO SOCIAL — shared pieces ────────────────────────────────────────────
///
/// The membership itself is decided entirely server-side (`applyApoyoMembership`
/// / `decideApoyoMembership`). Everything here is presentation: the program
/// rules a neighbour reads BEFORE joining, the status chip, and the router that
/// decides whether the user sees the join form or their standing.
///
/// Project convention: never a SnackBar. Every message is an AlertDialog or
/// inline text inside the card it belongs to.

// Palette — pulled from the styles already used across settings/rewards.
const Color kApoyoInk = Color(0xFF1A1A1A);
const Color kApoyoGreen = Color(0xFF2E7D32);
const Color kApoyoGreenTint = Color(0xFFE8F3EA);
const Color kApoyoGreenLine = Color(0xFFBFDCC5);
const Color kApoyoAmber = Color(0xFFB26A00);
const Color kApoyoAmberTint = Color(0xFFFFF6E5);
const Color kApoyoAmberLine = Color(0xFFF0DCB0);
const Color kApoyoRed = Color(0xFFC62828);
const Color kApoyoRedTint = Color(0xFFFDECEC);
const Color kApoyoRedLine = Color(0xFFF2C7C7);

/// Client mirror of `settings/apoyo_social`. Defaults match the Cloud
/// Functions' `APOYO_DEFAULTS`, so copy stays correct even if the settings
/// doc has not been created yet.
class ApoyoConfig {
  final bool enabled;
  final num defaultMaxOrderTotal;
  final num firstOrderMaxTotal;
  final bool firstOrderPickupOnly;
  final int suspensionCycles;
  final int strikesToBan;
  final num deliveryFee;
  final int reapplyAfterDays;
  final String storePhone;

  const ApoyoConfig({
    this.enabled = false,
    this.defaultMaxOrderTotal = 500,
    this.firstOrderMaxTotal = 250,
    this.firstOrderPickupOnly = true,
    this.suspensionCycles = 2,
    this.strikesToBan = 3,
    this.deliveryFee = 5,
    this.reapplyAfterDays = 30,
    this.storePhone = '',
  });

  factory ApoyoConfig.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const ApoyoConfig();
    const d = ApoyoConfig();
    num asNum(String k, num fallback) {
      final v = m[k];
      return v is num ? v : fallback;
    }

    int asInt(String k, int fallback) {
      final v = m[k];
      return v is num ? v.round() : fallback;
    }

    bool asBool(String k, bool fallback) {
      final v = m[k];
      return v is bool ? v : fallback;
    }

    return ApoyoConfig(
      enabled: m['enabled'] == true,
      defaultMaxOrderTotal:
          asNum('defaultMaxOrderTotal', d.defaultMaxOrderTotal),
      firstOrderMaxTotal: asNum('firstOrderMaxTotal', d.firstOrderMaxTotal),
      firstOrderPickupOnly:
          asBool('firstOrderPickupOnly', d.firstOrderPickupOnly),
      suspensionCycles: asInt('suspensionCycles', d.suspensionCycles),
      strikesToBan: asInt('strikesToBan', d.strikesToBan),
      deliveryFee: asNum('deliveryFee', d.deliveryFee),
      reapplyAfterDays: asInt('reapplyAfterDays', d.reapplyAfterDays),
      storePhone: (m['storePhone'] ?? '').toString().trim(),
    );
  }
}

/// `$500`, `$5`, `$12.50` — no trailing `.00` on whole pesos.
String apoyoMoney(num value) {
  final v = value.toDouble();
  return v == v.roundToDouble()
      ? '\$${v.round()}'
      : '\$${v.toStringAsFixed(2)}';
}

String apoyoDate(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year}';
}

/// Same logo bar every settings sub-screen uses. The back arrow is optional so
/// these pages also work when pushed as a standalone route.
PreferredSizeWidget apoyoAppBar(BuildContext context, {VoidCallback? onBack}) {
  final isDarkMode = Theme.of(context).brightness == Brightness.dark;
  return AppBar(
    backgroundColor: isDarkMode ? Colors.grey[900] : Colors.white,
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: true,
    automaticallyImplyLeading: false,
    leading: onBack == null
        ? null
        : IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: onBack,
            tooltip: 'Volver',
          ),
    title: SizedBox(
      height: 150,
      width: 250,
      child: Image.asset(
        isDarkMode ? AppImages.logowhite : AppImages.logo,
        fit: BoxFit.contain,
      ),
    ),
  );
}

Future<void> apoyoAlert(
  BuildContext context, {
  required String title,
  required String message,
  String actionLabel = 'Entendido',
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(actionLabel),
        ),
      ],
    ),
  );
}

/// White rounded card matching the "Agregar cupón" card in coupons_section.
class ApoyoCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;

  const ApoyoCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor ?? Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// 42×42 tinted icon tile — same shape as the VIP enroll card in rewards.
class ApoyoIconTile extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final Color line;
  final Color color;

  const ApoyoIconTile({
    super.key,
    required this.icon,
    this.tint = kApoyoGreenTint,
    this.line = kApoyoGreenLine,
    this.color = kApoyoGreen,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: line),
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }
}

Widget apoyoSectionLabel(String text) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: Colors.grey[500],
      ),
    ),
  );
}

Widget apoyoCardTitle(String text) {
  return Text(
    text,
    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
  );
}

Widget apoyoBody(String text, {Color? color}) {
  return Text(
    text,
    style: TextStyle(
      fontSize: 12.5,
      height: 1.35,
      color: color ?? Colors.grey[700],
    ),
  );
}

/// One rule line: icon + text. Bold when the rule is one a member gets hurt by
/// forgetting (cash complete, strikes).
Widget apoyoRule(
  IconData icon,
  String text, {
  Color? iconColor,
  bool strong = false,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: iconColor ?? Colors.grey[600]),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.35,
              fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
              color: strong ? Colors.black87 : Colors.grey[800],
            ),
          ),
        ),
      ],
    ),
  );
}

/// The program, in full. Shown on the join screen AND kept on the status
/// screen — a member should never have to remember a rule from a screen they
/// saw once.
class ApoyoRulesCard extends StatelessWidget {
  final ApoyoConfig config;
  const ApoyoRulesCard({super.key, required this.config});

  @override
  Widget build(BuildContext context) {
    return ApoyoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          apoyoCardTitle('Cómo funciona'),
          const SizedBox(height: 12),
          apoyoRule(
            Icons.calendar_month_outlined,
            'Pides de sábado a martes. El pedido cierra el martes a las '
            '11:59 PM.',
          ),
          apoyoRule(
            Icons.local_shipping_outlined,
            'Te lo llevamos el viernes después de las 3:00 PM por '
            '${apoyoMoney(config.deliveryFee)} de entrega.',
          ),
          apoyoRule(
            Icons.storefront_outlined,
            'O lo recoges gratis en la tienda el viernes de 4:00 a 7:00 PM.',
          ),
          apoyoRule(
            Icons.payments_outlined,
            'Pagas en EFECTIVO al recibir. No te cobramos nada por adelantado.',
            strong: true,
          ),
          apoyoRule(
            Icons.report_gmailerrorred_outlined,
            'El monto debe ir COMPLETO. Si falta dinero, no se entrega.',
            iconColor: kApoyoAmber,
            strong: true,
          ),
          apoyoRule(
            Icons.home_outlined,
            'Una membresía por domicilio.',
          ),
          apoyoRule(
            Icons.looks_one_outlined,
            config.firstOrderPickupOnly
                ? 'Tu primer pedido: máximo '
                    '${apoyoMoney(config.firstOrderMaxTotal)} y sólo para '
                    'recoger en la tienda.'
                : 'Tu primer pedido: máximo '
                    '${apoyoMoney(config.firstOrderMaxTotal)}.',
          ),
        ],
      ),
    );
  }
}

/// The strikes ladder. Deliberately loud and deliberately shown BEFORE
/// joining — a member must never discover this on the Friday they miss.
class ApoyoStrikesCard extends StatelessWidget {
  final ApoyoConfig config;
  final int? currentStrikes;

  const ApoyoStrikesCard({
    super.key,
    required this.config,
    this.currentStrikes,
  });

  @override
  Widget build(BuildContext context) {
    final strikes = currentStrikes ?? 0;
    return ApoyoCard(
      color: kApoyoAmberTint,
      borderColor: kApoyoAmberLine,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.gpp_maybe_outlined,
                  size: 20, color: kApoyoAmber),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Si no recoges o no pagas',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.brown.shade900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _step('1 falta', 'Te damos un aviso.'),
          _step('2 faltas', 'Suspensión de ${config.suspensionCycles} ciclos.'),
          _step('${config.strikesToBan} faltas',
              'Baja definitiva del domicilio.'),
          const SizedBox(height: 4),
          Text(
            'La comida ya está comprada cuando llega el viernes. Por eso una '
            'baja cierra el programa para todo el domicilio, no sólo para una '
            'persona.',
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: Colors.brown.shade700,
            ),
          ),
          if (strikes > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: kApoyoAmberLine),
              ),
              child: Text(
                strikes == 1
                    ? 'Tienes 1 falta registrada.'
                    : 'Tienes $strikes faltas registradas.',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: kApoyoAmber,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _step(String label, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: kApoyoAmberLine),
            ),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: kApoyoAmber,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.3,
                  color: Colors.brown.shade900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Human label + colour for an `apoyo_members.status`.
class ApoyoStatusStyle {
  final String label;
  final Color color;
  final Color tint;
  final Color line;
  final IconData icon;

  const ApoyoStatusStyle(
      this.label, this.color, this.tint, this.line, this.icon);

  static ApoyoStatusStyle of(String? status) {
    switch (status) {
      case 'pendiente':
        return const ApoyoStatusStyle('En revisión', kApoyoAmber,
            kApoyoAmberTint, kApoyoAmberLine, Icons.hourglass_top_outlined);
      case 'aprobado':
        return const ApoyoStatusStyle('Miembro activo', kApoyoGreen,
            kApoyoGreenTint, kApoyoGreenLine, Icons.verified_outlined);
      case 'suspendido':
        return const ApoyoStatusStyle('Suspendido', kApoyoAmber,
            kApoyoAmberTint, kApoyoAmberLine, Icons.pause_circle_outline);
      case 'rechazado':
        return const ApoyoStatusStyle('No aceptado', kApoyoRed, kApoyoRedTint,
            kApoyoRedLine, Icons.info_outline);
      case 'baja':
        return const ApoyoStatusStyle('Dado de baja', kApoyoRed, kApoyoRedTint,
            kApoyoRedLine, Icons.block_outlined);
      default:
        return ApoyoStatusStyle('Sin solicitud', Colors.grey.shade600,
            Colors.grey.shade100, Colors.grey.shade300, Icons.help_outline);
    }
  }
}

class ApoyoStatusChip extends StatelessWidget {
  final String? status;
  const ApoyoStatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final s = ApoyoStatusStyle.of(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: s.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        s.label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: s.color,
        ),
      ),
    );
  }
}

/// Entry point used by SettingsPage: streams the program config and the user's
/// own membership row, then shows the join form or their standing.
///
/// `apoyo_members/{uid}` is readable only by that user (and admins), so this
/// stream is safe for every signed-in account — a non-member simply gets a
/// non-existent doc.
class ApoyoSection extends StatefulWidget {
  final VoidCallback onBack;

  /// Called when the user has no address yet — SettingsPage swaps to its
  /// addresses tab instead of dead-ending the flow.
  final VoidCallback? onAddAddress;

  const ApoyoSection({super.key, required this.onBack, this.onAddAddress});

  @override
  State<ApoyoSection> createState() => ApoyoSectionState();
}

/// Public so SettingsPage can reach [handleBack] through a GlobalKey — the
/// same pattern MainMenuScreen already uses for Home/Cart/Recetas.
///
/// This page deliberately has NO PopScope of its own. It lives inside
/// SettingsPage's IndexedStack, which builds every section whether or not it
/// is the visible one, so a PopScope here would register on the enclosing
/// ModalRoute permanently: `ModalRoute.popDisposition` returns `doNotPop` if
/// ANY registered entry says so, and `onPopInvokedWithResult` fires on ALL of
/// them. An invisible section would then answer the Android back button.
class ApoyoSectionState extends State<ApoyoSection> {
  /// A rejected member who taps "Solicitar de nuevo" — the doc still exists,
  /// so the router needs an explicit override to show the form again.
  bool _forceJoin = false;

  /// Back-button hook for SettingsPage. Returns true when this section
  /// consumed the press (the re-apply form steps back to the status screen)
  /// and false when the caller should leave the section.
  bool handleBack() {
    if (_forceJoin) {
      setState(() => _forceJoin = false);
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    // Signed out: bail before opening any listener. SettingsPage keeps this
    // page alive inside its IndexedStack even on the login screen, and both
    // `settings/apoyo_social` and `apoyo_members/{uid}` require auth.
    if (uid == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: apoyoAppBar(context, onBack: widget.onBack),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Inicia sesión para ver el Apoyo Social.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Colors.grey[600]),
            ),
          ),
        ),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream:
          FirebaseFirestore.instance.doc('settings/apoyo_social').snapshots(),
      builder: (context, cfgSnap) {
        final config = ApoyoConfig.fromMap(cfgSnap.data?.data());

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream:
              FirebaseFirestore.instance.doc('apoyo_members/$uid').snapshots(),
          builder: (context, memberSnap) {
            if (memberSnap.connectionState == ConnectionState.waiting &&
                !memberSnap.hasData) {
              return Scaffold(
                backgroundColor: Colors.white,
                appBar: apoyoAppBar(context, onBack: widget.onBack),
                body: const SizedBox.shrink(),
              );
            }

            final member = memberSnap.data?.data();
            final showJoin = member == null || _forceJoin;

            if (showJoin) {
              return ApoyoJoinPage(
                config: config,
                previous: member,
                onBack: () {
                  if (_forceJoin) {
                    setState(() => _forceJoin = false);
                  } else {
                    widget.onBack();
                  }
                },
                onAddAddress: widget.onAddAddress,
                onSubmitted: () {
                  // The member doc now exists → this builder swaps to the
                  // status screen on the next snapshot.
                  if (mounted) setState(() => _forceJoin = false);
                },
              );
            }

            return ApoyoStatusPage(
              config: config,
              member: member,
              onBack: widget.onBack,
              onReapply: () => setState(() => _forceJoin = true),
            );
          },
        );
      },
    );
  }
}
