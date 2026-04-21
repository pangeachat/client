import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/join_codes/join_link_route_utils.dart';

void main() {
  group('resolveJoinClassCodeFromUri', () {
    test('uses legacy classcode query parameter', () {
      final classCode = resolveJoinClassCodeFromUri(
        uri: Uri.parse('/join_with_link?classcode=legacy12'),
      );

      expect(classCode, 'legacy12');
    });

    test('uses short link path parameter', () {
      final classCode = resolveJoinClassCodeFromUri(
        uri: Uri.parse('/234w9w'),
        pathParameters: const {'classCode': '234w9w'},
      );

      expect(classCode, '234w9w');
    });

    test('prefers query parameter when both are present', () {
      final classCode = resolveJoinClassCodeFromUri(
        uri: Uri.parse('/join?classcode=query99'),
        pathParameters: const {'classCode': 'path99'},
      );

      expect(classCode, 'query99');
    });

    test('ignores empty classcode query parameter', () {
      final classCode = resolveJoinClassCodeFromUri(
        uri: Uri.parse('/join?classcode='),
        pathParameters: const {'classCode': 'path99'},
      );

      expect(classCode, 'path99');
    });

    test('ignores whitespace-only classcode query parameter', () {
      final classCode = resolveJoinClassCodeFromUri(
        uri: Uri.parse('/join?classcode=%20%20%20'),
      );

      expect(classCode, isNull);
    });

    test('returns null when no query or path class code is present', () {
      final classCode = resolveJoinClassCodeFromUri(uri: Uri.parse('/join'));

      expect(classCode, isNull);
    });

    test('handles url-encoded classcode values', () {
      final classCode = resolveJoinClassCodeFromUri(
        uri: Uri.parse('/join?classcode=abc%2B123'),
      );

      expect(classCode, 'abc+123');
    });

    test('handles url-decoded short-link path parameter values', () {
      final classCode = resolveJoinClassCodeFromUri(
        uri: Uri.parse('/abc%2B123'),
        pathParameters: const {'classCode': 'abc+123'},
      );

      expect(classCode, 'abc+123');
    });
  });
}
