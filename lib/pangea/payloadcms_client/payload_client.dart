import 'dart:convert';
import 'dart:io';

import 'payload_models.dart';
import 'payload_query.dart';

/// Simple error logging for pure Dart (no Flutter dependencies)
class DartErrorHandler {
  static void logError({
    required Object e,
    StackTrace? s,
    Map<String, dynamic>? data,
  }) {
    print('ERROR: $e');
    if (s != null) {
      print('STACK: $s');
    }
    if (data != null) {
      print('DATA: $data');
    }
  }
}

/// Simple debugging utilities
class DartDebug {
  static const bool kDebugMode = true; // Set based on your needs

  static void debugPrint(String message) {
    if (kDebugMode) {
      print(message);
    }
  }
}

/// Simple HTTP client for pure Dart
class SimpleHttpClient {
  final Duration timeout;

  const SimpleHttpClient({this.timeout = const Duration(seconds: 30)});

  Future<HttpResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    final client = HttpClient();
    try {
      client.connectionTimeout = timeout;
      final request = await client.getUrl(Uri.parse(url));

      if (headers != null) {
        headers.forEach((key, value) {
          request.headers.add(key, value);
        });
      }

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      return HttpResponse(
        statusCode: response.statusCode,
        body: body,
        headers: _extractHeaders(response.headers),
      );
    } finally {
      client.close();
    }
  }

  Future<HttpResponse> post(
    String url, {
    Map<String, String>? headers,
    String? body,
  }) async {
    final client = HttpClient();
    try {
      client.connectionTimeout = timeout;
      final request = await client.postUrl(Uri.parse(url));

      if (headers != null) {
        headers.forEach((key, value) {
          request.headers.add(key, value);
        });
      }

      if (body != null) {
        request.write(body);
      }

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      return HttpResponse(
        statusCode: response.statusCode,
        body: responseBody,
        headers: _extractHeaders(response.headers),
      );
    } finally {
      client.close();
    }
  }

  Future<HttpResponse> put(
    String url, {
    Map<String, String>? headers,
    String? body,
  }) async {
    final client = HttpClient();
    try {
      client.connectionTimeout = timeout;
      final request = await client.putUrl(Uri.parse(url));

      if (headers != null) {
        headers.forEach((key, value) {
          request.headers.add(key, value);
        });
      }

      if (body != null) {
        request.write(body);
      }

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      return HttpResponse(
        statusCode: response.statusCode,
        body: responseBody,
        headers: _extractHeaders(response.headers),
      );
    } finally {
      client.close();
    }
  }

  Future<HttpResponse> delete(
    String url, {
    Map<String, String>? headers,
  }) async {
    final client = HttpClient();
    try {
      client.connectionTimeout = timeout;
      final request = await client.deleteUrl(Uri.parse(url));

      if (headers != null) {
        headers.forEach((key, value) {
          request.headers.add(key, value);
        });
      }

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      return HttpResponse(
        statusCode: response.statusCode,
        body: responseBody,
        headers: _extractHeaders(response.headers),
      );
    } finally {
      client.close();
    }
  }

  Map<String, String> _extractHeaders(HttpHeaders headers) {
    final result = <String, String>{};
    headers.forEach((name, values) {
      result[name] = values.join(', ');
    });
    return result;
  }

  void close() {
    // No-op for simple HTTP client
  }
}

/// Simple HTTP response wrapper
class HttpResponse {
  final int statusCode;
  final String body;
  final Map<String, String> headers;

  const HttpResponse({
    required this.statusCode,
    required this.body,
    required this.headers,
  });
}

/// Client for interacting with PayloadCMS API
///
/// Supports both authenticated and unauthenticated requests.
/// When [accessToken] is provided, all requests will include
/// an Authorization header with the Bearer token.
class PayloadClient {
  late String baseUrl;
  late String baseApiPath;
  final String? accessToken;
  final SimpleHttpClient _httpClient;

  /// Creates a new PayloadClient instance
  ///
  /// Parameters:
  /// - [httpClient]: Optional custom HTTP client
  /// - [baseApiPath]: Base API path (defaults to '/cms/api')
  /// - [accessToken]: Optional access token for authenticated requests
  /// - [baseUrl]: Base URL for the PayloadCMS instance
  PayloadClient({
    this.accessToken,
    String? baseApiPath,
    String? baseUrl,
  }) : _httpClient =  const SimpleHttpClient() {
    this.baseUrl = baseUrl ?? 'http://localhost:3000';
    this.baseApiPath = baseApiPath ?? '/cms/api';
  }

  /// Generic GET request to PayloadCMS API
  Future<Map<String, dynamic>> get(String endpoint) async {
    try {
      final uri = Uri.parse('$baseUrl$endpoint');
      final response = await _httpClient.get(
        uri.toString(),
        headers: _headers,
      );

      _handleError(response, endpoint: endpoint);

      return json.decode(response.body) as Map<String, dynamic>;
    } catch (e, s) {
      DartErrorHandler.logError(
        e: e,
        s: s,
        data: {'endpoint': endpoint, 'baseUrl': baseUrl},
      );
      rethrow;
    }
  }

  /// GET request with typed query support
  Future<Map<String, dynamic>> getWithQuery(
    String endpoint,
    PayloadQuery query,
  ) async {
    try {
      final queryParams = query.toQueryParams();
      final uri = Uri.parse('$baseUrl$endpoint').replace(
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
      );

      final response = await _httpClient.get(
        uri.toString(),
        headers: _headers,
      );

      _handleError(response, endpoint: endpoint, queryParams: queryParams);

      return json.decode(response.body) as Map<String, dynamic>;
    } catch (e, s) {
      DartErrorHandler.logError(
        e: e,
        s: s,
        data: {
          'endpoint': endpoint,
          'baseUrl': baseUrl,
          'query': query.toQueryParams()
        },
      );
      rethrow;
    }
  }

