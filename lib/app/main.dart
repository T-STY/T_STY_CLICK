import 'package:animations/animations.dart';
import 'package:click/app/settings/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_iconly/flutter_iconly.dart';

import '../../constants/app_colors.dart';
import 'cart/cart_page.dart';
import 'category/category.dart';
import 'home.dart';
import 'orderhistory/order_history_page.dart';


class MainMenuScreen extends StatefulWidget {

  const MainMenuScreen({
    super.key,
    this.backButton,
  });

  final Widget? backButton;

  @override
  MainMenuScreenState createState() => MainMenuScreenState();
}

class MainMenuScreenState extends State<MainMenuScreen> with TickerProviderStateMixin {
  late AnimationController _animationController;
  late final List<Widget> _allScreens = [
    CategoriesPage(),
    const OrderHistoryPage(),
    const Home(),
    const CartPage(),
    const SettingsPage(),
  ];
  final List<IconData> _selectedIcons = [
    IconlyBold.category,
    IconlyBold.notification,
    Icons.home,
    IconlyBold.bag,
    IconlyBold.setting
  ];

  final List<IconData> _unselectedIcons = [
    IconlyLight.category,
    IconlyLight.notification,
    Icons.home,
    IconlyLight.bag,
    IconlyLight.setting
  ];



  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  int _currentIndex = 2;

  void updateMenu(int index) {
    setState(() {
      _currentIndex = index;
      _animationController.forward(from: 0);
    });
  }

  @override
  Widget build(BuildContext context) {
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
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          PageTransitionSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, animation, secondAnimation) {
              return SharedAxisTransition(
                animation: animation,
                secondaryAnimation: secondAnimation,
                transitionType: SharedAxisTransitionType.horizontal,
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
    );
  }

  Widget _buildElevatedNavBar() {
    // Adjusting height and padding for better control over nav bar appearance
    double navBarHeight = MediaQuery.of(context).size.height * 0.1;
    double iconSize = MediaQuery.of(context).size.width * 0.08; // Example for responsive icon size

    // Determine bottom padding based on platform
    if (Theme.of(context).platform == TargetPlatform.iOS) {
// Reduce or remove additional bottom padding for iOS if needed
    }

    return Container(
      height: navBarHeight, // Include bottom padding in the total height
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 25.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16.0),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 20.0,
            spreadRadius: 10.0,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24.0),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          type: BottomNavigationBarType.fixed,
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
              icon: _paddedNavItem(
                _buildNavItem(index),
                index,
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _paddedNavItem(Widget child, int index) {
    return GestureDetector(
      onTap: () => updateMenu(index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 27), // Reduced padding
        child: child,
      ),
    );
  }

  Widget _buildNavItem(int index) {
    return ScaleTransition(
      scale: _currentIndex == index ? _animationController.drive(Tween<double>(begin: 1.0, end: 1.2)) : const AlwaysStoppedAnimation(1.0),
      child: Icon(
        _currentIndex == index ? _selectedIcons[index] : _unselectedIcons[index],
      ),
    );
  }
}

