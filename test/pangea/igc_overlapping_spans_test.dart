import 'package:flutter/widgets.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/igc_controller.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/igc_response_model.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/pangea_match_state_model.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/pangea_match_status_enum.dart';
import 'sentry_capture_harness.dart';

/// #9256: writing-assistance spans must never overlap. The server's eval moves
/// an edit that falls inside another edit to a later occurrence of its text,
/// but the response keeps the first occurrence, so a word the learner repeats
/// can arrive nested inside a longer correction. Accepting the longer one then
/// shifted the nested span to a negative offset, and the composer threw on
/// every frame slicing the text at it (CLIENT-EVS).
void main() {
  const text = 'estudio lunes martes miercoles y jueves y el jueves trabajo';
  const phrase = 'lunes martes miercoles y jueves';

  late SentryCaptureHarness harness;

  setUp(() async {
    harness = SentryCaptureHarness();
    await harness.init();
  });

  tearDown(() => harness.close());

  test('a span nested inside another is dropped and reported', () async {
    late IGCResponseModel response;
    final event = await harness.capture(() {
      response = IGCResponseModel.fromJson(
        _responseJson(text, [
          _span(text.indexOf(phrase), phrase.length, 'De lunes a jueves'),
          // Where the server's response puts it: the first "jueves", inside
          // the phrase, rather than the second one its eval validated.
          _span(text.indexOf('jueves'), 'jueves'.length, 'viernes'),
        ]),
      );
    });

    expect(response.matches.map((m) => m.match.errorSpan), [phrase]);
    expect(event.throwable, isA<StateError>());
  });

  test('a partial overlap keeps the span that starts first', () async {
    late IGCResponseModel response;
    await harness.capture(() {
      response = IGCResponseModel.fromJson(
        _responseJson(text, [
          _span(8, 12, 'x'), // "lunes martes"
          _span(14, 16, 'y'), // "artes miercoles"
        ]),
      );
    });

    expect(response.matches.map((m) => m.match.errorSpan), ['lunes martes']);
  });

  test('adjacent spans are both kept, with nothing reported', () async {
    late IGCResponseModel response;
    await harness.expectNoReport(() {
      response = IGCResponseModel.fromJson(
        _responseJson(text, [
          _span(8, 5, 'Lunes'), // "lunes"
          _span(13, 7, ' Martes'), // " martes", starting where "lunes" ends
        ]),
      );
    });

    expect(response.matches.map((m) => m.match.errorSpan), [
      'lunes',
      ' martes',
    ]);
  });

  test('accepting the outer correction leaves every span on its text', () {
    // The crash needs the outer correction near the start of the message, as
    // in the report: accepting it moved the nested span 14 places left, past
    // zero.
    const message = 'lunes martes miercoles y jueves, el martes trabajo';
    final controller = IgcController((_) {}, () {})
      ..loadResponse(
        IGCResponseModel.fromJson(
          _responseJson(message, [
            _span(0, phrase.length, 'De lunes a jueves'),
            _span(message.indexOf('martes'), 'martes'.length, 'Martes'),
            _span(message.indexOf('trabajo'), 'trabajo'.length, 'trabajé'),
          ]),
        ),
      );

    final outer = controller.matches.firstWhere(
      (m) => m.originalMatch.match.errorSpan == phrase,
    )..selectBestChoice();
    controller.updateMatchStatus(outer, PangeaMatchStatusEnum.accepted);

    expect(controller.currentText, 'De lunes a jueves, el martes trabajo');
    // The composer slices the current text at each span, in offset order.
    expect(
      controller.sortedMatches
          .map((m) => _sliceLikeTheComposer(controller, m))
          .toList(),
      ['De lunes a jueves', 'trabajo'],
    );
  });
}

String _sliceLikeTheComposer(IgcController controller, PangeaMatchState m) {
  final span = m.updatedMatch.match;
  return controller.currentText!.characters
      .getRange(span.offset, span.offset + span.length)
      .toString();
}

/// A server-shaped span. The text here is plain Latin, so code points and
/// grapheme clusters agree and offsets can be written directly.
Map<String, dynamic> _span(int offset, int length, String replacement) => {
  ModelKey.offset: offset,
  ModelKey.length: length,
  'choices': [
    {'value': replacement, 'type': 'suggestion'},
  ],
  'type': 'grammar',
};

Map<String, dynamic> _responseJson(
  String text,
  List<Map<String, dynamic>> spans,
) => {
  'original_input': text,
  'full_text_correction': null,
  'matches': spans,
  ModelKey.userL1: 'en',
  ModelKey.userL2: 'es',
};
