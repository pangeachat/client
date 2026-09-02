import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fluffychat/pangea/common/utils/svg_repo.dart';
import 'package:fluffychat/pangea/common/widgets/network_svg.dart';
import 'sentry_capture_harness.dart';

/// Language flags used to render with `SvgPicture.network`, which lets
/// vector_graphics own the fetch. On a transport failure it drops the future
/// its `whenComplete` returns, so the error reached Sentry as an UNHANDLED zone
/// error — 8,054 of them — even though the widget rendered its fallback fine.
/// With no repo in front there was no dedupe either, so one offline moment on a
/// list of flags fired an event per flag, and again on every rebuild (#8338).
///
/// [NetworkSvg] goes through [SvgRepo] instead. What's pinned here: a failed
/// fetch surfaces as a value, never as a throw or an escaped async error, and
/// one URL costs one fetch no matter how many widgets ask for it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // GetStorage needs path_provider; stub the channel to a temp dir.
    final tempDir = await Directory.systemTemp.createTemp('svg_repo_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('svg_cache');
  });

  const svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1"/>';

  // SvgRepo memoizes by URL for the life of the session, so each case needs a
  // URL no other case has used.
  var urlCounter = 0;
  String freshUrl() => 'https://assets.example.test/flag-${urlCounter++}.svg';

  /// Runs [body] with every top-level `http` call served by [handler].
  Future<T> withClient<T>(
    Future<http.Response> Function(http.Request) handler,
    Future<T> Function() body,
  ) => http.runWithClient(body, () => MockClient(handler));

  group('SvgRepo', () {
    test(
      'a transport failure returns an error result, it does not throw',
      () async {
        final url = freshUrl();
        final result = await withClient(
          (_) async => throw http.ClientException('Failed to fetch'),
          () => SvgRepo.get(url),
        );

        expect(result.isError, isTrue);
      },
    );

    test('a 404 returns an error result', () async {
      final url = freshUrl();
      final result = await withClient(
        (_) async => http.Response('nope', 404),
        () => SvgRepo.get(url),
      );

      expect(result.isError, isTrue);
    });

    test('one URL costs one fetch, however many callers ask', () async {
      final url = freshUrl();
      var fetches = 0;

      await withClient(
        (_) async {
          fetches++;
          return http.Response(svg, 200);
        },
        () async {
          await Future.wait([SvgRepo.get(url), SvgRepo.get(url)]);
          await SvgRepo.get(url);
        },
      );

      expect(fetches, 1);
    });

    test('a failure is not retried for the rest of the session', () async {
      final url = freshUrl();
      var fetches = 0;

      await withClient(
        (_) async {
          fetches++;
          throw http.ClientException('Failed to fetch');
        },
        () async {
          await SvgRepo.get(url);
          await SvgRepo.get(url);
        },
      );

      expect(fetches, 1);
    });

    test('a fetched SVG comes back intact', () async {
      final url = freshUrl();
      final result = await withClient(
        (_) async => http.Response(svg, 200),
        () => SvgRepo.get(url),
      );

      expect(result.asValue?.value, svg);
    });
  });

  /// The Sentry title is the only thing a triager can act on. A status alone
  /// names no asset (CLIENT-ECE), and a transport failure names one only when
  /// the exception happens to be a `ClientException` carrying its uri
  /// (CLIENT-EGM). Both branches carry the url themselves (#8733).
  group('what SvgRepo reports', () {
    late SentryCaptureHarness harness;

    setUp(() async {
      harness = SentryCaptureHarness();
      await harness.init();
    });

    tearDown(() => harness.close());

    test('a non-200 status names the url', () async {
      final url = freshUrl();
      final event = await withClient(
        (_) async => http.Response('nope', 404),
        () => harness.capture(() => SvgRepo.get(url)),
      );

      expect(event.throwable.toString(), contains('404'));
      expect(event.throwable.toString(), contains(url));
    });

    test('a transport failure names the url', () async {
      final url = freshUrl();
      final event = await withClient(
        (_) async => throw http.ClientException('Failed to fetch'),
        () => harness.capture(() => SvgRepo.get(url)),
      );

      expect(event.throwable.toString(), contains(url));
    });
  });

  group('NetworkSvg', () {
    /// Mounts the widget and lets the fetch actually run. The load reaches the
    /// filesystem (the SVG cache) and the mock client, neither of which the
    /// widget tester's fake clock will advance — hence [WidgetTester.runAsync].
    Future<void> mountAndLoad(
      WidgetTester tester,
      String url,
      Future<http.Response> Function(http.Request) handler,
    ) async {
      await tester.runAsync(() async {
        await withClient(handler, () async {
          await tester.pumpWidget(
            MaterialApp(
              home: NetworkSvg(
                svgUrl: url,
                errorWidget: const Text('fallback'),
                placeholder: const Text('loading'),
              ),
            ),
          );
          expect(find.text('loading'), findsOneWidget);

          // The widget awaits this exact memoized future.
          await SvgRepo.get(url);
          await Future<void>.delayed(Duration.zero);
        });
      });
      await tester.pump();
    }

    testWidgets('a failed load shows the fallback and leaks no async error', (
      tester,
    ) async {
      await mountAndLoad(
        tester,
        freshUrl(),
        (_) async => throw http.ClientException('Failed to fetch'),
      );

      expect(find.text('fallback'), findsOneWidget);
      // An escaped zone error would have failed this test by now — the old
      // SvgPicture.network path is exactly what produced one.
      expect(tester.takeException(), isNull);
    });

    testWidgets('a loaded SVG replaces the placeholder', (tester) async {
      await mountAndLoad(
        tester,
        freshUrl(),
        (_) async => http.Response(svg, 200),
      );

      expect(find.text('loading'), findsNothing);
      expect(find.text('fallback'), findsNothing);
    });
  });
}
