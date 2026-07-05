/// Field encoding for structured panel-token params.
///
/// A token param can carry several FIELDS joined by `.` — a construct detail's
/// lemma and category (`vocab:abrigadoro.adj`), an activity's id and session
/// bindings. Field content is open-ended, all-language text (a lemma can be
/// multiword, any script, with punctuation — see routing.instructions.md), so
/// each field is percent-encoded with its literal dots escaped too. That makes
/// `.` the one unambiguous field separator, and lets any content (commas,
/// colons, slashes, dots, any script) round-trip the URL losslessly without
/// ever colliding with the grammar's structural separators.
///
/// The whole param is percent-encoded once more by [PanelToken.encode] and
/// decoded once by [PanelToken.parse]; these helpers operate on the decoded
/// param, so the two layers never double-decode content.
abstract class TokenFields {
  /// Encode one field's content. `%` is escaped by [Uri.encodeComponent], so
  /// escaping `.` as `%2E` afterwards is unambiguous on decode.
  static String encode(String value) =>
      Uri.encodeComponent(value).replaceAll('.', '%2E');

  /// Decode one field back to its original content. A hand-edited or truncated
  /// `%` escape makes `Uri.decodeComponent` throw (an `ArgumentError`, or a
  /// `FormatException` on some inputs); a tampered URL must not crash route
  /// parsing, so degrade to the raw field either way.
  static String decode(String field) {
    try {
      return Uri.decodeComponent(field);
    } catch (_) {
      return field;
    }
  }

  /// Join already-[encode]d fields into a param.
  static String join(Iterable<String> encodedFields) => encodedFields.join('.');

  /// Split a param into its encoded fields.
  static List<String> split(String param) => param.split('.');
}
