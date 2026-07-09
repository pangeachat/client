import 'package:fluffychat/features/navigation/panel_types_enum.dart';
import 'package:fluffychat/features/navigation/token_params/token_param.dart';

/// One open-panel token from a workspace URL list (`left=` / `right=`).
///
/// [type] selects a `PanelDef` in `panel_registry.dart`; [param] is its
/// already-decoded argument (a room localpart, an analytics tab, an encoded
/// construct). See `routing.instructions.md`.
class PanelToken {
  final PanelTypesEnum type;
  final TokenParam? param;

  const PanelToken(this.type, [this.param]);

  static final RegExp _typePattern = RegExp(r'^[a-z][a-z-]*$');

  static bool _validType(String s) => _typePattern.hasMatch(s);

  /// Parse one URL list element. It arrives still percent-encoded and already
  /// split out of the comma list. The first `:` splits type from param, so a
  /// room localpart (`!abc`) or an encoded construct survives; the param is
  /// decoded only after that split. Returns null for a malformed type, or for a
  /// hand-edited/truncated `%` escape that would make `Uri.decodeComponent`
  /// throw — the bad token is skipped rather than aborting the whole route.
  static PanelToken? parse(String encodedElement) {
    if (encodedElement.isEmpty) return null;
    final i = encodedElement.indexOf(':');
    if (i < 0) {
      final type = PanelTypesEnum.fromString(encodedElement);
      return _validType(encodedElement) && type != null
          ? PanelToken(type)
          : null;
    }
    final type = encodedElement.substring(0, i);
    final parsedType = PanelTypesEnum.fromString(type);
    if (!_validType(type) || parsedType == null) return null;
    final String param;
    try {
      param = Uri.decodeComponent(encodedElement.substring(i + 1));
    } catch (_) {
      // Truncated/invalid `%` escape (ArgumentError or FormatException): skip
      // this token rather than aborting the whole route parse.
      return null;
    }

    try {
      final parsed = TokenParam.byType(type, param);
      return PanelToken(parsedType, parsed);
    } catch (e) {
      // A parse method (TokenFields.decode, enum fromRoute, etc.) threw on
      // malformed input — skip this token rather than aborting route parse.
      return null;
    }
  }

  /// Encode for a URL list. The param is percent-encoded so its own commas and
  /// colons can't be mistaken for list or field delimiters.
  String encode() => param == null
      ? type.name
      : '${type.name}:${Uri.encodeComponent(param!.build())}';

  @override
  bool operator ==(Object other) =>
      other is PanelToken && other.type == type && other.param == param;

  @override
  int get hashCode => Object.hash(type, param);

  @override
  String toString() => encode();
}
