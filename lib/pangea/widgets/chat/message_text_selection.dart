import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class MessageTextSelection {
  String? selectedText;
  String messageText = "";
  final StreamController<String?> selectionStream =
      StreamController<String?>.broadcast();

  void setMessageText(String text) {
    messageText = text;
  }

  void onTextSelection(TextSelection selection) => selection.isCollapsed == true
      ? clearTextSelection()
      : setTextSelection(selection);

  void setTextSelection(TextSelection selection) {
    selectedText = selection.textInside(messageText);
    if (BrowserContextMenu.enabled && kIsWeb) {
      BrowserContextMenu.disableContextMenu();
    }
    selectionStream.add(selectedText);
  }

  void clearTextSelection() {
    selectedText = null;
    if (kIsWeb && !BrowserContextMenu.enabled) {
      BrowserContextMenu.enableContextMenu();
    }
    selectionStream.add(selectedText);
  }

  int get offset => messageText.indexOf(selectedText!);
}
