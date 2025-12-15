import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';
import '../../components/horizontal_line.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_defaults.dart';
import '../../constants/app_images.dart';
import '../../custom_page_route.dart';
import '../../main.dart';
import '../app/main.dart';
import 'components/login_form.dart';
import 'sign_up_page.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({Key? key}) : super(key: key);

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
            const SizedBox(height: 54),  // Adjust as necessary
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
            Text(
              "Inicia Sesión",
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
            const LoginForm(),
            const Spacer(),

            // This part will be at the bottom
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('¿No tienes cuenta?',
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
                      customPageRoute(const SignupPage()),
                    );
                  },
                  child: Text(
                    'Registrar',
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
            const SizedBox(height: 5), // Some space at the very bottom
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
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 55.0, // Adjust as needed
        width: 55.0,  // Adjust as needed
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


class SocialLogins extends StatelessWidget {
  const SocialLogins({
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SocialIconButton(
          logoAsset: 'assets/images/google.png',
        onTap: () async {
      final success = await signInWithGoogle();
      if (success) {
        Navigator.pushAndRemoveUntil(
          context,
          customPageRoute(const MainMenuScreen()),
              (route) => false,
          );
      } else {
        // Handle the failure case, perhaps show an error message.
      }
          }
      ),
        const SizedBox(width: AppDefaults.margin * 4),
        // SocialIconButton(
        //   logoAsset: 'assets/images/fb.png',
        //   onTap: () async {
        //     final user = await signInWithFacebook();
        //     if (user != null) {
        //       Navigator.pushAndRemoveUntil(
        //         context,
        //         customPageRoute(const MainMenuScreen()),
        //             (route) => false,
        //       );
        //     } else {
        //
        //     }
        //   },
        // ),
      ],
    );
  }
}

Future<bool> signInWithGoogle() async {
  final FirebaseAuth auth = FirebaseAuth.instance;
  final GoogleSignIn googleSignIn = GoogleSignIn();
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  try {
    final GoogleSignInAccount? googleSignInAccount = await googleSignIn.signIn();

    if (googleSignInAccount != null) {
      final GoogleSignInAuthentication googleSignInAuthentication = await googleSignInAccount.authentication;

      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleSignInAuthentication.accessToken,
        idToken: googleSignInAuthentication.idToken,
      );

      final UserCredential authResult = await auth.signInWithCredential(credential);
      final User? user = authResult.user;

      if (user != null) {
        final userDocRef = firestore.collection('users').doc(user.uid);

        // Check if the user document exists in Firestore
        final docSnapshot = await userDocRef.get();
        if (!docSnapshot.exists) {
          // If the user document doesn't exist, create initial structure
          await userDocRef.set({
            'userInfo': {
              'name': user.displayName,
              'email': user.email,
            }
          });

          // Create placeholders in sub-collections
          await userDocRef.collection('addresses').doc('placeholder').set({'address': 'Placeholder'});
          await userDocRef.collection('cards').doc('placeholder').set({'cardNumber': 'Placeholder'});
          await userDocRef.collection('orderHistory').doc('placeholder').set({'status': 'Placeholder'});
          await userDocRef.collection('favourites').doc('placeholder').set({'item': 'Placeholder'});
          await userDocRef.collection('cart').doc('placeholder').set({'item': 'Placeholder'});
          await userDocRef.collection('userInfo').doc('userInfo').set({
            'mainAddress': '',
            'phoneNumber': '',
            'zipCode': ''
          });
        }

        return true;
      }
    }
  } catch (error) {
    print(error);
  }
  return false;
}


// Future<User?> signInWithFacebook() async {
//   final FirebaseFirestore firestore = FirebaseFirestore.instance;
//
//   try {
//     final LoginResult result = await FacebookAuth.instance.login(permissions: ['email', 'public_profile']);
//
//
//     if (result.status == LoginStatus.success) {
//       final OAuthCredential credential = FacebookAuthProvider.credential(result.accessToken!.token);
//       final UserCredential authResult = await FirebaseAuth.instance.signInWithCredential(credential);
//       final User? user = authResult.user;
//
//       if (user != null) {
//         final userDocRef = firestore.collection('users').doc(user.uid);
//
//         // Check if the user document exists in Firestore
//         final docSnapshot = await userDocRef.get();
//         if (!docSnapshot.exists) {
//           // Get user data from Facebook
//           final userData = await FacebookAuth.instance.getUserData(fields: "name,email,picture.width(200)");
//
//           // If the user document doesn't exist, create initial structure
//           await userDocRef.set({
//             'userInfo': {
//               'name': userData["name"],
//               'email': userData["email"],
//             }
//           });
//
//           // Create placeholders in sub-collections
//           await userDocRef.collection('addresses').doc('placeholder').set({'address': 'Placeholder'});
//           await userDocRef.collection('cards').doc('placeholder').set({'cardNumber': 'Placeholder'});
//           await userDocRef.collection('orderHistory').doc('placeholder').set({'status': 'Placeholder'});
//           await userDocRef.collection('favourites').doc('placeholder').set({'item': 'Placeholder'});
//           await userDocRef.collection('cart').doc('placeholder').set({'item': 'Placeholder'});
//           await userDocRef.collection('userInfo').doc('userInfo').set({
//             'mainAddress': '',
//             'phoneNumber': '',
//             'zipCode': ''
//           });
//         }
//       }
//
//       return user;
//     }
//   } catch (error) {
//   }
//   return null;
// }


