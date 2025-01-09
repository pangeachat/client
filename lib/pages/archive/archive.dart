import 'package:flutter/material.dart';

import 'package:adaptive_dialog/adaptive_dialog.dart';
import 'package:flutter_gen/gen_l10n/l10n.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/pages/archive/archive_view.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension/pangea_room_extension.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class Archive extends StatefulWidget {
  const Archive({super.key});

  @override
  ArchiveController createState() => ArchiveController();
}

class ArchiveController extends State<Archive> {
  List<Room> archive = [];

  Future<List<Room>> getArchive(BuildContext context) async {
    if (archive.isNotEmpty) return archive;
    // #Pangea
    //return archive = await Matrix.of(context).client.loadArchive();
    return archive = (await Matrix.of(context).client.loadArchive())
        .where((e) => (!e.isSpace && !e.isAnalyticsRoom))
        .toList();
    // Pangea#
  }

  void forgetRoomAction(int i) async {
    await showFutureLoadingDialog(
      context: context,
      future: () async {
        Logs().v('Forget room ${archive.last.getLocalizedDisplayname()}');
        await archive[i].forget();
        archive.removeAt(i);
      },
    );
    setState(() {});
  }

  void forgetAllAction() async {
    final archive = this.archive;
    final client = Matrix.of(context).client;
    if (archive.isEmpty) return;
    if (await showOkCancelAlertDialog(
          useRootNavigator: false,
          context: context,
          title: L10n.of(context).areYouSure,
          okLabel: L10n.of(context).yes,
          cancelLabel: L10n.of(context).cancel,
          message: L10n.of(context).clearArchive,
        ) !=
        OkCancelResult.ok) {
      return;
    }
    await showFutureLoadingDialog(
      context: context,
      future: () async {
        while (archive.isNotEmpty) {
          Logs().v('Forget room ${archive.last.getLocalizedDisplayname()}');
          await archive.last.forget();
          archive.removeLast();
        }
      },
    );
    client.clearArchivesFromCache();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => ArchiveView(this);
}
