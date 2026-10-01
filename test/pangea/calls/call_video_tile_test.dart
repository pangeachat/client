import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:matrix/matrix.dart' as matrix;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/calls/call_capture.dart';
import 'package:fluffychat/routes/chat/calls/call_media.dart';
import 'package:fluffychat/routes/chat/calls/call_panel.dart';
import 'package:fluffychat/routes/chat/calls/call_service.dart';
import 'package:fluffychat/routes/chat/calls/call_session.dart';
import 'package:fluffychat/routes/chat/calls/call_token_repo.dart';
import 'package:fluffychat/routes/chat/calls/pcm_chunker.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_response_model.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../fake_pangea_controller.dart';

/// #8795 — turning a camera off froze the video on its last frame (and showed
/// black on a reopen) instead of the participant's avatar.
///
/// The cause is that switching a camera off does not tear its track down:
/// LiveKit mutes the publication and leaves the last frame attached, so a
/// renderer left pointing at it freezes. The fix reads the camera as OFF when
/// its publication is muted or has no track -- the signal LiveKit itself
/// exposes ([CallVideoFeed.cameraIsOff]) -- and the view shows the avatar for
/// that tile instead ([CallVideoTile]). (A track that ENDS while un-muted has
/// no usable public signal on the pinned SDK; see [CallVideoFeed.cameraIsOff].)
///
/// The real [lk.VideoTrackRenderer] cannot be mounted in a widget test: it
/// opens a platform renderer and registers a view on the track through the
/// SDK's `@internal` API. So [CallVideoTile.buildVideoView] is an injectable
/// seam -- the real renderer in production, a findable stand-in here -- which
/// is the only way the video layer, and a camera going off then ON again, can
/// be exercised at all. The fix is proven across the real seams the panel
/// reads:
/// - the decision -- muted or absent is OFF -- is pinned pure
///   ([CallVideoFeed.cameraIsOff]) and on the mapping ([CallVideoFeed.of]);
/// - the slot assignment -- peer full-bleed, this device inset, each video or
///   avatar, INCLUDING a peer that never published (its slot is the avatar,
///   not a usurped self-view) -- is pinned pure ([CallVideoLayout.from]) and
///   its wiring into the panel pinned on the source;
/// - the tile shows the avatar and NO renderer for an off/absent track, and
///   with the DEFAULT (real) builder an off track never reaches a renderer;
/// - the panel, through `session.videoFeeds()`, shows the avatar for a muted
///   camera and never mounts a renderer; the video layer shows a live camera
///   as video and an off one as the avatar side by side; and a camera coming
///   back on RESTORES its video;
/// - the `usedVideo` latch counts an actual track, not mere feed-presence.

/// A non-null [lk.VideoTrack] the tests can hold to stand in a PRESENT camera
/// track. Deliberately never rendered: a muted track's whole point is that it
/// is present, and the view must decline to paint it. Any method call on it
/// throws, which is exactly what asserts the view never touches it.
class _StubVideoTrack extends Fake implements lk.VideoTrack {}

/// A media whose video feeds the test states outright, standing in for the
/// LiveKit room the real [CallMedia.videoFeeds] reads. Everything else is the
/// no-op stub the panel tests already use.
class _FeedMedia extends CallMedia {
  List<CallVideoFeed> feeds = const [];

  @override
  List<CallVideoFeed> videoFeeds() => feeds;

  @override
  Future<void> connect(CallToken grant, {required bool video}) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> dispose() async {}
}

class _NullSink implements CallAudioSink {
  @override
  Future<void> deliver(PcmChunk chunk, {Duration? within}) async {}

  @override
  void discarded(PcmChunk chunk) {}

  @override
  Future<bool> close() async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  setUpAll(() async {
    // Avatar reads BotName.byEnvironment, which needs GetStorage and dotenv.
    final tempDir = await Directory.systemTemp.createTemp('call_video_tile');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    dotenv.testLoad(
      mergeWith: {
        'BOT_NAME': 'pangeabot',
        'SYNAPSE_URL': 'https://fakeServer.notExisting',
      },
    );
    MatrixState.pangeaController = FakePangeaController();
    // The generated L10n loads deferred, so an un-preloaded locale leaves
    // `Localizations` rendering an empty placeholder and nothing to assert on.
    await lookupL10n(const Locale('en'));
  });

