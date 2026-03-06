import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_defaults.dart';
import '../../constants/app_images.dart';
import '../../custom_page_route.dart';
import '../../main.dart';
import 'components/login_form.dart';
import 'sign_up_page.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    Provider.of<ThemeNotifier>(context, listen: false);

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(0.0),
        child: AppBar(
          scrolledUnderElevation: 0,
          backgroundColor: Theme.of(context).brightness == Brightness.dark
              ? Colors.transparent
              : Colors.white,
        ),
      ),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 54),
            Padding(
              padding: const EdgeInsets.all(10),
              child: SizedBox(
                height: 45,
                width: 300,
                child: AspectRatio(
                  aspectRatio: 1 / 1,
                  child: Image.asset(
                    isDarkMode ? AppImages.logowhite : AppImages.logo,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppDefaults.margin * 2.5),
            Text(
              "Inicia Sesión",
              style: TextStyle(
                fontSize: 20.0,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.defaultWhite
                    : AppColors.defaultBlack,
                letterSpacing: 1.0,
                fontFamily: 'Gemini',
              ),
            ),
            const SizedBox(height: AppDefaults.margin * 2),
            const LoginForm(),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('¿No tienes cuenta?',
                    style: TextStyle(
                      fontSize: 15.0,
                      fontWeight: FontWeight.normal,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? AppColors.defaultWhite
                          : AppColors.defaultBlack,
                      letterSpacing: 0.8,
                      fontFamily: 'Gordita',
                    )),
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      customPageRoute(const SignupPage()),
                    );
                  },
                  child: Text('Registrar',
                      style: TextStyle(
                        fontSize: 15.0,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? AppColors.defaultWhite
                            : AppColors.defaultBlack,
                        letterSpacing: 0.8,
                        fontFamily: 'Gordita',
                      )),
                ),
              ],
            ),
            const SizedBox(height: 5),
          ],
        ),
      ),
    );
  }
}

class SocialIconButton extends StatelessWidget {
  final String logoAsset;
  final VoidCallback onTap;

  const SocialIconButton({
    required this.logoAsset,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 55.0,
        width: 55.0,
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage(logoAsset),
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}