import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/features/join_codes/space_code_repo.dart';
import 'package:fluffychat/features/navigation/legacy_redirects.dart';
import 'package:fluffychat/features/user/user_controller.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/pangea/common/utils/p_vguard.dart';
import 'package:fluffychat/widgets/matrix.dart';

class FakeClient implements Client {
  @override
  bool isLogged() => true;
  @override
  String get clientName => 'qa';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeUser implements UserController {
  bool finished = false;
  @override
  Future<bool> get finishedOnboarding async => finished;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeController implements PangeaController {
  final user = FakeUser();
  @override
  UserController get userController => user;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeMatrix implements MatrixState {
  final Matrix matrixWidget;
  FakeMatrix(this.matrixWidget);
  @override
  Matrix get widget => matrixWidget;
  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) =>
      'FakeMatrix';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late Directory temp;
  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('onboarding_destination_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => temp.path,
        );
    await GetStorage.init('class_storage');
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });
  tearDownAll(() => temp.delete(recursive: true));
  tearDown(() {
    PAuthGaurd.pController = null;
  });

  for (final initial in ['/vj3pc8b', '/']) {
    testWidgets('unfinished onboarding retains the class on $initial', (
      tester,
    ) async {
      await tester.runAsync(() => SpaceCodeRepo.clearDestination());
      if (initial == '/') {
        await tester.runAsync(
          () => SpaceCodeRepo.setDestination(
            '/?left=addcoursepage:private.jvj3pc8b',
          ),
        );
      }
      final controller = FakeController();
      PAuthGaurd.pController = controller;
      final matrix = FakeMatrix(Matrix(clients: [FakeClient()], store: prefs));
      final router = GoRouter(
        initialLocation: initial,
        redirect: (_, state) => LegacyRedirects.handle(state.uri),
        routes: [
          GoRoute(
            path: '/',
            redirect: PAuthGaurd.roomsRedirect,
            builder: (_, _) => const Text('World'),
          ),
          GoRoute(
            path: '/registration',
            builder: (_, _) => const Text('Registration'),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        Provider<MatrixState>.value(
          value: matrix,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/registration');
      expect(find.text('Registration'), findsOneWidget);
      expect(
        SpaceCodeRepo.destination,
        '/?left=addcoursepage:private.jvj3pc8b',
      );
      expect(SpaceCodeRepo.pendingJoinCode, 'vj3pc8b');
      // The saved destination is consumed once after setup finishes.
      controller.user.finished = true;
      router.go('/');
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.toString(),
        '/?left=addcoursepage:private.jvj3pc8b',
      );
      expect(SpaceCodeRepo.destination, isNull);
    });
  }
}
