import 'package:flutter/material.dart';

import 'package:fluffychat/config/themes.dart';

abstract class PageTitleStyle {
  static TextStyle? pageTitleStyle(BuildContext context) =>
      FluffyThemes.isColumnMode(context)
      ? Theme.of(context).textTheme.titleLarge
      : Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600);
}
