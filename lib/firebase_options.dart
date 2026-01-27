import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError(
          'iOS is not configured yet',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCVAGczu1lg0AYblXDzZh9gOCtmcOSR3Ow',           // From client[0].api_key[0].current_key
    appId: '1:332272872167:android:fcf0bdf1ecc63270511042',             // From client[0].client_info.mobilesdk_app_id
    messagingSenderId: '332272872167',   // From project_number
    projectId: 'cognicare-2acb1',          // From project_id
    storageBucket: 'cognicare-2acb1.firebasestorage.app',  // From storage_bucket
  );
}