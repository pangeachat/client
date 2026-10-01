import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/features/join_codes/join_code_constants.dart';
import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/panel_types_enum.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/routes/chat/chat_details/space_details.dart';
import 'package:fluffychat/routes/world/course_context_bar.dart';
import 'package:fluffychat/routes/world/left_panel/course_card_reveal.dart';
import 'package:fluffychat/routes/world/left_panel/floor_chevron.dart';
import 'package:fluffychat/routes/world/left_panel/left_panel_close_button.dart';
import 'package:fluffychat/routes/world/panel_card.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../fake_pangea_controller.dart';
import '../get_test_client.dart';

/// #8909 — on wide, the open course card's header is a tap target for the
/// collapse, the mirror of the context bar's whole-surface tap that reopens
/// it: one surface toggling, not a whole-surface tap one way and a single
/// glyph the other. The tap runs the chevron's own collapse — the card
/// shrinks to the bar's height first, then its token drops — it is
/// pointer-only, so the chevron stays the card's one announced, focusable
/// control, and the header's actions keep winning their own taps.

/// Skips `initMatrix()` — the card only wants a routed, localized subtree
/// with a client on it.
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
    super.key,
  });

  @override
  MatrixState createState() => _TestMatrixState();
}

/// The card's course-plan section asks the controller for the live
/// [MatrixState] (the tutorial backfill reads the signed-in user off it),
/// where the base fake's `noSuchMethod` null would throw.
class _CardTestPangeaController extends FakePangeaController {
  final GlobalKey<MatrixState> matrixKey;

  _CardTestPangeaController(this.matrixKey);

  @override
  MatrixState get matrixState => matrixKey.currentState!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const userId = '@test:fakeServer.notExisting';
  const spaceId = '!course:fakeServer.notExisting';
  const courseName = 'Español 101';
  const slotHeight = 600.0;
  final fullCard = slotHeight - PanelCard.margin.vertical;
  final matrixKey = GlobalKey<MatrixState>();

  late Client client;
  late Room room;
  late SharedPreferences store;
  late GoRouter router;

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('course_card_header');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (methodCall) async => tempDir.path,
    );
    // The card's post-frame notification nudge asks permission_handler; a
    // granted answer (1) makes it return before any dialog.
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/permissions/methods'),
      (methodCall) async => 1,
    );
    await GetStorage.init('env_override');
    dotenv.testLoad(
      mergeWith: {'SYNAPSE_URL': 'https://fakeServer.notExisting'},
    );
    SharedPreferences.setMockInitialValues({});
    store = await SharedPreferences.getInstance();
    MatrixState.pangeaController = _CardTestPangeaController(matrixKey);
  });

  Event stateEvent(String type, Map<String, dynamic> content) => Event(
    type: type,
    content: content,
    stateKey: '',
    senderId: userId,
    eventId: '\$$type',
    originServerTs: DateTime.now(),
    room: room,
  );

  setUp(() async {
    client = await getTestClient();
    room = Room(id: spaceId, client: client, membership: Membership.join);
    // A course is a space (the card's catch-up row reads its children), with
    // a join code so the header carries its share action.
    room.setState(
      stateEvent(EventTypes.RoomCreate, {'type': RoomCreationTypes.mSpace}),
    );
    room.setState(stateEvent(EventTypes.RoomName, {'name': courseName}));
    room.setState(
      stateEvent(EventTypes.RoomJoinRules, {
        ModelKey.joinRule: JoinRules.public.text,
        JoinCodeConstants.accessCode: 'ABC123',
      }),
    );
    client.rooms.add(room);
  });

  tearDown(() async {
    await client.dispose();
  });

  /// The wide course card as the left panel mounts it: inside its reveal,
  /// with the panel's own close control, over a course-scoped workspace
  /// whose `?left=` holds the course token.
  Future<void> pumpCard(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    router = GoRouter(
      initialLocation: '/?c=${Uri.encodeComponent(spaceId)}&left=course',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 600,
                height: slotHeight,
                child: CourseCardReveal(
                  animateIn: false,
                  child: SpaceDetails(
                    room: room,
                    embeddedCloseButton: LeftPanelCloseButton(
                      token: const CoursePanelToken(),
                      currentUri: state.uri,
                      foldedOver: false,
                      isColumnMode: true,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      _TestMatrix(
        key: matrixKey,
        clients: [client],
        store: store,
        child: MaterialApp.router(
          routerConfig: router,
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Uri uri() => router.routerDelegate.currentConfiguration.uri;
  bool courseOpen() =>
      parseOpenPanels(uri()).left.any((t) => t.type == PanelTypesEnum.course);

  /// The card's own surface — what the learner sees change height.
  double cardHeight(WidgetTester tester) => tester
      .getSize(
        find
            .descendant(
              of: find.byType(PanelCard),
              matching: find.byType(Material),
            )
            .first,
      )
      .height;

  testWidgets(
    'tapping the header title collapses the card the way the chevron does: '
    'shrink to the bar, then drop the token',
    (tester) async {
      await pumpCard(tester);
      expect(courseOpen(), isTrue);
      expect(cardHeight(tester), fullCard);

      await tester.tap(find.text(courseName));
      // The first frame seats the ticker; the next is 100ms into the shrink.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(courseOpen(), isTrue, reason: 'still shrinking: token kept');
      expect(cardHeight(tester), lessThan(fullCard));
      expect(cardHeight(tester), greaterThan(CourseContextBar.height));

      await tester.pumpAndSettle();
      expect(courseOpen(), isFalse, reason: 'at the bar\'s height: dropped');
      // The context is a scope, not a panel — collapsing never clears it.
      expect(activeSpaceIdFor(uri()), spaceId);
    },
  );

  testWidgets('the header\'s actions keep their own taps', (tester) async {
    await pumpCard(tester);

    await tester.tap(find.byIcon(Icons.share_outlined));
    await tester.pumpAndSettle();

    // The share menu opened, and the card is exactly where it was.
    expect(find.byWidgetPredicate((w) => w is PopupMenuItem), findsWidgets);
    expect(courseOpen(), isTrue);
    expect(cardHeight(tester), fullCard);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  });

  testWidgets(
    'the header tap is pointer-only: the chevron stays the one announced, '
    'focusable control',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpCard(tester);

      // The chevron is the button a keyboard or screen-reader user reaches.
      final chevron = tester.getSemantics(
        find.descendant(
          of: find.byType(ChevronToggle),
          matching: find.byType(IconButton),
        ),
      );
      expect(chevron.flagsCollection.isButton, isTrue);
      // Focusable is "focus state applies", whichever way it currently is.
      expect(chevron.flagsCollection.isFocused, isNot(Tristate.none));
      expect(chevron.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);

      final headerTap = tester.widget<InkWell>(
        find
            .ancestor(of: find.text(courseName), matching: find.byType(InkWell))
            .first,
      );
      expect(headerTap.excludeFromSemantics, isTrue);
      expect(headerTap.canRequestFocus, isFalse);
      semantics.dispose();
    },
  );
}
