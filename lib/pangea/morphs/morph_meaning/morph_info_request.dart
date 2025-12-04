import 'package:fluffychat/pangea/learning_settings/enums/gender_enum.dart';

class MorphInfoRequest {
  final String userL1;
  final String userL2;
  final GenderEnum userGender;

  MorphInfoRequest({
    required this.userL1,
    required this.userL2,
    required this.userGender,
  });

  Map<String, dynamic> toJson() {
    return {
      'user_l1': userL1,
      'user_l2': userL2,
      'user_gender': userGender.string,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MorphInfoRequest &&
          userL1 == other.userL1 &&
          userL2 == other.userL2 &&
          userGender == other.userGender;

  @override
  int get hashCode => userL1.hashCode ^ userL2.hashCode ^ userGender.hashCode;

  String get storageKey {
    return userL1 + userL2 + userGender.string;
  }
}
