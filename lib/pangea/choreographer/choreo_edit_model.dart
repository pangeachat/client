import 'dart:math';

/// Changes made to previous choreo step's text
/// Remove substring of length 'length', starting at position 'offset'
/// Then add String 'insert' at that position
class ChoreoEditModel {
  final int offset;
  final int length;
  final String insert;

  /// Normal constructor created from preexisting ChoreoEdit values
  const ChoreoEditModel({this.offset = 0, this.length = 0, this.insert = ""});

  /// Constructor that determines and saves
  /// edits differentiating originalText and editedText
  factory ChoreoEditModel.fromText({
    required String originalText,
    required String editedText,
  }) {
    if (originalText == editedText) {
      // No changes, return empty edit
      return const ChoreoEditModel();
    }

    final offset = _firstDifference(originalText, editedText);
    final length =
        _lastDifference(originalText, editedText, offset) + 1 - offset;
    final insert = _insertion(originalText, editedText, offset, length);
    return ChoreoEditModel(offset: offset, length: length, insert: insert);
  }

  factory ChoreoEditModel.fromJson(Map<String, dynamic> json) {
    return ChoreoEditModel(
      offset: json[_offsetKey],
      length: json[_lengthKey],
      insert: json[_insertKey],
    );
  }

  static const _offsetKey = "offst_v2";
  static const _lengthKey = "lngth_v2";
  static const _insertKey = "insrt_v2";

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    data[_offsetKey] = offset;
    data[_lengthKey] = length;
    data[_insertKey] = insert;
    return data;
  }

  /// Find index of first character where strings differ
  static int _firstDifference(String originalText, String editedText) {
    var i = 0;
    final minLength = min(originalText.length, editedText.length);
    while (i < minLength && originalText[i] == editedText[i]) {
      i++;
    }
    return i;
  }

  /// Starting at the end of both text versions,
  /// traverse backward until a non-matching char is found
  static int _lastDifference(
    String originalText,
    String editedText,
    int offset,
  ) {
    var i = originalText.length - 1;
    var j = editedText.length - 1;
    while (min(i, j) >= offset && originalText[i] == editedText[j]) {
      i--;
      j--;
    }
    return i;
  }

  /// Length of inserted text is the length of deleted text,
  /// plus the difference in string length
  /// If dif is -x and length of deleted text is x,
  /// inserted text is empty string
  static String _insertion(
    String originalText,
    String editedText,
    int offset,
    int length,
  ) {
    final insertLength = length + (editedText.length - originalText.length);
    return editedText.substring(offset, offset + insertLength);
  }

  /// Given the original string, use offset, length, and insert
  /// to find the edited version of the string
  String editedText(String originalText) {
    return originalText.replaceRange(offset, offset + length, insert);
  }
}
