import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:share_plus/share_plus.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/announcing_snackbar.dart';
import '../widgets/matrix.dart';

// #Pangea
// Pangea#

abstract class FluffyShare {
  static Future<void> share(
    String text,
    BuildContext context, {
    bool copyOnly = false,
  }) async {
    if (PlatformInfos.isMobile && !copyOnly) {
      final box = context.findRenderObject() as RenderBox;
      await SharePlus.instance.share(
        ShareParams(
          text: text,
          sharePositionOrigin: box.localToGlobal(Offset.zero) & box.size,
        ),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    // #Pangea
    ScaffoldMessenger.of(context).showSnackBarAnnounced(
      SnackBar(content: Text(L10n.of(context).copiedToClipboard)),
    );
    // Pangea#
    return;
  }

  static Future<void> shareInviteLink(BuildContext context) async {
    final client = Matrix.of(context).client;
    // #Pangea
    // final ownProfile = await client.fetchOwnProfile();
    // Pangea#
    await FluffyShare.share(
      // #Pangea
      // L10n.of(context).inviteText(
      //   ownProfile.displayName ?? client.userID!,
      //   'https://matrix.to/#/${client.userID}?client=im.fluffychat',
      // ),
      "${Environment.frontendURL}/#/invite_user/${Uri.encodeComponent(client.userID!)}",
      // Pangea#
      context,
    );
  }
}
