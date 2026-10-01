import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/user/user_directory_search.dart';

/// #9009 — the shared debounced directory search behind the New Direct
/// Message panel and the invite page's Public filter.
void main() {
  /// Comfortably past [UserDirectorySearch.debounce], so a pending search has
  /// fired and its response has landed.
  Future<void> settle() => Future.delayed(
    UserDirectorySearch.debounce + const Duration(milliseconds: 80),
  );

  /// Builds a search whose backend records every term it is asked for and, by
  /// default, answers with one profile named after that term.
  ({UserDirectorySearch search, List<String> calls}) build({
    Future<List<Profile>> Function(String)? backend,
  }) {
    final calls = <String>[];
    final search = UserDirectorySearch.withSearch(
      search: (term) {
        calls.add(term);
        return backend?.call(term) ??
            Future.value([Profile(userId: '@$term:pangea.chat')]);
      },
      onChanged: () {},
    );
    return (search: search, calls: calls);
  }

  group('UserDirectorySearch', () {
    test(
      'debounces: only the last term of a burst reaches the server',
      () async {
        final h = build();
        h.search
          ..search('a')
          ..search('av')
          ..search('ava');
        expect(h.calls, isEmpty, reason: 'nothing fires before the debounce');

        await settle();
        expect(h.calls, ['ava']);
        expect(h.search.results.single.userId, '@ava:pangea.chat');
        expect(h.search.lastSearch, 'ava');
      },
    );

    test('re-typing the term already shown does not spend a request', () async {
      final h = build();
      h.search.search('ava');
      await settle();
      expect(h.calls, ['ava']);

      h.search.search('ava');
      await settle();
      expect(
        h.calls,
        ['ava'],
        reason: 'the directory is rate-limited; repeats are not worth a call',
      );
    });

    test('an empty term clears results without a request', () async {
      final h = build();
      h.search.search('ava');
      await settle();
      expect(h.search.results, isNotEmpty);

      h.search.search('');
      expect(h.search.results, isEmpty);
      expect(h.search.lastSearch, isNull);
      await settle();
      expect(h.calls, ['ava'], reason: 'clearing costs no request');
    });

    test('a slow response cannot overwrite a newer term', () async {
      final completers = <String, Completer<List<Profile>>>{};
      final h = build(
        backend: (term) =>
            (completers[term] = Completer<List<Profile>>()).future,
      );

      h.search.search('ava');
      await settle();
      h.search.search('ben');
      await settle();
      expect(h.calls, ['ava', 'ben']);

      // The stale "ava" response lands last and must be dropped whole.
      completers['ben']!.complete([Profile(userId: '@ben:pangea.chat')]);
      await Future.delayed(Duration.zero);
      completers['ava']!.complete([Profile(userId: '@ava:pangea.chat')]);
      await Future.delayed(Duration.zero);

      expect(h.search.results.single.userId, '@ben:pangea.chat');
      expect(h.search.lastSearch, 'ben');
    });

    test('a failed search keeps the results it had', () async {
      var fail = false;
      final h = build(
        backend: (term) => fail
            ? Future.error(Exception('429'))
            : Future.value([Profile(userId: '@$term:pangea.chat')]),
      );

      h.search.search('ava');
      await settle();
      expect(h.search.results, hasLength(1));

      fail = true;
      h.search.search('avas');
      await settle();

      expect(h.search.error, isNotNull);
      expect(
        h.search.results.single.userId,
        '@ava:pangea.chat',
        reason: 'a rate-limited keystroke must not read as "nobody matches"',
      );
    });

    test(
      'searchNow skips the debounce, and a retry after a failure runs',
      () async {
        var fail = true;
        final h = build(
          backend: (term) => fail
              ? Future.error(Exception('429'))
              : Future.value([Profile(userId: '@$term:pangea.chat')]),
        );

        h.search.searchNow('ava');
        await Future.delayed(Duration.zero);
        expect(h.calls, [
          'ava',
        ], reason: 'searchNow does not wait out the debounce');
        expect(h.search.error, isNotNull);

        // The dedupe guard must not swallow a retry of a term that failed.
        fail = false;
        h.search.search('ava');
        await settle();
        expect(h.calls, ['ava', 'ava']);
        expect(h.search.error, isNull);
        expect(h.search.results, hasLength(1));
      },
    );

    test('dispose cancels a pending search', () async {
      final h = build();
      h.search.search('ava');
      h.search.dispose();
      await settle();
      expect(h.calls, isEmpty);
    });
  });
}
