import 'package:click/theme.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'app/cart/cart_provider.dart';
import 'app/main.dart';
import 'auth/login_page.dart';
import 'components/custom_loader.dart';
import 'custom_page_route.dart';
import 'firebase_options.dart';
import 'package:provider/provider.dart';

class ThemeNotifier with ChangeNotifier {
  final ThemeData lightTheme;
  final ThemeData darkTheme;
  bool _isDark = false;

  ThemeNotifier(this.lightTheme, this.darkTheme);

  ThemeData get currentTheme => _isDark ? darkTheme : lightTheme;

  bool get isDark => _isDark;

  void toggleTheme() {
    _isDark = !_isDark;
    notifyListeners(); // Make sure this is called to update listeners
  }
}


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );



  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: [SystemUiOverlay.top], // Ensure the status bar is visible
  );

  // Add this block
  await FirebaseAppCheck.instance.activate(
    androidProvider: AndroidProvider.debug, // Use .playIntegrity for release
    appleProvider: AppleProvider.appAttest,
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => ThemeNotifier(
          AppTheme(context).lightTheme,
          AppTheme(context).darkTheme,
        )),
        ChangeNotifierProvider(create: (_) => CartProvider()), // Add CartProvider here
        // Add other providers if needed
      ],
      child: const NetworkAwareApp(), // Your top-level widget
    ),
  );
}
class NetworkAwareApp extends StatefulWidget {
  const NetworkAwareApp({super.key});

  @override
  _NetworkAwareAppState createState() => _NetworkAwareAppState();
}

class _NetworkAwareAppState extends State<NetworkAwareApp> {
  bool _isOnline = false;

  @override
  void initState() {
    super.initState();
    _checkConnectivity();
  }

  Future<void> _checkConnectivity() async {
    var connectivityResult = await (Connectivity().checkConnectivity());
    if (connectivityResult == ConnectivityResult.none) {
      setState(() => _isOnline = false);
    } else {
      setState(() => _isOnline = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isOnline) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text("No Internet Connection"),
                ElevatedButton(
                  onPressed: _checkConnectivity,
                  child: const Text("Retry"),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return const MyApp();
  }
}
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeNotifier>(
      builder: (context, themeNotifier, child) {
        _setStatusBarStyle(context); // Set status bar style here

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'T_STY',
          theme: themeNotifier.currentTheme,
          initialRoute: '/',
          onGenerateRoute: _generateRoute,
          onUnknownRoute: (settings) => customPageRoute(Center(
            child: Text('Unknown route: ${settings.name}'),
          )),
        );
      },
    );
  }

  Route? _generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/':
        return FirebaseAuth.instance.currentUser != null
            ? customPageRouteBuilder(CheckUserScreen())
            : customPageRouteBuilder(const LoginPage());
      default:
        return customPageRouteBuilder(
          const Scaffold(body: Center(child: Text('Route not found'))),
        );
    }
  }
  void _setStatusBarStyle(BuildContext context) {
    ThemeData theme = Theme.of(context);
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,  // Transparent status bar
      statusBarIconBrightness: theme.brightness == Brightness.dark ? Brightness.light : Brightness.dark,  // Adjusts the icon brightness based on the theme
    ));
  }

}

PageRouteBuilder<T> customPageRouteBuilder<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 500),
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(opacity: animation, child: child);
    },
  );
}

class CheckUserScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    _checkUser(context);
    return const Scaffold(
      // Replaced Center(child: CircularProgressIndicator())
      body: CustomLoader(),
    );
  }
}

  Future<void> _checkUser(BuildContext context) async {
    try {
      // Attempt to refresh the user's profile
      await FirebaseAuth.instance.currentUser?.reload();
      // If reload is successful, navigate to the main menu screen
      Navigator.of(context).pushReplacement(customPageRouteBuilder(const MainMenuScreen()));
    } catch (e) {
      // If an error occurs, likely due to the user being disabled, sign out and navigate to login
      await FirebaseAuth.instance.signOut();
      Navigator.of(context).pushReplacement(customPageRouteBuilder(const LoginPage()));
    }
  }
