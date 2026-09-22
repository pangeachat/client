import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/pangea/common/utils/base_response.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/chat/choreographer/choreo_constants.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/pangea_match_model.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/span_data_model.dart';
import 'package:fluffychat/routes/chat/events/tokens/grapheme_offset_index.dart';

/// The server addresses each span in Unicode code points; the client, and the
/// choreo record it saves, in grapheme clusters. This model is where the two
/// meet: [IGCResponseModel.fromJson] converts in, [toJson] converts back out
/// for feedback reruns.
class IGCResponseModel extends BaseResponse {
  final String originalInput;
  final String? fullTextCorrection;
  final List<PangeaMatch> matches;
  final String userL1;
  final String userL2;

  /// Whether interactive translation is enabled.
  /// Defaults to true for V2 responses which don't include this field.
  final bool enableIT;

  /// Whether in-context grammar is enabled.
  /// Defaults to true for V2 responses which don't include this field.
  final bool enableIGC;

  IGCResponseModel({
    required this.originalInput,
    required this.fullTextCorrection,
    required this.matches,
    required this.userL1,
    required this.userL2,
    this.enableIT = true,
    this.enableIGC = true,
  });

  factory IGCResponseModel.fromJson(Map<String, dynamic> json) {
    final String originalInput = json["original_input"];
    return IGCResponseModel(
      matches: json["matches"] != null
          ? (json["matches"] as Iterable).map<PangeaMatch>((e) {
              final serverMatch = PangeaMatch.fromJson(
                e as Map<String, dynamic>,
                fullText: originalInput,
              );
              return PangeaMatch(
                match: _codepointsToGraphemes(serverMatch.match),
                status: serverMatch.status,
              );
            }).toList()
          : [],
      originalInput: originalInput,
      fullTextCorrection: json["full_text_correction"],
      userL1: json[ModelKey.userL1],
      userL2: json[ModelKey.userL2],
      // V2 responses don't include these fields; default to true
      enableIT: json[ChoreoConstants.enableIT] ?? true,
      enableIGC: json[ChoreoConstants.enableIGC] ?? true,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    "original_input": originalInput,
    "full_text_correction": fullTextCorrection,
    // Serialize as flat SpanData objects matching server's SpanDataV2 schema
    "matches": matches
        .map((e) => _graphemesToCodepoints(e.match).toJson())
        .toList(),
    ModelKey.userL1: userL1,
    ModelKey.userL2: userL2,
    ChoreoConstants.enableIT: enableIT,
    ChoreoConstants.enableIGC: enableIGC,
  };

  /// A boundary that falls inside a grapheme cluster widens to take in the
  /// whole cluster, so a correction never splits a character.
  static SpanData _codepointsToGraphemes(SpanData span) {
    final index = GraphemeOffsetIndex.fromText(span.fullText);
    final codepointEnd = span.offset + span.length;
    if (span.offset < 0 ||
        span.length < 0 ||
        codepointEnd > index.codepointCount) {
      ErrorHandler.logError(
        e: RangeError(
          'IGC span [${span.offset}, $codepointEnd) lies outside its text '
          'of ${index.codepointCount} code points',
        ),
        data: {
          'offset': span.offset,
          'length': span.length,
          'codepointCount': index.codepointCount,
        },
      );
    }
    final start = index.graphemeStartOfCodepoint(span.offset);
    return span.copyWith(
      offset: start,
      length: index.graphemeEndOfCodepoint(codepointEnd) - start,
    );
  }

  static SpanData _graphemesToCodepoints(SpanData span) {
    final index = GraphemeOffsetIndex.fromText(span.fullText);
    final start = index.codepointStartOfGrapheme(span.offset);
    return span.copyWith(
      offset: start,
      length: index.codepointStartOfGrapheme(span.offset + span.length) - start,
    );
  }
}
