import 'package:flutter/foundation.dart';

import 'package:matrix/matrix.dart';
import 'package:universal_html/html.dart' as html;

import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/join_codes/join_rule_extension.dart';

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

      // CloudFront viewer-request fn at app.{staging.,}pangea.chat 302s
      // bare 7-char codes to /#/join_with_link?classcode=<code>. See
      // pangeachat/devops#105.
      return "$initialUrl/$code";
    } else {
      return code;
    }
  }
}
