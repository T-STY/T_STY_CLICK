import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Mirrors the allow-list in `firestore.rules` (isAdmin) and the Cloud
/// Functions' ADMIN_UIDS. Used ONLY to keep developer tools — like the
/// raycaster's mod menu — out of customers' hands.
///
/// This is a UI gate, not a security boundary: a tampered client could skip
/// it. The actual protection against minting puntos is the server-side daily
/// earn cap inside `updateRewardsSaldo`, which bounds ANY client.
const List<String> kArcadeAdminUids = <String>[
  'HnqE2Asz6HPvmM10OAIAsu1RaL62',
  'dZ8iFN6Gg4N3vykY7GUya2hyYiL2',
];

bool isArcadeAdmin() {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  return uid != null && kArcadeAdminUids.contains(uid);
}

/// Cost of one play, in puntos (1 punto = $1 MXN off an order).
///
/// Kept deliberately low: puntos are earned at 1% of spend, so at the old
/// price of 5 a single play cost the entire reward from a $500 order and the
/// arcade priced itself out of being a habit. The floor on how low this can
/// go is set by the games that pay puntos back — the server-side daily earn
/// cap in `updateRewardsSaldo` is what keeps a cheap play from becoming a
/// farming loop.
const double kArcadePlayCost = 2.0;

final ValueNotifier<int> arcadeInsufficientSaldoTick = ValueNotifier<int>(0);

void notifyInsufficientSaldo() => arcadeInsufficientSaldoTick.value++;

/// Bridge for the "this replay costs N puntos" prompt.
///
/// The request originates deep inside a game screen (13 of them all call
/// [chargeForReplay]), but the prompt has to be drawn by the arcade shell so
/// it lands INSIDE the console bezel, under the CRT overlay — a per-screen
/// dialog would float over the whole phone and break the cabinet illusion.
/// So the game asks here, the shell renders the prompt and completes the
/// future with the player's answer. One implementation, zero changes to the
/// individual games.
final ValueNotifier<Completer<bool>?> arcadeReplayConfirm =
    ValueNotifier<Completer<bool>?>(null);

/// Nesting depth of the hub's attract-mode demo (`_HeroDemoGame`).
///
/// The demo builds a REAL cartridge, so when it plays itself to game over its
/// restart runs the PAID replay path against the signed-in user's wallet —
/// charging someone for a demo they never started, on a loop, while they just
/// sit on the hub. A counter rather than a bool because several demo widgets
/// can be mounted at once (hero card + carousel).
int _arcadeDemoDepth = 0;

bool get arcadeDemoMode => _arcadeDemoDepth > 0;
void enterArcadeDemo() => _arcadeDemoDepth++;
void exitArcadeDemo() {
  if (_arcadeDemoDepth > 0) _arcadeDemoDepth--;
}

Future<bool> _askReplayConfirm() {
  final pending = arcadeReplayConfirm.value;
  // A prompt is already on screen — don't stack a second one.
  if (pending != null && !pending.isCompleted) return Future<bool>.value(false);
  final completer = Completer<bool>();
  arcadeReplayConfirm.value = completer;
  return completer.future;
}

/// Server-mediated saldo move. Replaces the old client-side
/// `batch.update({'saldo': ...})` pattern that the 11 arcade games
/// used — those writes hit `rewards/{docId}` which is admin-only,
/// so they silently failed for every non-admin user. Now every
/// client move (debits AND credits) routes through the
/// `updateRewardsSaldo` Cloud Function, which:
///   * verifies auth
///   * resolves the wallet via the caller's `users/{uid}/rewardsCard/cardInfo`
///   * caps |delta| at 50 per call as an anti-cheat backstop
///   * applies the delta in a transaction so concurrent moves
///     can't double-spend
///   * mirrors the new saldo to the user's owner-readable card doc
///   * returns the authoritative new saldo
///
/// On success returns the new saldo. On failure (network, anti-
/// cheat reject, no wallet, insufficient funds via server-side
/// floor at 0) returns null and the caller should leave its local
/// optimistic state alone — the next successful call will catch up
/// against the server's authoritative value.
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

/// Game restart charge. Pre-flight checks the cached saldo to fail
/// fast (and surface the insufficient-saldo toast) without burning
/// a CF round-trip; the server-side transaction is still the
/// source of truth, so a stale client view that under-counts can't
/// short-circuit a real charge that's about to succeed.
///
/// The `rewardsDocRef` parameter is kept on the signature for
/// backwards compatibility with the game-screen call sites — the
/// CF resolves the wallet itself from the auth context, so the
/// ref isn't actually used.
Future<double?> chargeForReplay({
  required String userId,
  required DocumentReference rewardsDocRef,
  required double currentSaldo,
}) async {
  // The attract-mode demo restarts itself indefinitely. It must never spend
  // the user's puntos, and must never raise the cost prompt — returning the
  // unchanged balance lets the demo loop freely for free.
  if (arcadeDemoMode) return currentSaldo;

  if (currentSaldo < kArcadePlayCost) {
    notifyInsufficientSaldo();
    return null;
  }
  // Never spend without asking. Every game's restart path lands here, so the
  // confirmation can't be skipped by any individual screen.
  final confirmed = await _askReplayConfirm();
  if (!confirmed) return null;
  return applyArcadeDelta(
    delta: -kArcadePlayCost,
    reason: 'arcade_replay',
  );
}
