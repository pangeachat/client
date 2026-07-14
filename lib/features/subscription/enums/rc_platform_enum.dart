import 'dart:io';

import 'package:flutter/foundation.dart';

enum RCPlatform {
  stripe,
  android,
  apple;

  RCPlatform get currentPlatform => kIsWeb
      ? RCPlatform.stripe
      : Platform.isAndroid
      ? RCPlatform.android
      : RCPlatform.apple;

  String get string {
    return currentPlatform == RCPlatform.stripe
        ? 'stripe'
        : currentPlatform == RCPlatform.android
        ? 'play_store'
        : 'app_store';
  }
}
