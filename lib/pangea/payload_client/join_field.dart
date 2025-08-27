import 'package:fluffychat/pangea/payload_client/string_or_t.dart';

class JoinField<T> {
  final List<StringOr<T>>? docs;
  final bool? hasNextPage;
  final int? totalDocs;

  const JoinField({
    this.docs,
    this.hasNextPage,
    this.totalDocs,
  });

  factory JoinField.fromJson(
    Map<String, dynamic> json, {
    required T Function(Object? json) decodeT,
  }) {
    final raw = json['docs'];
    final list = (raw is List)
        ? raw.map((e) => StringOr<T>.fromJson(e, decodeT)).toList()
        : null;

    return JoinField<T>(
      docs: list,
      hasNextPage: json['hasNextPage'] as bool?,
      totalDocs: json['totalDocs'] as int?,
    );
  }

  Map<String, dynamic> toJson({
    required Object? Function(T value) encodeT,
  }) {
    return {
      'docs': docs?.map((e) => e.toJson(encodeT)).toList(),
      'hasNextPage': hasNextPage,
      'totalDocs': totalDocs,
    };
  }
}
