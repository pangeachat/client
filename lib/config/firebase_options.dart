// ignore_for_file: lines_longer_than_80_chars, avoid_classes_with_only_static_members

import 'dart:convert';

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

import 'package:fluffychat/pangea/common/config/environment.dart';

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
        return macos;
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

  // ---- unified resolver ----

  static FirebaseOptions _fromEnvOrDefault(
    String? encodedOptions,
    FirebaseOptions fallback,
  ) {
    if (encodedOptions == null || encodedOptions.trim().isEmpty) {
      return fallback;
    }
    return fromBase64(encodedOptions);
  }

  // ---- platform getters ----

  static FirebaseOptions get web => _fromEnvOrDefault(
    Environment.googleAnalyticsFirebaseOptionsBase64,
    _defaultWeb,
  );

  static FirebaseOptions get android => _fromEnvOrDefault(
    Environment.googleAnalyticsFirebaseOptionsBase64,
    _defaultAndroid,
  );

  static FirebaseOptions get ios => _fromEnvOrDefault(
    Environment.googleAnalyticsFirebaseOptionsBase64,
    _defaultIos,
  );

  static FirebaseOptions get macos => _fromEnvOrDefault(
    Environment.googleAnalyticsFirebaseOptionsBase64,
    _defaultMacos,
  );

  // ---- defaults ----

  static const FirebaseOptions _defaultWeb = FirebaseOptions(
    apiKey: 'AIzaSyAjc6fIYN8QAGgYs0xvIiZUEPuRKqAY2-s',
    authDomain: 'pangea-chat-staging-analytics.firebaseapp.com',
    projectId: 'pangea-chat-staging-analytics',
    storageBucket: 'pangea-chat-staging-analytics.firebasestorage.app',
    messagingSenderId: '501707239068',
    appId: '1:501707239068:web:eaeeb7798b28693d904759',
    measurementId: 'G-2N2GZLRMZV',
  );

  static const FirebaseOptions _defaultAndroid = FirebaseOptions(
    apiKey: 'AIzaSyAyWBbl83WXzbVr6txyCmlUsZhpWomQfdg',
    appId: '1:545984292675:android:d808acce7a80c20bb931f6',
    messagingSenderId: '545984292675',
    projectId: 'pangea-chat-936ee',
    databaseURL: 'https://pangea-chat-936ee-default-rtdb.firebaseio.com',
    storageBucket: 'pangea-chat-936ee.firebasestorage.com',
    androidClientId:
        '545984292675-2amsnoan1mt6lec1fld1a7eagu6gej7o.apps.googleusercontent.com',
  );

  static const FirebaseOptions _defaultIos = FirebaseOptions(
    apiKey: 'AIzaSyCl8QZd9_PnaqJY2zLHCwlsmSWdq7hnH-U',
    appId: '1:545984292675:ios:1226406ecc36e056b931f6',
    messagingSenderId: '545984292675',
    projectId: 'pangea-chat-936ee',
    databaseURL: 'https://pangea-chat-936ee-default-rtdb.firebaseio.com',
    storageBucket: 'pangea-chat-936ee.firebasestorage.com',
    iosClientId:
        '545984292675-f5p76l3h9sibsonrct7a8l9ca3c69at0.apps.googleusercontent.com',
    iosBundleId: 'com.talktolearn.chat',
  );

  static const FirebaseOptions _defaultMacos = FirebaseOptions(
    apiKey: 'AIzaSyCl8QZd9_PnaqJY2zLHCwlsmSWdq7hnH-U',
    appId: '1:545984292675:ios:1226406ecc36e056b931f6',
    messagingSenderId: '545984292675',
    projectId: 'pangea-chat-936ee',
    databaseURL: 'https://pangea-chat-936ee-default-rtdb.firebaseio.com',
    storageBucket: 'pangea-chat-936ee.firebasestorage.com',
    iosClientId:
        '545984292675-f5p76l3h9sibsonrct7a8l9ca3c69at0.apps.googleusercontent.com',
    iosBundleId: 'com.talktolearn.chat',
  );

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
