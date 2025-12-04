import 'package:fluffychat/pangea/choreographer/igc/span_data_model.dart';
import 'package:fluffychat/pangea/learning_settings/enums/gender_enum.dart';

class SpanDetailsResponse {
  final String userL1;
  final String userL2;
  final GenderEnum userGender;
  final bool enableIT;
  final bool enableIGC;
  final SpanData span;

  const SpanDetailsResponse({
    required this.userL1,
    required this.userL2,
    required this.userGender,
    required this.enableIGC,
    required this.enableIT,
    required this.span,
  });

  factory SpanDetailsResponse.fromJson(Map<String, dynamic> json) =>
      SpanDetailsResponse(
        userL1: json['user_l1'] as String,
        userL2: json['user_l2'] as String,
        userGender: json['user_gender'] is String
            ? GenderEnumExtension.fromString(json['user_gender'])
            : GenderEnum.unselected,
        enableIT: json['enable_it'] as bool,
        enableIGC: json['enable_igc'] as bool,
        span: SpanData.fromJson(json['span']),
      );
}
