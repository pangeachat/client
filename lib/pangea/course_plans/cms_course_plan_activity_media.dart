import 'package:fluffychat/pangea/payload_client/user_reference.dart';

/// Represents course plan activity media from the CMS API
class CmsCoursePlanActivityMedia {
  final String id;
  final String? alt;
  final List<dynamic>
      coursePlanActivities; // Can contain strings or CoursePlanActivity objects
  final UserReference? createdBy;
  final UserReference? updatedBy;
  final String? prefix;
  final String updatedAt;
  final String createdAt;
  final String? url;
  final String? thumbnailURL;
  final String? filename;
  final String? mimeType;
  final int? filesize;
  final int? width;
  final int? height;
  final double? focalX;
  final double? focalY;

  CmsCoursePlanActivityMedia({
    required this.id,
    this.alt,
    required this.coursePlanActivities,
    this.createdBy,
    this.updatedBy,
    this.prefix,
    required this.updatedAt,
    required this.createdAt,
    this.url,
    this.thumbnailURL,
    this.filename,
    this.mimeType,
    this.filesize,
    this.width,
    this.height,
    this.focalX,
    this.focalY,
  });

  factory CmsCoursePlanActivityMedia.fromJson(Map<String, dynamic> json) {
    return CmsCoursePlanActivityMedia(
      id: json['id'] as String,
      alt: json['alt'] as String?,
      coursePlanActivities: json['coursePlanActivities'] as List<dynamic>,
      createdBy: json['createdBy'] != null
          ? UserReference.fromJson(json['createdBy'] as Map<String, dynamic>)
          : null,
      updatedBy: json['updatedBy'] != null
          ? UserReference.fromJson(json['updatedBy'] as Map<String, dynamic>)
          : null,
      prefix: json['prefix'] as String?,
      updatedAt: json['updatedAt'] as String,
      createdAt: json['createdAt'] as String,
      url: json['url'] as String?,
      thumbnailURL: json['thumbnailURL'] as String?,
      filename: json['filename'] as String?,
      mimeType: json['mimeType'] as String?,
      filesize: json['filesize'] as int?,
      width: json['width'] as int?,
      height: json['height'] as int?,
      focalX: (json['focalX'] as num?)?.toDouble(),
      focalY: (json['focalY'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'alt': alt,
      'coursePlanActivities': coursePlanActivities,
      'createdBy': createdBy?.toJson(),
      'updatedBy': updatedBy?.toJson(),
      'prefix': prefix,
      'updatedAt': updatedAt,
      'createdAt': createdAt,
      'url': url,
      'thumbnailURL': thumbnailURL,
      'filename': filename,
      'mimeType': mimeType,
      'filesize': filesize,
      'width': width,
      'height': height,
      'focalX': focalX,
      'focalY': focalY,
    };
  }
}
