import 'package:flutter/material.dart';

class TutorialAnchorRegistry {
  TutorialAnchorRegistry._();

  static final instance = TutorialAnchorRegistry._();

  final Map<String, GlobalKey> _anchors = {};

  GlobalKey register(String id) {
    return _anchors.putIfAbsent(id, () => GlobalKey());
  }

  GlobalKey? get(String id) => _anchors[id];
}
