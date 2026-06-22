/// One open-panel token from a workspace URL list (`left=` / `right=`).
///
/// [type] selects a `PanelDef` in `panel_registry.dart`; [param] is its
/// already-decoded argument (a room localpart, an analytics tab, an encoded
/// construct). See `routing.instructions.md`.
class PanelToken {
  final String type;
  final String? param;

  const PanelToken(this.type, [this.param]);

  /// Parse one URL list element. It arrives still percent-encoded and already
  /// split out of the comma list. The first `:` splits type from param, so a
  /// room localpart (`!abc`) or an encoded construct survives; the param is
  /// decoded only after that split. Returns null for a malformed type.
  static PanelToken? parse(String encodedElement) {
    if (encodedElement.isEmpty) return null;
    final i = encodedElement.indexOf(':');
    if (i < 0) {
      return _validType(encodedElement) ? PanelToken(encodedElement) : null;
    }
    final type = encodedElement.substring(0, i);
    if (!_validType(type)) return null;
    final param = Uri.decodeComponent(encodedElement.substring(i + 1));
    return PanelToken(type, param.isEmpty ? null : param);
  }

  /// Encode for a URL list. The param is percent-encoded so its own commas and
  /// colons can't be mistaken for list or field delimiters.
  String encode() =>
      param == null ? type : '$type:${Uri.encodeComponent(param!)}';

  static final RegExp _typePattern = RegExp(r'^[a-z][a-z-]*$');

  static bool _validType(String s) => _typePattern.hasMatch(s);

  @override
  bool operator ==(Object other) =>
      other is PanelToken && other.type == type && other.param == param;

  @override
  int get hashCode => Object.hash(type, param);

  @override
  String toString() => encode();
}
