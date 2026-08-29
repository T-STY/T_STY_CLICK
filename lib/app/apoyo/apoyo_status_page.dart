import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../components/bottom_fade.dart';
import '../../utils/phone_format.dart';
import 'apoyo_common.dart';
import 'apoyo_order_section.dart';

/// ── APOYO SOCIAL — status ───────────────────────────────────────────────────
///
/// Renders `apoyo_members/{uid}` (streamed by [ApoyoSection]) for every status
/// the server can set. The rules card stays on this screen too: a member who
/// joined weeks ago should be able to re-read how the cycle works without
/// hunting for the sign-up flow they can no longer reach.
///
/// The week itself — the open cycle, the member's order for it, and the way
/// in and out while it is open — lives in [ApoyoOrderSection], which is the
/// only part of this screen with listeners of its own.
class ApoyoStatusPage extends StatelessWidget {
  final ApoyoConfig config;
  final Map<String, dynamic> member;
  final VoidCallback? onBack;

  /// Rejected members only: switches back to the join form.
  final VoidCallback? onReapply;

  const ApoyoStatusPage({
    super.key,
    required this.config,
    required this.member,
    this.onBack,
    this.onReapply,
  });

  String get _status => (member['status'] ?? '').toString();

  int get _strikes => (member['strikes'] as num?)?.toInt() ?? 0;

  String get _reason => (member['decisionReason'] ?? '').toString().trim();

  DateTime? get _decidedAt {
    final v = member['decidedAt'];
    return v is Timestamp ? v.toDate().toLocal() : null;
  }

