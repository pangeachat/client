// ignore_for_file: lines_longer_than_80_chars, avoid_classes_with_only_static_members

import 'dart:convert';

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

import 'package:fluffychat/pangea/common/config/environment.dart';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return fromBase64(Environment.googleAnalyticsFirebaseOptionsBase64!);
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  // ---- decoding helpers ----

  static FirebaseOptions fromBase64(String encodedOptions) {
    final decodedOptions = utf8.decode(base64Decode(encodedOptions.trim()));
    final options = json.decode(decodedOptions);
    if (options is! Map<String, dynamic>) {
      throw const FormatException(
        'GOOGLE_ANALYTICS_FIREBASE_OPTIONS_BASE64 must decode to a JSON object',
      );
    }
    return fromJson(options);
  }

  static FirebaseOptions fromJson(Map<String, dynamic> json) {
    return FirebaseOptions(
      apiKey: _requiredString(json, 'apiKey'),
      appId: _requiredString(json, 'appId'),
      messagingSenderId: _requiredString(json, 'messagingSenderId'),
      projectId: _requiredString(json, 'projectId'),
      authDomain: _optionalString(json, 'authDomain'),
      databaseURL: _optionalString(json, 'databaseURL'),
      storageBucket: _optionalString(json, 'storageBucket'),
      measurementId: _optionalString(json, 'measurementId'),
      trackingId: _optionalString(json, 'trackingId'),
      deepLinkURLScheme: _optionalString(json, 'deepLinkURLScheme'),
      androidClientId: _optionalString(json, 'androidClientId'),
      iosClientId: _optionalString(json, 'iosClientId'),
      iosBundleId: _optionalString(json, 'iosBundleId'),
      appGroupId: _optionalString(json, 'appGroupId'),
    );
  }

  static String _requiredString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String && value.isNotEmpty) return value;
    throw FormatException(
      'GOOGLE_ANALYTICS_FIREBASE_OPTIONS_BASE64 is missing "$key"',
    );
  }

  static String? _optionalString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is String) return value;
    throw FormatException(
      'GOOGLE_ANALYTICS_FIREBASE_OPTIONS_BASE64 "$key" must be a string',
    );
  }
}
