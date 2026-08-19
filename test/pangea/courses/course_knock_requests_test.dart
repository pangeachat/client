import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/constants/default_power_level.dart';
import 'package:fluffychat/pangea/spaces/knocking_users_badge.dart';
import 'package:fluffychat/pangea/spaces/space_constants.dart';
import 'package:fluffychat/routes/chat/chat_details/course_overview/course_knock_requests.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../fake_pangea_controller.dart';
import '../get_test_client.dart';

/// Skips `initMatrix()` — background push, notification listeners and the
/// Pangea controller are all irrelevant here and none of them stand up under
/// `flutter test`. The member-actions menu only wants `Matrix.of(context)`.
class _TestMatrixState extends MatrixState {
  @override
  // ignore: must_call_super
  void initState() {}
}

class _TestMatrix extends Matrix {
  const _TestMatrix({
    required super.clients,
    required super.store,
    required super.child,
  });

  @override
  MatrixState createState() => _TestMatrixState();
}

/// Coverage for the course page's join-request card (#8462, split out of the
/// Catch up card of #8357): the in-course knock review surface the avatar
/// badges elsewhere point the admin at. It must name each knocker with an
/// Approve action for admins — live via KnockingUsersBuilder — carry the
/// knock glyph and a Deny-all action rather than the bell and Mark all read,
/// and stay hidden entirely for non-admins (knock review is admin-only by
/// design).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;
  late SharedPreferences store;

  const userId = '@test:fakeServer.notExisting';
  const knockerId = '@knocker:fakeServer.notExisting';
  const knockerName = 'Kai Knocker';

  setUpAll(() async {
    // `Avatar` resolves the bot name from the environment at build time, which
    // reads GetStorage (path_provider-backed) and dotenv.
    final tempDir = await Directory.systemTemp.createTemp('course_knock');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    dotenv.testLoad(
      mergeWith: {
        'BOT_NAME': '@bot:example.org',
        'SYNAPSE_URL': 'https://fakeServer.notExisting',
      },
    );
    SharedPreferences.setMockInitialValues({});
    store = await SharedPreferences.getInstance();
    // The member-actions menu reads the static controller while building its
    // profile card (level and about-me).
    MatrixState.pangeaController = FakePangeaController();
  });

  setUp(() async {
    client = await getTestClient();
  });

  tearDown(() async {
    await client.dispose();
  });

  /// A course space with [knockers] users knocking on it. [ownPowerLevel]
  /// decides whether the viewer is the admin who can act on those knocks.
  Room courseRoom({required int ownPowerLevel, int knockers = 1}) {
    final room = Room(
      id: '!course:fakeServer.notExisting',
      client: client,
      membership: Membership.join,
    );
    // A real course room IS a space, and the SDK gates space reads on the
    // create event's type.
    room.setState(
      Event(
        type: EventTypes.RoomCreate,
        content: {'type': 'm.space'},
        stateKey: '',
        senderId: userId,
        eventId: '\$create',
        originServerTs: DateTime.now(),
        room: room,
      ),
    );
    room.setState(
      Event(
        type: EventTypes.RoomPowerLevels,
        content: {
          ...RoomDefaults.defaultPowerLevelsContent(),
          'users': {userId: ownPowerLevel},
        },
        stateKey: '',
        senderId: userId,
        eventId: '\$powerLevels',
        originServerTs: DateTime.now(),
        room: room,
      ),
    );
    for (var i = 0; i < knockers; i++) {
      room.setState(
        Event(
          type: EventTypes.RoomMember,
          content: {
            'membership': 'knock',
            'displayname': i == 0 ? knockerName : 'Knocker $i',
          },
          stateKey: i == 0 ? knockerId : '@knocker$i:fakeServer.notExisting',
          senderId: i == 0 ? knockerId : '@knocker$i:fakeServer.notExisting',
          eventId: '\$knock$i',
          originServerTs: DateTime.now(),
          room: room,
        ),
      );
    }
    return room;
  }

  Future<void> pumpKnockRequests(
    WidgetTester tester,
    Room room, {
    double width = 360,
    double textScale = 1.0,
  }) async {
    await tester.pumpWidget(
      _TestMatrix(
        clients: [client],
        store: store,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: Scaffold(
              // The real page scrolls vertically (CourseOverview), so only
              // horizontal overflow is the card's problem to solve.
              body: SingleChildScrollView(
                child: SizedBox(
                  width: width,
                  child: CourseKnockRequests(room: room),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // L10n's delegate resolves from a deferred library, so the card isn't in
    // the tree until localizations finish loading.
    await tester.pumpAndSettle();
  }

  testWidgets('an admin sees the knocking user with an Approve action', (
    tester,
  ) async {
    await pumpKnockRequests(
      tester,
      courseRoom(ownPowerLevel: SpaceConstants.powerLevelOfAdmin),
    );

    final context = tester.element(find.byType(CourseKnockRequests));
    final l10n = L10n.of(context);
    // The descriptive header, not "Catch up" — it must say what the card is.
    expect(find.text(l10n.usersAreTryingToJoinCourse), findsOneWidget);
    // The row names the pending knocker, not just a generic label.
    expect(find.text(knockerName), findsOneWidget);
    expect(find.text(l10n.knocking), findsOneWidget);
    expect(find.text(l10n.approve), findsOneWidget);
  });

  testWidgets('the card is marked with the knock glyph, never the bell', (
    tester,
  ) async {
    await pumpKnockRequests(
      tester,
      courseRoom(ownPowerLevel: SpaceConstants.powerLevelOfAdmin),
    );

    // The bell belongs to course pings; a pending knock wears the same "!"
    // the course avatar's badge does.
    expect(find.byIcon(KnockingUsersBadge.icon), findsOneWidget);
    expect(find.byIcon(Icons.notifications_outlined), findsNothing);
  });

  testWidgets('the bulk action denies rather than marks read', (tester) async {
    await pumpKnockRequests(
      tester,
      courseRoom(ownPowerLevel: SpaceConstants.powerLevelOfAdmin),
    );

    final context = tester.element(find.byType(CourseKnockRequests));
    final l10n = L10n.of(context);
    expect(find.text(l10n.denyAllUsers), findsOneWidget);
    expect(find.text(l10n.markAllRead), findsNothing);
  });

  testWidgets('the knocker avatar is a tap target', (tester) async {
    // Restored in #8462: the avatar opens the shared member-actions menu —
    // profile, about-me, and a DM — so an admin can vet a stranger before
    // letting them into the course. The menu's own contents belong to
    // `showMemberActionsPopupMenu`, which the participant list already drives;
    // what this card owns is that the avatar is wired to it at all.
    await pumpKnockRequests(
      tester,
      courseRoom(ownPowerLevel: SpaceConstants.powerLevelOfAdmin),
    );

    final avatarTap = tester.widget<InkWell>(
      find.ancestor(of: find.byType(Avatar), matching: find.byType(InkWell)),
    );
    expect(avatarTap.onTap, isNotNull);
  });

  testWidgets('a non-admin sees no join-request card at all', (tester) async {
    await pumpKnockRequests(tester, courseRoom(ownPowerLevel: 0));

    final context = tester.element(find.byType(CourseKnockRequests));
    final l10n = L10n.of(context);
    expect(find.text(l10n.usersAreTryingToJoinCourse), findsNothing);
    expect(find.text(l10n.approve), findsNothing);
  });

  testWidgets('the long header fits a narrow screen at large text sizes', (
    tester,
  ) async {
    // The header is a full sentence, and gets longer in most other languages.
    // A RenderFlex overflow throws in tests, so this fails loudly if the row
    // ever stops wrapping.
    await pumpKnockRequests(
      tester,
      courseRoom(ownPowerLevel: SpaceConstants.powerLevelOfAdmin, knockers: 3),
      width: 320,
      textScale: 2.0,
    );

    expect(tester.takeException(), isNull);
    final context = tester.element(find.byType(CourseKnockRequests));
    expect(
      find.text(L10n.of(context).usersAreTryingToJoinCourse),
      findsOneWidget,
    );
  });
}
