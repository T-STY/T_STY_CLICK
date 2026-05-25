import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../components/bottom_fade.dart';
import '../../constants/app_images.dart';

class CouponsSection extends StatefulWidget {
  final VoidCallback onBack;
  const CouponsSection({super.key, required this.onBack});

  @override
  State<CouponsSection> createState() => _CouponsSectionState();
}

class _CouponsSectionState extends State<CouponsSection> {
  final _codeCtrl = TextEditingController();
  bool _applying = false;
  String? _flash;
  Timer? _flashTimer;

  @override
  void dispose() {
    _flashTimer?.cancel();
    _codeCtrl.dispose();
    super.dispose();
  }

  void _showFlash(String type) {
    _flashTimer?.cancel();
    setState(() => _flash = type);
    _flashTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _flash = null);
    });
  }

  void _onError() {
    _codeCtrl.clear();
    FocusScope.of(context).unfocus();
    _showFlash('error');
  }

  void _onSuccess() {
    _codeCtrl.clear();
    FocusScope.of(context).unfocus();
    _showFlash('success');
  }

  Future<void> _applyCoupon() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) {
      _onError();
      return;
    }
    setState(() => _applying = true);
    try {
      await FirebaseFunctions.instance
          .httpsCallable('claimCoupon')
          .call(<String, dynamic>{'code': code});
      if (!mounted) return;
      _onSuccess();
    } catch (_) {
      if (!mounted) return;
      _onError();
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final userId = FirebaseAuth.instance.currentUser?.uid;
    final couponsRef = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('coupons');

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) widget.onBack();
      },
      child: Scaffold(
        backgroundColor: isDarkMode ? Colors.grey[900] : Colors.white,
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          backgroundColor: isDarkMode ? Colors.grey[900] : Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          automaticallyImplyLeading: false,
          title: SizedBox(
            height: 150,
            width: 250,
            child: Image.asset(
              isDarkMode ? AppImages.logowhite : AppImages.logo,
              fit: BoxFit.contain,
            ),
          ),
        ),
        body: BottomFade(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 150),
            children: [
              _buildAddCard(),
              const SizedBox(height: 20),
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 6),
                child: Text(
                  'Mis cupones',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: couponsRef.snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const SizedBox.shrink();
                  }
                  final docs = snapshot.data?.docs ?? [];
                  if (docs.isEmpty) return _emptyState();

                  final items = docs.map((d) => {...d.data(), 'code': d.id}).toList();
                  items.sort((a, b) {
                    final ua = (a['used'] == true) ? 1 : 0;
                    final ub = (b['used'] == true) ? 1 : 0;
                    if (ua != ub) return ua - ub;
                    final ea = a['expiry_date'];
                    final eb = b['expiry_date'];
                    if (ea is Timestamp && eb is Timestamp) {
                      return ea.compareTo(eb);
                    }
                    return 0;
                  });

                  return Column(
                    children: [for (final c in items) _couponCard(c)],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAddCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Agregar cupón',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Ingresa un código para guardarlo en tu cuenta.',
            style: TextStyle(fontSize: 12.5, color: Colors.grey[600]),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _codeCtrl,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [UpperCaseTextFormatter()],
                  decoration: InputDecoration(
                    hintText: 'Código de cupón',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
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
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 48,
                width: 124,
                child: ElevatedButton(
                  onPressed: _applying ? null : _applyCoupon,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _flash == 'error'
                        ? Colors.red
                        : _flash == 'success'
                            ? const Color(0xFF2E7D32)
                            : Colors.black,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.black,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: _applying
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(
                          _flash == 'error'
                              ? 'Error'
                              : _flash == 'success'
                                  ? 'Agregado'
                                  : 'Aplicar',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(Icons.confirmation_number_outlined,
              size: 48, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text('Aún no tienes cupones',
              style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('Agrega un código arriba para empezar.',
              style: TextStyle(color: Colors.grey[400], fontSize: 12.5)),
        ],
      ),
    );
  }

  Widget _couponCard(Map<String, dynamic> c) {
    final code = (c['code'] ?? '').toString();
    final pct = (c['percentage'] as num?)?.toDouble() ?? 0;
    final maxDisc = (c['max_discount'] as num?)?.toDouble() ?? 0;
    final used = c['used'] == true;
    final expiry =
        c['expiry_date'] is Timestamp ? (c['expiry_date'] as Timestamp) : null;
    final expired =
        expiry != null && expiry.toDate().isBefore(DateTime.now());

    final String statusLabel = used
        ? 'Usado'
        : expired
            ? 'Vencido'
            : 'Activo';
    final Color statusColor = used
        ? Colors.grey
        : expired
            ? Colors.red
            : const Color(0xFF2E7D32);
    final bool inactive = used || expired;
    final List<Color> stubColors = inactive
        ? [Colors.grey.shade500, Colors.grey.shade600]
        : [const Color(0xFF1A1A1A), const Color(0xFF3A3A3A)];
    const double stubW = 96;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PhysicalShape(
        clipper: const _CouponTicketClipper(stubWidth: stubW),
        clipBehavior: Clip.antiAlias,
        color: Colors.white,
        elevation: 2.5,
        shadowColor: Colors.black.withValues(alpha: 0.22),
        child: SizedBox(
          height: 112,
          child: Stack(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: stubW,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: stubColors,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${pct.toStringAsFixed(0)}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            height: 1.0,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'DESCUENTO',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 7.5,
                              letterSpacing: 1.0,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 14, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  code,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.0,
                                    color:
                                        inactive ? Colors.grey : Colors.black,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  statusLabel,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: statusColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (maxDisc > 0) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Hasta \$${maxDisc.toStringAsFixed(0)} de descuento',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 13, color: Colors.grey[700]),
                            ),
                          ],
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(Icons.event_outlined,
                                  size: 15, color: Colors.grey[500]),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  expiry != null
                                      ? 'Vence ${_fmtDate(expiry)}'
                                      : 'Sin fecha de vencimiento',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 12.5, color: Colors.grey[600]),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              Positioned(
                left: stubW - 1,
                top: 14,
                bottom: 14,
                child: CustomPaint(
                  size: const Size(2, double.infinity),
                  painter: _CouponDashedLine(Colors.grey.shade300),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtDate(Timestamp ts) {
    final d = ts.toDate().toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}

class _CouponTicketClipper extends CustomClipper<Path> {
  final double stubWidth;
  const _CouponTicketClipper({required this.stubWidth});

  @override
  Path getClip(Size size) {
    const double radius = 9;
    const double corner = 16;
    final rrect = Path()
      ..addRRect(RRect.fromRectAndRadius(
          Offset.zero & size, const Radius.circular(corner)));
    final notches = Path()
      ..addOval(Rect.fromCircle(center: Offset(stubWidth, 0), radius: radius))
      ..addOval(Rect.fromCircle(
          center: Offset(stubWidth, size.height), radius: radius));
    return Path.combine(PathOperation.difference, rrect, notches);
  }

  @override
  bool shouldReclip(covariant _CouponTicketClipper oldClipper) =>
      oldClipper.stubWidth != stubWidth;
}

class _CouponDashedLine extends CustomPainter {
  final Color color;
  _CouponDashedLine(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    const double dash = 4, gap = 4;
    final double x = size.width / 2;
    double y = 0;
    while (y < size.height) {
      final double end = (y + dash).clamp(0, size.height).toDouble();
      canvas.drawLine(Offset(x, y), Offset(x, end), paint);
      y += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _CouponDashedLine old) => old.color != color;
}