  /// The server re-checks this; here it only decides whether the button reads
  /// "Solicitar de nuevo" or tells them the date they can.
  DateTime? get _reapplyDate {
    final decided = _decidedAt;
    if (decided == null) return null;
    return decided.add(Duration(days: config.reapplyAfterDays));
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDarkMode ? Colors.grey[900] : Colors.white,
      body: BottomFade(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 150),
          children: [
            _headerCard(),
            const SizedBox(height: 14),
            ..._statusBody(context),
          ],
        ),
      ),
    );
  }

  // ── header ────────────────────────────────────────────────────────────────

  Widget _headerCard() {
    final s = ApoyoStatusStyle.of(_status);
    return ApoyoCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ApoyoIconTile(
            icon: s.icon,
            tint: s.tint,
            line: s.line,
            color: s.color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Apoyo Social',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800),
                      ),
                    ),
                    ApoyoStatusChip(status: _status),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _headline(),
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _headline() {
    switch (_status) {
      case 'pendiente':
        return 'Tu solicitud está en revisión.';
      case 'aprobado':
        return 'Ya eres parte del programa.';
      case 'suspendido':
        return 'Tu acceso está suspendido por ahora.';
      case 'rechazado':
        return 'Por ahora no pudimos aceptarte.';
      case 'baja':
        return 'Tu acceso al programa fue dado de baja.';
      default:
        return 'Aquí verás el estado de tu membresía.';
    }
  }

  // ── per-status body ───────────────────────────────────────────────────────

  List<Widget> _statusBody(BuildContext context) {
    switch (_status) {
      case 'pendiente':
        return [
          _messageCard(
            icon: Icons.hourglass_top_outlined,
            title: 'Tu solicitud está en revisión',
            body: 'La tienda revisa cada solicitud a mano. En cuanto haya una '
                'respuesta te llega una notificación al teléfono, aquí mismo '
                'en la app. No necesitas hacer nada más ni volver a '
                'registrarte.',
            tint: kApoyoAmberTint,
            line: kApoyoAmberLine,
            accent: kApoyoAmber,
          ),
          const SizedBox(height: 14),
          _submittedDataCard(),
          const SizedBox(height: 22),
          apoyoSectionLabel('El programa'),
          ApoyoRulesCard(config: config),
          const SizedBox(height: 14),
          ApoyoStrikesCard(config: config, currentStrikes: _strikes),
          ..._storePhoneBlock(),
        ];

      case 'aprobado':
        return [
          _messageCard(
            icon: Icons.celebration_outlined,
            title: '¡Bienvenido al Apoyo Social!',
            body: 'Ya puedes pedir en cada ciclo. Pides de sábado a martes, '
                'cierra el martes a las 11:59 PM, y lo recibes el viernes.',
            tint: kApoyoGreenTint,
            line: kApoyoGreenLine,
            accent: kApoyoGreen,
          ),
          if (member['firstOrderDone'] != true) ...[
            const SizedBox(height: 14),
            _firstOrderCard(),
          ],
          const SizedBox(height: 14),
          _limitCard(),
          const SizedBox(height: 22),
          apoyoSectionLabel('Tu pedido'),
          ApoyoOrderSection(config: config, member: member),
          const SizedBox(height: 22),
          apoyoSectionLabel('El programa'),
          ApoyoRulesCard(config: config),
          const SizedBox(height: 14),
          ApoyoStrikesCard(config: config, currentStrikes: _strikes),
          ..._storePhoneBlock(),
        ];

      case 'suspendido':
        return [
          _messageCard(
            icon: Icons.pause_circle_outline,
            title: 'Tu acceso está suspendido',
            body: 'No puedes pedir durante '
                '${_suspensionCycles()} ${_suspensionCycles() == 1 ? 'ciclo' : 'ciclos'}. '
                'Después de eso la tienda puede reactivarte.'
                '${_reason.isEmpty ? '' : '\n\nMotivo: $_reason'}',
            tint: kApoyoAmberTint,
            line: kApoyoAmberLine,
            accent: kApoyoAmber,
          ),
          const SizedBox(height: 14),
          ApoyoStrikesCard(config: config, currentStrikes: _strikes),
          const SizedBox(height: 22),
          apoyoSectionLabel('El programa'),
          ApoyoRulesCard(config: config),
          ..._storePhoneBlock(),
        ];

      case 'rechazado':
        return [
          _messageCard(
            icon: Icons.info_outline,
            title: 'Por ahora no pudimos aceptarte',
            body: _reason.isEmpty
                ? 'La tienda revisó tu solicitud y por ahora no pudo '
                    'aceptarte en el programa. No es definitivo.'
                : 'La tienda revisó tu solicitud y por ahora no pudo '
                    'aceptarte.\n\nMotivo: $_reason',
            tint: kApoyoRedTint,
            line: kApoyoRedLine,
            accent: kApoyoRed,
          ),
          const SizedBox(height: 14),
          _reapplyCard(),
          ..._storePhoneBlock(),
        ];

      case 'baja':
        return [
          _messageCard(
            icon: Icons.block_outlined,
            title: 'Baja del programa',
            body: 'Tu acceso al Apoyo Social fue dado de baja y el domicilio '
                'ya no puede participar.'
                '${_reason.isEmpty ? '' : '\n\nMotivo: $_reason'}'
                '\n\nSi crees que es un error, habla con la tienda.',
            tint: kApoyoRedTint,
            line: kApoyoRedLine,
            accent: kApoyoRed,
          ),
          ..._storePhoneBlock(),
        ];

      default:
        return [
          _messageCard(
            icon: Icons.help_outline,
            title: 'Estado no disponible',
            body: 'No pudimos leer el estado de tu membresía. Intenta más '
                'tarde o habla con la tienda.',
            tint: Colors.grey.shade100,
            line: Colors.grey.shade300,
            accent: Colors.grey.shade700,
          ),
          ..._storePhoneBlock(),
        ];
    }
  }

  int _suspensionCycles() {
    final v = member['suspensionCycles'];
    if (v is num && v > 0) return v.round();
    return config.suspensionCycles;
  }

  // ── pieces ────────────────────────────────────────────────────────────────

  Widget _messageCard({
    required IconData icon,
    required String title,
    required String body,
    required Color tint,
    required Color line,
    required Color accent,
  }) {
    return ApoyoCard(
      color: tint,
      borderColor: line,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(
              fontSize: 13,
              height: 1.4,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  /// What the user actually sent — so a pending member can check they typed
  /// the right phone without digging through the form again.
  Widget _submittedDataCard() {
    final phone = (member['phone'] ?? '').toString();
    final address = [
      (member['addressLine'] ?? '').toString().trim(),
      (member['colonia'] ?? '').toString().trim(),
    ].where((s) => s.isNotEmpty).join(', ');
    final note = (member['note'] ?? '').toString().trim();
    final applied = member['appliedAt'];

    return ApoyoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          apoyoCardTitle('Lo que enviaste'),
          const SizedBox(height: 12),
          if (address.isNotEmpty)
            apoyoRule(Icons.location_on_outlined, address),
          if (phone.isNotEmpty)
            apoyoRule(Icons.phone_android, formatMxPhone(phone)),
          if (note.isNotEmpty) apoyoRule(Icons.sticky_note_2_outlined, note),
          if (applied is Timestamp)
            apoyoRule(Icons.event_outlined,
                'Enviada el ${apoyoDate(applied.toDate().toLocal())}'),
          const SizedBox(height: 2),
          apoyoBody(
              '¿Algún dato quedó mal? Habla con la tienda antes de que '
              'revisen tu solicitud.'),
        ],
      ),
    );
  }

  Widget _firstOrderCard() {
    return ApoyoCard(
      color: kApoyoAmberTint,
      borderColor: kApoyoAmberLine,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.looks_one_outlined,
                  size: 20, color: kApoyoAmber),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Tu primer pedido',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: kApoyoInk,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            config.firstOrderPickupOnly || member['forcePickup'] == true
                ? 'El primero es de máximo '
                    '${apoyoMoney(config.firstOrderMaxTotal)} y sólo para '
                    'RECOGER en la tienda: el viernes de 4:00 a 7:00 PM. '
                    'A partir del segundo pedido puedes pedir entrega a '
                    'domicilio por ${apoyoMoney(config.deliveryFee)}.'
                : 'El primero es de máximo '
                    '${apoyoMoney(config.firstOrderMaxTotal)}.',
            style: const TextStyle(
              fontSize: 13,
              height: 1.4,
              color: kApoyoInk,
            ),
          ),
        ],
      ),
    );
  }

  Widget _limitCard() {
    final custom = member['maxOrderTotal'];
    final limit = custom is num ? custom : config.defaultMaxOrderTotal;
    final delivered = (member['cyclesDelivered'] as num?)?.toInt() ?? 0;

    return ApoyoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          apoyoCardTitle('Tu membresía'),
          const SizedBox(height: 12),
          apoyoRule(Icons.account_balance_wallet_outlined,
              'Límite por pedido: ${apoyoMoney(limit)}.'),
          apoyoRule(Icons.payments_outlined,
              'Pagas en efectivo al recibir, con el monto completo.'),
          if (delivered > 0)
            apoyoRule(
                Icons.check_circle_outline,
                delivered == 1
                    ? 'Llevas 1 entrega recibida.'
                    : 'Llevas $delivered entregas recibidas.',
                iconColor: kApoyoGreen),
          if (_strikes > 0)
            apoyoRule(
              Icons.gpp_maybe_outlined,
              _strikes == 1
                  ? 'Tienes 1 falta. Con ${config.strikesToBan} se da de baja '
                      'el domicilio.'
                  : 'Tienes $_strikes faltas. Con ${config.strikesToBan} se da '
                      'de baja el domicilio.',
              iconColor: kApoyoAmber,
              strong: true,
            ),
        ],
      ),
    );
  }

  Widget _reapplyCard() {
    final when = _reapplyDate;
    final canReapply = when == null || !DateTime.now().isBefore(when);
    final waitText = when == null
        ? ''
        : 'Sí, pero hay que esperar. Podrás enviar una nueva solicitud a '
            'partir del ${apoyoDate(when)}.';

    return ApoyoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          apoyoCardTitle('¿Puedo intentar otra vez?'),
          const SizedBox(height: 6),
          apoyoBody(
            canReapply
                ? 'Sí. Puedes enviar una nueva solicitud cuando quieras.'
                : waitText,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: canReapply ? onReapply : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: kApoyoInk,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                disabledForegroundColor: Colors.grey.shade600,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text(
                'Solicitar de nuevo',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _storePhoneBlock() {
    if (config.storePhone.isEmpty) return const [];
    return [
      const SizedBox(height: 14),
      ApoyoCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(Icons.store_outlined, size: 18, color: Colors.grey[600]),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '¿Dudas? Llama a la tienda: ${config.storePhone}',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.3,
                  color: Colors.grey[700],
                ),
              ),
            ),
          ],
        ),
      ),
    ];
  }
}
