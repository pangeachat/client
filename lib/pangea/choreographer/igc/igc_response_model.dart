import 'package:fluffychat/pangea/choreographer/igc/pangea_match_model.dart';
import 'package:fluffychat/pangea/common/constants/model_keys.dart';

class IGCResponseModel {
  final String originalInput;
  final String? fullTextCorrection;
  final List<PangeaMatch> matches;
  final String userL1;
  final String userL2;
  final bool enableIT;
  final bool enableIGC;

  IGCResponseModel({
    required this.originalInput,
    required this.fullTextCorrection,
    required this.matches,
    required this.userL1,
    required this.userL2,
    required this.enableIT,
    required this.enableIGC,
  });

  factory IGCResponseModel.fromJson(Map<String, dynamic> json) {
    return IGCResponseModel(
      matches: json["matches"] != null
          ? (json["matches"] as Iterable)
                .map<PangeaMatch>((e) {
                  return PangeaMatch.fromJson(e as Map<String, dynamic>);
                })
                .toList()
                .cast<PangeaMatch>()
          : [],
      originalInput: json["original_input"],
      fullTextCorrection: json["full_text_correction"],
      userL1: json[ModelKey.userL1],
      userL2: json[ModelKey.userL2],
      enableIT: json[ModelKey.enableIT],
      enableIGC: json[ModelKey.enableIGC],
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
