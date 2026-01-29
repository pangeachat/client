import 'package:fluffychat/pangea/user/analytics_profile_model.dart';

class PublicProfileModel {
  final AnalyticsProfileModel analytics;
  final String? country;
  final String? about;

  const PublicProfileModel({
    required this.analytics,
    this.country,
    this.about,
  });

  Map<String, dynamic> toJson() {
    final json = analytics.toJson();

    if (country != null) {
      json['country'] = country;
    }

    if (about != null) {
      json['about'] = about;
    }

    return json;
  }

  factory PublicProfileModel.fromJson(Map<String, dynamic> json) {
    final analytics = AnalyticsProfileModel.fromJson(json);

    final country = json.containsKey('country') ? json['country'] : null;
    final about = json.containsKey('about') ? json['about'] : null;

    return PublicProfileModel(
      analytics: analytics,
      country: country,
      about: about,
    );
  }

  PublicProfileModel copyWith({
    AnalyticsProfileModel? analytics,
    String? country,
    String? about,
  }) {
    return PublicProfileModel(
      analytics: analytics ?? this.analytics,
      country: country ?? this.country,
      about: about ?? this.about,
    );
  }
}
