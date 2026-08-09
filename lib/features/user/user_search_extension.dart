import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/common/config/environment.dart';

extension UserSearchExtension on Client {
  Future<SearchUserDirectoryResponse> searchUser(
    String search, {
    int? limit,
  }) async {
    String searchText = search;
    if (!searchText.startsWith("@")) {
      searchText = "@$searchText";
    }
    if (!searchText.contains(":")) {
      searchText = "$searchText:${Environment.homeServer}";
    }
    return searchUserDirectory(searchText, limit: limit);
  }
}
