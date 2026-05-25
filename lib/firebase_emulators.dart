import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Whether the app should talk to the local Firebase emulator suite instead of
/// production. Off by default — turn it on for integration tests / manual QA:
///
///   flutter run --dart-define=USE_FIREBASE_EMULATOR=true
///   flutter test integration_test --dart-define=USE_FIREBASE_EMULATOR=true
const bool useFirebaseEmulator =
    bool.fromEnvironment('USE_FIREBASE_EMULATOR', defaultValue: false);

// Android emulators reach the host machine via 10.0.2.2; everything else uses
// loopback.
String get _emulatorHost {
  if (!kIsWeb && Platform.isAndroid) return '10.0.2.2';
  return '127.0.0.1';
}

/// Point Firestore / Auth / Functions at the local emulators when
/// [useFirebaseEmulator] is set. Call once, right after Firebase.initializeApp.
/// No-op in production builds.
Future<void> connectToFirebaseEmulatorsIfNeeded() async {
  if (!useFirebaseEmulator) return;
  final host = _emulatorHost;

  FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
  FirebaseFunctions.instance.useFunctionsEmulator(host, 5001);
  await FirebaseAuth.instance.useAuthEmulator(host, 9099);
}
