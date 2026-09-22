import 'package:diacritic/diacritic.dart';

class SearchTextUtil {
  /// [text] folded for a plain-text search match: lowercased, diacritics
  /// removed, so "espanol" finds "Español". Apply it to both the query and
  /// the text searched.
  static String normalize(String text) => removeDiacritics(text).toLowerCase();
}
