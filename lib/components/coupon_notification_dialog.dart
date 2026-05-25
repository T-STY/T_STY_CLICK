import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_iconly/flutter_iconly.dart';
import 'package:vibration/vibration.dart';
import '../constants/app_colors.dart';

class CouponNotificationDialog extends StatefulWidget {
  const CouponNotificationDialog({super.key, required this.code, this.message});

  final String code;
  final String? message;

  static Future<void> show(BuildContext context, String code,
      {String? message}) {
    return showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (_) => CouponNotificationDialog(code: code, message: message),
    );
  }

  @override
  State<CouponNotificationDialog> createState() =>
      _CouponNotificationDialogState();
}

class _CouponNotificationDialogState extends State<CouponNotificationDialog> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (await Vibration.hasVibrator()) {
      Vibration.vibrate(duration: 30);
    }
    if (!mounted) return;
    setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: Container(color: Colors.black.withValues(alpha: 0.15)),
          ),
        ),
        Center(
          child: AlertDialog(
            backgroundColor: isDark ? AppColors.primary : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(25.0),
            ),
            titlePadding: const EdgeInsets.fromLTRB(20, 20, 8, 0),
            title: Row(
              children: [
                Icon(IconlyBold.discount,
                    color: Theme.of(context).iconTheme.color, size: 28.0),
                const SizedBox(width: 12.0),
                const Expanded(
                  child: Text(
                    '¡Un cupón para ti!',
                    style: TextStyle(
                        fontSize: 17.0, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  color: Theme.of(context).iconTheme.color,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.message ??
                      'Gracias por ser de nuestros favoritos. Toca el código para copiarlo.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14.0, height: 1.35),
                ),
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: _copy,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : AppColors.backgroundLight,
                      borderRadius: BorderRadius.circular(14.0),
                      border: Border.all(
                        color: _copied
                            ? Colors.green
                            : (isDark
                                ? Colors.white24
                                : Colors.black12),
                        width: 1.4,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            widget.code,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 22.0,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2.0,
                              color: isDark
                                  ? AppColors.defaultWhite
                                  : AppColors.defaultBlack,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Icon(
                          _copied ? Icons.check_circle : Icons.copy_rounded,
                          size: 20,
                          color: _copied
                              ? Colors.green
                              : Theme.of(context).iconTheme.color,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                AnimatedOpacity(
                  opacity: _copied ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: const Text(
                    '¡Código copiado!',
                    style: TextStyle(
                      fontSize: 13.0,
                      color: Colors.green,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
