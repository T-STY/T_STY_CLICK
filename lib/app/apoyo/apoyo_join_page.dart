import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../components/bottom_fade.dart';
import '../../utils/phone_format.dart';
import '../settings/addresses_section.dart';
import 'apoyo_common.dart';

/// ── APOYO SOCIAL — join ─────────────────────────────────────────────────────
///
/// This screen is the ONLY place a neighbour learns the rules of the program,
/// so everything that can cost them later — cash on delivery, the exact
/// amount, the strikes ladder — is on-screen and readable BEFORE the button
/// they press to join, never behind a tap.
///
/// The server (`applyApoyoMembership`) re-checks every gate and returns a
/// finished Spanish sentence for each rejection; we render `e.message` as-is.
class ApoyoJoinPage extends StatefulWidget {
  final ApoyoConfig config;

  /// Existing membership row, when the user was rejected and is applying
  /// again. Used only to explain the previous decision.
  final Map<String, dynamic>? previous;

  final VoidCallback? onBack;

  /// Sends the user to the addresses screen. When null, this page pushes the
  /// addresses screen itself — a user without an address must never dead-end.
  final VoidCallback? onAddAddress;

  final VoidCallback? onSubmitted;

  const ApoyoJoinPage({
    super.key,
    required this.config,
    this.previous,
    this.onBack,
    this.onAddAddress,
    this.onSubmitted,
  });

  @override
  State<ApoyoJoinPage> createState() => _ApoyoJoinPageState();
}

class _ApoyoJoinPageState extends State<ApoyoJoinPage> {
  final _phoneCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  String? _selectedAddressId;
  bool _accepted = false;

  /// Re-entrancy latch: a double tap must never fire two applications.
  bool _submitting = false;

  /// Sticky once the callable succeeded. The member doc arrives on the next
  /// Firestore snapshot, so for a beat after the confirmation dialog this
  /// form is still on screen — without this the button would re-arm and a
  /// second tap would earn an `already-exists` rejection for no reason.
  bool _sent = false;

  /// One-shot auto-pick, so re-selecting by hand isn't undone on every
  /// snapshot from the addresses stream.
  bool _autoPicked = false;

