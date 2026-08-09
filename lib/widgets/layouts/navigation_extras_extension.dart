import 'dart:async';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/panel_types_enum.dart';
import 'package:fluffychat/widgets/share_scaffold_dialog.dart';

extension NavigationExtrasExtension on GoRouterState {
  List<ShareItem>? navigatorShareItems(PanelToken token) {
    if (token.type != PanelTypesEnum.room) return null;
    return extra is List<ShareItem> ? extra as List<ShareItem> : null;
  }

  Completer<String>? navigatorCourseCompleter(PanelToken token) {
    if (token.type != PanelTypesEnum.addcoursepage) return null;
    return extra is Completer<String> ? extra as Completer<String> : null;
  }
}
