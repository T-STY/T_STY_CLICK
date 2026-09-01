import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../components/bottom_fade.dart';
import '../../utils/phone_format.dart';
import '../settings/addresses_section.dart';
import 'apoyo_common.dart';

class ApoyoJoinPage extends StatefulWidget {
  final ApoyoConfig config;

  final Map<String, dynamic>? previous;

  final VoidCallback? onBack;

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
  final _refCtrl = TextEditingController();
  final _altCtrl = TextEditingController();

  String? _fulfillment;
  String? _selectedAddressId;
  bool _accepted = false;

  bool _submitting = false;

  bool _sent = false;

  bool _autoPicked = false;

  @override
  void initState() {
    super.initState();
    _prefillPhone();
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _refCtrl.dispose();
    _altCtrl.dispose();
    super.dispose();
  }

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

        setState(() => _phoneCtrl.text = formatMxPhone(digits));
      }
    } catch (_) {

    }
  }

  static bool _isRepeated(String tenDigits) =>
      RegExp(r'^(\d)\1{9}$').hasMatch(tenDigits);

  String get _phoneDigits => _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');

  bool get _phoneValid =>
      _phoneDigits.length == 10 && !_isRepeated(_phoneDigits);

  bool get _wantsDelivery => _fulfillment == 'entrega';

  bool get _canSubmit =>
      widget.config.enabled &&
      _selectedAddressId != null &&
      _fulfillment != null &&
      _phoneValid &&
      (!_wantsDelivery || _refCtrl.text.trim().length >= 4) &&
      _accepted &&
      !_submitting &&
      !_sent;

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
        'fulfillment': _fulfillment,
        'reference': _refCtrl.text.trim(),
        'altReceiver': _altCtrl.text.trim(),
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
            _weekCard(),
            const SizedBox(height: 14),
            _fulfillmentCompareCard(),
            const SizedBox(height: 14),
            _limitsCard(),
            const SizedBox(height: 14),
            _failCard(),
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

  Widget _plainField({
    required TextEditingController controller,
    required String hint,
    int maxLines = 1,
    int? maxLength,
    VoidCallback? onChanged,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      maxLength: maxLength,
      textCapitalization: TextCapitalization.sentences,
      onChanged: onChanged == null ? null : (_) => onChanged(),
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
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
    );
  }

  Widget _fulfillmentPicker() {
    return Row(
      children: [
        Expanded(
          child: _fulfillmentTile(
            value: 'recoger',
            icon: Icons.storefront_outlined,
            title: 'La recojo',
            detail: 'Viernes 4 a 7 PM · gratis',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _fulfillmentTile(
            value: 'entrega',
            icon: Icons.delivery_dining_outlined,
            title: 'Que me llegue',
            detail: 'Viernes desde 3 PM · '
                '${apoyoMoney(widget.config.deliveryFee)}',
          ),
        ),
      ],
    );
  }

  Widget _fulfillmentTile({
    required String value,
    required IconData icon,
    required String title,
    required String detail,
  }) {
    final on = _fulfillment == value;
    return InkWell(
      onTap: () => setState(() => _fulfillment = value),
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: on ? kApoyoInk : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: on ? kApoyoInk : Colors.grey.shade300,
            width: 1.3,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22, color: on ? Colors.white : kApoyoInk),
            const SizedBox(height: 8),
            Text(title,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: on ? Colors.white : kApoyoInk)),
            const SizedBox(height: 2),
            Text(detail,
                style: TextStyle(
                    fontSize: 11.5,
                    height: 1.3,
                    color: on ? Colors.white70 : Colors.grey[600])),
          ],
        ),
      ),
    );
  }

  Widget _weekCard() {
    return ApoyoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          apoyoCardTitle('Así es tu semana'),
          const SizedBox(height: 4),
          apoyoBody('Cada semana es el mismo ciclo. Si te lo saltas, esperas '
              'a la siguiente.'),
          const SizedBox(height: 16),
          _step(
            n: '1',
            day: 'SÁBADO A MARTES',
            title: 'Pides',
            detail: 'Escoges del catálogo de la semana. Puedes cambiar tu '
                'pedido las veces que quieras mientras esté abierto.',
          ),
          _step(
            n: '2',
            day: 'MARTES 11:59 PM',
            title: 'Cierra',
            detail: 'Después de esa hora ya no se puede pedir ni cambiar. '
                'La tienda compra con lo que juntaron todos.',
          ),
          _step(
            n: '3',
            day: 'VIERNES',
            title: 'Te llega o la recoges',
            detail: 'Entrega desde las 3:00 PM, o la recoges en la tienda '
                'entre 4:00 y 7:00 PM.',
          ),
          _step(
            n: '4',
            day: 'AL RECIBIR',
            title: 'Pagas en efectivo',
            detail: 'El monto completo, en el momento. No hay apartados ni '
                'pagos en partes.',
            last: true,
          ),
        ],
      ),
    );
  }

  Widget _step({
    required String n,
    required String day,
    required String title,
    required String detail,
    bool last = false,
  }) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: kApoyoInk,
                  shape: BoxShape.circle,
                ),
                child: Text(n,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900)),
              ),
              if (!last)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: kApoyoGreenLine,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(day,
                      style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                          color: kApoyoAmber)),
                  const SizedBox(height: 2),
                  Text(title,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: kApoyoInk)),
                  const SizedBox(height: 3),
                  Text(detail,
                      style: TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: Colors.grey[600])),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fulfillmentCompareCard() {
    return ApoyoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          apoyoCardTitle('¿Te llega o la recoges?'),
          const SizedBox(height: 4),
          apoyoBody('Tú eliges al registrarte. Es lo único que cuesta aparte.'),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _optionBox(
                  icon: Icons.storefront_outlined,
                  title: 'La recoges',
                  price: 'Gratis',
                  detail: 'Viernes de 4:00 a 7:00 PM en la tienda.',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _optionBox(
                  icon: Icons.delivery_dining_outlined,
                  title: 'Te llega',
                  price: apoyoMoney(widget.config.deliveryFee),
                  detail: 'Viernes desde las 3:00 PM, en tu domicilio.',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _optionBox({
    required IconData icon,
    required String title,
    required String price,
    required String detail,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kApoyoGreenTint,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kApoyoGreenLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: kApoyoInk),
          const SizedBox(height: 8),
          Text(title,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: kApoyoInk)),
          const SizedBox(height: 2),
          Text(price,
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: kApoyoInk)),
          const SizedBox(height: 6),
          Text(detail,
              style: TextStyle(
                  fontSize: 12, height: 1.3, color: Colors.grey[600])),
        ],
      ),
    );
  }

  Widget _limitsCard() {
    final c = widget.config;
    return ApoyoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          apoyoCardTitle('Lo que hay que saber antes'),
          const SizedBox(height: 12),
          _bullet('Una membresía por domicilio',
              'Si ya hay alguien registrado en tu casa, la tienda lo revisa '
              'antes de aprobar.'),
          _bullet('Tu primer pedido llega hasta ${apoyoMoney(c.firstOrderMaxTotal)}',
              c.firstOrderPickupOnly
                  ? 'Y ese primero se recoge en la tienda, no se entrega.'
                  : 'Después subes hasta ${apoyoMoney(c.defaultMaxOrderTotal)} por semana.'),
          _bullet('Después, hasta ${apoyoMoney(c.defaultMaxOrderTotal)} por semana',
              'Es un apoyo para la despensa, no una tienda de mayoreo.',
              last: true),
        ],
      ),
    );
  }

  Widget _failCard() {
    final c = widget.config;
    return ApoyoCard(
      color: kApoyoRedTint,
      borderColor: kApoyoRedLine,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: kApoyoRed),
              SizedBox(width: 8),
              Text('Si no recoges o no pagas',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: kApoyoInk)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'La tienda ya compró esa despensa con el dinero de todos. Si no '
            'la recoges o no la pagas, alguien más se queda sin la suya.',
            style: TextStyle(
                fontSize: 12.5, height: 1.4, color: Colors.grey[700]),
          ),
          const SizedBox(height: 10),
          Text(
            'A las ${c.strikesToBan} fallas quedas fuera del programa. '
            'Antes de eso te suspendemos ${c.suspensionCycles} '
            '${c.suspensionCycles == 1 ? "semana" : "semanas"}. '
            'Si quedas fuera, puedes volver a pedir entrada después de '
            '${c.reapplyAfterDays} días.',
            style: const TextStyle(
                fontSize: 12.5,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: kApoyoInk),
          ),
        ],
      ),
    );
  }

  Widget _bullet(String title, String detail, {bool last = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 6),
            decoration: const BoxDecoration(
                color: kApoyoInk, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: kApoyoInk)),
                const SizedBox(height: 2),
                Text(detail,
                    style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: Colors.grey[600])),
              ],
            ),
          ),
        ],
      ),
    );
  }

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
          const SizedBox(height: 20),
          apoyoCardTitle('¿Cómo la quieres recibir?'),
          const SizedBox(height: 4),
          apoyoBody(
              'Esto define tu viernes. Puedes cambiarlo después hablando con '
              'la tienda.'),
          const SizedBox(height: 10),
          _fulfillmentPicker(),
          if (_wantsDelivery) ...[
            const SizedBox(height: 20),
            apoyoCardTitle('¿Cómo reconocemos tu casa?'),
            const SizedBox(height: 4),
            apoyoBody(
                'Color, portón, o qué hay enfrente. Con la pura calle y '
                'número a veces no damos, y si no damos contigo se pierde '
                'la entrega.'),
            const SizedBox(height: 10),
            _plainField(
              controller: _refCtrl,
              hint: 'Casa azul con portón negro, frente a la papelería',
              maxLines: 2,
              maxLength: 140,
              onChanged: () => setState(() {}),
            ),
          ],
          const SizedBox(height: 20),
          apoyoCardTitle(
              _wantsDelivery
                  ? '¿Quién recibe y paga si no estás? (opcional)'
                  : '¿Quién puede recoger si no puedes ir? (opcional)'),
          const SizedBox(height: 4),
          apoyoBody(
              _wantsDelivery
                  ? 'El viernes por la tarde mucha gente trabaja. Si dejas '
                      'un nombre, no perdemos el viaje ni te cuenta como '
                      'falla.'
                  : 'Si alguien más va por ella, dinos quién para '
                      'entregársela sin problema.'),
          const SizedBox(height: 10),
          _plainField(
            controller: _altCtrl,
            hint: 'Nombre de quien recibe',
            maxLines: 1,
            maxLength: 80,
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
