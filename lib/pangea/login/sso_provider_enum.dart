import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';

enum SSOProvider {
  google,
  apple;

  String get id {
    switch (this) {
      case SSOProvider.google:
        return "oidc-google";
      case SSOProvider.apple:
        return "oidc-apple";
    }
  }

  String get asset {
    switch (this) {
      case SSOProvider.google:
        return "assets/pangea/google.svg";
      case SSOProvider.apple:
        return "assets/pangea/apple.svg";
    }
  }

  String description(BuildContext context) {
    switch (this) {
      case SSOProvider.google:
        return L10n.of(context).withGoogle;
      case SSOProvider.apple:
        return L10n.of(context).withApple;
    }
  }
}
