import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/join_codes/space_code_controller.dart';

/// A course link pasted into a code field joins with the link's code (#9376).
/// The fields once cut input at 10 characters, so a pasted
/// `https://app.pangea.chat/<code>` reached the server as `https://ap`.
void main() {
  group('SpaceCodeController.codeFromInput', () {
    test('unwraps a pasted course link to its code', () {
      expect(
        SpaceCodeController.codeFromInput('https://app.pangea.chat/abc1234'),
        'abc1234',
      );
      expect(
        SpaceCodeController.codeFromInput(
          ' https://app.staging.pangea.chat/abc1234/?utm_source=email\n',
        ),
        'abc1234',
      );
    });

    test('sends a typed code as typed, without surrounding spaces', () {
      expect(SpaceCodeController.codeFromInput('abc1234'), 'abc1234');
      expect(SpaceCodeController.codeFromInput(' abc1234\n'), 'abc1234');
    });

    test('leaves any other text for the server to judge', () {
      for (final text in [
        'https://example.com/world',
        'https://app.pangea.chat/chats',
        'https://app.pangea.chat/room/abc1234',
        'not a code',
      ]) {
        expect(SpaceCodeController.codeFromInput(text), text);
      }
    });
  });
}
