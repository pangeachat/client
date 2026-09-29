import 'package:matrix/matrix.dart';

extension DirectChatContactsExtension on Client {
  /// The people this user already has a direct chat with, de-duplicated.
  ///
  /// This is what both the invite page and the New Direct Message panel mean
  /// by "my contacts" (#9009). It is local state, so it answers a partial name
  /// instantly and without spending one of the directory search's rate-limited
  /// requests.
  List<User> get directChatContacts {
    final seen = <String>{};
    final contacts = <User>[];
    for (final room in rooms.where((r) => r.isDirectChat)) {
      final user = room.unsafeGetUserFromMemoryOrFallback(
        room.directChatMatrixID!,
      );
      if (!seen.add(user.id)) continue;
      contacts.add(user);
    }
    return contacts;
  }
}

extension ContactSearchExtension on List<User> {
  /// The contacts whose display name or Matrix ID contains [search].
  List<User> matching(String search) {
    if (search.isEmpty) return this;
    return where(
      (u) => _nameOrIdContains(u.calcDisplayname(), u.id, search),
    ).toList();
  }

  /// A copy sorted by display name, case-insensitively.
  List<User> sortedByDisplayname() {
    final sorted = [...this];
    sorted.sort(
      (a, b) => a.calcDisplayname().toLowerCase().compareTo(
        b.calcDisplayname().toLowerCase(),
      ),
    );
    return sorted;
  }
}

extension ChatSearchRoomExtension on Room {
  /// Whether the chat list's search [search] finds this chat: by its name, or
  /// for a direct chat by the other person's Matrix ID too, so a contact found
  /// by username in the user searches is found here as well (#9322).
  bool matchesChatSearch(String search, MatrixLocalizations i18n) {
    if (search.isEmpty) return true;
    final name = getLocalizedDisplayname(i18n);
    final partnerId = isDirectChat ? directChatMatrixID : null;
    return partnerId == null
        ? name.toLowerCase().contains(search.toLowerCase())
        : _nameOrIdContains(name, partnerId, search);
  }
}

bool _nameOrIdContains(String name, String matrixId, String search) {
  final term = search.toLowerCase();
  return name.toLowerCase().contains(term) ||
      matrixId.toLowerCase().contains(term);
}
