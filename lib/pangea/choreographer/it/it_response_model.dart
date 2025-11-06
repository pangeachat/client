import 'package:flutter/material.dart';

import 'package:collection/collection.dart';

import 'package:fluffychat/pangea/choreographer/choreo_constants.dart';
import 'package:fluffychat/pangea/choreographer/it/completed_it_step_model.dart';

class ITResponseModel {
  final String fullTextTranslation;
  final List<ContinuanceModel> continuances;
  final List<ContinuanceModel>? goldContinuances;
  final bool isFinal;
  final String? translationId;
  final int payloadId;

  const ITResponseModel({
    required this.fullTextTranslation,
    required this.continuances,
    required this.translationId,
    required this.goldContinuances,
    required this.isFinal,
    required this.payloadId,
  });

  factory ITResponseModel.fromJson(Map<String, dynamic> json) {
    //PTODO - is continuances a variable type? can we change that?
    if (json['continuances'].runtimeType == String) {
      debugPrint("continuances was string - ${json['continuances']}");
      json['continuances'] = [];
      json['finished'] = true;
    }

    final List<ContinuanceModel> interimCont = (json['continuances'] as List)
        .mapIndexed((index, e) {
          e["index"] = index;
          return ContinuanceModel.fromJson(e);
        })
        .toList()
        .take(ChoreoConstants.numberOfITChoices)
        .toList()
        .cast<ContinuanceModel>()
        //can't do this on the backend because step translation can't filter them out
        .where((element) => element.inDictionary)
        .toList();

    interimCont.shuffle();

    return ITResponseModel(
      fullTextTranslation: json["full_text_translation"] ?? json["translation"],
      continuances: interimCont,
      translationId: json['translation_id'],
      payloadId: json['payload_id'] ?? 0,
      isFinal: json['finished'] ?? false,
      goldContinuances: json['gold_continuances'] != null
          ? (json['gold_continuances'] as Iterable).map((e) {
              e["gold"] = true;
              return ContinuanceModel.fromJson(e);
            }).toList()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['full_text_translation'] = fullTextTranslation;
    data['continuances'] = continuances.map((v) => v.toJson()).toList();
    if (translationId != null) {
      data['translation_id'] = translationId;
    }
    data['payload_id'] = payloadId;
    data["finished"] = isFinal;
    return data;
  }
}
