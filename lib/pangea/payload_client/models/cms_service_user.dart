import 'package:fluffychat/pangea/payload_client/polymorphic_relationship.dart';

class CmsServiceUser {
  final String id;
  final String name;
  final PolymorphicRelationship createdBy;
  final PolymorphicRelationship updatedBy;
  final String updatedAt;
  final String createdAt;

  CmsServiceUser({
    required this.id,
    required this.name,
    required this.createdBy,
    required this.updatedBy,
    required this.updatedAt,
    required this.createdAt,
  });

  factory CmsServiceUser.fromJson(Map<String, dynamic> json) {
    return CmsServiceUser(
      id: json['id'] as String,
      name: json['name'] as String,
      createdBy: PolymorphicRelationship.fromJson(
        json['createdBy'] as Map<String, dynamic>,
      ),
      updatedBy: PolymorphicRelationship.fromJson(
        json['updatedBy'] as Map<String, dynamic>,
      ),
      updatedAt: json['updatedAt'] as String,
      createdAt: json['createdAt'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'createdBy': createdBy.toJson(),
      'updatedBy': updatedBy.toJson(),
      'updatedAt': updatedAt,
      'createdAt': createdAt,
    };
  }
}
