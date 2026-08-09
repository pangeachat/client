import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/navigation/workspace_query.dart';

void main() {
  group('parts', () {
    test('an empty query has no parts', () {
      expect(WorkspaceQuery.parts(''), isEmpty);
    });

    test('splits on & keeping each segment verbatim', () {
      expect(WorkspaceQuery.parts('a=1&b=2&flag'), ['a=1', 'b=2', 'flag']);
    });
  });

  group('removeKeys', () {
    test('drops a bare flag and a key=value, by key', () {
      final parts = WorkspaceQuery.parts('left=room:x&m=course:y&flag');
      WorkspaceQuery.removeKeys(parts, {'m', 'flag'});
      expect(parts, ['left=room:x']);
    });

    test(
      'matches only the exact key, not a prefix sibling (left vs leftish)',
      () {
        final parts = WorkspaceQuery.parts('left=a&leftish=b');
        WorkspaceQuery.removeKeys(parts, {'left'});
        expect(parts, ['leftish=b']);
      },
    );

    test('drops a bare key flag (no =) too', () {
      final parts = WorkspaceQuery.parts('left&right=x');
      WorkspaceQuery.removeKeys(parts, {'left'});
      expect(parts, ['right=x']);
    });
  });

  group('location', () {
    test('omits the ? when there is nothing to carry', () {
      expect(WorkspaceQuery.location('/', []), '/');
    });

    test('joins parts after the path', () {
      expect(WorkspaceQuery.location('/', ['a=1', 'b=2']), '/?a=1&b=2');
    });
  });

  group('valueOf', () {
    test('returns the first matching value', () {
      expect(
        WorkspaceQuery.valueOf('left=room:x&m=course:y', 'left'),
        'room:x',
      );
    });

    test('an absent key is null', () {
      expect(WorkspaceQuery.valueOf('a=1', 'left'), isNull);
    });

    test('a bare flag yields an empty string', () {
      expect(WorkspaceQuery.valueOf('left&a=1', 'left'), '');
    });
  });

  // The whole reason this helper exists: the raw query carries already-encoded
  // token params (a `c=%21id` context, a construct param's field encoding)
  // that a second Uri encode would corrupt. The split/drop/rejoin must leave
  // those bytes untouched.
  group('encode-safety', () {
    test('an already-encoded course context survives parts → location', () {
      const q = 'c=%21id&left=course';
      final parts = WorkspaceQuery.parts(q);
      expect(WorkspaceQuery.location('/', parts), '/?$q');
    });

    test('a field-encoded construct param round-trips unchanged', () {
      const q = 'right=vocab:ir%2520de%2520compras.adj';
      final parts = WorkspaceQuery.parts(q);
      WorkspaceQuery.removeKeys(parts, {'left'}); // unrelated drop, no-op here
      expect(WorkspaceQuery.location('/', parts), '/?$q');
    });

    test('valueOf returns the value still percent-encoded', () {
      expect(WorkspaceQuery.valueOf('c=%21id', 'c'), '%21id');
    });
  });
}
