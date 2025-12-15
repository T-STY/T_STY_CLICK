import 'dart:math';

import 'package:flutter/rendering.dart';

import 'asset_paths.dart';
import 'enumerations.dart';

class AppConstants {
  const AppConstants._();

  static const String packageName = 'flutter_credit_card';
  static const String fontFamily = 'halter';

  static const String threeX = 'XXX';
  static const String fourX = 'XXXX';
  static const String sixteenX = 'XXXX XXXX XXXX XXXX';
  static const String cardNumberMask = 'T_STY-0000000000'; // "T_STY-" + 10 digits
  static const String expiryDateMask = '00/00';
  static const String cvvMask = '0000';
  static const String cvv = 'CVV';
  static const String cardHolderCaps = 'TITULAR DE TARJETA';
  static const String cardHolder = 'Titular de Tarjeta';
  static const String cardNumber = 'Número de telefono';
  static const String expiryDate = 'Fecha de Caducidad';
  static const String expiryDateShort = 'MM/YY';
  static const String validThru = 'CLIENTE\nDESDE';
  static const String cvvValidationMessage = 'Por favor, introduzca un NIP válido';
  static const String dateValidationMessage = 'Por favor, introduzca una fecha válida';
  static const String numberValidationMessage = 'Por favor ingrese un número válido';

  static const double floatWebBreakPoint = 650;
  static const double creditCardAspectRatio = 0.5714;
  static const double creditCardPadding = 16;
  static const double creditCardIconSize = 48;
  static const BorderRadius creditCardBorderRadius = BorderRadius.all(
    Radius.circular(10),
  );

  static const double minRestBackVel = 0.01;
  static const double maxRestBackVel = 0.05;
  static const double defaultRestBackVel = 0.8;

  static const Duration fps60 = Duration(microseconds: 16666);
  static const Duration fps60Offset = Duration(microseconds: 16667);
  static const Duration defaultAnimDuration = Duration(milliseconds: 500);

  /// Color constants
  static const Color defaultGlareColor = Color(0xffFFFFFF);
  static const Color floatingShadowColor = Color(0x4D000000);
  static const Color defaultCardBgColor = Color(0xff1b447b);

  static const double defaultMaximumAngle = pi / 10;
  static const double minBlurRadius = 10;

  /// Gyroscope channel constants
  static const String gyroMethodChannelName = 'com.simform.flutter_credit_card';
  static const String gyroEventChannelName =
      'com.simform.flutter_credit_card/gyroscope';
  static const String isGyroAvailableMethod = 'isGyroscopeAvailable';
  static const String initiateMethod = 'initiateEvents';
  static const String cancelMethod = 'cancelEvents';

  // TODO(aditya): Switch to records instead of list as key for the inner map. For ex (start: 655021, end: 655058).
  /// Credit Card number prefix patterns as of March 2019.
  ///
  /// The key of outer map divides all the available prefixes using the
  /// first digit of the credit card number, decreasing the number of
  /// prefixes to loop through.
  ///
  /// The key of inner [Map] is a list of length 2 that represents range of the
  /// number prefix (i.e. [655021, 655058] matches any number prefix that falls
  /// under range of 655021 and 655058 inclusive), and the value is the card
  /// type that range of number prefix is for.
  ///
  /// Make sure to keep the keys sorted in descending order starting from the
  /// first digit of the start range.
  static const Map<int, Map<List<int?>, CardType>> cardNumPatterns = <int, Map<List<int?>, CardType>>{
    9: <List<int?>, CardType>{
      <int?>[9999, 9999]: CardType.t_sty, // Unique prefix for T_STY-
    },
    6: <List<int?>, CardType>{
      <int?>[655021, 655058]: CardType.elo,
      <int?>[655000, 655019]: CardType.elo,
      <int?>[6521, 6522]: CardType.rupay,
      <int?>[651652, 651679]: CardType.elo,
      <int?>[650901, 650978]: CardType.elo,
      <int?>[650720, 650727]: CardType.elo,
      <int?>[650700, 650718]: CardType.elo,
      <int?>[650541, 650598]: CardType.elo,
      <int?>[650485, 650538]: CardType.elo,
      <int?>[650405, 650439]: CardType.elo,
      <int?>[650035, 650051]: CardType.elo,
      <int?>[650031, 650033]: CardType.elo,
      <int?>[65, null]: CardType.discover,
      <int?>[644, 649]: CardType.discover,
      <int?>[636368, null]: CardType.elo,
      <int?>[636297, null]: CardType.elo,
      <int?>[627780, null]: CardType.elo,
      <int?>[622126, 622925]: CardType.discover,
      <int?>[62, null]: CardType.unionpay,
      <int?>[606282, null]: CardType.hipercard,
      <int?>[6011, null]: CardType.discover,
      <int?>[60, null]: CardType.rupay,
    },
    5: <List<int?>, CardType>{
      <int?>[51, 55]: CardType.mastercard,
      <int?>[509000, 509999]: CardType.elo,
      <int?>[506699, 506778]: CardType.elo,
      <int?>[504175, null]: CardType.elo,
    },
    4: <List<int?>, CardType>{
      <int?>[457631, 457632]: CardType.elo,
      <int?>[457393, null]: CardType.elo,
      <int?>[451416, null]: CardType.elo,
      <int?>[438935, null]: CardType.elo,
      <int?>[431274, null]: CardType.elo,
      <int?>[401178, 401179]: CardType.elo,
      <int?>[4, null]: CardType.visa,
    },
    3: <List<int?>, CardType>{
      <int?>[34, 37]: CardType.americanExpress,
    },
    2: <List<int?>, CardType>{
      <int?>[2720, null]: CardType.mastercard,
      <int?>[270, 271]: CardType.mastercard,
      <int?>[23, 26]: CardType.mastercard,
      <int?>[223, 229]: CardType.mastercard,
      <int?>[2221, 2229]: CardType.mastercard,
    },

  };

  // AppConstants.dart
  static const Map<CardType, String> cardTypeIconAsset = <CardType, String>{
    CardType.visa: AssetPaths.visa,
    CardType.rupay: AssetPaths.rupay,
    CardType.americanExpress: AssetPaths.americanExpress,
    CardType.mastercard: AssetPaths.mastercard,
    CardType.unionpay: AssetPaths.unionpay,
    CardType.discover: AssetPaths.discover,
    CardType.elo: AssetPaths.elo,
    CardType.hipercard: AssetPaths.hipercard,
    CardType.t_sty: AssetPaths.t_sty, // Mapped custom card type to its icon
  };


}
