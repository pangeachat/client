import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';

enum DownloadType {
  txt,
  csv,
  xlsx;

  String get mimetype {
    switch (this) {
      case DownloadType.txt:
        return 'text/plain';
      case DownloadType.csv:
        return 'text/csv';
      case DownloadType.xlsx:
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
  }

  String get extension {
    switch (this) {
      case DownloadType.txt:
        return 'txt';
      case DownloadType.csv:
        return 'csv';
      case DownloadType.xlsx:
        return 'xlsx';
    }
  }

  String copy(BuildContext context) {
    final l10n = L10n.of(context);
    switch (this) {
      case DownloadType.csv:
        return l10n.commaSeparatedFile;
      case DownloadType.xlsx:
        return l10n.excelFile;
      case DownloadType.txt:
        return l10n.plainTextFile;
    }
  }
}
