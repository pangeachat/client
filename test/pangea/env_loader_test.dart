import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fluffychat/pangea/common/config/env_loader.dart';

void main() {
  group('EnvLoader.looksLikeEnvFile', () {
    test('accepts a typical env file', () {
      const content = """
ENVIRONMENT = 'staging'
CHOREO_API = 'https://api.staging.pangea.chat'
SYNAPSE_URL = 'https://matrix.staging.pangea.chat'
""";
      expect(EnvLoader.looksLikeEnvFile(content), isTrue);
    });

    test('accepts env with comments, blank lines, and unquoted values', () {
      const content = """
# comment
FOO=bar

BAZ = 'qux'
""";
      expect(EnvLoader.looksLikeEnvFile(content), isTrue);
    });

    test('rejects HTML served by SPA index fallback', () {
      const content = """
<!DOCTYPE html>
<html>
<head><title>app</title></head>
<body></body>
</html>
""";
      expect(EnvLoader.looksLikeEnvFile(content), isFalse);
    });

    test('rejects empty content', () {
      expect(EnvLoader.looksLikeEnvFile(''), isFalse);
      expect(EnvLoader.looksLikeEnvFile('   \n  '), isFalse);
    });

    test('rejects plain text without assignments', () {
      expect(EnvLoader.looksLikeEnvFile('not an env file'), isFalse);
    });
  });

  group('EnvLoader.tryLoadFromWebRoot', () {
    test('loads dotenv from a valid response', () async {
      final client = MockClient(
        (request) async => http.Response("FOO = 'bar'\nBAZ = 'qux'\n", 200),
      );
      final loaded = await EnvLoader.tryLoadFromWebRoot(client: client);
      expect(loaded, isTrue);
      expect(dotenv.env['FOO'], 'bar');
      expect(dotenv.env['BAZ'], 'qux');
    });

    test('returns false on SPA index fallback HTML', () async {
      final client = MockClient(
        (request) async => http.Response('<!DOCTYPE html><html></html>', 200),
      );
      expect(await EnvLoader.tryLoadFromWebRoot(client: client), isFalse);
    });

    test('returns false on non-200 response', () async {
      final client = MockClient(
        (request) async => http.Response('Not Found', 404),
      );
      expect(await EnvLoader.tryLoadFromWebRoot(client: client), isFalse);
    });

    test('returns false when the request throws', () async {
      final client = MockClient(
        (request) async => throw http.ClientException('network down'),
      );
      expect(await EnvLoader.tryLoadFromWebRoot(client: client), isFalse);
    });
  });
}
