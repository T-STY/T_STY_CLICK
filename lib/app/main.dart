import 'package:animations/animations.dart';
import 'package:click/app/settings/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_iconly/flutter_iconly.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import 'cart/cart_page.dart';
import 'cart/cart_provider.dart';
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
    // 1. Set a stable height range.
    // This ensures it's at least 65px on small phones and max 80px on large screens.
    double screenHeight = MediaQuery
        .of(context)
        .size
        .height;
    double navBarHeight = (screenHeight * 0.1).clamp(65.0, 80.0);

    // 2. Clamp icon size so it doesn't get massive on tablets/web
    double screenWidth = MediaQuery
        .of(context)
        .size
        .width;
    double iconSize = (screenWidth * 0.08).clamp(24.0, 32.0);

    return Container(
      // 3. Margin should be smaller on mobile, larger on web
      margin: EdgeInsets.symmetric(
          horizontal: screenWidth > 600 ? 40.0 : 16.0,
          vertical: screenWidth > 600 ? 30.0 : 20.0
      ),
      height: navBarHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24.0), // Match ClipRRect
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 20.0,
            spreadRadius: 2.0, // Reduced spread to avoid "glow" overlap
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24.0),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: updateMenu,
          // Use the built-in tap handler
          type: BottomNavigationBarType.fixed,
          selectedFontSize: 0,
          unselectedFontSize: 0,
          iconSize: iconSize,
          selectedItemColor: Theme
              .of(context)
              .brightness == Brightness.dark
              ? Colors.white
              : AppColors.primary,
          unselectedItemColor: Theme
              .of(context)
              .brightness == Brightness.dark
              ? Colors.grey[500]
              : const Color(0xFFD0D0D0),
          backgroundColor: Theme
              .of(context)
              .brightness == Brightness.dark
              ? Colors.grey[800]
              : Colors.white,
          items: List.generate(5, (index) {
            return BottomNavigationBarItem(
              label: "",
              // 4. Removed the heavy vertical padding here
              icon: _buildNavItem(index),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index) {
    // 5. Use a simple Padding or Center instead of a huge fixed number
    return Padding(
      padding: const EdgeInsets.only(top: 8.0), // Small top nudge for alignment
      child: ScaleTransition(
        scale: _currentIndex == index
            ? _animationController.drive(Tween<double>(begin: 1.0, end: 1.2))
            : const AlwaysStoppedAnimation(1.0),
        child: index == 3 // Index 3 is your Cart/Bag icon
            ? Consumer<CartProvider>(
          builder: (context, cart, child) {
            // Get the total number of items
            int itemCount = cart.items.length;

            return Badge(
              label: Text(itemCount.toString()),
              isLabelVisible: itemCount > 0, // Hide badge if cart is empty
              backgroundColor: AppColors.primary,
              child: Icon(
                _currentIndex == index
                    ? _selectedIcons[index]
                    : _unselectedIcons[index],
              ),
            );
          },
        )
            : Icon(
          _currentIndex == index
              ? _selectedIcons[index]
              : _unselectedIcons[index],
        ),
      ),
    );
  }
}
