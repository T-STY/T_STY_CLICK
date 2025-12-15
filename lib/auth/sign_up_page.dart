import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../components/horizontal_line.dart';
import '../../constants/constants.dart';
import '../../custom_page_route.dart';
import '../../main.dart';
import 'components/signup_form.dart';
import 'login_page.dart';

class SignupPage extends StatelessWidget {
  const SignupPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {

    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final themeNotifier = Provider.of<ThemeNotifier>(context, listen: false);

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
                    isDarkMode ? AppImages.logowhite : AppImages.logo, // Conditionally set the logo based on the theme
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppDefaults.margin * 2.5),
            // Header
            Text(
              "Registrar",
              style: TextStyle(
                fontSize: 20.0,  // Example size you want
                fontWeight: FontWeight.bold,
                color: Theme.of(context).brightness == Brightness.dark ? AppColors.defaultWhite : AppColors.defaultBlack,
                letterSpacing: 1.0,  // If you have a specific letter spacing in mind
                fontFamily: 'Gemini',  // Specify the font family explicitly
                // ... any other properties you want to set
              ),
            ),
            const SizedBox(height: AppDefaults.margin * 2),

            /// Sign up forms
            const SignUpForm(),
            const Spacer(),
            /// Already have an account
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('¿Ya tienes una cuenta?',
                    style: TextStyle(
                      fontSize: 15.0,  // Example size you want
                      fontWeight: FontWeight.normal,
                      color: Theme.of(context).brightness == Brightness.dark ? AppColors.defaultWhite : AppColors.defaultBlack,
                      letterSpacing: 0.8,  // If you have a specific letter spacing in mind
                      fontFamily: 'Gordita',  // Specify the font family explicitly
                      // ... any other properties you want to set
                    )
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
                        fontSize: 15.0,  // Example size you want
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).brightness == Brightness.dark ? AppColors.defaultWhite : AppColors.defaultBlack,
                        letterSpacing: 0.8,  // If you have a specific letter spacing in mind
                        fontFamily: 'Gordita',  // Specify the font family explicitly
                        // ... any other properties you want to set
                      )
                  ),
                ),
              ],
            ),
            SizedBox(height: 5,)
          ],
        ),
      ),
    );
  }
}