  /// Generic POST request to PayloadCMS API
  Future<Map<String, dynamic>> post(
    String endpoint,
    Map<String, dynamic> data,
  ) async {
    try {
      final uri = Uri.parse('$baseUrl$endpoint');
      final response = await _httpClient.post(
        uri.toString(),
        headers: _headers,
        body: json.encode(data),
      );

      _handleError(response, endpoint: endpoint, requestData: data);

      return json.decode(response.body) as Map<String, dynamic>;
    } catch (e, s) {
      DartErrorHandler.logError(
        e: e,
        s: s,
        data: {'endpoint': endpoint, 'baseUrl': baseUrl, 'requestData': data},
      );
      rethrow;
    }
  }

  /// Generic PUT request to PayloadCMS API
  Future<Map<String, dynamic>> put(
    String endpoint,
    Map<String, dynamic> data,
  ) async {
    try {
      final uri = Uri.parse('$baseUrl$endpoint');
      final response = await _httpClient.put(
        uri.toString(),
        headers: _headers,
        body: json.encode(data),
      );

      _handleError(response, endpoint: endpoint, requestData: data);

      return json.decode(response.body) as Map<String, dynamic>;
    } catch (e, s) {
      DartErrorHandler.logError(
        e: e,
        s: s,
        data: {'endpoint': endpoint, 'baseUrl': baseUrl, 'requestData': data},
      );
      rethrow;
    }
  }

  /// Generic DELETE request to PayloadCMS API
  Future<Map<String, dynamic>> delete(String endpoint) async {
    try {
      final uri = Uri.parse('$baseUrl$endpoint');
      final response = await _httpClient.delete(
        uri.toString(),
        headers: _headers,
      );

      _handleError(response, endpoint: endpoint);

      return json.decode(response.body) as Map<String, dynamic>;
    } catch (e, s) {
      DartErrorHandler.logError(
        e: e,
        s: s,
        data: {'endpoint': endpoint, 'baseUrl': baseUrl},
      );
      rethrow;
    }
  }

  /// Get paginated results from PayloadCMS API
  Future<Map<String, dynamic>> getPaginated(
    String endpoint, {
    int page = 1,
    int limit = 10,
    Map<String, String>? queryParams,
  }) async {
    final params = <String, String>{
      'page': page.toString(),
      'limit': limit.toString(),
      ...?queryParams,
    };

    final query = params.entries
        .map(
          (e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
        )
        .join('&');

    final endpointWithQuery =
        endpoint.contains('?') ? '$endpoint&$query' : '$endpoint?$query';

    return get(endpointWithQuery);
  }

  /// Get paginated results with typed query support
  Future<Map<String, dynamic>> getPaginatedWithQuery(
    String endpoint,
    PayloadQuery query,
  ) async {
    return getWithQuery(endpoint, query);
  }

  /// Create a new query builder for fluent query construction
  PayloadQueryBuilder queryBuilder() {
    return PayloadQueryBuilder();
  }

  /// Get a single document from a collection with type-safe parsing
  Future<T> getDocument<T extends PayloadDocument>(
    String collection,
    String id,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    final response = await get('$baseApiPath/$collection/$id');
    return fromJson(response);
  }

  /// Get paginated collection results with type-safe parsing
  Future<PayloadPaginatedResponse<T>> getCollection<T extends PayloadDocument>(
    String collection,
    T Function(Map<String, dynamic>) fromJson, {
    int page = 1,
    int limit = 10,
  }) async {
    final response = await getPaginated(
      '$baseApiPath/$collection',
      page: page,
      limit: limit,
    );
    return PayloadPaginatedResponse<T>.fromJson(response, fromJson);
  }

  /// Get paginated collection results with typed query support
  Future<PayloadPaginatedResponse<T>>
      getCollectionWithQuery<T extends PayloadDocument>(
    String collection,
    PayloadQuery query,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    final response = await getWithQuery('$baseApiPath/$collection', query);
    return PayloadPaginatedResponse<T>.fromJson(response, fromJson);
  }

  /// Create a new document in a collection
  Future<T> createDocument<T extends PayloadDocument>(
    String collection,
    Map<String, dynamic> data,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    final response = await post('$baseApiPath/$collection', data);
    return fromJson(response);
  }

  /// Update an existing document in a collection
  Future<T> updateDocument<T extends PayloadDocument>(
    String collection,
    String id,
    Map<String, dynamic> data,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    final response = await put('$baseApiPath/$collection/$id', data);
    return fromJson(response);
  }

  /// Delete a document from a collection
  Future<T> deleteDocument<T extends PayloadDocument>(
    String collection,
    String id,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    final response = await delete('$baseApiPath/$collection/$id');
    return fromJson(response);
  }

  void _handleError(
    HttpResponse response, {
    required String endpoint,
    Map<String, dynamic>? requestData,
    Map<String, String>? queryParams,
  }) {
    if (response.statusCode >= 400) {
      // Simple logging without Flutter dependencies
      print('PayloadCMS API Error - Status: ${response.statusCode}');
      print('Endpoint: $endpoint');
      print('Response: ${response.body}');
      if (requestData != null) {
        print('Request Data: $requestData');
      }
      if (queryParams != null) {
        print('Query Params: $queryParams');
      }

      throw Exception(
        'PayloadCMS API Error: ${response.statusCode} - ${response.body}',
      );
    }
  }

  Map<String, String> get _headers {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (accessToken != null) {
      headers['Authorization'] = 'Bearer $accessToken';
    }

    return headers;
  }

  void dispose() {
    _httpClient.close();
  }
}
