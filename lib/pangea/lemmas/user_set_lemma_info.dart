import 'package:collection/collection.dart';

class UserSetLemmaInfo {
  final String? meaning;
  final List<String>? emojis;

  UserSetLemmaInfo({this.emojis, this.meaning});

  factory UserSetLemmaInfo.fromJson(Map<String, dynamic> json) {
    return UserSetLemmaInfo(
      emojis: json["emojis"] != null ? List<String>.from(json["emojis"]) : null,
      meaning: json['meaning'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {'emojis': emojis, 'meaning': meaning};
  }

  UserSetLemmaInfo copyWith({List<String>? emojis, String? meaning}) {
    return UserSetLemmaInfo(
      emojis: emojis ?? this.emojis,
      meaning: meaning ?? this.meaning,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserSetLemmaInfo &&
          runtimeType == other.runtimeType &&
          const ListEquality().equals(emojis, other.emojis) &&
          meaning == other.meaning;

  @override
  int get hashCode =>
      meaning.hashCode ^ const ListEquality().hash(emojis ?? []);
}
