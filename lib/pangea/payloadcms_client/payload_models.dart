/// Generic models for PayloadCMS API responses
library;

/// Interface for PayloadCMS documents that can be serialized from JSON
abstract class PayloadDocument {
  /// Create document from JSON map
  factory PayloadDocument.fromJson(Map<String, dynamic> json) {
    throw UnimplementedError(
        'PayloadDocument.fromJson must be implemented by subclasses');
  }

  /// Convert document to JSON map
  Map<String, dynamic> toJson();

  /// Document ID
  String get id;
}

/// Generic paginated response from PayloadCMS
class PayloadPaginatedResponse<T extends PayloadDocument> {
  final List<T> docs;
  final int totalDocs;
  final int limit;
  final int totalPages;
  final int page;
  final int pagingCounter;
  final bool hasPrevPage;
  final bool hasNextPage;
  final int? prevPage;
  final int? nextPage;

  const PayloadPaginatedResponse({
    required this.docs,
    required this.totalDocs,
    required this.limit,
    required this.totalPages,
    required this.page,
    required this.pagingCounter,
    required this.hasPrevPage,
    required this.hasNextPage,
    this.prevPage,
    this.nextPage,
  });

  /// Create from JSON with custom document factory
  factory PayloadPaginatedResponse.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) documentFactory,
  ) {
    return PayloadPaginatedResponse<T>(
      docs: (json['docs'] as List<dynamic>?)
              ?.map((doc) => documentFactory(doc as Map<String, dynamic>))
              .toList() ??
          [],
      totalDocs: json['totalDocs'] as int? ?? 0,
      limit: json['limit'] as int? ?? 10,
      totalPages: json['totalPages'] as int? ?? 0,
      page: json['page'] as int? ?? 1,
      pagingCounter: json['pagingCounter'] as int? ?? 1,
      hasPrevPage: json['hasPrevPage'] as bool? ?? false,
      hasNextPage: json['hasNextPage'] as bool? ?? false,
      prevPage: json['prevPage'] as int?,
      nextPage: json['nextPage'] as int?,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'docs': docs.map((doc) => doc.toJson()).toList(),
      'totalDocs': totalDocs,
      'limit': limit,
      'totalPages': totalPages,
      'page': page,
      'pagingCounter': pagingCounter,
      'hasPrevPage': hasPrevPage,
      'hasNextPage': hasNextPage,
      'prevPage': prevPage,
      'nextPage': nextPage,
    };
  }

  /// Create empty response
  static PayloadPaginatedResponse<T> empty<T extends PayloadDocument>() {
    return PayloadPaginatedResponse<T>(
      docs: const [],
      totalDocs: 0,
      limit: 0,
      totalPages: 0,
      page: 1,
      pagingCounter: 1,
      hasPrevPage: false,
      hasNextPage: false,
    );
  }

  /// Check if response has any documents
  bool get isEmpty => docs.isEmpty;

  /// Check if response has documents
  bool get isNotEmpty => docs.isNotEmpty;

  /// Get first document or null
  T? get firstOrNull => docs.isNotEmpty ? docs.first : null;

  /// Get last document or null
  T? get lastOrNull => docs.isNotEmpty ? docs.last : null;
}

/// Single document response from PayloadCMS
class PayloadDocumentResponse<T extends PayloadDocument> {
  final T document;
  final String? message;

  const PayloadDocumentResponse({
    required this.document,
    this.message,
  });

  /// Create from JSON with custom document factory
  factory PayloadDocumentResponse.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) documentFactory,
  ) {
    return PayloadDocumentResponse<T>(
      document: documentFactory(json),
      message: json['message'] as String?,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    final result = document.toJson();
    if (message != null) {
      result['message'] = message;
    }
    return result;
  }
}

/// Error response from PayloadCMS
class PayloadErrorResponse {
  final String message;
  final List<PayloadError>? errors;
  final int? statusCode;

  const PayloadErrorResponse({
    required this.message,
    this.errors,
    this.statusCode,
  });

  factory PayloadErrorResponse.fromJson(Map<String, dynamic> json) {
    return PayloadErrorResponse(
      message: json['message'] as String? ?? 'Unknown error',
      errors: (json['errors'] as List<dynamic>?)
          ?.map((error) => PayloadError.fromJson(error as Map<String, dynamic>))
          .toList(),
      statusCode: json['statusCode'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'message': message,
      if (errors != null) 'errors': errors!.map((e) => e.toJson()).toList(),
      if (statusCode != null) 'statusCode': statusCode,
    };
  }
}

/// Individual error from PayloadCMS
class PayloadError {
  final String message;
  final String? field;
  final String? code;

  const PayloadError({
    required this.message,
    this.field,
    this.code,
  });

  factory PayloadError.fromJson(Map<String, dynamic> json) {
    return PayloadError(
      message: json['message'] as String,
      field: json['field'] as String?,
      code: json['code'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'message': message,
      if (field != null) 'field': field,
      if (code != null) 'code': code,
    };
  }
}
