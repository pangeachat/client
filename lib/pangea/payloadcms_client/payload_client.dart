import 'dart:convert';

import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/payloadcms_client/payload_models.dart';
import 'package:fluffychat/pangea/payloadcms_client/payload_query.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:sentry_flutter/sentry_flutter.dart';

/// Client for interacting with PayloadCMS API
///
/// Supports both authenticated and unauthenticated requests.
/// When [accessToken] is provided, all requests will include
/// an Authorization header with the Bearer token.
class PayloadClient {
  late String baseUrl;
  late String baseApiPath;
  final String? accessToken;
  final http.Client _httpClient;

  /// Creates a new PayloadClient instance
  ///
  /// Parameters:
  /// - [httpClient]: Optional custom HTTP client
  /// - [baseApiPath]: Base API path (defaults to '/cms/api')
  /// - [accessToken]: Optional access token for authenticated requests
  PayloadClient({
    http.Client? httpClient,
    String? baseApiPath,
    this.accessToken,
  }) : _httpClient = httpClient ?? http.Client() {
    baseUrl = Environment.cmsApi;
    this.baseApiPath = baseApiPath ?? '/cms/api';
  }

  /// Generic GET request to PayloadCMS API
  Future<Map<String, dynamic>> get(String endpoint) async {
    try {
      final uri = Uri.parse('$baseUrl$endpoint');
      final response = await _httpClient.get(
        uri,
        headers: _headers,
      );

      _handleError(response, endpoint: endpoint);

      final responseBody = utf8.decode(response.bodyBytes);
      return json.decode(responseBody) as Map<String, dynamic>;
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {
          'endpoint': endpoint,
          'baseUrl': baseUrl,
        },
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
        uri,
        headers: _headers,
      );

      _handleError(response, endpoint: endpoint, queryParams: queryParams);

      final responseBody = utf8.decode(response.bodyBytes);
      return json.decode(responseBody) as Map<String, dynamic>;
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {
          'endpoint': endpoint,
          'baseUrl': baseUrl,
          'query': query.toQueryParams(),
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
        uri,
        headers: _headers,
        body: json.encode(data),
      );

      _handleError(response, endpoint: endpoint, requestData: data);

      final responseBody = utf8.decode(response.bodyBytes);
      return json.decode(responseBody) as Map<String, dynamic>;
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {
          'endpoint': endpoint,
          'baseUrl': baseUrl,
          'requestData': data,
        },
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
        uri,
        headers: _headers,
        body: json.encode(data),
      );

      _handleError(response, endpoint: endpoint, requestData: data);

      final responseBody = utf8.decode(response.bodyBytes);
      return json.decode(responseBody) as Map<String, dynamic>;
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {
          'endpoint': endpoint,
          'baseUrl': baseUrl,
          'requestData': data,
        },
      );
      rethrow;
    }
  }

  /// Generic DELETE request to PayloadCMS API
  Future<Map<String, dynamic>> delete(String endpoint) async {
    try {
      final uri = Uri.parse('$baseUrl$endpoint');
      final response = await _httpClient.delete(
        uri,
        headers: _headers,
      );

      _handleError(response, endpoint: endpoint);

      final responseBody = utf8.decode(response.bodyBytes);
      return json.decode(responseBody) as Map<String, dynamic>;
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {
          'endpoint': endpoint,
          'baseUrl': baseUrl,
        },
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
    final response = await getPaginated('$baseApiPath/$collection',
        page: page, limit: limit);
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
    http.Response response, {
    required String endpoint,
    Map<String, dynamic>? requestData,
    Map<String, String>? queryParams,
  }) {
    if (response.statusCode >= 400) {
      if (kDebugMode) {
        debugPrint('PayloadCMS API Error - Status: ${response.statusCode}');
        debugPrint('Endpoint: $endpoint');
        debugPrint('Response: ${response.body}');
        if (requestData != null) {
          debugPrint('Request Data: $requestData');
        }
        if (queryParams != null) {
          debugPrint('Query Params: $queryParams');
        }
      }

      // Add breadcrumb for Sentry
      Sentry.addBreadcrumb(
        Breadcrumb.http(
          url: response.request?.url ?? Uri.parse('$baseUrl$endpoint'),
          method: response.request?.method ?? 'Unknown',
          statusCode: response.statusCode,
        ),
      );

      if (requestData != null) {
        Sentry.addBreadcrumb(
          Breadcrumb(
            message: 'PayloadCMS API Request Data',
            data: requestData,
          ),
        );
      }

      throw http.ClientException(
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
