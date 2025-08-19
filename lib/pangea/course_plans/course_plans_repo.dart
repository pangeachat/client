import 'package:fluffychat/pangea/payloadcms_client/payload_client.dart';
import 'package:fluffychat/pangea/payloadcms_client/payload_models.dart';

/// CEFR levels for courses
enum CefrLevel {
  prea1('PREA1'),
  a1('A1'),
  a2('A2'),
  b1('B1'),
  b2('B2'),
  c1('C1'),
  c2('C2');

  const CefrLevel(this.value);
  final String value;

  static CefrLevel fromString(String value) {
    return CefrLevel.values.firstWhere(
      (level) => level.value == value,
      orElse: () => CefrLevel.a1,
    );
  }
}

/// User reference for created/updated by fields
class UserReference {
  final String relationTo;
  final String value;

  const UserReference({
    required this.relationTo,
    required this.value,
  });

  factory UserReference.fromJson(Map<String, dynamic> json) {
    return UserReference(
      relationTo: json['relationTo'] as String,
      value: json['value'] is String
          ? json['value'] as String
          : (json['value'] as Map<String, dynamic>)['id'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'relationTo': relationTo,
      'value': value,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UserReference &&
        other.relationTo == relationTo &&
        other.value == value;
  }

  @override
  int get hashCode => Object.hash(relationTo, value);

  @override
  String toString() => 'UserReference(relationTo: $relationTo, value: $value)';
}

/// Modules relationship for courses
class CoursePlanModulesRelation {
  final List<String> docs;
  final bool? hasNextPage;
  final int? totalDocs;

  const CoursePlanModulesRelation({
    required this.docs,
    this.hasNextPage,
    this.totalDocs,
  });

  factory CoursePlanModulesRelation.fromJson(Map<String, dynamic> json) {
    final docsJson = json['docs'] as List<dynamic>? ?? [];
    final docs = docsJson.map((doc) {
      if (doc is String) {
        return doc;
      } else if (doc is Map<String, dynamic>) {
        return doc['id'] as String;
      }
      return doc.toString();
    }).toList();

    return CoursePlanModulesRelation(
      docs: docs,
      hasNextPage: json['hasNextPage'] as bool?,
      totalDocs: json['totalDocs'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'docs': docs,
      if (hasNextPage != null) 'hasNextPage': hasNextPage,
      if (totalDocs != null) 'totalDocs': totalDocs,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CoursePlanModulesRelation &&
        _listEquals(other.docs, docs) &&
        other.hasNextPage == hasNextPage &&
        other.totalDocs == totalDocs;
  }

  @override
  int get hashCode => Object.hash(Object.hashAll(docs), hasNextPage, totalDocs);

  @override
  String toString() => 'CoursePlanModulesRelation(docs: ${docs.length} items, '
      'hasNextPage: $hasNextPage, totalDocs: $totalDocs)';

  static bool _listEquals<T>(List<T>? a, List<T>? b) {
    if (a == null) return b == null;
    if (b == null || a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Model representing a course
class CoursePlan implements PayloadDocument {
  @override
  final String id;
  final String title;
  final String description;
  final CefrLevel cefrLevel;
  final String l1;
  final String l2;
  final CoursePlanModulesRelation coursePlanModules;
  final UserReference? createdBy;
  final UserReference? updatedBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CoursePlan({
    required this.id,
    required this.title,
    required this.description,
    required this.cefrLevel,
    required this.l1,
    required this.l2,
    required this.coursePlanModules,
    this.createdBy,
    this.updatedBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CoursePlan.fromJson(Map<String, dynamic> json) {
    return CoursePlan(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      cefrLevel: CefrLevel.fromString(json['cefrLevel'] as String),
      l1: json['l1'] as String,
      l2: json['l2'] as String,
      coursePlanModules: CoursePlanModulesRelation.fromJson(
        json['coursePlanModules'] as Map<String, dynamic>? ?? {},
      ),
      createdBy: json['createdBy'] != null
          ? UserReference.fromJson(json['createdBy'] as Map<String, dynamic>)
          : null,
      updatedBy: json['updatedBy'] != null
          ? UserReference.fromJson(json['updatedBy'] as Map<String, dynamic>)
          : null,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'cefrLevel': cefrLevel.value,
      'l1': l1,
      'l2': l2,
      'coursePlanModules': coursePlanModules.toJson(),
      if (createdBy != null) 'createdBy': createdBy!.toJson(),
      if (updatedBy != null) 'updatedBy': updatedBy!.toJson(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CoursePlan &&
        other.id == id &&
        other.title == title &&
        other.description == description &&
        other.cefrLevel == cefrLevel &&
        other.l1 == l1 &&
        other.l2 == l2 &&
        other.coursePlanModules == coursePlanModules &&
        other.createdBy == createdBy &&
        other.updatedBy == updatedBy &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      title,
      description,
      cefrLevel,
      l1,
      l2,
      coursePlanModules,
      createdBy,
      updatedBy,
      createdAt,
      updatedAt,
    );
  }

  @override
  String toString() {
    return 'Course(id: $id, title: $title, l1: $l1, l2: $l2, cefrLevel: ${cefrLevel.value})';
  }
}

/// Repository for managing courses data from PayloadCMS
class CoursesRepo extends PayloadClient {
  /// Create a CoursesRepo instance
  CoursesRepo({
    super.accessToken,
    super.baseUrl,
    super.baseApiPath,
  });

  /// Find courses with pagination
  Future<PayloadPaginatedResponse<CoursePlan>> find({
    int page = 1,
    int limit = 10,
  }) async {
    final query = queryBuilder().paginate(page, limit).build();

    return getCollectionWithQuery('course-plans', query, CoursePlan.fromJson);
  }

  /// Find a specific course by ID
  Future<CoursePlan> findById(String courseId) async {
    return getDocument('course-plans', courseId, CoursePlan.fromJson);
  }

  /// Update a specific course by ID
  Future<CoursePlan> update(String courseId, Map<String, dynamic> data) async {
    return updateDocument('course-plans', courseId, data, CoursePlan.fromJson);
  }

  /// Delete a specific course by ID
  Future<CoursePlan> deleteCourse(String courseId) async {
    return deleteDocument('course-plans', courseId, CoursePlan.fromJson);
  }

  /// Create a new course
  Future<CoursePlan> create(Map<String, dynamic> data) async {
    return createDocument('course-plans', data, CoursePlan.fromJson);
  }
}
