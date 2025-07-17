class PowerupsModel {
  final int powerups;
  final DateTime updated;

  PowerupsModel({
    required this.powerups,
    required this.updated,
  });

  Map<String, dynamic> toJson() {
    return {
      'powerups': powerups,
      'updated': updated.toIso8601String(),
    };
  }

  factory PowerupsModel.fromJson(Map<String, dynamic> json) {
    return PowerupsModel(
      powerups: json['powerups'],
      updated: DateTime.parse(json['updated']),
    );
  }
}
