import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/igc_controller.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/igc_response_model.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/pangea_match_status_enum.dart';

/// Covers the signal the manual re-check branches on (#8193).
///
/// When the user taps the assistance ring on a message assistance has already
/// finished with, [IgcController.hasAppliedMatches] decides what happens next:
///
/// - `true`  — corrections are baked into the text, so re-check the text as it
///   stands now. Reusing the previous request would rewind the input to its
///   pre-correction state and make the user click through every match again.
/// - `false` — assistance found nothing to fix and the user disagrees, so the
///   click is feedback and the server escalates to a stronger model.
void main() {
  IGCResponseModel responseFor(
    String input, {
    List<Map<String, dynamic>> matches = const [],
  }) => IGCResponseModel.fromJson({
    'original_input': input,
    'full_text_correction': null,
    'matches': matches,
    ModelKey.userL1: 'en',
    ModelKey.userL2: 'es',
  });

  Map<String, dynamic> spanJson({
    required int offset,
    required int length,
    required String replacement,
  }) => {
    'message': 'Check the verb ending',
    'short_message': 'verb',
    'choices': [
      {'value': replacement, 'type': 'suggestion'},
    ],
    ModelKey.offset: offset,
    ModelKey.length: length,
    'type': 'verbConjugation',
  };

  late IgcController igc;

  setUp(() => igc = IgcController((_) {}, () {}));
  tearDown(() => igc.dispose());

  test('no applied matches when assistance returned nothing to fix', () {
    igc.adoptResponse(responseFor('Yo quiero hablar español.'));

    expect(igc.currentText, 'Yo quiero hablar español.');
    expect(igc.hasAppliedMatches, isFalse);
  });

  test('no applied matches while a returned match is still open', () {
    igc.adoptResponse(
      responseFor(
        'Yo querer hablar español.',
        matches: [spanJson(offset: 3, length: 6, replacement: 'quiero')],
      ),
    );

    expect(igc.hasAppliedMatches, isFalse);
  });

  test('accepting a match marks the text as changed since the check', () {
    igc.adoptResponse(
      responseFor(
        'Yo querer hablar español.',
        matches: [spanJson(offset: 3, length: 6, replacement: 'quiero')],
      ),
    );

    final match = igc.matches.single;
    match.selectBestChoice();
    igc.updateMatchStatus(match, PangeaMatchStatusEnum.accepted);

    expect(igc.currentText, 'Yo quiero hablar español.');
    expect(igc.hasAppliedMatches, isTrue);
  });

  test('undoing every accepted match restores the checked text', () {
    igc.adoptResponse(
      responseFor(
        'Yo querer hablar español.',
        matches: [spanJson(offset: 3, length: 6, replacement: 'quiero')],
      ),
    );

    final match = igc.matches.single;
    match.selectBestChoice();
    igc.updateMatchStatus(match, PangeaMatchStatusEnum.accepted);
    igc.updateMatchStatus(match, PangeaMatchStatusEnum.undo);

    expect(igc.currentText, 'Yo querer hablar español.');
    expect(igc.hasAppliedMatches, isFalse);
  });

  test('the next check starts from the text the previous run produced', () {
    igc.adoptResponse(
      responseFor(
        'Yo querer hablar español.',
        matches: [spanJson(offset: 3, length: 6, replacement: 'quiero')],
      ),
    );

    final match = igc.matches.single;
    match.selectBestChoice();
    igc.updateMatchStatus(match, PangeaMatchStatusEnum.accepted);

    // What Choreographer.requestWritingAssistance(recheck: true) does before
    // sending the new request: drop the finished run, then check the corrected
    // text rather than the text the previous request was about.
    final corrected = igc.currentText!;
    igc.clear();

    expect(igc.hasAppliedMatches, isFalse);
    expect(igc.matches, isEmpty);

    igc.adoptResponse(responseFor(corrected));

    expect(igc.currentText, 'Yo quiero hablar español.');
    expect(igc.hasAppliedMatches, isFalse);
  });
}
