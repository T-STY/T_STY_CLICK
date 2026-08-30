import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

const List<String> kArcadeAdminUids = <String>[
  'HnqE2Asz6HPvmM10OAIAsu1RaL62',
  'dZ8iFN6Gg4N3vykY7GUya2hyYiL2',
];

bool isArcadeAdmin() {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  return uid != null && kArcadeAdminUids.contains(uid);
}

const double kArcadePlayCost = 2.0;

final ValueNotifier<int> arcadeInsufficientSaldoTick = ValueNotifier<int>(0);

void notifyInsufficientSaldo() => arcadeInsufficientSaldoTick.value++;

final ValueNotifier<Completer<bool>?> arcadeReplayConfirm =
    ValueNotifier<Completer<bool>?>(null);

int _arcadeDemoDepth = 0;

bool get arcadeDemoMode => _arcadeDemoDepth > 0;
void enterArcadeDemo() => _arcadeDemoDepth++;
void exitArcadeDemo() {
  if (_arcadeDemoDepth > 0) _arcadeDemoDepth--;
}

Future<bool> _askReplayConfirm() {
  final pending = arcadeReplayConfirm.value;

  if (pending != null && !pending.isCompleted) return Future<bool>.value(false);
  final completer = Completer<bool>();
  arcadeReplayConfirm.value = completer;
  return completer.future;
}

Future<double?> applyArcadeDelta({
  required double delta,
  required String reason,
}) async {
  if (delta == 0) return null;
  try {
    final callable =
        FirebaseFunctions.instance.httpsCallable('updateRewardsSaldo');
    final res = await callable.call({
      'delta': delta,
      'reason': reason,
    });
    final data = res.data;
    if (data is Map) {
      final raw = data['saldo'];
      if (raw is num) return raw.toDouble();
    }
  } catch (e) {
    if (kDebugMode) debugPrint('updateRewardsSaldo failed: $e');
  }
  return null;
}

Future<double?> chargeForReplay({
  required String userId,
  required DocumentReference rewardsDocRef,
  required double currentSaldo,
}) async {

  if (arcadeDemoMode) return currentSaldo;

  if (currentSaldo < kArcadePlayCost) {
    notifyInsufficientSaldo();
    return null;
  }

  final confirmed = await _askReplayConfirm();
  if (!confirmed) return null;
  return applyArcadeDelta(
    delta: -kArcadePlayCost,
    reason: 'arcade_replay',
  );
}
