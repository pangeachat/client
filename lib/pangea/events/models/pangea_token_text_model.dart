import 'package:flutter/widgets.dart';

class PangeaTokenText {
  int offset;
  String content;
  int length;

  PangeaTokenText({
    required this.offset,
    required this.content,
    required this.length,
  });

  factory PangeaTokenText.fromJson(Map<String, dynamic> json) {
    final content = json[_contentKey] as String;
    return PangeaTokenText(
      offset: json[_offsetKey],
      content: content,
      length: content.characters.length,
    );
  }

  static PangeaTokenText fromString(String content) {
    return PangeaTokenText(
      offset: 0,
      content: content,
      length: content.characters.length,
    );
  }

  static const String _offsetKey = "offset";
  static const String _contentKey = "content";

  Map<String, dynamic> toJson() => {_offsetKey: offset, _contentKey: content};

  //override equals and hashcode
  @override
  bool operator ==(Object other) {
    if (other is PangeaTokenText) {
      return other.offset == offset &&
          other.content == content &&
          other.length == length;
    }
    return false;
  }

  @override
  int get hashCode => offset.hashCode ^ content.hashCode ^ length.hashCode;

  String get uniqueKey => "$content-$offset-$length";
}
