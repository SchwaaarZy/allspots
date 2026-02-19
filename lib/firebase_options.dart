import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions are not configured for web.',
      );
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBuR3_AQq905D49EkFr_7R-8vptUaQTG2E',
    appId: '1:474928599645:android:02d435ce5d6c9689f3b3b4',
    messagingSenderId: '474928599645',
    projectId: 'allspots-5872e',
    databaseURL: 'https://allspots-5872e-default-rtdb.europe-west1.firebasedatabase.app',
    storageBucket: 'allspots-5872e.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAGaSR1PT2NSsfkhMa3FdKuSKOuWAWlsfA',
    appId: '1:474928599645:ios:38e47bf3530fa449f3b3b4',
    messagingSenderId: '474928599645',
    projectId: 'allspots-5872e',
    databaseURL: 'https://allspots-5872e-default-rtdb.europe-west1.firebasedatabase.app',
    storageBucket: 'allspots-5872e.firebasestorage.app',
    iosBundleId: 'com.allspots.app',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyAGaSR1PT2NSsfkhMa3FdKuSKOuWAWlsfA',
    appId: '1:474928599645:ios:38e47bf3530fa449f3b3b4',
    messagingSenderId: '474928599645',
    projectId: 'allspots-5872e',
    databaseURL: 'https://allspots-5872e-default-rtdb.europe-west1.firebasedatabase.app',
    storageBucket: 'allspots-5872e.firebasestorage.app',
    iosBundleId: 'com.allspots.app',
  );
}
