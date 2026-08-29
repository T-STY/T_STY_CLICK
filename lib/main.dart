import 'dart:async';
import 'dart:io';
import 'package:click/theme.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app/apoyo/apoyo_cart_provider.dart';
import 'app/cart/cart_provider.dart';
import 'app/main.dart';
import 'components/custom_loader.dart';
import 'firebase_emulators.dart';
import 'firebase_options.dart';
import 'package:provider/provider.dart';
import 'services/local_notifications_service.dart';
import 'services/push_notifications_service.dart';

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
  // Loads the Spanish date-symbol tables that `DateFormat(<pattern>, 'es')`
  // depends on. Without this, any `DateFormat(..., 'es')` call throws
  // LocaleDataException at first build — e.g. the order history's
  // "2 jun · 14:30" formatter. Cheap one-time tree shake.
  await initializeDateFormatting('es', null);
  await connectToFirebaseEmulatorsIfNeeded();

  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: [SystemUiOverlay.top],
  );
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  if (!useFirebaseEmulator) {
    try {
      await FirebaseAppCheck.instance.activate(
        androidProvider:
            kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
        appleProvider:
            kDebugMode ? AppleProvider.debug : AppleProvider.appAttest,
      );
    } catch (e) {
      debugPrint('App Check activation failed (non-fatal): $e');
    }
  }

  unawaited(PushNotificationsService.instance.init());
  unawaited(LocalNotificationsService.instance.init());

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => ThemeNotifier(
          AppTheme(context).lightTheme,
          AppTheme(context).darkTheme,
        )),
        ChangeNotifierProvider(create: (_) => CartProvider()),
        // Apoyo Social keeps its own selection: ids and quantities for one
        // weekly cycle, never prices, and never mixed into the store cart the
        // user may already have waiting for a normal delivery.
        ChangeNotifierProvider(create: (_) => ApoyoCartProvider()),
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
  bool _isOnline = true;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  StreamSubscription<User?>? _authSub;
  String? _lastFcmUid;

  @override
  void initState() {
    super.initState();
    _checkConnectivity();
    _connSub = Connectivity().onConnectivityChanged.listen((result) {
      final newValue = !result.contains(ConnectivityResult.none);
      if (!mounted) return;
      if (_isOnline != newValue) {
        setState(() => _isOnline = newValue);
      }
    });
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        _lastFcmUid = user.uid;
        PushNotificationsService.instance.registerForCurrentUser();
      } else if (_lastFcmUid != null) {
        final prev = _lastFcmUid!;
        _lastFcmUid = null;
        PushNotificationsService.instance.clearForUser(prev);
      }
    });
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _authSub?.cancel();
    super.dispose();
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
    return Consumer<ThemeNotifier>(
      builder: (context, themeNotifier, child) {
        _setStatusBarStyle(context);

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          navigatorKey: PushNotificationsService.navigatorKey,
          title: 'T_STY: Mi Supercito',
          theme: themeNotifier.currentTheme,
          home: _isOnline
              ? const CheckUserScreen()
              : Scaffold(
                  body: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.wifi_off, size: 50, color: Colors.grey),
                        const SizedBox(height: 20),
                        const Text("No Internet Connection",
                            style: TextStyle(fontSize: 18)),
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
      },
    );
  }

  void _setStatusBarStyle(BuildContext context) {
    ThemeData theme = Theme.of(context);
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: theme.brightness == Brightness.dark
          ? Brightness.light
          : Brightness.dark,
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

  static const String _flexibleDismissKey = 'flexible_update_dismissed_at';
  static const Duration _flexibleCooldown = Duration(hours: 24);

  Future<void> _runStartupChecks() async {
    _UpdateType updateStatus = await _checkForUpdate();

    if (updateStatus == _UpdateType.forced) {
      if (mounted) _showUpdateDialog(forced: true);
    } else if (updateStatus == _UpdateType.flexible &&
        await _shouldShowFlexiblePrompt()) {
      if (mounted) _showUpdateDialog(forced: false);
    } else {
      await _checkUser();
    }
  }

  Future<bool> _shouldShowFlexiblePrompt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dismissedAt = prefs.getInt(_flexibleDismissKey) ?? 0;
      final elapsed = DateTime.now().millisecondsSinceEpoch - dismissedAt;
      return elapsed > _flexibleCooldown.inMilliseconds;
    } catch (_) {
      return true;
    }
  }

  Future<void> _dismissFlexiblePrompt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
          _flexibleDismissKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  Future<_UpdateType> _checkForUpdate() async {
    try {
      final remoteConfig = FirebaseRemoteConfig.instance;

      await remoteConfig.setDefaults(const {
        'min_required_version': '0.0.0',
        'latest_recommended_version': '0.0.0',
      });

      await remoteConfig.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 5),
        minimumFetchInterval: const Duration(hours: 1),
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
                ? "Debes actualizar la aplicación para continuar usando T_STY: Mi Supercito."
                : "¡Hay una nueva versión de T_STY: Mi Supercito disponible con nuevas funciones!"),
            actions: [
              if (!forced)
                TextButton(
                  onPressed: () async {
                    final nav = Navigator.of(context);
                    await _dismissFlexiblePrompt();
                    nav.pop();
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
    User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      user = await FirebaseAuth.instance
          .authStateChanges()
          .where((u) => u != null)
          .first
          .timeout(const Duration(seconds: 3), onTimeout: () => null);
      user ??= FirebaseAuth.instance.currentUser;
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
