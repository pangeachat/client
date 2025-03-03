import 'package:flutter/material.dart';

class InputPasteListener {
  final TextEditingController controller;
  final VoidCallback onPaste;

  String _currentText = '';

  InputPasteListener(this.controller, this.onPaste) {
    controller.addListener(() {
      final difference =
          controller.text.characters.length - _currentText.characters.length;
      if (difference.abs() > 1) onPaste();
      _currentText = controller.text;
    });
  }
}
