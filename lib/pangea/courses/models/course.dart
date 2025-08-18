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
  final String
      value; // Could be User or MatrixUser object, but we'll keep as ID

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
class CourseModulesRelation {
  final List<String> docs; // Course module IDs
  final bool? hasNextPage;
  final int? totalDocs;

  const CourseModulesRelation({
    required this.docs,
    this.hasNextPage,
    this.totalDocs,
  });

  factory CourseModulesRelation.fromJson(Map<String, dynamic> json) {
    final docsJson = json['docs'] as List<dynamic>? ?? [];
    final docs = docsJson.map((doc) {
      if (doc is String) {
        return doc;
      } else if (doc is Map<String, dynamic>) {
        return doc['id'] as String;
      }
      return doc.toString();
    }).toList();

    return CourseModulesRelation(
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
    return other is CourseModulesRelation &&
        _listEquals(other.docs, docs) &&
        other.hasNextPage == hasNextPage &&
        other.totalDocs == totalDocs;
  }

  @override
  int get hashCode => Object.hash(Object.hashAll(docs), hasNextPage, totalDocs);

  @override
  String toString() => 'CourseModulesRelation(docs: ${docs.length} items, '
      'hasNextPage: $hasNextPage, totalDocs: $totalDocs)';

  // Helper method for list equality
  static bool _listEquals<T>(List<T>? a, List<T>? b) {
    if (a == null) return b == null;
    if (b == null || a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Model representing a course from PayloadCMS
class Course implements PayloadDocument {
  @override
  final String id;
  final String title;
  final String description;
  final CefrLevel cefrLevel;
  final String l1; // Language 1 (source language)
  final String l2; // Language 2 (target language)
  final CourseModulesRelation modules;
  final UserReference? createdBy;
  final UserReference? updatedBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Course({
    required this.id,
    required this.title,
    required this.description,
    required this.cefrLevel,
    required this.l1,
    required this.l2,
    required this.modules,
    this.createdBy,
    this.updatedBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Course.fromJson(Map<String, dynamic> json) {
    return Course(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      cefrLevel: CefrLevel.fromString(json['cefrLevel'] as String),
      l1: json['l1'] as String,
      l2: json['l2'] as String,
      modules: CourseModulesRelation.fromJson(
        json['modules'] as Map<String, dynamic>? ?? {},
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
      'modules': modules.toJson(),
      if (createdBy != null) 'createdBy': createdBy!.toJson(),
      if (updatedBy != null) 'updatedBy': updatedBy!.toJson(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Course &&
        other.id == id &&
        other.title == title &&
        other.description == description &&
        other.cefrLevel == cefrLevel &&
        other.l1 == l1 &&
        other.l2 == l2 &&
        other.modules == modules &&
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
      modules,
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

/// Type alias for courses paginated response
typedef CoursesResponse = PayloadPaginatedResponse<Course>;
