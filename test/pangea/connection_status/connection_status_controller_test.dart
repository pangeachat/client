import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/features/connection_status/connection_status_controller.dart';
import 'package:fluffychat/features/connection_status/filtered_network_controller.dart';
import 'package:fluffychat/features/connection_status/network_host_category.dart';
import 'package:fluffychat/features/connection_status/network_probe.dart';
import 'package:fluffychat/features/connection_status/network_type.dart';
import 'package:fluffychat/features/connection_status/network_verdict.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';

/// #9512 — when the connection to the chat server counts as lost, and why.
void main() {
  const unreachableKey = 'connection-status-chat-server-unreachable';
  final controller = ConnectionStatusController.instance;
  late NetworkProbeResult neutralAnswer;
  late int probes;
  late StreamController<List<ConnectivityResult>> networkChanges;
  late bool resumed;

  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // A report reads Environment.appConfigOverride from a GetStorage box that
    // needs path_provider; stub the channel to a temp dir so init is silent.
    final tempDir = await Directory.systemTemp.createTemp(
      'connection_status_controller_test',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
  });

  /// Fakes the network, leaving the foreground check as it is.
  void fakeNetwork() {
    controller.probe = (url) async {
      probes++;
      return neutralAnswer;
    };
    controller.onNetworkChanged = () => networkChanges.stream;
    controller.currentNetworkType = () async => NetworkType.wifi;
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    neutralAnswer = NetworkProbeResult.answered;
    probes = 0;
    networkChanges = StreamController.broadcast();
    resumed = true;
    fakeNetwork();
    controller.isAppInForeground = () => resumed;
  });

  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  tearDown(() async {
    // A report in flight must land before the keys are cleared, or it lands
    // in the next test.
    await settle();
    controller.resetForTest();
    ErrorHandler.resetReportedOnceKeysForTest();
    unawaited(networkChanges.close());
  });

  SyncStatusUpdate connectionFailure() => SyncStatusUpdate(
    SyncStatus.error,
    error: SdkError(
      exception: SyncConnectionException(http.ClientException('failed')),
    ),
  );

  Future<void> fail(int times) async {
    for (var i = 0; i < times; i++) {
      controller.onSyncStatus(
        const SyncStatusUpdate(SyncStatus.waitingForResponse),
      );
      controller.onSyncStatus(connectionFailure());
    }
    await settle();
  }

  test('one failed sync is not a lost connection', () async {
    await fail(1);

    expect(controller.status.value, ConnectionStatus.connected);
    expect(probes, 0);
  });

  test(
    'two failed syncs with no neutral answer is offline, and not reported',
    () async {
      neutralAnswer = NetworkProbeResult.slow;

      await fail(2);

      expect(controller.status.value, ConnectionStatus.offline);
      expect(
        ErrorHandler.reportedOnceKeysForTest,
        isNot(contains(unreachableKey)),
      );
    },
  );

  test(
    'two failed syncs while the device is online is unreachable, reported once',
    () async {
      await fail(2);
      expect(controller.status.value, ConnectionStatus.unreachable);
      expect(ErrorHandler.reportedOnceKeysForTest, contains(unreachableKey));

      // Further failures inside the reclassify window do not probe again.
      final probesAfterFirst = probes;
      await fail(3);
      expect(probes, probesAfterFirst);
    },
  );

  test(
    'a Matrix error is the server answering, not a lost connection',
    () async {
      for (var i = 0; i < 3; i++) {
        controller.onSyncStatus(
          SyncStatusUpdate(
            SyncStatus.error,
            error: SdkError(
              exception: MatrixException.fromJson({
                'errcode': 'M_UNKNOWN_TOKEN',
                'error': 'expired',
              }),
            ),
          ),
        );
      }
      await settle();

      expect(controller.status.value, ConnectionStatus.connected);
    },
  );

  test('failures while the app is in the background do not count', () async {
    resumed = false;
    await fail(3);

    expect(controller.status.value, ConnectionStatus.connected);
  });

  group('#9434 the real foreground check', () {
    setUp(() {
      // resetForTest puts the real check back; the network stays faked.
      controller.resetForTest();
      fakeNetwork();
    });
    tearDown(
      () => binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed),
    );

    test('counts failures in an unfocused window', () async {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await fail(2);

      expect(controller.status.value, ConnectionStatus.unreachable);
    });

    for (final state in [AppLifecycleState.hidden, AppLifecycleState.paused]) {
      test('ignores failures while ${state.name}', () async {
        binding.handleAppLifecycleStateChanged(state);
        await fail(3);

        expect(controller.status.value, ConnectionStatus.connected);
      });
    }
  });

  test('a successful sync between failures resets the count', () async {
    await fail(1);
    controller.onSyncStatus(const SyncStatusUpdate(SyncStatus.finished));
    await fail(1);

    expect(controller.status.value, ConnectionStatus.connected);
  });

  test('the device reporting no network is offline at once', () async {
    controller.onSyncStatus(const SyncStatusUpdate(SyncStatus.finished));
    networkChanges.add([ConnectivityResult.none]);
    await settle();

    expect(controller.status.value, ConnectionStatus.offline);
    expect(probes, 0);
  });

  // Before sign-in there is no sync loop, so the device's own report is the
  // only signal. See connection-status.instructions.md, "Before sign-in".
  group('before any account signs in', () {
    test('the device reporting no network is offline', () async {
      controller.watchDevice();
      networkChanges.add([ConnectivityResult.none]);
      await settle();

      expect(controller.status.value, ConnectionStatus.offline);
      expect(probes, 0);
    });

    test('the device reporting a network again says back online', () async {
      controller.watchDevice();
      networkChanges.add([ConnectivityResult.none]);
      await settle();
      networkChanges.add([ConnectivityResult.wifi]);
      await settle();

      expect(controller.status.value, ConnectionStatus.backOnline);
      expect(probes, 0);
    });

    test('signing out while the device is offline keeps it offline', () async {
      controller.onSyncStatus(const SyncStatusUpdate(SyncStatus.finished));
      networkChanges.add([ConnectivityResult.none]);
      await settle();
      expect(controller.status.value, ConnectionStatus.offline);

      controller.reset();
      expect(controller.status.value, ConnectionStatus.offline);

      // The device's report still reaches the banner on the sign-in page.
      networkChanges.add([ConnectivityResult.wifi]);
      await settle();
      expect(controller.status.value, ConnectionStatus.backOnline);
    });

    // A failed sign-in request starts the chat-server check; its first
    // result is the banner's signal, since no sync loop can be.
    test(
      'the chat-server check says can\'t reach at once, and reports',
      () async {
        controller.onChatServerChecked(NetworkVerdict.filtered);

        expect(controller.status.value, ConnectionStatus.unreachable);
        await settle();
        expect(ErrorHandler.reportedOnceKeysForTest, contains(unreachableKey));
      },
    );

    test('the chat-server check says offline when nothing answers', () {
      controller.onChatServerChecked(NetworkVerdict.offline);

      expect(controller.status.value, ConnectionStatus.offline);
    });

    test('a chat server that answers says back online', () {
      controller.onChatServerChecked(NetworkVerdict.filtered);
      controller.onChatServerAnswered();
      expect(controller.status.value, ConnectionStatus.backOnline);

      controller.onChatServerChecked(NetworkVerdict.filtered);
      controller.onChatServerChecked(NetworkVerdict.reachable);
      expect(controller.status.value, ConnectionStatus.backOnline);
    });
  });

  test('with an account signed in, the chat-server check says nothing', () {
    controller.onSyncStatus(const SyncStatusUpdate(SyncStatus.finished));
    controller.onChatServerChecked(NetworkVerdict.filtered);
    controller.onChatServerAnswered();

    expect(controller.status.value, ConnectionStatus.connected);
  });

  test(
    'with an account signed in, a network again waits for the sync to confirm',
    () async {
      controller.onSyncStatus(const SyncStatusUpdate(SyncStatus.finished));
      networkChanges.add([ConnectivityResult.none]);
      await settle();
      expect(controller.status.value, ConnectionStatus.offline);

      networkChanges.add([ConnectivityResult.wifi]);
      await settle();
      expect(controller.status.value, ConnectionStatus.offline);

      controller.onSyncStatus(const SyncStatusUpdate(SyncStatus.finished));
      expect(controller.status.value, ConnectionStatus.backOnline);
    },
  );

  test(
    'a new network while lost asks again whether the device is online',
    () async {
      neutralAnswer = NetworkProbeResult.slow;
      await fail(2);
      expect(controller.status.value, ConnectionStatus.offline);

      neutralAnswer = NetworkProbeResult.answered;
      networkChanges.add([ConnectivityResult.wifi]);
      await settle();

      expect(controller.status.value, ConnectionStatus.unreachable);
    },
  );

  testWidgets('a successful sync after a loss says back online, then clears', (
    tester,
  ) async {
    await tester.runAsync(() => fail(2));
    expect(controller.status.value, ConnectionStatus.unreachable);

    controller.onSyncStatus(const SyncStatusUpdate(SyncStatus.finished));
    expect(controller.status.value, ConnectionStatus.backOnline);

    await tester.pump(ConnectionStatusController.backOnlineFor);
    expect(controller.status.value, ConnectionStatus.connected);
  });

  test('a successful sync while connected changes nothing', () async {
    controller.onSyncStatus(const SyncStatusUpdate(SyncStatus.finished));

    expect(controller.status.value, ConnectionStatus.connected);
  });

  test('reset forgets a lost connection', () async {
    await fail(2);
    controller.reset();

    expect(controller.status.value, ConnectionStatus.connected);
  });

  // #9513 — when practice started now runs offline.
  test('Pangea is out of reach while either banner is up', () {
    final blocked = FilteredNetworkController.instance.blocked;
    addTearDown(FilteredNetworkController.instance.resetForTest);
    expect(controller.cannotReachPangea, isFalse);

    for (final status in [
      ConnectionStatus.offline,
      ConnectionStatus.unreachable,
    ]) {
      controller.status.value = status;
      expect(controller.cannotReachPangea, isTrue, reason: status.name);
    }
    controller.status.value = ConnectionStatus.backOnline;
    expect(controller.cannotReachPangea, isFalse);

    blocked.value = {NetworkHostCategory.video, NetworkHostCategory.map};
    expect(controller.cannotReachPangea, isFalse);
    blocked.value = {NetworkHostCategory.pangeaApi};
    expect(controller.cannotReachPangea, isTrue);
  });
}
