/// Represents a user reference in CMS
class UserReference {
  final String relationTo;
  final dynamic value; // Can be String or User/MatrixUser/ServiceUser object

  UserReference({
    required this.relationTo,
    required this.value,
  });

  factory UserReference.fromJson(Map<String, dynamic> json) {
    return UserReference(
      relationTo: json['relationTo'] as String,
      value: json['value'], // Keep as dynamic since it can be string or object
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'relationTo': relationTo,
      'value': value,
    };
  }
}
