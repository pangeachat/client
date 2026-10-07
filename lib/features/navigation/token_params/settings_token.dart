import 'package:fluffychat/features/navigation/token_fields.dart';
import 'package:fluffychat/features/navigation/token_params/token_param.dart';

class SettingsTokenParam extends TokenParam {
  /// The discount page; a gift link's code rides this token's field
  /// (subscriptions.instructions.md § Gift link).
  static const String discountPage = 'subscription/discount';
  static const String _selectedPage = 'subscription/selected';

  final String subpage;
  final String? planId;

  /// The promo code a gift link carried into [discountPage]. Never part of
  /// the screen name — see `SettingsPagePanelToken.screenName`.
  final String? promoCode;
  const SettingsTokenParam({
    required this.subpage,
    this.planId,
    this.promoCode,
  });

  @override
  bool get isPushed => subpage.contains('/');

  @override
  SettingsTokenParam? get poppedParam => isPushed
      ? SettingsTokenParam(
          subpage: subpage.substring(0, subpage.lastIndexOf('/')),
        )
      : null;

  /// The one field a page may carry after its name.
  String? get _field => switch (subpage) {
    _selectedPage => planId,
    discountPage => promoCode,
    _ => null,
  };

  @override
  String build() {
    final field = _field;
    if (field == null) return subpage;
    return TokenFields.join([subpage, TokenFields.encode(field)]);
  }

  factory SettingsTokenParam.parse(String param) {
    for (final page in const [_selectedPage, discountPage]) {
      if (!param.startsWith(page)) continue;
      final chunks = TokenFields.split(param);
      final field = chunks.length < 2 ? null : TokenFields.decode(chunks[1]);
      return SettingsTokenParam(
        subpage: page,
        planId: page == _selectedPage ? field : null,
        promoCode: page == discountPage ? field : null,
      );
    }
    return SettingsTokenParam(subpage: param);
  }

  @override
  bool operator ==(Object other) =>
      other is SettingsTokenParam && other.subpage == subpage;

  @override
  int get hashCode => Object.hashAll([subpage]);
}
