enum CardType {
  visa,
  mastercard,
  americanExpress,
  rupay,
  unionpay,
  discover,
  elo,
  hipercard,
  t_sty, // Add your custom card type
}


/// The type of floating event.
enum FloatingType {
  pointer,
  gyroscope;

  bool get isPointer => this == pointer;

  bool get isGyroscope => this == gyroscope;
}