  // Any test that swaps in the video-view stand-in below restores the real
  // renderer afterwards, so the default-builder tests always see the platform
  // widget they assert is absent.
  tearDown(() => CallVideoTile.buildVideoView = lk.VideoTrackRenderer.new);

  final videoRenderer = find.byType(lk.VideoTrackRenderer);

  // A findable stand-in for the un-mountable platform renderer, keyed by the
  // track so two live tiles never collide. Installed via
  // [CallVideoTile.buildVideoView] to exercise the video layer and a camera
  // coming back ON -- neither reachable with the real renderer under test.
  Widget liveVideoStandIn(lk.VideoTrack track) => KeyedSubtree(
    key: ValueKey('live-video:${identityHashCode(track)}'),
    child: const SizedBox.expand(),
  );
  final liveVideoViews = find.byWidgetPredicate(
    (widget) =>
        widget.key is ValueKey &&
        '${(widget.key as ValueKey).value}'.startsWith('live-video:'),
  );

  Future<void> pumpTile(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(body: child),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('CallVideoFeed.cameraIsOff', () {
    // The one decision the freeze bug turned on -- the canonical LiveKit
    // signal: a camera is off when its publication is muted or has no track.
    test('a muted camera is off even with its track still present', () {
      expect(
        CallVideoFeed.cameraIsOff(muted: true, hasTrack: true),
        isTrue,
        reason:
            'a switched-off camera stays published and muted; its last frame '
            'is still attached and must NOT be rendered',
      );
    });

    test('an unmuted camera with a track is on', () {
      expect(CallVideoFeed.cameraIsOff(muted: false, hasTrack: true), isFalse);
    });

    test('a camera with no track is off', () {
      expect(CallVideoFeed.cameraIsOff(muted: false, hasTrack: false), isTrue);
      expect(CallVideoFeed.cameraIsOff(muted: true, hasTrack: false), isTrue);
    });
  });

  group('CallVideoFeed.of', () {
    test(
      'a muted publication is a feed whose camera is off, track retained',
      () {
        final track = _StubVideoTrack();
        final feed = CallVideoFeed.of(
          track: track,
          muted: true,
          isLocal: false,
        );

        expect(feed.cameraOff, isTrue, reason: 'muted is off');
        expect(
          feed.track,
          same(track),
          reason:
              'the frozen track is kept -- which is exactly why the view must '
              'decide on cameraOff and not on the track being non-null',
        );
        expect(feed.isLocal, isFalse);
      },
    );

    test('an unmuted publication with a track is on', () {
      final feed = CallVideoFeed.of(
        track: _StubVideoTrack(),
        muted: false,
        isLocal: true,
      );
      expect(feed.cameraOff, isFalse);
      expect(feed.isLocal, isTrue);
    });

    test('a publication with no track is off', () {
      final feed = CallVideoFeed.of(track: null, muted: false, isLocal: false);
      expect(feed.cameraOff, isTrue);
      expect(feed.track, isNull);
    });
  });

  // The panel's two slots resolved from the feeds. A live renderer cannot be
  // mounted in a widget test, so the slot assignment -- which participant is
  // full-bleed, which is the inset, and which shows video vs the avatar -- is
  // pinned here, purely. Feeds are built through `.of` so no impossible state
  // (a track-less feed that is not `cameraOff`) can stand in for a live camera.
  group('CallVideoLayout.from', () {
    CallVideoFeed peerLive() => CallVideoFeed.of(
      track: _StubVideoTrack(),
      muted: false,
      isLocal: false,
    );
    CallVideoFeed peerOff() =>
        CallVideoFeed.of(track: _StubVideoTrack(), muted: true, isLocal: false);
    CallVideoFeed selfLive() =>
        CallVideoFeed.of(track: _StubVideoTrack(), muted: false, isLocal: true);
    CallVideoFeed selfOff() =>
        CallVideoFeed.of(track: _StubVideoTrack(), muted: true, isLocal: true);

    test(
      'both cameras live: peer full-bleed and self inset both show video',
      () {
        final layout = CallVideoLayout.from([peerLive(), selfLive()]);
        expect(layout.hasVideo, isTrue);
        expect(layout.peer?.cameraOff, isFalse);
        expect(layout.self?.cameraOff, isFalse);
      },
    );

    test('peer live, self off: the self inset falls back to the avatar', () {
      final layout = CallVideoLayout.from([peerLive(), selfOff()]);
      expect(layout.hasVideo, isTrue);
      expect(layout.peer?.cameraOff, isFalse);
      expect(
        layout.self,
        isNotNull,
        reason: 'this device published a camera, so it keeps an inset',
      );
      expect(
        layout.self?.cameraOff,
        isTrue,
        reason: 'that inset shows the avatar, not a frozen self-view',
      );
    });

    test(
      'peer off, self live: the peer full-bleed falls back to the avatar',
      () {
        final layout = CallVideoLayout.from([peerOff(), selfLive()]);
        expect(layout.hasVideo, isTrue);
        expect(layout.peer?.cameraOff, isTrue);
        expect(layout.self?.cameraOff, isFalse);
      },
    );

    test('peer never published, self live: the peer keeps the full-bleed', () {
      // The RED finding: laying the feeds out in publication order made the
      // single local feed the full-bleed and dropped the peer off the screen.
      // The peer slot must resolve to null here -- which the panel renders as
      // the peer's avatar full-bleed -- and this device's live camera is the
      // inset, never the full-bleed.
      final layout = CallVideoLayout.from([selfLive()]);
      expect(layout.hasVideo, isTrue);
      expect(
        layout.peer,
        isNull,
        reason: 'no peer camera -> the peer full-bleed is the avatar',
      );
      expect(
        layout.self?.cameraOff,
        isFalse,
        reason: 'my live camera is the inset, not the full-bleed',
      );
    });

    test('self never published, peer live: no inset', () {
      final layout = CallVideoLayout.from([peerLive()]);
      expect(layout.hasVideo, isTrue);
      expect(layout.peer?.cameraOff, isFalse);
      expect(layout.self, isNull, reason: 'this device has no camera to inset');
    });

    test('both cameras off: the voice layout', () {
      final layout = CallVideoLayout.from([peerOff(), selfOff()]);
      expect(
        layout.hasVideo,
        isFalse,
        reason: 'no live camera -> the big peer avatar, as if none was on',
      );
    });

    test('no feeds at all: the voice layout', () {
      final layout = CallVideoLayout.from(const []);
      expect(layout.hasVideo, isFalse);
      expect(layout.peer, isNull);
      expect(layout.self, isNull);
    });

    test('camera on then off: the self inset swaps to the avatar, peer '
        'unchanged', () {
      // The transition the bug is about, at the layout it turns on. The peer is
      // live throughout; this device's camera goes off.
      final on = CallVideoLayout.from([peerLive(), selfLive()]);
      expect(on.self?.cameraOff, isFalse, reason: 'self starts live');

      final off = CallVideoLayout.from([peerLive(), selfOff()]);
      expect(
        off.self?.cameraOff,
        isTrue,
        reason: 'the self inset is now the avatar',
      );
      expect(
        off.peer?.cameraOff,
        isFalse,
        reason: 'the peer full-bleed is untouched by the self camera',
      );
      expect(
        off.hasVideo,
        isTrue,
        reason: 'the peer camera keeps it a video call',
      );
    });
  });

  // The full-bleed/inset wiring cannot be exercised through a pumped video
  // layout -- that needs a live renderer -- so it is pinned on the source, the
  // convention this suite uses for facts cheap to assert here and expensive
  // through a whole widget tree. What it guards is the RED regression: the
  // full-bleed must be the PEER slot and the inset THIS device's, never the
  // publication-ordered `feeds.first` that dropped a camera-less peer.
  test('the panel lays the peer full-bleed and this device inset', () {
    final source = File(
      'lib/routes/chat/calls/call_panel.dart',
    ).readAsStringSync();
    final start = source.indexOf('Widget _videoLayer(');
    expect(start, greaterThan(-1), reason: '_videoLayer must still exist');
    final body = source.substring(start, source.indexOf('\n  }', start));

    final peerAt = body.indexOf('_slotTile(layout.peer, isLocal: false)');
    final selfAt = body.indexOf('_slotTile(layout.self, isLocal: true');
    expect(
      peerAt,
      greaterThan(-1),
      reason: 'the peer slot must be laid out full-bleed',
    );
    expect(selfAt, greaterThan(peerAt), reason: 'this device is the inset');
    expect(
      body.contains('layout.self != null'),
      isTrue,
      reason: 'the inset appears only once this device has published a camera',
    );
    for (final ordered in ['feeds.first', 'feeds[1]']) {
      expect(
        body.contains(ordered),
        isFalse,
        reason:
            'publication-ordered layout dropped a camera-less peer off the '
            'screen (#8795); the slots come from CallVideoLayout now',
      );
    }
  });

  group('CallVideoTile', () {
    testWidgets('a camera-off tile shows the avatar and no renderer, even with '
        'a track still attached', (tester) async {
      // The core of the fix: a PRESENT but disabled track renders the avatar,
      // never a (frozen) renderer. The old behaviour -- render the track it was
      // handed -- would build a VideoTrackRenderer on the stub here, whose init
      // touches the stub and throws, so this bites the regression twice over:
      // the renderer is found, and an exception is raised.
      await pumpTile(
        tester,
        CallVideoTile(
          track: _StubVideoTrack(),
          cameraOff: true,
          avatarUrl: null,
          name: 'Ada',
        ),
      );

      expect(find.byType(Avatar), findsOneWidget);
      expect(
        videoRenderer,
        findsNothing,
        reason: 'a disabled camera must not keep a renderer on its last frame',
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'the avatar path must not have touched the disabled track',
      );
    });

    testWidgets('a tile with no track shows the avatar', (tester) async {
      await pumpTile(
        tester,
        const CallVideoTile(
          track: null,
          cameraOff: false,
          avatarUrl: null,
          name: 'Ada',
        ),
      );

      expect(find.byType(Avatar), findsOneWidget);
      expect(videoRenderer, findsNothing);
    });
  });

  group('CallPanel through the session seam', () {
    late _FeedMedia media;
    late CallSession session;

    Future<CallSession> aSession() async {
      final client = matrix.Client(
        'call-video-tile-test',
        httpClient: matrix.FakeMatrixApi(),
        database: await matrix.MatrixSdkDatabase.init(
          'call-video-tile-test',
          database: await databaseFactoryFfi.openDatabase(':memory:'),
          sqfliteFactory: databaseFactoryFfi,
        ),
      );
      await client.login(
        matrix.LoginType.mLoginPassword,
        token: 'abcd',
        identifier: matrix.AuthenticationUserIdentifier(
          user: '@test:fakeServer.notExisting',
        ),
        deviceId: 'GHTYAJCE',
      );
      await client.abortSync();
      return CallSession.start(
        room: matrix.Room(id: '!r:server', client: client),
        video: false,
        callService: CallService(client),
        transcribe: (request) async =>
            SpeechToTextResponseModel(results: const []),
        userL1: 'en',
        userL2: 'es',
        analytics: (eventId, uses, language) async {},
        onReleased: (_) {},
        mediaOverride: media,
        captureOverride: CallCaptureService(sink: _NullSink()),
      );
    }

    // Built in setUp, never in a test body: `testWidgets` runs its body in a
    // fake-async zone, and the login and database here are real I/O.
    setUp(() async {
      media = _FeedMedia();
      session = await aSession();
    });
    tearDown(() => session.dispose());

    Future<void> pumpPanel(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(body: CallPanel(session: session)),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a muted camera renders the avatar, never a frozen renderer', (
      tester,
    ) async {
      // The bug's own shape: a camera that WAS on and is now off. Its track is
      // still attached (the stub), and it is muted. Fed through the real
      // `session.videoFeeds()` seam, the panel must show the avatar and mount
      // no renderer. Under the old behaviour the muted track would reach a
      // VideoTrackRenderer, which would touch the stub and throw -- so this
      // fails loudly if the mute is ever ignored again.
      media.feeds = [
        CallVideoFeed.of(track: _StubVideoTrack(), muted: true, isLocal: false),
      ];

      await pumpPanel(tester);

      expect(
        videoRenderer,
        findsNothing,
        reason: 'a muted camera must not paint its frozen last frame',
      );
      expect(
        find.byType(Avatar),
        findsWidgets,
        reason: 'the off camera falls back to the participant avatar',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the video layer renders live video for the on camera and the '
        'avatar for the off one', (tester) async {
      // The mixed case a single muted feed never reached: with this device's
      // camera still ON, `hasVideo` is true and the panel takes the VIDEO
      // layer. The peer's off camera must be the full-bleed avatar, and only
      // the live self camera a video view -- a regression that rendered the
      // muted peer track would put a second video view on screen.
      CallVideoTile.buildVideoView = liveVideoStandIn;
      media.feeds = [
        CallVideoFeed.of(track: _StubVideoTrack(), muted: true, isLocal: false),
        CallVideoFeed.of(track: _StubVideoTrack(), muted: false, isLocal: true),
      ];

      await pumpPanel(tester);

      expect(
        liveVideoViews,
        findsOneWidget,
        reason: 'only the ON (self) camera renders video in the video layer',
      );
      expect(
        find.byType(Avatar),
        findsWidgets,
        reason: 'the OFF (peer) camera is laid out as the full-bleed avatar',
      );
      expect(
        videoRenderer,
        findsNothing,
        reason: 'the real renderer is stubbed',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a camera going off then on again restores its live video', (
      tester,
    ) async {
      // on -> off -> ON. The peer stays live so the panel holds the video
      // layer throughout and only this device's inset moves. A tile that
      // dropped to the avatar and never came back would leave one video view
      // on the final frame; the restore is what this pins.
      CallVideoTile.buildVideoView = liveVideoStandIn;
      final peerTrack = _StubVideoTrack();
      final selfTrack = _StubVideoTrack();

      Future<void> pumpWith({required bool selfOn}) async {
        media.feeds = [
          CallVideoFeed.of(track: peerTrack, muted: false, isLocal: false),
          CallVideoFeed.of(track: selfTrack, muted: !selfOn, isLocal: true),
        ];
        await pumpPanel(tester);
      }

      await pumpWith(selfOn: true);
      expect(
        liveVideoViews,
        findsNWidgets(2),
        reason: 'both cameras live -> peer full-bleed and self inset video',
      );

      await pumpWith(selfOn: false);
      expect(
        liveVideoViews,
        findsOneWidget,
        reason: 'self off -> only the peer renders; the self inset is avatar',
      );

      await pumpWith(selfOn: true);
      expect(
        liveVideoViews,
        findsNWidgets(2),
        reason: 'self camera back on -> its live video is RESTORED',
      );
      expect(tester.takeException(), isNull);
    });

    test('videoFeeds latches usedVideo for a published camera track', () {
      // A camera switched off keeps its last frame attached, so its feed still
      // carries a track: video WAS rendered, and the timeline records it. This
      // is the same thing the old flat `videoTracks()` latched on.
      expect(session.usedVideo, isFalse, reason: 'nothing published yet');
      media.feeds = [
        CallVideoFeed.of(track: _StubVideoTrack(), muted: true, isLocal: false),
      ];
      session.videoFeeds();
      expect(
        session.usedVideo,
        isTrue,
        reason: 'a published camera track means the call rendered video',
      );
    });

    test('videoFeeds does not latch usedVideo for a track-less publication', () {
      // A publication that never produced a track rendered no video. Latching
      // on mere feed-presence would record a video call that never showed one;
      // the old `videoTracks()` only ever counted actual tracks.
      media.feeds = [
        CallVideoFeed.of(track: null, muted: false, isLocal: false),
      ];
      session.videoFeeds();
      expect(
        session.usedVideo,
        isFalse,
        reason: 'no track was ever rendered, so this is not a video call',
      );
    });
  });
}
