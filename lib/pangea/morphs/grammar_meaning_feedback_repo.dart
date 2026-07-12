import 'dart:convert';

import 'package:http/http.dart';

import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// One value's regenerated meaning copy from the feedback response.
class GrammarMeaningValueUpdate {
  final String value;
  final String title;
  final String description;

  const GrammarMeaningValueUpdate({
    required this.value,
    required this.title,
    required this.description,
  });

  static GrammarMeaningValueUpdate fromJson(Map<String, dynamic> json) =>
      GrammarMeaningValueUpdate(
        value: json['value'],
        title: json['title'],
        description: json['description'],
      );
}

/// The regenerated per-feature meaning bundle returned by the feedback POST.
///
/// Meaning rows bundle per FEATURE server-side, so flagging one value
/// regenerates (and returns) the whole feature's translations.
class GrammarMeaningFeedbackResponse {
  final String feature;
  final String featureTitle;
  final List<GrammarMeaningValueUpdate> values;

  const GrammarMeaningFeedbackResponse({
    required this.feature,
    required this.featureTitle,
    required this.values,
  });

  static GrammarMeaningFeedbackResponse fromJson(Map<String, dynamic> json) =>
      GrammarMeaningFeedbackResponse(
        feature: json['feature'],
        featureTitle: json['feature_title'],
        values: List.from(json['values'])
            .map(
              (v) => GrammarMeaningValueUpdate.fromJson(
                Map<String, dynamic>.from(v),
              ),
            )
            .toList(),
      );
}

/// Feedback on a grammar meaning card (the flag icon, #6839).
///
/// POSTs to the choreographer's translation-only endpoint
/// (`/choreo/grammar_constructs/meaning`), which audits the existing row
/// with the user's feedback, regenerates the feature's meaning bundle in
/// place, and returns the regenerated copy synchronously (choreo #2548).
class GrammarMeaningFeedbackRepo {
  static Future<GrammarMeaningFeedbackResponse> submitFeedback({
    required String feature,
    required String targetLanguage,
    required String userL1,
    required String feedback,
  }) async {
    final Requests req = Requests(
      accessToken: MatrixState.pangeaController.userController.accessToken,
    );

    final Response res = await req.post(
      url: PApiUrls.grammarConstructMeaning,
      body: {
        'feature': feature,
        'target_language': targetLanguage,
        'user_l1': userL1,
        'feedback': [
          {'feedback': feedback},
        ],
      },
    );

    if (res.statusCode != 200) {
      throw Exception(
        'Failed to submit grammar meaning feedback: ${res.statusCode} ${res.body}',
      );
    }

    final decodedBody = jsonDecode(utf8.decode(res.bodyBytes));
    return GrammarMeaningFeedbackResponse.fromJson(decodedBody);
  }
}
