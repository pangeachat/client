import 'dart:convert';

import 'package:http/http.dart' hide Client;
import 'package:matrix/matrix.dart';
import 'package:matrix/matrix_api_lite/generated/api.dart';

import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';

extension UserDirectorySearchApiExtension on Api {
  /// Searches the user directory through Pangea's own Synapse endpoint rather
  /// than the stock `/_matrix/client/v3/user_directory/search`.
  ///
  /// The stock endpoint takes its `LIMIT + 1` rows from the database and only
  /// *then* runs the visibility filter (`limit_user_directory`), so a search
  /// whose top matches are all non-public returns nothing and Synapse never
  /// refetches to compensate. The Pangea endpoint pushes that filtering into
  /// the SQL, so the limit applies to rows the caller may actually see.
  ///
  /// The server clamps [limit] to 1..50 and rate-limits per requester, so a
  /// caller must expect a 429 (see [UserDirectorySearch], which keeps the last
  /// results rather than blanking the list).
  Future<SearchUserDirectoryResponse> searchPangeaUserDirectory(
    String searchTerm, {
    int limit = 50,
  }) async {
    final requestUri = Uri(
      path: '_synapse/client/pangea/v1/user_directory/search',
    );
    final request = Request('POST', baseUri!.resolveUri(requestUri));
    request.headers['content-type'] = 'application/json';
    request.headers['authorization'] = 'Bearer ${bearerToken!}';
    request.bodyBytes = utf8.encode(
      jsonEncode({'search_term': searchTerm, 'limit': limit}),
    );
    final response = await Response.fromStream(await httpClient.send(request));
    if (response.statusCode != 200) {
      // This call bypasses `Requests` (Synapse endpoint, Matrix SDK client and
      // token), so it raises the typed failure itself rather than throwing the
      // response — see repos-and-error-handling.instructions.md.
      throw PangeaHttpException.fromResponse(response);
    }
    // The endpoint answers in the spec's own shape — `{limited, results:
    // [{user_id, display_name, avatar_url}]}` — so the generated model parses
    // it unchanged and every call site keeps its `Profile` results.
    return SearchUserDirectoryResponse.fromJson(
      jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, Object?>,
    );
  }
}

extension UserSearchExtension on Client {
  /// Searches the user directory for [search] as typed.
  ///
  /// Until #9009 this completed a bare term into a full Matrix ID
  /// (`ava` → `@ava:pangea.chat`) before handing it to the stock endpoint.
  /// That decoration is gone: the term is passed through, so a partial name
  /// matches by prefix, and a user on another homeserver — whom the appended
  /// local domain could never match — is reachable again.
  Future<SearchUserDirectoryResponse> searchUser(String search, {int? limit}) =>
      searchPangeaUserDirectory(search, limit: limit ?? 50);
}