  @override
  void initState() {
    super.initState();
    _prefillPhone();
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  /// Prefill from the profile phone. Signup writes a `0000000000` placeholder,
  /// and the server rejects repeated-digit numbers — so a placeholder is left
  /// out rather than pre-filled into a guaranteed error.
  Future<void> _prefillPhone() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('userInfo')
          .doc('userInfo')
          .get();
      final raw = (snap.data()?['phoneNumber'] ?? '').toString();
      final digits = raw.replaceAll(RegExp(r'\D'), '');
      if (!mounted) return;
      if (digits.length == 10 && !_isRepeated(digits)) {
        // setState, not a bare assignment: `_canSubmit` and the inline phone
        // error are computed in build(), and the controller alone does not
        // rebuild this State.
        setState(() => _phoneCtrl.text = formatMxPhone(digits));
      }
    } catch (_) {
      // Offline / missing profile doc — the field just starts empty.
    }
  }

  static bool _isRepeated(String tenDigits) =>
      RegExp(r'^(\d)\1{9}$').hasMatch(tenDigits);

  String get _phoneDigits => _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');

  bool get _phoneValid =>
      _phoneDigits.length == 10 && !_isRepeated(_phoneDigits);

  bool get _canSubmit =>
      widget.config.enabled &&
      _selectedAddressId != null &&
      _phoneValid &&
      _accepted &&
      !_submitting &&
      !_sent;

  /// Mirrors the server's `householdKeyFrom`: it needs at least two of
  /// street / number / colonia to identify the dwelling. Anything less is
  /// refused server-side, so we flag it here instead of spending a round trip
  /// on a guaranteed error.
  static bool _addressUsable(Map<String, dynamic> a) {
    var filled = 0;
    for (final k in ['street', 'streetNumber', 'colonia']) {
      if ((a[k] ?? '').toString().trim().isNotEmpty) filled++;
    }
    return filled >= 2;
  }

  static String _addressTitle(Map<String, dynamic> a) {
    final line = [
      (a['street'] ?? '').toString().trim(),
      (a['streetNumber'] ?? '').toString().trim(),
    ].where((s) => s.isNotEmpty).join(' ');
    return line.isEmpty ? 'Dirección sin calle' : line;
  }

  static String _addressSubtitle(Map<String, dynamic> a) {
    return [
      (a['colonia'] ?? '').toString().trim(),
      (a['city'] ?? '').toString().trim(),
      (a['zipCode'] ?? '').toString().trim(),
    ].where((s) => s.isNotEmpty).join(', ');
  }

  void _goToAddresses() {
    final jump = widget.onAddAddress;
    if (jump != null) {
      jump();
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) =>
            AddressesSection(onBack: () => Navigator.of(ctx).pop()),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    final addressId = _selectedAddressId;
    if (addressId == null) return;

    setState(() => _submitting = true);
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('applyApoyoMembership')
          .call(<String, dynamic>{
        'addressId': addressId,
        'phone': _phoneDigits,
        'note': _noteCtrl.text.trim(),
      });
      if (!mounted) return;

      final data = res.data;
      final warnings = data is Map
          ? ((data['householdWarning'] as num?)?.toInt() ?? 0)
          : 0;

      setState(() => _sent = true);
      FocusScope.of(context).unfocus();
      await apoyoAlert(
        context,
        title: 'Solicitud enviada',
        message: warnings > 0
            ? 'La tienda va a revisar tu solicitud y te avisamos con una '
                'notificación.\n\nYa hay otra membresía registrada en tu '
                'domicilio. Como sólo se permite una por domicilio, la tienda '
                'lo revisará antes de aprobarte.'
            : 'La tienda va a revisar tu solicitud y te avisamos con una '
                'notificación. No necesitas hacer nada más.',
      );
      if (!mounted) return;
      widget.onSubmitted?.call();
    } on FirebaseFunctionsException catch (e) {
      // Rejections come back as finished Spanish sentences written for the
      // member (household blocked, phone blocked, already applied, re-apply
      // too soon…); `apoyoCallableMessage` renders those verbatim and swaps
      // only the SDK's English transport strings for the fallback.
      if (!mounted) return;
      await apoyoAlert(
        context,
        title: 'No pudimos registrarte',
        message: apoyoCallableMessage(
          e,
          'No se pudo enviar tu solicitud. Revisa tu conexión e intenta de '
          'nuevo.',
        ),
      );
    } catch (_) {
      if (!mounted) return;
      await apoyoAlert(
        context,
        title: 'No pudimos registrarte',
        message: 'No se pudo enviar tu solicitud. Revisa tu conexión e '
            'intenta de nuevo.',
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDarkMode ? Colors.grey[900] : Colors.white,
      resizeToAvoidBottomInset: true,
      body: BottomFade(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 150),
          children: [
            _hero(),
            const SizedBox(height: 14),
            if (widget.previous != null) ...[
              _previousDecisionCard(),
              const SizedBox(height: 14),
            ],
            ApoyoRulesCard(config: widget.config),
            const SizedBox(height: 14),
            ApoyoStrikesCard(config: widget.config),
            const SizedBox(height: 22),
            apoyoSectionLabel('Tus datos'),
            _formCard(),
          ],
        ),
      ),
    );
  }

  Widget _hero() {
    return ApoyoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const ApoyoIconTile(icon: Icons.volunteer_activism_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Apoyo Social',
                      style: TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Despensa de la semana a precio de apoyo, para vecinos '
                      'de la colonia.',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.3,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: kApoyoGreenTint,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kApoyoGreenLine),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.how_to_reg_outlined,
                    size: 18, color: kApoyoGreen),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Lee todo antes de registrarte. La tienda revisa cada '
                    'solicitud a mano y te avisa por notificación.',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: kApoyoInk,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Shown only when re-applying after a rejection, so the user isn't left
  /// guessing what changed.
  Widget _previousDecisionCard() {
    final reason = (widget.previous?['decisionReason'] ?? '').toString().trim();
    return ApoyoCard(
      color: kApoyoAmberTint,
      borderColor: kApoyoAmberLine,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.history, size: 18, color: kApoyoAmber),
              SizedBox(width: 8),
              Text(
                'Solicitud anterior',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: kApoyoInk,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            reason.isEmpty
                ? 'Tu solicitud anterior no fue aceptada. Puedes volver a '
                    'intentarlo con tus datos actualizados.'
                : 'Motivo de la vez anterior: $reason',
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: kApoyoInk,
            ),
          ),
        ],
      ),
    );
  }

  Widget _formCard() {
    return ApoyoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          apoyoCardTitle('¿A dónde llega tu despensa?'),
          const SizedBox(height: 4),
          apoyoBody(
              'Elige el domicilio donde vives. Sólo se acepta una membresía '
              'por domicilio.'),
          const SizedBox(height: 12),
          _addressPicker(),
          const SizedBox(height: 18),
          apoyoCardTitle('Teléfono'),
          const SizedBox(height: 4),
          apoyoBody('10 dígitos. Lo usamos para avisarte de tu entrega.'),
          const SizedBox(height: 10),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [MxPhoneFormatter()],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: '(312) 123 - 4567',
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              filled: true,
              fillColor: Colors.grey[50],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: kApoyoInk),
              ),
            ),
          ),
          if (_phoneCtrl.text.isNotEmpty && !_phoneValid) ...[
            const SizedBox(height: 6),
            const Text(
              'Escribe un teléfono válido de 10 dígitos.',
              style: TextStyle(fontSize: 12, color: kApoyoRed),
            ),
          ],
          const SizedBox(height: 18),
          apoyoCardTitle('¿Algo que debamos saber? (opcional)'),
          const SizedBox(height: 4),
          apoyoBody(
              'Por ejemplo: cuántas personas viven contigo, o si alguien de '
              'la casa tiene alguna necesidad especial.'),
          const SizedBox(height: 10),
          TextField(
            controller: _noteCtrl,
            maxLines: 3,
            maxLength: 300,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Escribe aquí…',
              filled: true,
              fillColor: Colors.grey[50],
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: kApoyoInk),
              ),
            ),
          ),
          const SizedBox(height: 4),
          _acceptCheckbox(),
          const SizedBox(height: 14),
          _submitButton(),
          if (!widget.config.enabled) ...[
            const SizedBox(height: 10),
            Text(
              'Las inscripciones al Apoyo Social están cerradas por ahora. '
              'Vuelve a intentarlo más adelante.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: Colors.grey[600],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _addressPicker() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('addresses')
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) return _noAddressState();

        final usableIds = <String>[
          for (final d in docs)
            if (_addressUsable(d.data())) d.id,
        ];

        // Keep the selection honest against a stream that can change under us
        // (address deleted or edited into an unusable shape), and pre-pick the
        // obvious answer when there is only one.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final current = _selectedAddressId;
          if (current != null && !usableIds.contains(current)) {
            setState(() => _selectedAddressId = null);
            return;
          }
          if (current == null && !_autoPicked && usableIds.length == 1) {
            setState(() {
              _autoPicked = true;
              _selectedAddressId = usableIds.first;
            });
          }
        });

        return Column(
          children: [
            for (final d in docs) _addressTile(d.id, d.data()),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _goToAddresses,
                icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                label: const Text('Agregar o editar direcciones'),
                style: TextButton.styleFrom(
                  foregroundColor: kApoyoInk,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _noAddressState() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.location_off_outlined,
                  size: 18, color: Colors.grey[600]),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Todavía no tienes una dirección guardada',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          apoyoBody(
              'Necesitamos tu domicilio para registrarte. Agrégalo y vuelve '
              'a esta pantalla.'),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              onPressed: _goToAddresses,
              style: ElevatedButton.styleFrom(
                backgroundColor: kApoyoInk,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text(
                'Agregar mi dirección',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _addressTile(String id, Map<String, dynamic> a) {
    final usable = _addressUsable(a);
    final selected = _selectedAddressId == id;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected ? kApoyoGreenTint : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: usable ? () => setState(() => _selectedAddressId = id) : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? kApoyoGreen : Colors.grey.shade300,
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 20,
                  color: !usable
                      ? Colors.grey.shade400
                      : selected
                          ? kApoyoGreen
                          : Colors.grey.shade500,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _addressTitle(a),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color:
                              usable ? Colors.black87 : Colors.grey.shade500,
                        ),
                      ),
                      if (_addressSubtitle(a).isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          _addressSubtitle(a),
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                      if (!usable) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Esta dirección necesita calle, número y colonia '
                          'para poder usarla en el programa.',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.3,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        GestureDetector(
                          onTap: _goToAddresses,
                          child: const Text(
                            'Completar dirección',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: kApoyoInk,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _acceptCheckbox() {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => setState(() => _accepted = !_accepted),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 26,
              height: 26,
              child: Checkbox(
                value: _accepted,
                activeColor: kApoyoGreen,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (v) => setState(() => _accepted = v ?? false),
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: 3),
                child: Text(
                  'Entiendo que pago en efectivo al recibir y que el monto '
                  'debe ir completo.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _submitButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: _canSubmit ? _submit : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: kApoyoInk,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey.shade300,
          disabledForegroundColor: Colors.grey.shade600,
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: _submitting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : Text(
                _sent ? 'Solicitud enviada' : 'Enviar mi solicitud',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold),
              ),
      ),
    );
  }
}
