import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyChTcuRwOh3aWW-Bbakfsg5cQ1vkyVAw1Y',
    appId: '1:163376358846:web:d3687c8e05643b3c8405ef',
    messagingSenderId: '163376358846',
    projectId: 'arthemis-f2966',
    authDomain: 'arthemis-f2966.firebaseapp.com',
    databaseURL: 'https://arthemis-f2966-default-rtdb.firebaseio.com',
    storageBucket: 'arthemis-f2966.appspot.com',
    measurementId: 'G-LGTYC2VX4Y',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDCo76QVr-P_hs8vUNwTIfh0L9-kaAG5a4',
    appId: '1:163376358846:android:3a7b44460abc216b8405ef',
    messagingSenderId: '163376358846',
    projectId: 'arthemis-f2966',
    databaseURL: 'https://arthemis-f2966-default-rtdb.firebaseio.com',
    storageBucket: 'arthemis-f2966.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAPxcV8j0LR0WOhEdY-YMxg5-9eexXIIN8',
    appId: '1:163376358846:ios:d708cd0888c2cbdf8405ef',
    messagingSenderId: '163376358846',
    projectId: 'arthemis-f2966',
    databaseURL: 'https://arthemis-f2966-default-rtdb.firebaseio.com',
    storageBucket: 'arthemis-f2966.appspot.com',
    iosClientId: '163376358846-9g9g22hd7rgslqqdnm53lqung8b3pk29.apps.googleusercontent.com',
    iosBundleId: 'com.tsty.mx.beyond',
  );

}