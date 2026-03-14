import 'dart:io';
import 'package:click/theme.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app/cart/cart_provider.dart';
import 'app/main.dart';
import 'components/custom_loader.dart';
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
    notifyListeners();
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: [SystemUiOverlay.top],
  );
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  await FirebaseAppCheck.instance.activate(
    androidProvider: AndroidProvider.debug,
    appleProvider: AppleProvider.appAttest,
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => ThemeNotifier(
          AppTheme(context).lightTheme,
          AppTheme(context).darkTheme,
        )),
        ChangeNotifierProvider(create: (_) => CartProvider()),
      ],
      child: const NetworkAwareApp(),
    ),
  );
}

class NetworkAwareApp extends StatefulWidget {
  const NetworkAwareApp({super.key});

  @override
  NetworkAwareAppState createState() => NetworkAwareAppState();
}

class NetworkAwareAppState extends State<NetworkAwareApp> {
  bool _isOnline = false;

  @override
  void initState() {
    super.initState();
    _checkConnectivity();
  }

  Future<void> _checkConnectivity() async {
    final List<ConnectivityResult> connectivityResult = await (Connectivity().checkConnectivity());

    if (connectivityResult.contains(ConnectivityResult.none)) {
      setState(() => _isOnline = false);
    } else {
      setState(() => _isOnline = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isOnline) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.wifi_off, size: 50, color: Colors.grey),
                const SizedBox(height: 20),
                const Text("No Internet Connection", style: TextStyle(fontSize: 18)),
                const SizedBox(height: 20),
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
        _setStatusBarStyle(context);

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'T_STY: Beyond',
          theme: themeNotifier.currentTheme,
          initialRoute: '/',
          onGenerateRoute: _generateRoute,
          onUnknownRoute: (settings) => customPageRouteBuilder(Center(
            child: Text('Unknown route: ${settings.name}'),
          )),
        );
      },
    );
  }

  Route? _generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/':
        return customPageRouteBuilder(const CheckUserScreen());
      default:
        return customPageRouteBuilder(
          const Scaffold(body: Center(child: Text('Route not found'))),
        );
    }
  }

  void _setStatusBarStyle(BuildContext context) {
    ThemeData theme = Theme.of(context);
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: theme.brightness == Brightness.dark ? Brightness.light : Brightness.dark,
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

enum _UpdateType { none, flexible, forced }

class CheckUserScreen extends StatefulWidget {
  const CheckUserScreen({super.key});

  @override
  CheckUserScreenState createState() => CheckUserScreenState();
}

class CheckUserScreenState extends State<CheckUserScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runStartupChecks();
    });
  }

  Future<void> _runStartupChecks() async {
    _UpdateType updateStatus = await _checkForUpdate();

    if (updateStatus == _UpdateType.forced) {
      if (mounted) _showUpdateDialog(forced: true);
    } else if (updateStatus == _UpdateType.flexible) {
      if (mounted) _showUpdateDialog(forced: false);
    } else {
      await _checkUser();
    }
  }

  Future<_UpdateType> _checkForUpdate() async {
    try {
      final remoteConfig = FirebaseRemoteConfig.instance;

      await remoteConfig.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: const Duration(hours: 1), // Set back to 1 hour
      ));

      await remoteConfig.fetchAndActivate();

      String minVersion = remoteConfig.getString('min_required_version');
      String recommendedVersion = remoteConfig.getString('latest_recommended_version');

      if (minVersion.isEmpty) minVersion = "0.0.0";
      if (recommendedVersion.isEmpty) recommendedVersion = "0.0.0";

      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      String currentVersion = packageInfo.version;

      debugPrint("Current: $currentVersion | Min: $minVersion | Rec: $recommendedVersion");

      if (_isVersionLower(currentVersion, minVersion)) {
        return _UpdateType.forced;
      }

      if (_isVersionLower(currentVersion, recommendedVersion)) {
        return _UpdateType.flexible;
      }

      return _UpdateType.none;

    } catch (e) {
      debugPrint("Remote config error: $e");
      return _UpdateType.none;
    }
  }

  bool _isVersionLower(String current, String target) {
    List<int> c = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    List<int> t = target.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    int len = c.length > t.length ? c.length : t.length;
    for (int i = 0; i < len; i++) {
      int cVal = i < c.length ? c[i] : 0;
      int tVal = i < t.length ? t[i] : 0;

      if (cVal < tVal) return true;
      if (cVal > tVal) return false;
    }
    return false;
  }

  void _showUpdateDialog({required bool forced}) {
    showDialog(
      context: context,
      barrierDismissible: !forced,
      builder: (BuildContext context) {
        return PopScope(
          canPop: !forced,
          child: AlertDialog(
            title: Text(forced ? "Actualización Requerida" : "Actualización Disponible"),
            content: Text(forced
                ? "Debes actualizar la aplicación para continuar usando T_STY: Beyond."
                : "¡Hay una nueva versión de T_STY: Beyond disponible con nuevas funciones!"),
            actions: [
              if (!forced)
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _checkUser();
                  },
                  child: const Text("Más tarde"),
                ),
              ElevatedButton(
                onPressed: _launchStore,
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.black,
                ),
                child: const Text("Actualizar Ahora"),
              ),
            ],
          ),
        );
      },
    );
  }

  void _launchStore() async {
    const String androidPackageId = "com.t_sty.mx.click";
    const String iosAppId = "6757348875";

    final url = Platform.isAndroid
        ? Uri.parse("market://details?id=$androidPackageId")
        : Uri.parse("https://apps.apple.com/app/id$iosAppId");

    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        final webUrl = Platform.isAndroid
            ? Uri.parse("https://play.google.com/store/apps/details?id=$androidPackageId")
            : Uri.parse("https://apps.apple.com/app/id$iosAppId");
        if (await canLaunchUrl(webUrl)) {
          await launchUrl(webUrl, mode: LaunchMode.externalApplication);
        }
      }
    } catch (e) {
      debugPrint("Could not launch store: $e");
    }
  }

  Future<void> _checkUser() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      if (mounted) {
        Navigator.of(context).pushReplacement(
            customPageRouteBuilder(const MainMenuScreen()));
      }
      return;
    }

    try {
      await user.reload();
    } catch (e) {
      // Only sign out if the user account is truly invalid (disabled/deleted).
      // Network errors should NOT force a logout — the cached token is still
      // valid and Firebase will refresh it once connectivity returns.
      if (e is FirebaseAuthException &&
          (e.code == 'user-disabled' || e.code == 'user-not-found')) {
        await FirebaseAuth.instance.signOut();
      } else {
        debugPrint('user.reload() failed (non-fatal): $e');
      }
    }

    if (mounted) {
      Navigator.of(context).pushReplacement(
          customPageRouteBuilder(const MainMenuScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: CustomLoader(),
    );
  }
}