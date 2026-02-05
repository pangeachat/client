import 'package:fluffychat/pangea/choreographer/igc/pangea_match_status_enum.dart';
import 'package:fluffychat/pangea/choreographer/igc/span_data_type_enum.dart';
import 'match_rule_id_model.dart';
import 'span_data_model.dart';

class PangeaMatch {
  final SpanData match;
  final PangeaMatchStatusEnum status;

  const PangeaMatch({required this.match, required this.status});

  factory PangeaMatch.fromJson(Map<String, dynamic> json) {
    return PangeaMatch(
      match: SpanData.fromJson(json[_matchKey] as Map<String, dynamic>),
      status: json[_statusKey] != null
          ? PangeaMatchStatusEnum.fromString(json[_statusKey] as String)
          : PangeaMatchStatusEnum.open,
    );
  }

  Map<String, dynamic> toJson() => {
    _matchKey: match.toJson(),
    _statusKey: status.name,
  };

  static const _matchKey = "match";
  static const _statusKey = "status";

  bool get isITStart =>
      match.rule?.id == MatchRuleIdModel.interactiveTranslation ||
      [
        SpanDataTypeEnum.itStart,
        SpanDataTypeEnum.itStart.name,
      ].contains(match.type.typeName);

  bool get _needsTranslation => match.rule?.id != null
      ? [
          MatchRuleIdModel.tokenNeedsTranslation,
          MatchRuleIdModel.tokenSpanNeedsTranslation,
        ].contains(match.rule!.id)
      : false;

  bool get isOutOfTargetMatch => isITStart || _needsTranslation;

  bool get isGrammarMatch => !isOutOfTargetMatch;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PangeaMatch) return false;
    return other.match == match && other.status == status;
  }

  @override
  int get hashCode {
    return match.hashCode ^ status.hashCode;
  }
}
