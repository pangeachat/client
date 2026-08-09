import 'package:flutter/material.dart';

class LayerLinkAndKey {
  late LabeledGlobalKey key;
  late LayerLink link;
  String transformTargetId;

  LayerLinkAndKey(this.transformTargetId) {
    key = LabeledGlobalKey(transformTargetId);
    link = LayerLink();
  }

  Map<String, dynamic> toJson() => {
    "key": key.toString(),
    "link": link.toString(),
    "transformTargetId": transformTargetId,
  };

  @override
  operator ==(Object other) =>
      identical(this, other) ||
      other is LayerLinkAndKey &&
          runtimeType == other.runtimeType &&
          key == other.key &&
          link == other.link &&
          transformTargetId == other.transformTargetId;

  @override
  int get hashCode => key.hashCode ^ link.hashCode ^ transformTargetId.hashCode;
}
