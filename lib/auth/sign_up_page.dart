import 'package:flutter/material.dart';
import '../../constants/constants.dart';
import '../../custom_page_route.dart';
import 'components/signup_form.dart';
import 'login_page.dart';

class SignupPage extends StatelessWidget {
  const SignupPage({super.key});

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

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
              "Registrar",
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
            const SignUpForm(),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '¿Ya tienes una cuenta?',
                  style: TextStyle(
                    fontSize: 15.0,
                    fontWeight: FontWeight.normal,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? AppColors.defaultWhite
                        : AppColors.defaultBlack,
                    letterSpacing: 0.8,
                    fontFamily: 'Gordita',
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      customPageRoute(const LoginPage()),
                    );
                  },
                  child: Text(
                    'Ingresar',
                    style: TextStyle(
                      fontSize: 15.0,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? AppColors.defaultWhite
                          : AppColors.defaultBlack,
                      letterSpacing: 0.8,
                      fontFamily: 'Gordita',
                    ),
                  ),
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