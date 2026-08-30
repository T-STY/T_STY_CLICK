import 'package:animations/animations.dart';
import 'package:click/app/settings/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../constants/app_colors.dart';
import '../components/coupon_notification_dialog.dart';
import '../components/geo_nav_icons.dart';
import '../services/local_notifications_service.dart';
import '../services/notification_actions.dart';
import '../services/push_notifications_service.dart';
import 'cart/cart_page.dart';
import 'cart/cart_provider.dart';
import 'home.dart';
import 'orderhistory/order_history_page.dart';
import 'recipes_tab.dart';

class MainMenuScreen extends StatefulWidget {

  const MainMenuScreen({
    super.key,
    this.backButton,
  });

  final Widget? backButton;

  @override
  MainMenuScreenState createState() => MainMenuScreenState();
}

class MainMenuScreenState extends State<MainMenuScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _animationController;
  final GlobalKey<CartPageState> _cartKey = GlobalKey<CartPageState>();
  final GlobalKey<HomeState> _homeKey = GlobalKey<HomeState>();
  final GlobalKey<RecetasScreenState> _recetasKey =
      GlobalKey<RecetasScreenState>();
  DateTime? _lastBackPressed;
  late final List<Widget> _allScreens = [
    RecetasScreen(key: _recetasKey),
    const OrderHistoryPage(),
    Home(key: _homeKey, onSwitchTab: updateMenu),
    CartPage(key: _cartKey),
    const SettingsPage(),
  ];
  final List<GeoIconKind> _navIcons = [
    GeoIconKind.recipe,
    GeoIconKind.orders,
    GeoIconKind.home,
    GeoIconKind.cart,
    GeoIconKind.settings,
  ];

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    WidgetsBinding.instance.addObserver(this);
    NotificationActions.instance.pending.addListener(_onPendingAction);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onPendingAction();

      if (_currentIndex == 2 && mounted) {
        PushNotificationsService.instance
            .maybeNudgePermission(context, source: 'home');
      }
    });
  }

  @override
  void dispose() {
    NotificationActions.instance.pending.removeListener(_onPendingAction);
    WidgetsBinding.instance.removeObserver(this);
    _animationController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    final cart = Provider.of<CartProvider>(context, listen: false);
    if (state == AppLifecycleState.paused) {
      if (cart.items.isNotEmpty) {
        LocalNotificationsService.instance.scheduleCartReminders();
      }
    } else if (state == AppLifecycleState.resumed) {
      LocalNotificationsService.instance.cancelCartReminders();
    }
  }

  void _onPendingAction() {
    final data = NotificationActions.instance.pending.value;
    if (data == null || !mounted) return;
    NotificationActions.instance.consume();

    final type = data['type'];
    if (type == 'order_status') {
      _goToTab(1);
    } else if (type == 'cart_reminder') {
      _goToTab(3);
    } else if (type == 'coupon') {
      final code =
          (data['couponCode'] ?? data['code'] ?? '').toString().trim();
      final message = (data['message'] ?? data['body'])?.toString();
      if (code.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            CouponNotificationDialog.show(context, code, message: message);
          }
        });
      }
    }
  }

  void _goToTab(int index) {
    if (!mounted) return;
    setState(() {
      _currentIndex = index;
      _animationController.forward(from: 0);
    });
    _maybeNudgeForTab(index);
  }

  void _maybeNudgeForTab(int index) {
    if (!mounted) return;
    final source = switch (index) {
      3 => 'cart',
      2 => 'home',
      _ => null,
    };
    if (source == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      PushNotificationsService.instance
          .maybeNudgePermission(context, source: source);
    });
  }

  int _currentIndex = 2;

  void updateMenu(int index) {
    if (index == _currentIndex) {
      if (index == 0) _recetasKey.currentState?.handleBack();
      if (index == 2) _homeKey.currentState?.handleBack();
      if (index == 3) _cartKey.currentState?.handleBack();
    }
    if (index != _currentIndex) {
      _maybeNudgeForTab(index);
    }
    setState(() {
      _currentIndex = index;
      _animationController.forward(from: 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_currentIndex == 0 &&
            (_recetasKey.currentState?.handleBack() ?? false)) {
          return;
        }
        if (_currentIndex == 2 &&
            (_homeKey.currentState?.handleBack() ?? false)) {
          return;
        }
        if (_currentIndex == 3 &&
            (_cartKey.currentState?.handleBack() ?? false)) {
          return;
        }
        final now = DateTime.now();
        if (_lastBackPressed == null ||
            now.difference(_lastBackPressed!) > const Duration(seconds: 2)) {
          _lastBackPressed = now;
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(0.0),
        child: AppBar(
          scrolledUnderElevation: 0,
          backgroundColor: Theme
              .of(context)
              .brightness == Brightness.dark
              ? Colors.transparent
              : Colors.white,
        ),
      ),
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          PageTransitionSwitcher(
            duration: const Duration(milliseconds: 400),
            transitionBuilder: (child, animation, secondAnimation) {
              return FadeThroughTransition(
                animation: animation,
                secondaryAnimation: secondAnimation,
                child: child,
              );
            },
            child: _allScreens[_currentIndex],
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: _buildElevatedNavBar(),
          ),
        ],
      ),
      ),
    );
  }

 Widget _buildElevatedNavBar() {
    double screenHeight = MediaQuery.of(context).size.height;
    double navBarHeight = (screenHeight * 0.1).clamp(65.0, 80.0);

    double screenWidth = MediaQuery.of(context).size.width;
    double iconSize = (screenWidth * 0.08).clamp(24.0, 32.0);

    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: screenWidth > 600 ? 40.0 : 8.0,
        vertical: screenWidth > 600 ? 30.0 : 20.0,
      ),
      height: navBarHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24.0),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 20.0,
            spreadRadius: 2.0,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24.0),
        child: MediaQuery.removePadding(
          context: context,
          removeBottom: true,
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: updateMenu,
            type: BottomNavigationBarType.fixed,
            elevation: 0,
            showSelectedLabels: false,
            showUnselectedLabels: false,
            selectedFontSize: 0,
            unselectedFontSize: 0,
            iconSize: iconSize,
            selectedItemColor: Theme.of(context).brightness == Brightness.dark
                ? Colors.white
                : AppColors.primary,
            unselectedItemColor: Theme.of(context).brightness == Brightness.dark
                ? Colors.grey[500]
                : const Color(0xFFD0D0D0),
            backgroundColor: Theme.of(context).brightness == Brightness.dark
                ? Colors.grey[800]
                : Colors.white,
            items: List.generate(5, (index) {
              return BottomNavigationBarItem(
                label: "",
                icon: _buildNavItem(index),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool selected = _currentIndex == index;
    final Color color = selected
        ? (isDark ? Colors.white : AppColors.primary)
        : (isDark ? Colors.grey[500]! : const Color(0xFFD0D0D0));
    final double iconSize =
        (MediaQuery.of(context).size.width * 0.08).clamp(24.0, 32.0);
    final Widget icon =
        GeoNavIcon(kind: _navIcons[index], color: color, size: iconSize);

    return ScaleTransition(
      scale: selected
          ? _animationController.drive(Tween<double>(begin: 1.0, end: 1.2))
          : const AlwaysStoppedAnimation(1.0),
      child: index == 3
          ? Consumer<CartProvider>(
              builder: (context, cart, child) {
                int itemCount = cart.items.length;
                return Badge(
                  label: Text(itemCount.toString()),
                  isLabelVisible: itemCount > 0,
                  backgroundColor: AppColors.primary,
                  child: icon,
                );
              },
            )
          : icon,
    );
  }
}
