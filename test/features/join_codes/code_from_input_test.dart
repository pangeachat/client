import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';

import 'package:fluffychat/features/join_codes/space_code_controller.dart';

/// A course link pasted into a code field joins with the link's code (#9376).
/// The fields once cut input at 10 characters, so a pasted
/// `https://app.pangea.chat/<code>` reached the server as `https://ap`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Environment.frontendURL reads the GetStorage-backed config override
    // first, which needs path_provider; stub it so the box reads empty and
    // FRONTEND_URL comes from dotenv.
    final tempDir = await Directory.systemTemp.createTemp('code_from_input');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
  });

  group('SpaceCodeController.codeFromInput', () {
    setUp(
      () => dotenv.testLoad(
        mergeWith: {'FRONTEND_URL': 'https://app.pangea.chat'},
      ),
    );

    test('unwraps a pasted course link to its code', () {
      expect(
        SpaceCodeController.codeFromInput('https://app.pangea.chat/abc1234'),
        'abc1234',
      );
      expect(
        SpaceCodeController.codeFromInput(
          ' https://app.pangea.chat/abc1234/?utm_source=email\n',
        ),
        'abc1234',
      );
    });

    test('unwraps links on the build\'s own app host, staging included', () {
      dotenv.testLoad(
        mergeWith: {'FRONTEND_URL': 'https://app.staging.pangea.chat'},
      );
      expect(
        SpaceCodeController.codeFromInput(
          'https://app.staging.pangea.chat/abc1234',
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
        'https://example.com/abc1234',
        'https://app.staging.pangea.chat/abc1234',
        'https://app.pangea.chat/chats',
        'https://app.pangea.chat/room/abc1234',
        'not a code',
      ]) {
        expect(SpaceCodeController.codeFromInput(text), text);
      }
    });
  });
}
