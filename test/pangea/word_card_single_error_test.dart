import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' show Response, runWithClient;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/error_indicator.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_repo.dart';
import 'package:fluffychat/pangea/lemmas/lemma_meaning_builder.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/routes/chat/events/phonetic_transcription/phonetic_transcription_builder.dart';
import 'package:fluffychat/routes/chat/events/phonetic_transcription/pt_v2_repo.dart';
import 'package:fluffychat/routes/chat/toolbar/word_card/word_zoom_widget.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'fake_pangea_controller.dart';
import 'get_test_client.dart';
import 'word_card_test_matrix.dart';

/// #8902 — the word card's sections each fetched and each showed their own
/// failure, so a throttled backend put the same "we're loading a lot" chip on
/// the card twice. The card now loads once per source and, when nothing
/// loaded, shows one indicator; when one source loaded, that section stays
/// and only the other's failure shows.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const choreoApi = 'https://api.test.pangea.chat';
  const rateLimitedCopy = "We're loading a lot right now";

  late Client client;
  late SharedPreferences store;

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('word_card_error');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    // The pronunciation strip stops TTS on dispose; the engine is not under
    // test. The `get*` queries must answer with a list — the plugin's dynamic
    // returns are cast, and a cast failure lands in an error handler that
    // breaks into the debugger and hangs the run.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'), (
          methodCall,
        ) async {
          return methodCall.method.startsWith('get') ? [] : 1;
        });
    await GetStorage.init('env_override');
    dotenv.testLoad(
      mergeWith: {
        'SYNAPSE_URL': 'https://fakeServer.notExisting',
        'CHOREO_API': choreoApi,
      },
    );
    SharedPreferences.setMockInitialValues({});
    store = await SharedPreferences.getInstance();

    // Open both repos' disk caches here, on the real clock, rather than
    // letting the first case do it. Each repo is a singleton that awaits a
    // one-shot init future on every read; a completed future schedules its
    // awaiter's microtask on the zone it was CREATED in, so an init created
    // inside one case's FakeAsync leaves every later case's read parked on a
    // queue nobody flushes — stuck on the shimmer with the backend never
    // asked. (`registerStorageKey` in that init reads the controller.)
    MatrixState.pangeaController = FakePangeaController();
    await LemmaInfoRepo.instance.clearCache();
    await PTV2Repo.instance.clearCache();
  });

  setUp(() async {
    client = await getTestClient();
  });

  tearDown(() => client.dispose());

  Response json(int status, Map<String, dynamic> body) => Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );

  final throttled = json(429, {'detail': 'rate limited'});

  /// The backend for one case: [lemma] answers the meaning read,
  /// [transcription] the pronunciation read.
  MockClient backend({
    required Response lemma,
    required Response transcription,
  }) => MockClient((request) async {
    final path = request.url.path;
    if (path.endsWith('/lemma_definition')) return lemma;
    if (path.endsWith('/phonetic_transcription_v2')) return transcription;
    fail('unexpected request: $path');
  });

  /// Each case gets its own [word]: the repos are singletons with a disk
  /// cache, so a meaning loaded in one case would answer the next case's read.
  ///
  /// English throughout — one locale per isolate, or a second set of
  /// delegates loads asynchronously and leaves the subtree empty.
  Future<void> pumpCard(WidgetTester tester, String word) async {
    await tester.pumpWidget(
      WordCardTestMatrix(
        clients: [client],
        store: store,
        accessToken: 'syt_test_token',
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: WordZoomWidget(
              token: PangeaTokenText(
                offset: 0,
                content: word,
                length: word.length,
              ),
              construct: ConstructIdentifier(
                lemma: word,
                type: ConstructTypeEnum.vocab,
                category: 'VERB',
              ),
              langCode: 'de',
              pos: 'VERB',
              enableEmojiSelection: false,
              enableEmojiReactions: false,
              // Wide enough that the test font's square glyphs keep a
              // section's error copy on the two lines the real font gives it
              // at the card's default width; how the card fits at narrow
              // widths is not under test, and an overflow fails the test.
              maxWidth: 700.0,
            ),
          ),
        ),
      ),
    );

    // Both reads have to land before anything is asserted. The repos open
    // their disk cache first, which is real I/O the fake clock will not
    // advance (hence `runAsync`), and the card shimmers throughout, so
    // `pumpAndSettle` would time out. The two builders are polled for a
    // terminal state rather than the UI, so a case cannot pass on a section
    // that is merely still loading.
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 20)),
      );
      // With a duration: `GetStorage` opens the cache box on a zero-duration
      // timer, which only fires when the test clock moves — and a whole
      // second of it, so a read that waits out a throttle before answering
      // (#8794) still lands inside this loop.
      await tester.pump(const Duration(seconds: 1));
      if (find.byType(LemmaMeaningBuilder).evaluate().isEmpty) continue;
      // `.first`, so the same poll runs against the pre-fix card too, where
      // each section held its own builder — the negative control for this
      // file.
      final lemma = tester.state<LemmaMeaningBuilderState>(
        find.byType(LemmaMeaningBuilder).first,
      );
      final transcription = tester.state<PhoneticTranscriptionBuilderState>(
        find.byType(PhoneticTranscriptionBuilder).first,
      );
      if ((lemma.isLoaded || lemma.isError) &&
          (transcription.isLoaded || transcription.isError)) {
        break;
      }
    }
    // A loaded read is written to the disk cache on a zero-duration timer;
    // let it fire rather than end the case with a timer pending.
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('nothing loaded: one indicator for the whole card', (
    tester,
  ) async {
    await runWithClient(() async {
      await pumpCard(tester, 'freut');

      expect(
        find.byType(ErrorIndicator),
        findsOneWidget,
        reason: 'the two sections\' failures collapse into one (#8902)',
      );
      expect(
        find.textContaining(rateLimitedCopy, findRichText: true),
        findsOneWidget,
        reason: 'a throttle on either read picks the wait-a-moment copy',
      );
    }, () => backend(lemma: throttled, transcription: throttled));
  });

  testWidgets('meaning loaded, transcription throttled: the meaning stays', (
    tester,
  ) async {
    await runWithClient(
      () async {
        await pumpCard(tester, 'lacht');

        expect(
          find.textContaining('to laugh', findRichText: true),
          findsOneWidget,
          reason: 'a section that loaded keeps its content',
        );
        expect(
          find.byType(ErrorIndicator),
          findsOneWidget,
          reason: 'only the failed section shows its failure',
        );
        expect(
          find.textContaining(rateLimitedCopy, findRichText: true),
          findsOneWidget,
        );
      },
      () => backend(
        lemma: json(200, {
          'emoji': ['😂'],
          'meaning': 'to laugh',
        }),
        transcription: throttled,
      ),
    );
  });

  testWidgets(
    'transcription loaded, meaning throttled: the transcription stays',
    (tester) async {
      await runWithClient(
        () async {
          await pumpCard(tester, 'weint');

          expect(
            find.textContaining('vaɪnt', findRichText: true),
            findsOneWidget,
            reason: 'a section that loaded keeps its content',
          );
          expect(
            find.byType(ErrorIndicator),
            findsOneWidget,
            reason: 'only the failed section shows its failure',
          );
        },
        () => backend(
          lemma: throttled,
          transcription: json(200, {
            'pronunciations': [
              {'transcription': 'vaɪnt', 'tts_phoneme': 'vaɪnt'},
            ],
          }),
        ),
      );
    },
  );
}
