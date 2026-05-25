import 'package:flutter/services.dart';

String formatMxPhone(String value) {
  final digits = value.replaceAll(RegExp(r'\D'), '');
  final c = digits.length > 10 ? digits.substring(0, 10) : digits;
  if (c.isEmpty) return '';
  if (c.length <= 3) return '($c';
  if (c.length <= 6) return '(${c.substring(0, 3)}) ${c.substring(3)}';
  return '(${c.substring(0, 3)}) ${c.substring(3, 6)} - ${c.substring(6)}';
}

class MxPhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final formatted = formatMxPhone(newValue.text);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
