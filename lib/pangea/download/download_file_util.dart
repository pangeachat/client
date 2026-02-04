import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:universal_html/html.dart' as webfile;

import 'package:fluffychat/pages/chat/recording_view_model.dart';
import 'package:fluffychat/pangea/download/download_type_enum.dart';

class DownloadUtil {
  static Future<void> downloadFile(
    dynamic contents,
    String filename,
    DownloadType fileType,
  ) async {
    if (kIsWeb) {
      final blob = webfile.Blob([contents], fileType.mimetype, 'native');
      webfile.AnchorElement(
        href: webfile.Url.createObjectUrlFromBlob(blob).toString(),
      )
        ..setAttribute("download", filename)
        ..click();
      return;
    }

    final allowed = await Permission.storage.request().isGranted;
    if (!allowed) {
      throw PermissionException();
    }

    if (await Permission.storage.request().isGranted) {
      Directory? directory;

      if (Platform.isIOS) {
        directory = await getApplicationDocumentsDirectory();
      } else {
        directory = Directory('/storage/emulated/0/Download');
        if (!await directory.exists()) {
          directory = await getExternalStorageDirectory();
        }
      }

      final File f = File("${directory!.path}/$filename");
      File resp;
      if (fileType == DownloadType.txt || fileType == DownloadType.csv) {
        resp = await f.writeAsString(contents);
      } else {
        resp = await f.writeAsBytes(contents);
      }
      OpenFile.open(resp.path);
    }
  }
}
