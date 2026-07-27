import 'package:flutter/foundation.dart';

import 'package:matrix/matrix.dart';
import 'package:universal_html/html.dart' as html;

import 'package:fluffychat/features/join_codes/join_rule_extension.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';

enum ShareCodeType { code, link }

class ShareRoomCodeUtil {
  static String? getRoomCodeToShare(Room room, ShareCodeType type) {
    final joinCode = room.joinCode;
    if (joinCode == null) return null;
    return _getShareText(joinCode, type);
  }

  static String _getShareText(String code, ShareCodeType type) {
    if (type == ShareCodeType.link) {
      final String initialUrl = kIsWeb
          ? html.window.origin!
          : Environment.frontendURL;

      // The shareable link is just the bare short code. The SPA serves any
      // path (index.html fallback) and the client's LegacyRedirects folds
      // `/<code>` into the join-with-code leaf — no redirect hop.
      return "$initialUrl/$code";
    } else {
      return code;
    }
  }
}
