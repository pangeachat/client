import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import 'package:fluffychat/pangea/common/widgets/user_profile_builder.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../../utils/test_client.dart';

/// #8233: the avatar on an activity role card flickered back to the letter
/// placeholder whenever a chat event rebuilt the timeline around it. The
/// profile lookup is always a future, so both a remount and a plain dependency
/// change used to hand the builder a null profile again for a frame or more.
class _FakeMatrixState extends MatrixState {
  _FakeMatrixState(this._client);

  final Client _client;

  @override
  Client get client => _client;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const userId = '@avarose20:example.invalid';

  late Client client;

  setUpAll(() async {
    client = await prepareTestClient();
    // Seed the SDK's profile cache so the lookup resolves from the database
    // and never reaches the network — the same path a warm client takes.
    await client.database.storeUserProfile(
      userId,
      CachedProfileInformation.fromProfile(
        ProfileInformation(
          displayname: 'Ava Rose',
          avatarUrl: Uri.parse('mxc://example.invalid/ava'),
        ),
        outdated: false,
        updated: DateTime.now(),
      ),
    );
  });

  tearDownAll(() => client.dispose());

  late List<Profile?> built;

  setUp(() {
    UserProfileBuilder.clearLastResolvedForTest();
    built = [];
  });

  Widget host({Key? key, Brightness brightness = Brightness.light}) =>
      MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: Provider<MatrixState>.value(
          value: _FakeMatrixState(client),
          child: UserProfileBuilder(
            key: key,
            userId: userId,
            builder: (context, profile) {
              // The real callers (UserProfileAvatar, UserProfileName) read
              // L10n/Theme off this context, so the element carries inherited
              // dependencies. Without one, didChangeDependencies never fires a
              // second time and the regression is invisible.
              Theme.of(context);
              built.add(profile);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

  testWidgets('a remount draws the resolved profile on its first frame', (
    tester,
  ) async {
    await tester.pumpWidget(host(key: const ValueKey('first')));
    await tester.pumpAndSettle();
    expect(built.last?.displayName, 'Ava Rose');

    // A new key forces the State to be recreated, which is what an ancestor
    // rebuilding its child list into a different shape does to these cards.
    built = [];
    await tester.pumpWidget(host(key: const ValueKey('second')));
    await tester.pump();

    expect(
      built,
      isNotEmpty,
      reason: 'the remounted builder should have been built',
    );
    expect(
      built.map((p) => p?.displayName),
      everyElement('Ava Rose'),
      reason: 'a remount must not flash the fallback before re-resolving',
    );
  });

  testWidgets('a dependency change does not blank a resolved profile', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(built.last?.displayName, 'Ava Rose');

    // Same State, new inherited theme: this drives didChangeDependencies.
    built = [];
    await tester.pumpWidget(host(brightness: Brightness.dark));
    await tester.pumpAndSettle();

    expect(built, isNotEmpty);
    expect(
      built.map((p) => p?.displayName),
      everyElement('Ava Rose'),
      reason: 'a dependency change must not reset the resolved profile',
    );
  });
}
