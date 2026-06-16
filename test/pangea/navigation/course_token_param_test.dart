import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/navigation/course_token_param.dart';
import 'package:fluffychat/features/navigation/panel_token.dart';

void main() {
  group('CourseTokenParam', () {
    test('round-trips a space id with a tab', () {
      final encoded = CourseTokenParam.encode('!s', 'participants');
      expect(encoded, '!s|participants');
      final decoded = CourseTokenParam.decode(encoded);
      expect(decoded.spaceLocalpart, '!s');
      expect(decoded.tab, 'participants');
    });

    test('a missing or empty tab yields just the space id', () {
      expect(CourseTokenParam.encode('!s', null), '!s');
      expect(CourseTokenParam.encode('!s', ''), '!s');
      final decoded = CourseTokenParam.decode('!s');
      expect(decoded.spaceLocalpart, '!s');
      expect(decoded.tab, isNull);
    });

    test('survives the full PanelToken URL encode/parse round-trip', () {
      final token = PanelToken('course', CourseTokenParam.encode('!s', 'chat'));
      // The pipe is percent-encoded so it can't be mistaken for a delimiter.
      expect(token.encode().contains('|'), isFalse);
      final back = PanelToken.parse(token.encode())!;
      expect(back.type, 'course');
      final decoded = CourseTokenParam.decode(back.param!);
      expect(decoded.spaceLocalpart, '!s');
      expect(decoded.tab, 'chat');
    });
  });
}
