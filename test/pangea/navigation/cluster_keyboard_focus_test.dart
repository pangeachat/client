import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/world_user_cluster.dart';
import 'package:fluffychat/widgets/avatar.dart';

/// Keyboard reachability for the cluster's Settings avatar and language flag
/// (#7219): both were bare GestureDetectors with no focus node, so Tab skipped
/// them entirely — the "Settings" and "Learning settings" stops in the shell's
/// expected tab order could never be reached or activated by keyboard. They
/// are InkWell-backed now; these tests pin that each one takes focus from a
/// single Tab, shows its gold focus ring, and fires its tap on Enter.
void main() {
  setUpAll(() {
    // `Avatar` resolves the bot name from the environment at build time;
    // initialize dotenv with an inline value so no real `.env` file is needed
    // (CI has none).
    dotenv.testLoad(fileInput: 'BOT_NAME=@bot:example.org');
    // The flag chip fetches its SVG over HTTP; the test binding's default
    // client 400s every request with an empty body, which the SVG parser
    // reports as an uncatchable async "Invalid SVG data" zone error. Serve a
    // minimal valid SVG instead so the real chip renders offline.
    HttpOverrides.global = _FakeSvgHttpOverrides();
  });

  tearDownAll(() => HttpOverrides.global = null);

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(body: Center(child: child)),
      ),
    );
    // The L10n delegates load asynchronously, so one pump isn't enough for
    // the home to mount (same as the other mobile-chrome tests).
    await tester.pumpAndSettle();
  }

  /// The widget under [finder] shows its focus ring: some descendant
  /// Container carries a non-null foregroundDecoration.
  bool showsFocusRing(WidgetTester tester, Finder finder) => tester
      .widgetList<Container>(
        find.descendant(of: finder, matching: find.byType(Container)),
      )
      .any((c) => c.foregroundDecoration != null);

  testWidgets('settings avatar: Tab focuses it, ring shows, Enter activates', (
    tester,
  ) async {
    var taps = 0;
    await pump(
      tester,
      ClusterAvatar(avatarUrl: null, name: 'Tester', onTap: () => taps++),
    );

    final avatar = find.byType(ClusterAvatar);
    expect(showsFocusRing(tester, avatar), isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(
      Focus.of(tester.element(find.byType(Avatar))).hasFocus,
      isTrue,
      reason: 'one Tab must land on the avatar (it is the only stop here)',
    );
    expect(showsFocusRing(tester, avatar), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('language flag: Tab focuses it, ring shows, Enter activates', (
    tester,
  ) async {
    var taps = 0;
    final es = LanguageModel(langCode: 'es-ES', displayName: 'Spanish');
    await pump(tester, ClusterLanguageFlag(language: es, onTap: () => taps++));

    final flag = find.byType(ClusterLanguageFlag);
    expect(showsFocusRing(tester, flag), isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(showsFocusRing(tester, flag), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(taps, 1);
  });
}

/// Serves every HTTP request a 200 with a minimal valid SVG body, replacing
/// the test binding's default 400-everything client (see [main]'s setUpAll).
/// `package:http`'s IOClient — what flutter_svg's network loader uses — runs
/// on `dart:io`'s [HttpClient], so overriding at this level covers it.
class _FakeSvgHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _FakeHttpClient();
}

class _FakeHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _FakeHttpClientRequest();

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _FakeHttpClientRequest();

  // Config setters/getters IOClient pokes (autoUncompress etc.) — accept and
  // ignore everything else.
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpClientRequest implements HttpClientRequest {
  @override
  final HttpHeaders headers = _FakeHttpHeaders();

  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.drain<void>();

  @override
  Future<HttpClientResponse> close() async => _FakeHttpClientResponse();

  @override
  Future<HttpClientResponse> get done => close();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  static final List<int> _svgBytes = utf8.encode(
    '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"/>',
  );

  @override
  int get statusCode => 200;

  @override
  String get reasonPhrase => 'OK';

  @override
  int get contentLength => _svgBytes.length;

  @override
  bool get isRedirect => false;

  @override
  bool get persistentConnection => false;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  final HttpHeaders headers = _FakeHttpHeaders();

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(_svgBytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpHeaders implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  void forEach(void Function(String name, List<String> values) action) {}

  @override
  List<String>? operator [](String name) => null;

  @override
  String? value(String name) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
