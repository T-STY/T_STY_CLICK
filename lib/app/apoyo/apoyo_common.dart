import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'apoyo_join_page.dart';
import 'apoyo_status_page.dart';

const Color kApoyoInk = Color(0xFF1A1A1A);
const Color kApoyoGreen = kApoyoInk;
const Color kApoyoGreenTint = Color(0xFFF4F4F4);
const Color kApoyoGreenLine = Color(0xFFE4E4E4);
const Color kApoyoAmber = Color(0xFF5A5A5A);
const Color kApoyoAmberTint = Color(0xFFF7F7F7);
const Color kApoyoAmberLine = Color(0xFFE4E4E4);
const Color kApoyoRed = Color(0xFFC62828);
const Color kApoyoRedTint = Color(0xFFFDECEC);
const Color kApoyoRedLine = Color(0xFFF2C7C7);

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

PreferredSizeWidget apoyoAppBar(
  BuildContext context, {
  VoidCallback? onBack,
  String title = 'Apoyo Social',
}) {
  final isDarkMode = Theme.of(context).brightness == Brightness.dark;
  return AppBar(
    backgroundColor: isDarkMode ? Colors.grey[900] : Colors.white,
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: false,
    automaticallyImplyLeading: false,
    leading: onBack == null
        ? null
        : IconButton(
            icon: Icon(Icons.arrow_back,
                color: isDarkMode ? Colors.white : Colors.black),
            onPressed: onBack,
            tooltip: 'Volver',
          ),
    title: Text(
      title,
      style: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: isDarkMode ? Colors.white : kApoyoInk,
      ),
    ),
  );
}

const Set<String> kApoyoTransportCodes = <String>{
  'unavailable',
  'deadline-exceeded',
  'internal',
  'unknown',
  'cancelled',
};

String apoyoCallableMessage(FirebaseFunctionsException e, String fallback) {
  final authored = !kApoyoTransportCodes.contains(e.code) &&
      (e.message ?? '').trim().isNotEmpty;
  return authored ? e.message! : fallback;
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

class ApoyoDisclosure extends StatefulWidget {
  final String title;
  final String? trailing;
  final Widget child;
  final bool initiallyOpen;

  const ApoyoDisclosure({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.initiallyOpen = false,
  });

  @override
  State<ApoyoDisclosure> createState() => _ApoyoDisclosureState();
}

class _ApoyoDisclosureState extends State<ApoyoDisclosure> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    return ApoyoCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => setState(() => _open = !_open),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 15, 14, 15),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: kApoyoInk,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ),
                    if (widget.trailing != null && !_open)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          widget.trailing!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    AnimatedRotation(
                      turns: _open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 160),
                      child: Icon(Icons.keyboard_arrow_down_rounded,
                          size: 22, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: widget.child,
            ),
            crossFadeState:
                _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 160),
            sizeCurve: Curves.easeOutCubic,
          ),
        ],
      ),
    );
  }
}

Widget apoyoSpecRow(String label, String value, {bool strong = false}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.3,
              color: Colors.grey.shade500,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              height: 1.3,
              color: strong ? kApoyoInk : Colors.grey.shade800,
              fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
  );
}

class ApoyoRulesCard extends StatelessWidget {
  final ApoyoConfig config;
  final bool initiallyOpen;
  const ApoyoRulesCard({
    super.key,
    required this.config,
    this.initiallyOpen = false,
  });

  @override
  Widget build(BuildContext context) {
    return ApoyoDisclosure(
      title: 'Cómo funciona',
      trailing: 'Cierra martes 11:59 PM',
      initiallyOpen: initiallyOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          apoyoSpecRow('Pides', 'Sábado a martes · cierra 11:59 PM'),
          apoyoSpecRow('Entrega',
              'Viernes desde 3:00 PM · ${apoyoMoney(config.deliveryFee)}'),
          apoyoSpecRow('Recoger', 'Viernes 4:00 a 7:00 PM · gratis'),
          apoyoSpecRow('Pago', 'Efectivo al recibir, monto completo',
              strong: true),
          apoyoSpecRow('Membresía', 'Una por domicilio'),
          apoyoSpecRow(
            'Primer pedido',
            config.firstOrderPickupOnly
                ? 'Hasta ${apoyoMoney(config.firstOrderMaxTotal)}, sólo en tienda'
                : 'Hasta ${apoyoMoney(config.firstOrderMaxTotal)}',
          ),
        ],
      ),
    );
  }
}

class ApoyoStrikesCard extends StatelessWidget {
  final ApoyoConfig config;
  final int? currentStrikes;
  final bool initiallyOpen;

  const ApoyoStrikesCard({
    super.key,
    required this.config,
    this.currentStrikes,
    this.initiallyOpen = false,
  });

  @override
  Widget build(BuildContext context) {
    final strikes = currentStrikes ?? 0;
    return ApoyoDisclosure(
      title: 'Si no recoges o no pagas',
      trailing: strikes > 0 ? 'Llevas $strikes' : null,
      initiallyOpen: initiallyOpen || strikes > 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          apoyoSpecRow('1 falta', 'Aviso'),
          apoyoSpecRow(
              '2 faltas', 'Suspensión de ${config.suspensionCycles} ciclos'),
          apoyoSpecRow('3 faltas', 'Baja del domicilio', strong: true),
          const SizedBox(height: 2),
          Text(
            'Tu despensa ya está comprada cuando llega el viernes.',
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (strikes > 0) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: kApoyoRedTint,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: kApoyoRedLine),
              ),
              child: Text(
                strikes == 1
                    ? 'Llevas 1 falta.'
                    : 'Llevas $strikes faltas.',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: kApoyoRed,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

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

class ApoyoSection extends StatefulWidget {
  final VoidCallback onBack;

  final VoidCallback? onAddAddress;

  const ApoyoSection({super.key, required this.onBack, this.onAddAddress});

  @override
  State<ApoyoSection> createState() => ApoyoSectionState();
}

class ApoyoSectionState extends State<ApoyoSection> {

  bool _forceJoin = false;

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

    if (uid == null) {
      return Scaffold(
        backgroundColor: Colors.white,
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
              return const Scaffold(
                backgroundColor: Colors.white,
                        body: SizedBox.shrink(),
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

class ApoyoHomeEntry extends StatelessWidget {
  final VoidCallback onTap;
  const ApoyoHomeEntry({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream:
          FirebaseFirestore.instance.doc('settings/apoyo_social').snapshots(),
      builder: (context, cfgSnap) {
        final config = ApoyoConfig.fromMap(cfgSnap.data?.data());
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream:
              FirebaseFirestore.instance.doc('apoyo_members/$uid').snapshots(),
          builder: (context, memberSnap) {
            final member = memberSnap.data?.data();
            if (!config.enabled && member == null) {
              return const SizedBox.shrink();
            }
            final status = (member?['status'] ?? '').toString();
            final String note;
            switch (status) {
              case 'aprobado':
                note = 'Haz tu pedido de la semana';
              case 'pendiente':
                note = 'Tu solicitud está en revisión';
              case 'suspendido':
                note = 'Tu acceso está suspendido';
              case 'baja':
                note = 'Diste de baja el programa';
              case 'rechazado':
                note = 'Solicitud no aceptada';
              default:
                note = 'Despensa semanal a precio de apoyo';
            }

            return Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: onTap,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(14, 13, 10, 13),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: kApoyoInk,
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: const Icon(Icons.volunteer_activism_outlined,
                              color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Apoyo Social',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: kApoyoInk,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                note,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: Colors.grey.shade600,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded,
                            color: Colors.grey.shade400, size: 22),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
