import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

const double kArcadePlayCost = 5.0;

final ValueNotifier<int> arcadeInsufficientSaldoTick = ValueNotifier<int>(0);

void notifyInsufficientSaldo() => arcadeInsufficientSaldoTick.value++;

Future<double?> chargeForReplay({
  required String userId,
  required DocumentReference rewardsDocRef,
  required double currentSaldo,
}) async {
  if (currentSaldo < kArcadePlayCost) {
    notifyInsufficientSaldo();
    return null;
  }
  final newSaldo = currentSaldo - kArcadePlayCost;
  try {
    final userCardRef = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('rewardsCard')
        .doc('cardInfo');
    final batch = FirebaseFirestore.instance.batch();
    batch.update(userCardRef, {'saldo': newSaldo});
    batch.update(rewardsDocRef, {'saldo': newSaldo});
    await batch.commit();
  } catch (_) {}
  return newSaldo;
}
