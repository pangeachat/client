import 'package:country_picker/country_picker.dart';

import 'package:fluffychat/pangea/events/constants/pangea_event_types.dart';
import 'package:fluffychat/pangea/user/analytics_profile_model.dart';

class PublicProfileModel {
  final AnalyticsProfileModel analytics;
  final String? country;
  final String? about;

  const PublicProfileModel({required this.analytics, this.country, this.about});

  String? get countryEmoji =>
      country != null ? CountryService().findByName(country!)?.flagEmoji : null;

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

    final profileJson =
        json[PangeaEventTypes.profileAnalytics] as Map<String, dynamic>?;

    final String? country = profileJson != null ? profileJson['country'] : null;
    final String? about = profileJson != null ? profileJson['about'] : null;

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
