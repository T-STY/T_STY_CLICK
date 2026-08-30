import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';
import '../../constants/app_images.dart';

class CreateNewCard extends StatefulWidget {
  final VoidCallback onBack;
  const CreateNewCard({super.key, required this.onBack});

  @override
  State<CreateNewCard> createState() => _CreateNewCardState();
}

class _CreateNewCardState extends State<CreateNewCard> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  String _phone = '';
  String _holder = '';
  String _nip = '';

  bool _isLoading = false;

  late final String _customerSince;

  @override
  void initState() {
    super.initState();
    _customerSince = _formatCustomerSince(DateTime.now());
  }

  String _formatCustomerSince(DateTime d) {
    try {
      final out = DateFormat('d MMM yyyy', 'es').format(d);
      return out.isEmpty
          ? out
          : out[0].toUpperCase() + out.substring(1);
    } catch (_) {
      return DateFormat('yyyy-MM-dd').format(d);
    }
  }

  String? _validatePhone(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Ingresa tu número de teléfono';
    if (!RegExp(r'^\d{10}$').hasMatch(v)) {
      return 'Debe ser un número de 10 dígitos';
    }
    return null;
  }

  String? _validateHolder(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Ingresa tu nombre';
    if (v.length < 2) return 'Demasiado corto';
    if (!RegExp(r"^[a-zA-ZÁÉÍÓÚÜÑáéíóúüñ\s'.-]+$").hasMatch(v)) {
      return 'Solo letras, espacios y guiones';
    }
    return null;
  }

  static const Set<String> _weakPins = {

    '1234', '4321', '2345', '3456', '4567',
    '5678', '6789', '7890', '0123', '0987',
    '9876', '8765', '7654', '6543', '5432',

    '1212', '1004', '2000', '2580',
    '1122', '1313', '2001', '1010',
  };

  String? _validatePin(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Crea tu NIP';
    if (!RegExp(r'^\d{4}$').hasMatch(v)) return 'Deben ser 4 dígitos';
    if (RegExp(r'^(\d)\1{3}$').hasMatch(v)) {
      return 'Elige un NIP menos común';
    }
    if (_weakPins.contains(v)) return 'Elige un NIP menos común';
    return null;
  }

  void _showAlertDialog(String title, String message) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveCard() async {
    if (_isLoading) return;
    if (!(_formKey.currentState?.validate() ?? false)) {
      _showAlertDialog(
          'Revisa el formulario', 'Por favor corrige los campos marcados.');
      return;
    }
    setState(() => _isLoading = true);

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      if (!mounted) return;
      _showAlertDialog('Error', 'Usuario no autenticado.');
      setState(() => _isLoading = false);
      return;
    }

    try {
      await FirebaseFunctions.instance
          .httpsCallable('createRewardsWallet')
          .call(<String, dynamic>{
        'phone': _phone,
        'pin': _nip,
        'holderName': _holder,
      });

      if (!mounted) return;
      _showAlertDialog(
          'Listo', 'Tu monedero se creó y quedó vinculado a tu cuenta.');

      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) widget.onBack();
      });
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      _showAlertDialog('Error',
          e.message ?? 'No se pudo crear el monedero. Intenta de nuevo.');
    } catch (e) {
      if (!mounted) return;
      debugPrint('Error creating card: $e');
      _showAlertDialog(
          'Error', 'No se pudo crear el monedero. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.onBack();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          title: SizedBox(
            height: 180,
            width: 300,
            child: AspectRatio(
              aspectRatio: 1 / 1,
              child: Image.asset(
                isDarkMode ? AppImages.logowhite : AppImages.logo,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
        body: SafeArea(
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: CustomScrollView(
              slivers: [

                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _EyebrowLabel('NUEVO MONEDERO'),
                        const SizedBox(height: 6),
                        const Text(
                          'Crea tu cochinito',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                            color: Color(0xFF141414),
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Acumula saldo en cada compra y úsalo en tienda o en la app.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[700],
                            height: 1.35,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                SliverList(
                  delegate: SliverChildListDelegate.fixed([
                    const SizedBox(height: 16),
                    _FieldCard(
                      icon: Icons.person_outline_rounded,
                      label: 'Tu nombre',
                      hint: 'Como aparecerá en tu cochinito',
                      keyboardType: TextInputType.name,
                      textCapitalization: TextCapitalization.words,
                      validator: _validateHolder,
                      onChanged: (v) => setState(() => _holder = v),
                    ),
                    const SizedBox(height: 10),
                    _FieldCard(
                      icon: Icons.phone_iphone_rounded,
                      label: 'Número de teléfono',
                      hint: '10 dígitos',
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(10),
                      ],
                      validator: _validatePhone,
                      onChanged: (v) => setState(() => _phone = v),
                    ),
                    const SizedBox(height: 10),
                    _FieldCard(
                      icon: Icons.lock_outline_rounded,
                      label: 'NIP',
                      hint: '4 dígitos (no uses 1234 ni 0000)',
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(4),
                      ],
                      validator: _validatePin,
                      onChanged: (v) => setState(() => _nip = v),
                    ),
                  ]),
                ),

                SliverToBoxAdapter(
                  child: Padding(
                    padding:
                        const EdgeInsets.fromLTRB(16, 18, 16, 120),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _InfoRow(
                          icon: Icons.shield_outlined,
                          text:
                              'Usarás tu NIP para gastar saldo en tienda y en la app. Guárdalo en un lugar seguro.',
                        ),
                        const SizedBox(height: 14),
                        _SinceBadge(label: 'Te unes el $_customerSince'),
                        const SizedBox(height: 18),
                        _PrimaryButton(
                          label: 'Crear monedero',
                          isLoading: _isLoading,
                          onPressed: _isLoading ? null : _saveCard,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EyebrowLabel extends StatelessWidget {
  final String text;
  const _EyebrowLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        color: Color(0xFF6B7280),
        letterSpacing: 1.6,
      ),
    );
  }
}

class _FieldCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String hint;
  final String? Function(String?) validator;
  final ValueChanged<String> onChanged;
  final TextInputType keyboardType;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final bool obscureText;

  const _FieldCard({
    required this.icon,
    required this.label,
    required this.hint,
    required this.validator,
    required this.onChanged,
    this.keyboardType = TextInputType.text,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.obscureText = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF6F7F9),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE3E5EC)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF141414),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: Colors.white, size: 19),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                  TextFormField(
                    onChanged: onChanged,
                    validator: validator,
                    keyboardType: keyboardType,
                    textCapitalization: textCapitalization,
                    inputFormatters: inputFormatters,
                    obscureText: obscureText,
                    style: const TextStyle(
                      fontSize: 15.5,
                      color: Color(0xFF141414),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                    cursorColor: const Color(0xFF141414),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: hint,
                      hintStyle: const TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,

                      errorStyle: const TextStyle(
                        fontSize: 11,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 16, color: Colors.grey[600]),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: Colors.grey[700],
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _SinceBadge extends StatelessWidget {
  final String label;
  const _SinceBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.event_outlined,
                size: 13, color: Color(0xFF6B7280)),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF6B7280),
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final bool isLoading;
  final VoidCallback? onPressed;

  const _PrimaryButton({
    required this.label,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF141414),
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFF141414),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: isLoading
            ? SizedBox(
                width: 36,
                height: 36,
                child: Lottie.asset(
                  'assets/animations/animation.json',
                  fit: BoxFit.contain,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
      ),
    );
  }
}
