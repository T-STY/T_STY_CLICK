import 'package:flutter/material.dart';

import 'constants/constants.dart';

class AppTheme {
  final BuildContext context;
  AppTheme(this.context);

  /// Default Font Family Name
  final String _defaultFont = 'Grodita';

  ThemeData get lightTheme {
    return ThemeData(
      primaryColor: Colors.white,
      scaffoldBackgroundColor: Colors.white,
      colorScheme: const ColorScheme.light(
        primary:  Colors.black,
        secondary: Colors.white, // Or any other color you prefer
        // ... you can add other properties as needed ...
      ),
      brightness: Brightness.light,
      fontFamily: _defaultFont,
      textTheme: ThemeData.light().textTheme.apply(
            fontFamily: _defaultFont,
          ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          minimumSize: const Size(double.infinity, 40),
          elevation: 0,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.all(AppDefaults.padding),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.primary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: AppDefaults.borderRadius,
          borderSide: BorderSide.none,
        ),
        // enabledBorder: defaultOutlineInputBorder,
        // focusedBorder: defaultOutlineInputBorder,
        floatingLabelBehavior: FloatingLabelBehavior.never,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: Theme.of(context)
            .textTheme
            .titleLarge!
            .copyWith(fontFamily: 'Avenir'),
        iconTheme: const IconThemeData(color: AppColors.defaultBlack),
      ),
      buttonTheme: const ButtonThemeData(
        shape: StadiumBorder(),
        padding: EdgeInsets.all(16),
      ),
      sliderTheme: const SliderThemeData(
        thumbColor: AppColors.primary,
        activeTrackColor: AppColors.primary,
      ),
      cardTheme: const CardThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(16.0),
          ),
        ),
      ),
    );
  }

  ThemeData get darkTheme {
    return ThemeData(
      primaryColor: AppColors.primaryDark, // assuming you have a dark variant
      scaffoldBackgroundColor: AppColors.scaffoldBackgroundDark,
      colorScheme: const ColorScheme.dark(secondary: AppColors.primaryDark),
      brightness: Brightness.dark,
      fontFamily: _defaultFont,
      textTheme: ThemeData.dark().textTheme.apply(
        fontFamily: _defaultFont,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryDark,
          minimumSize: const Size(double.infinity, 40),
          elevation: 0,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.all(AppDefaults.padding),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.primaryDark),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.inputFieldDark, // assuming a dark background color
        border: OutlineInputBorder(
          borderRadius: AppDefaults.borderRadius,
          borderSide: BorderSide.none,
        ),
        floatingLabelBehavior: FloatingLabelBehavior.never,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.appBarDark, // assuming a darker app bar color
        elevation: 0,
        centerTitle: true,
        titleTextStyle: Theme.of(context)
            .textTheme
            .titleLarge!
            .copyWith(fontFamily: 'Avenir', color: Colors.white),
        iconTheme: const IconThemeData(color: AppColors.defaultWhite),
      ),
      buttonTheme: const ButtonThemeData(
        shape: StadiumBorder(),
        padding: EdgeInsets.all(16),
      ),
      sliderTheme: const SliderThemeData(
        thumbColor: AppColors.primaryDark,
        activeTrackColor: AppColors.primaryDark,
      ),
      cardTheme: const CardThemeData(
        color: AppColors.cardDark, // assuming a darker card color
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(16.0),
          ),
        ),
      ),
    );
  }


}
