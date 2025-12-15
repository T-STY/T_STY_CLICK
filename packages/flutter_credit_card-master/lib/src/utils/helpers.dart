import 'package:flutter/widgets.dart';

import '../models/custom_card_type_icon.dart';
import 'constants.dart';
import 'enumerations.dart';

/// Uses the predefined prefixes from [AppConstants.cardNumPatterns] to match
/// with the prefix of the [cardNumber] in order to detect the [CardType].
/// Defaults to [CardType.otherBrand] if unable to detect a type.
CardType detectCCType(String cardNumber) {
  if (cardNumber.isEmpty) {
    return CardType.t_sty; // Consider using a default type like unknown
  }

  // Remove any spaces
  cardNumber = cardNumber.replaceAll(RegExp(r'\s+\b|\b\s'), '');

  // Check for 'T_STY-' prefix first
  if (cardNumber.startsWith('T_STY-') && cardNumber.length == 15) { // "T_STY-" + 10 digits = 15 characters
    return CardType.t_sty;
  }

  // Ensure the first character is a digit
  if (!RegExp(r'^\d').hasMatch(cardNumber)) {
    return CardType.t_sty; // Or another default type
  }

  final int firstDigit;
  try {
    firstDigit = int.parse(cardNumber.substring(0, 1));
  } catch (e) {
    return CardType.t_sty; // Default if parsing fails
  }

  if (!AppConstants.cardNumPatterns.containsKey(firstDigit)) {
    return CardType.t_sty;
  }

  final Map<List<int?>, CardType> cardNumPatternSubMap =
  AppConstants.cardNumPatterns[firstDigit]!;

  final int ccPatternNum;
  try {
    ccPatternNum = int.parse(cardNumber);
  } catch (e) {
    return CardType.t_sty;
  }

  for (final List<int?> range in cardNumPatternSubMap.keys) {
    if (range.length != 2 || range.first == null) {
      continue;
    }

    final int start = range.first!;
    final int? end = range.last;

    // Adjust the cardNumber prefix as per the length of start prefix range.
    final int startLen = start.toString().length;
    if (startLen > cardNumber.length) {
      continue; // Not enough digits to parse
    }

    final int subPatternNum;
    try {
      subPatternNum = int.parse(cardNumber.substring(0, startLen));
    } catch (e) {
      continue;
    }

    if ((end == null && subPatternNum == start) ||
        ((end != null) &&
            subPatternNum <= end &&
            subPatternNum >= start)) {
      return cardNumPatternSubMap[range]!;
    }
  }

  return CardType.t_sty; // Default if no pattern matches
}


/// Returns the icon for the card type if detected else will return a
/// [SizedBox].
Widget getCardTypeImage({
  required List<CustomCardTypeIcon> customIcons,
  CardType? cardType,
}) {
  const Widget blankSpace =
  SizedBox.square(dimension: AppConstants.creditCardIconSize);

  if (cardType == null) {
    return blankSpace;
  }

  return customIcons.firstWhere(
        (CustomCardTypeIcon element) => element.cardType == cardType,
    orElse: () {
      final bool isKnownCardType =
      AppConstants.cardTypeIconAsset.containsKey(cardType);

      return CustomCardTypeIcon(
        cardType: isKnownCardType ? cardType : CardType.t_sty,
        cardImage: isKnownCardType
            ? Image.asset(
          AppConstants.cardTypeIconAsset[cardType]!,
          height: AppConstants.creditCardIconSize,
          width: AppConstants.creditCardIconSize,
          package: AppConstants.packageName,
        )
            : blankSpace,
      );
    },
  ).cardImage;
}
