class CmsAdminUser {
  final String id;
  final String email;
  final List<String> roles;
  final String updatedAt;
  final String createdAt;

  CmsAdminUser({
    required this.id,
    required this.email,
    required this.roles,
    required this.updatedAt,
    required this.createdAt,
  });

  factory CmsAdminUser.fromJson(Map<String, dynamic> json) {
    return CmsAdminUser(
      id: json['id'] as String,
      email: json['email'] as String,
      roles: List<String>.from(json['roles'] as List),
      updatedAt: json['updatedAt'] as String,
      createdAt: json['createdAt'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'roles': roles,
      'updatedAt': updatedAt,
      'createdAt': createdAt,
    };
  }
}
