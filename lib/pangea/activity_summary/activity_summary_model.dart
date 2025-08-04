import 'package:fluffychat/pangea/activity_summary/activity_summary_response_model.dart';

class ActivitySummaryAnalytics {
  final int xp;
  final int vocab;
  final int morphs;

  ActivitySummaryAnalytics({
    required this.xp,
    required this.vocab,
    required this.morphs,
  });

  Map<String, dynamic> toJson() {
    return {
      'xp': xp,
      'vocab': vocab,
      'morphs': morphs,
    };
  }

  factory ActivitySummaryAnalytics.fromJson(Map<String, dynamic> json) {
    return ActivitySummaryAnalytics(
      xp: json['xp'] as int,
      vocab: json['vocab'] as int,
      morphs: json['morphs'] as int,
    );
  }
}

class ActivitySummaryModel {
  final ActivitySummaryResponseModel response;
  final ActivitySummaryAnalytics analytics;

  ActivitySummaryModel({
    required this.response,
    required this.analytics,
  });

  Map<String, dynamic> toJson() {
    return {
      'response': response.toJson(),
      'analytics': analytics.toJson(),
    };
  }

  factory ActivitySummaryModel.fromJson(Map<String, dynamic> json) {
    return ActivitySummaryModel(
      response: ActivitySummaryResponseModel.fromJson(json['response']),
      analytics: ActivitySummaryAnalytics.fromJson(json['analytics']),
    );
  }
}
