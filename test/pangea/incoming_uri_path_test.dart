import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/navigation/legacy_redirects.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// The installed-app deep-link leg: iOS Universal Links / Android App Links
/// deliver the full `app.pangea.chat` URL to the running app, and
/// [MatrixState.incomingUriToPath] maps it to the in-app location the router
/// resolves. The mapped path must be exactly what `LegacyRedirects` folds —
/// a bare `/<code>` course join link and a `/<uuid>` activity link reach
/// their token flows with no per-shape rewrite in between
/// (joining-courses.instructions.md, Deep Linking).
void main() {
  group('MatrixState.incomingUriToPath', () {
    test('a bare course-code link maps to its path and folds', () {
      final path = MatrixState.incomingUriToPath(
        Uri.parse('https://app.pangea.chat/vj3pc8b'),
      );
      expect(path, '/vj3pc8b');
      expect(
        LegacyRedirects.resolve(Uri.parse(path)),
        contains('addcoursepage:private'),
      );
    });

    test('an activity uuid link maps to its path and folds', () {
      const uuid = 'a1aed3f6-1ef7-4ed0-bc46-4a393aaf880b';
      final path = MatrixState.incomingUriToPath(
        Uri.parse('https://app.pangea.chat/$uuid'),
      );
      expect(path, '/$uuid');
      expect(LegacyRedirects.resolve(Uri.parse(path)), contains(uuid));
    });

    test('activity link params ride along', () {
      const uuid = 'a1aed3f6-1ef7-4ed0-bc46-4a393aaf880b';
      final path = MatrixState.incomingUriToPath(
        Uri.parse('https://app.pangea.chat/$uuid?launch=true'),
      );
      expect(path, '/$uuid?launch=true');
      final folded = LegacyRedirects.resolve(Uri.parse(path));
      expect(folded, contains(uuid));
    });

    test('a root link maps to the world', () {
      expect(
        MatrixState.incomingUriToPath(Uri.parse('https://app.pangea.chat/')),
        '/',
      );
    });

    test('a legacy fragment link maps to the fragment path', () {
      expect(
        MatrixState.incomingUriToPath(
          Uri.parse('https://app.pangea.chat/#/world'),
        ),
        '/world',
      );
    });
  });
}
