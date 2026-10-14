import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/features/connection_status/connection_status_controller.dart';
import 'package:fluffychat/features/connection_status/network_probe.dart';
import 'package:fluffychat/features/connection_status/network_type.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';

/// #9512 — when the connection to the chat server counts as lost, and why.
void main() {
  const unreachableKey = 'connection-status-chat-server-unreachable';
  final controller = ConnectionStatusController.instance;
  late NetworkProbeResult neutralAnswer;
  late int probes;
  late StreamController<List<ConnectivityResult>> networkChanges;
  late bool resumed;

  TestWidgetsFlutterBinding.ensureInitialized();

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

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    neutralAnswer = NetworkProbeResult.answered;
    probes = 0;
    networkChanges = StreamController.broadcast();
    resumed = true;
    controller.probe = (url) async {
      probes++;
      return neutralAnswer;
    };
    controller.onNetworkChanged = () => networkChanges.stream;
    controller.currentNetworkType = () async => NetworkType.wifi;
    controller.isAppResumed = () => resumed;
  });

  tearDown(() async {
    controller.resetForTest();
    ErrorHandler.resetReportedOnceKeysForTest();
    unawaited(networkChanges.close());
  });

  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

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
}
