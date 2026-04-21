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
  });
}
