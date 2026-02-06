import 'package:fluffychat/pangea/choreographer/igc/pangea_match_model.dart';
import 'package:fluffychat/pangea/common/constants/model_keys.dart';

class IGCResponseModel {
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
          ? (json["matches"] as Iterable)
              .map<PangeaMatch>(
                (e) => PangeaMatch.fromJson(
                  e as Map<String, dynamic>,
                  fullText: originalInput,
                ),
              )
              .toList()
              .cast<PangeaMatch>()
          : [],
      originalInput: originalInput,
      fullTextCorrection: json["full_text_correction"],
      userL1: json[ModelKey.userL1],
      userL2: json[ModelKey.userL2],
      // V2 responses don't include these fields; default to true
      enableIT: json[ModelKey.enableIT] ?? true,
      enableIGC: json[ModelKey.enableIGC] ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        "original_input": originalInput,
        "full_text_correction": fullTextCorrection,
        "matches": matches.map((e) => e.toJson()).toList(),
        ModelKey.userL1: userL1,
        ModelKey.userL2: userL2,
        ModelKey.enableIT: enableIT,
        ModelKey.enableIGC: enableIGC,
      };
}
