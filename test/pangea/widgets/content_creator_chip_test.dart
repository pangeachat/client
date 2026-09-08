import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/content_creator_chip.dart';
import 'package:fluffychat/pangea/common/widgets/user_profile_builder.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../../utils/test_client.dart';

/// Content is credited to whoever made it. The failure these lock down is
/// misattribution: PangeaChat's name and logo may appear ONLY over content the
/// system user genuinely owns, never over a teacher's — not when their profile
/// carries no name, and not when no owner was recorded at all.
class _FakeMatrixState extends MatrixState {
  _FakeMatrixState(this._client);

  final Client _client;

  @override
  Client get client => _client;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const namedOwner = '@profeceniza02:pangea.chat';
  const namelessOwner = '@quietteacher:pangea.chat';

  late Client client;

  setUpAll(() async {
    client = await prepareTestClient();
    // Seeding the SDK's profile cache resolves the lookup from the database,
    // the same path a warm client takes, and never reaches the network.
    await client.database.storeUserProfile(
      namedOwner,
      CachedProfileInformation.fromProfile(
        ProfileInformation(displayname: 'Señora Díaz'),
        outdated: false,
        updated: DateTime.now(),
      ),
    );
    // A real account with nothing filled in: the profile resolves, and carries
    // neither a display name nor an avatar.
    await client.database.storeUserProfile(
      namelessOwner,
      CachedProfileInformation.fromProfile(
        ProfileInformation(),
        outdated: false,
        updated: DateTime.now(),
      ),
    );
  });

  tearDownAll(() => client.dispose());

  setUp(() async {
    UserProfileBuilder.clearLastResolvedForTest();
    // Avatar asks BotName.byEnvironment whether it is drawing the bot's face,
    // which reads Environment.appConfigOverride (GetStorage) then dotenv.
    // Unstubbed, the build throws and GetStorage's lazy init leaks a pending
    // timer into the test zone. Stubbed per test: flutter_test clears mock
    // method-call handlers between tests.
    final tempDir = await Directory.systemTemp.createTemp('creator_credit');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    dotenv.testLoad(mergeWith: {'BOT_NAME': 'pangeabot'});
  });

