import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/instructions/instruction_settings.dart';
import 'package:fluffychat/features/user/user_controller.dart';
import 'package:fluffychat/features/user/user_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/pangea/morphs/morph_features_and_tags.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/analytics_details_popup.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/morph_analytics_list_view.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// #9124 — the grammar list's instruction tooltip must leave no gap once
/// dismissed.
///
/// Dismissing it records the dismissal on the learner's profile, but nothing
/// rebuilds the list until that write comes back through sync, so spacing the
/// list added beside the tooltip outlived it.
void main() {
  setUp(() {
    MatrixState.pangeaController = _FakePangeaController();
  });

  Future<void> pumpList(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: MorphAnalyticsListView(controller: _FakeAnalyticsView()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  double contentExtent(WidgetTester tester) => tester.allRenderObjects
      .whereType<RenderSliver>()
      .where((sliver) => sliver.parent is RenderViewport)
      .fold(0.0, (sum, sliver) => sum + sliver.geometry!.scrollExtent);

  testWidgets('dismissing the tooltip takes its spacing with it', (
    tester,
  ) async {
    await pumpList(tester);
    expect(contentExtent(tester), greaterThan(0));

    await tester.tap(find.byIcon(Icons.close_outlined));
    await tester.pumpAndSettle();

    expect(contentExtent(tester), 0);
  });
}

class _FakePangeaController implements PangeaController {
  @override
  final UserController userController = _FakeUserController();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Applies profile writes in memory but never echoes them on
/// [settingsUpdateStream] — the state between a write and its sync.
class _FakeUserController implements UserController {
  @override
  final Completer<void> initCompleter = Completer<void>()..complete();

  @override
  Profile profile = Profile(
    userSettings: UserSettings(),
    instructionSettings: InstructionSettings(instructions: {}),
  );

  @override
  Future<void> updateProfile(
    Profile Function(Profile) update, {
    waitForDataInSync = false,
  }) async => profile = update(profile);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// No target language and no grammar features, so the tooltip is the list's
/// only content.
class _FakeAnalyticsView
    with Diagnosticable
    implements ConstructAnalyticsViewState {
  @override
  MorphFeaturesAndTags morphs = MorphFeaturesAndTags(
    targetLanguage: 'de',
    userL1: 'en',
    features: [],
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
