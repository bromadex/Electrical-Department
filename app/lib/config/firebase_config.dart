import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'env.dart';

/// Firebase identifiers for push notifications (API.md section 8). They are
/// public by design: they ship inside every copy of the app. The service
/// account that sends pushes stays on the server (push-send function).
///
/// Values come from Firebase console → Project settings → Your apps. While
/// [projectId] or a platform's API key is empty, push notifications are off
/// on that platform and the rest of the app works as before.
class FirebaseConfig {
  static const projectId = 'bravura-electrical';
  static const messagingSenderId = '86873598340';

  /// Web app (Project settings → Your apps → Web).
  static const webApiKey = 'AIzaSyDQIL-yxEInieH8DiEpx1RDyRskzhu9JN8';
  static const webAppId = '1:86873598340:web:4dac6dddf033ead74c15d1';

  /// Cloud Messaging → Web configuration → Web push certificates (public key).
  static const vapidKey =
      'BOh6KBFCSmUIp1XNf9p8txPr1GOIRn62NDvnPKJwwAvq3gZyb3vBGsRq4yLcSkf_3whSj-7Mjj0Prsw_d6F3yJs';

  /// Android app `com.bravura.electrical_department` (the prod flavor). The
  /// dev flavor has another package name and no Firebase app, so no pushes.
  static const androidApiKey = 'AIzaSyAxoeYAigVZ5sKHlthI7kCHEi3qScSHSVo';
  static const androidAppId = '1:86873598340:android:c40986ec6314a2234c15d1';

  /// Options for this platform, or null when push is not set up for it.
  static FirebaseOptions? get options {
    if (projectId.isEmpty) return null;
    if (kIsWeb) {
      if (webApiKey.isEmpty || webAppId.isEmpty) return null;
      return const FirebaseOptions(
        apiKey: webApiKey,
        appId: webAppId,
        messagingSenderId: messagingSenderId,
        projectId: projectId,
      );
    }
    if (defaultTargetPlatform == TargetPlatform.android && Env.isProd) {
      if (androidApiKey.isEmpty) return null;
      return const FirebaseOptions(
        apiKey: androidApiKey,
        appId: androidAppId,
        messagingSenderId: messagingSenderId,
        projectId: projectId,
      );
    }
    return null;
  }
}