  Future<void> pumpChip(
    WidgetTester tester, {
    required String? ownerId,
    VoidCallback? onTap,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        // The test host can't load Material 3's ink-sparkle shader.
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: Provider<MatrixState>.value(
          value: _FakeMatrixState(client),
          child: Scaffold(
            body: ContentCreatorChip(ownerId: ownerId, onTap: onTap),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('ContentCreatorChip.creatorName', () {
    test('uses the profile display name when there is one', () {
      expect(
        ContentCreatorChip.creatorName(
          ownerId: namedOwner,
          displayName: 'Señora Díaz',
        ),
        'Señora Díaz',
      );
    });

    test('falls back to the whole MXID, never the localpart', () {
      for (final displayName in [null, '', '   ']) {
        expect(
          ContentCreatorChip.creatorName(
            ownerId: namedOwner,
            displayName: displayName,
          ),
          namedOwner,
        );
      }
    });
  });

  group('ContentCreatorChip.isSystemOwned', () {
    test('only the system MXID is Pangea-owned', () {
      expect(
        ContentCreatorChip.isSystemOwned(ContentCreatorChip.systemOwnerId),
        isTrue,
      );
      expect(ContentCreatorChip.isSystemOwned(namedOwner), isFalse);
    });

    test('an absent or blank owner is unknown, NOT system-owned', () {
      expect(ContentCreatorChip.isSystemOwned(null), isFalse);
      expect(ContentCreatorChip.isSystemOwned(''), isFalse);
      expect(ContentCreatorChip.isSystemOwned('  '), isFalse);
      expect(ContentCreatorChip.hasCredit(null), isFalse);
      expect(ContentCreatorChip.hasCredit('  '), isFalse);
      expect(ContentCreatorChip.hasCredit(namedOwner), isTrue);
    });
  });

  testWidgets('the system owner is credited with the Pangea name and logo', (
    tester,
  ) async {
    await pumpChip(tester, ownerId: ContentCreatorChip.systemOwnerId);

    expect(find.text('PangeaChat'), findsOneWidget);
    expect(find.byType(SvgPicture), findsOneWidget);
  });

  testWidgets("a teacher is credited with their own profile name", (
    tester,
  ) async {
    await pumpChip(tester, ownerId: namedOwner);

    expect(find.text('Señora Díaz'), findsOneWidget);
    expect(find.byType(Avatar), findsOneWidget);
    expect(
      find.text('PangeaChat'),
      findsNothing,
      reason: "a person's activity must never be credited to Pangea",
    );
    expect(find.byType(SvgPicture), findsNothing);
  });

  testWidgets('an owner with no display name shows the stored MXID whole', (
    tester,
  ) async {
    await pumpChip(tester, ownerId: namelessOwner);

    expect(find.text(namelessOwner), findsOneWidget);
    expect(
      find.text('quietteacher'),
      findsNothing,
      reason: 'the localpart would read as a name they chose',
    );
    expect(
      find.byIcon(Icons.person_outline),
      findsOneWidget,
      reason: 'a nameless owner gets a neutral contact icon',
    );
    expect(find.byType(Avatar), findsNothing);
    expect(find.text('PangeaChat'), findsNothing);
  });

  testWidgets('no owner recorded credits nobody — not Pangea', (tester) async {
    for (final ownerId in [null, '', '   ']) {
      await pumpChip(tester, ownerId: ownerId);

      expect(find.text('PangeaChat'), findsNothing);
      expect(find.byType(SvgPicture), findsNothing);
      expect(find.byType(Text), findsNothing);
      expect(tester.getSize(find.byType(ContentCreatorChip)), Size.zero);
    }
  });

  testWidgets('the credit is inert until it has a destination', (tester) async {
    // The layout is stable either way — the InkWell is always in the tree, so
    // client#8825 is a destination change rather than a re-layout. What must
    // NOT ship early is the affordance: a live tap target that does nothing
    // announces itself to a screen reader as actionable and takes keyboard
    // focus, then no-ops on Enter (accessibility.instructions.md: every
    // interactive element announces what it is and does).
    await pumpChip(tester, ownerId: namedOwner);
    expect(tester.widget<InkWell>(find.byType(InkWell)).onTap, isNull);
  });

  testWidgets('the credit is tappable once given a destination', (
    tester,
  ) async {
    var taps = 0;
    await pumpChip(tester, ownerId: namedOwner, onTap: () => taps++);
    expect(tester.widget<InkWell>(find.byType(InkWell)).onTap, isNotNull);
    await tester.tap(find.text('Señora Díaz'));
    expect(taps, 1);
  });

  Future<void> pumpCredit(
    WidgetTester tester, {
    required String? ownerId,
    double avatarSize = ContentCreatorCredit.detailAvatarSize,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Provider<MatrixState>.value(
          value: _FakeMatrixState(client),
          child: Scaffold(
            body: ContentCreatorCredit(
              ownerId: ownerId,
              avatarSize: avatarSize,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('ContentCreatorCredit', () {
    testWidgets('labels the credit so it cannot read as a control', (
      tester,
    ) async {
      await pumpCredit(tester, ownerId: namedOwner);

      expect(find.text('Created by'), findsOneWidget);
      expect(find.text('Señora Díaz'), findsOneWidget);
    });

    testWidgets('an unknown owner collapses the label with the credit', (
      tester,
    ) async {
      // The label must not survive on its own: "Created by" over nothing
      // states an attribution the row cannot make.
      for (final ownerId in [null, '', '   ']) {
        await pumpCredit(tester, ownerId: ownerId);

        expect(find.text('Created by'), findsNothing);
        expect(find.byType(Text), findsNothing);
        expect(tester.getSize(find.byType(ContentCreatorCredit)), Size.zero);
      }
    });

    testWidgets('the same widget serves both placements, at two sizes', (
      tester,
    ) async {
      // One widget, so the create-course credit and the course page's More
      // section can never drift into two different-looking credits for the
      // same person — only the avatar scale differs.
      expect(
        ContentCreatorCredit.prominentAvatarSize,
        greaterThan(ContentCreatorCredit.detailAvatarSize),
      );
      for (final size in [
        ContentCreatorCredit.detailAvatarSize,
        ContentCreatorCredit.prominentAvatarSize,
      ]) {
        await pumpCredit(tester, ownerId: namedOwner, avatarSize: size);
        expect(find.text('Created by'), findsOneWidget);
        expect(
          tester.getSize(find.byType(Avatar)).width,
          size,
          reason: 'the avatar carries the placement\'s scale',
        );
      }
    });

    testWidgets('Pangea is credited only for its own content', (tester) async {
      await pumpCredit(tester, ownerId: ContentCreatorChip.systemOwnerId);
      expect(find.text('PangeaChat'), findsOneWidget);

      await pumpCredit(tester, ownerId: namelessOwner);
      expect(find.text('PangeaChat'), findsNothing);
      expect(find.text(namelessOwner), findsOneWidget);
    });
  });
}
