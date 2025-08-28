class CmsMatrixUser {
  final String id;
  final String username;
  final String updatedAt;
  final String createdAt;

  CmsMatrixUser({
    required this.id,
    required this.username,
    required this.updatedAt,
    required this.createdAt,
  });

  factory CmsMatrixUser.fromJson(Map<String, dynamic> json) {
    return CmsMatrixUser(
      id: json['id'] as String,
      username: json['username'] as String,
      updatedAt: json['updatedAt'] as String,
      createdAt: json['createdAt'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'updatedAt': updatedAt,
      'createdAt': createdAt,
    };
  }
}
