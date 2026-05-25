// Smoke end-to-end tests against the local Firebase emulator suite.
//
// Run (needs a booted device/simulator + emulators running):
//
//   firebase emulators:start --only firestore,auth,functions      # terminal 1
//   flutter test integration_test/smoke_test.dart \
//     --dart-define=USE_FIREBASE_EMULATOR=true                     # terminal 2
//
// These prove the app's Auth / Firestore / Functions wiring reaches the
// emulators and that a real Cloud Function round-trips — without touching
// production. They are intentionally self-contained (no pre-seeded data).
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:click/firebase_emulators.dart';
import 'package:click/firebase_options.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await connectToFirebaseEmulatorsIfNeeded();
    expect(
      useFirebaseEmulator,
      isTrue,
      reason: 'Run with --dart-define=USE_FIREBASE_EMULATOR=true',
    );
    // Fresh session each run.
    await FirebaseAuth.instance.signOut();
  });

  testWidgets('Auth emulator: create + sign in a user', (tester) async {
    final email = 'qa${DateTime.now().microsecondsSinceEpoch}@test.dev';
    final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
      email: email,
      password: 'pw123456',
    );
    expect(cred.user, isNotNull);
    expect(FirebaseAuth.instance.currentUser?.uid, cred.user!.uid);
  });

  testWidgets('Firestore emulator: owner can write + read their own subtree',
      (tester) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final ref = FirebaseFirestore.instance.doc('users/$uid/cart/item1');
    await ref.set({'qty': 2, 'productId': 'p1'});
    final snap = await ref.get();
    expect(snap.data()?['qty'], 2);
  });

  testWidgets('Firestore rules: a stranger\'s order is unreadable',
      (tester) async {
    // Reading an order that isn't ours must be denied by the rules.
    await expectLater(
      FirebaseFirestore.instance.doc('orders/not-mine').get(),
      throwsA(isA<FirebaseException>()),
    );
  });

  testWidgets('Functions emulator: getRewardsBalance round-trips',
      (tester) async {
    final res = await FirebaseFunctions.instance
        .httpsCallable('getRewardsBalance')
        .call();
    final data = Map<String, dynamic>.from(res.data as Map);
    expect(data['hasWallet'], isFalse);
    expect(data['saldo'], 0);
  });
}
