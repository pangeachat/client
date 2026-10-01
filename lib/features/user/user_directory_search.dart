import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/user/user_search_extension.dart';

/// Debounced public-directory search, shared by the New Direct Message panel
/// and the room invite page so the two surfaces answer a typed name the same
/// way (#9009).
///
/// Owned by the `State` that searches: it holds the results and calls
/// [onChanged] when they move, leaving the `setState` to its owner. Dispose it
/// with the owner.
class UserDirectorySearch {
  UserDirectorySearch({required Client client, required this.onChanged})
    : _search = ((term) => client.searchUser(term).then((r) => r.results));

  /// Test seam: the directory call itself. `searchUser` is an extension
  /// method, so it is statically dispatched and cannot be overridden on a fake
  /// [Client].
  @visibleForTesting
  UserDirectorySearch.withSearch({
    required Future<List<Profile>> Function(String) search,
    required this.onChanged,
  }) : _search = search;

  final Future<List<Profile>> Function(String) _search;

  /// Called whenever [results], [loading] or [error] change.
  final void Function() onChanged;

  static const Duration debounce = Duration(milliseconds: 500);

  List<Profile> results = const [];
  bool loading = false;

  /// The last term actually sent to the server, set once its response lands.
  /// Distinguishes "no results for what you typed" from "not searched yet",
  /// which the empty states read.
  String? lastSearch;

  /// The last failure, cleared by the next search that gets a response.
  Object? error;

  Timer? _coolDown;

  /// The in-flight term, so a slow response cannot overwrite a newer one.
  String? _inFlight;

  /// Searches [term] after [debounce], replacing any pending search.
  ///
  /// An empty term clears the results without a request, and re-typing the
  /// term already shown is a no-op — the server allows only a handful of
  /// searches a minute, so repeats are not worth one of them.
  void search(String term) {
    _coolDown?.cancel();
    if (term.isEmpty) {
      _inFlight = null;
      if (results.isEmpty && lastSearch == null && !loading) return;
      results = const [];
      lastSearch = null;
      loading = false;
      error = null;
      onChanged();
      return;
    }
    if (term == lastSearch && error == null) return;
    _coolDown = Timer(debounce, () => _run(term));
  }

  /// Runs [term] now, skipping the debounce — for a filter switch or a retry,
  /// where the user has already waited.
  void searchNow(String term) {
    _coolDown?.cancel();
    if (term.isEmpty) {
      search(term);
      return;
    }
    _run(term);
  }

  Future<void> _run(String term) async {
    _inFlight = term;
    loading = true;
    onChanged();

    List<Profile>? found;
    Object? failure;
    try {
      found = await _search(term);
    } catch (e) {
      failure = e;
    }

    // A response that lost the race to a newer term is dropped whole, so the
    // list never shows results for a term the user has already moved off.
    if (_inFlight != term) return;

    _inFlight = null;
    loading = false;
    lastSearch = term;
    error = failure;
    // A failed search keeps the results it had. The server rate-limits
    // searches (429), and blanking the list mid-typing would make a burst of
    // keystrokes look like "nobody by that name".
    if (found != null) results = found;
    onChanged();
  }

  void dispose() {
    _coolDown?.cancel();
    _coolDown = null;
    _inFlight = null;
  }
}
