import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/choreographer/igc/pangea_match_model.dart';
import 'package:fluffychat/pangea/choreographer/igc/pangea_match_status_enum.dart';

void main() {
  group('PangeaMatch.fromJson', () {
    group('V1 format (wrapped with match key)', () {
      test('parses match wrapper correctly', () {
        final Map<String, dynamic> jsonData = {
          'match': {
            'message': 'Grammar error',
            'short_message': 'grammar',
            'choices': [
              {'value': 'correction', 'type': 'bestCorrection'},
            ],
            'offset': 10,
            'length': 4,
            'full_text': 'Some full text',
            'type': 'grammar',
          },
          'status': 'open',
        };

        final PangeaMatch match = PangeaMatch.fromJson(jsonData);

        expect(match.match.offset, 10);
        expect(match.match.length, 4);
        expect(match.match.fullText, 'Some full text');
        expect(match.status, PangeaMatchStatusEnum.open);
      });

      test('uses parentFullText as fallback when no full_text in match', () {
        final Map<String, dynamic> jsonData = {
          'match': {
            'message': 'Error',
            'choices': [
              {'value': 'fix', 'type': 'bestCorrection'},
            ],
            'offset': 5,
            'length': 3,
            'type': 'grammar',
          },
          'status': 'open',
        };

        final PangeaMatch match = PangeaMatch.fromJson(
          jsonData,
          fullText: 'Parent original input',
        );

        expect(match.match.fullText, 'Parent original input');
      });

      test('parses status from V1 format', () {
        final Map<String, dynamic> jsonData = {
          'match': {
            'message': 'Error',
            'choices': [],
            'offset': 0,
            'length': 1,
            'type': 'grammar',
          },
          'status': 'accepted',
        };

        final PangeaMatch match = PangeaMatch.fromJson(jsonData);

        expect(match.status, PangeaMatchStatusEnum.accepted);
      });
    });

    group('V2 format (flat SpanData)', () {
      test('parses flat SpanData correctly', () {
        final Map<String, dynamic> jsonData = {
          'message': 'Grammar error',
          'short_message': 'grammar',
          'choices': [
            {'value': 'correction', 'type': 'bestCorrection'},
          ],
          'offset': 10,
          'length': 4,
          'type': 'grammar',
        };

        final PangeaMatch match = PangeaMatch.fromJson(jsonData);

        expect(match.match.offset, 10);
        expect(match.match.length, 4);
        expect(match.match.message, 'Grammar error');
        // V2 format always defaults to open status
        expect(match.status, PangeaMatchStatusEnum.open);
      });

      test('uses parentFullText when provided', () {
        final Map<String, dynamic> jsonData = {
          'message': 'Error',
          'choices': [
            {'value': 'fix', 'type': 'bestCorrection'},
          ],
          'offset': 5,
          'length': 3,
          'type': 'vocabulary',
        };

        final PangeaMatch match = PangeaMatch.fromJson(
          jsonData,
          fullText: 'The original input text',
        );

        expect(match.match.fullText, 'The original input text');
      });

      test('parses type as string in V2 format', () {
        final Map<String, dynamic> jsonData = {
          'message': 'Out of target',
          'choices': [],
          'offset': 0,
          'length': 5,
          'type': 'itStart', // String type in V2
        };

        final PangeaMatch match = PangeaMatch.fromJson(jsonData);

        expect(match.isITStart, true);
      });

      test('handles V2 format with string type grammar', () {
        final Map<String, dynamic> jsonData = {
          'message': 'Tense error',
          'choices': [
            {'value': 'went', 'type': 'bestCorrection'},
          ],
          'offset': 2,
          'length': 4,
          'type': 'grammar', // String type in V2
        };

        final PangeaMatch match = PangeaMatch.fromJson(jsonData);

        expect(match.isGrammarMatch, true);
        expect(match.isITStart, false);
      });
    });

    group('backward compatibility', () {
      test('V1 format with type as object still works', () {
        final Map<String, dynamic> jsonData = {
          'match': {
            'message': 'Error',
            'choices': [],
            'offset': 0,
            'length': 1,
            'type': {'type_name': 'grammar'}, // Old object format
          },
          'status': 'open',
        };

        final PangeaMatch match = PangeaMatch.fromJson(jsonData);

        expect(match.isGrammarMatch, true);
      });

      test('V2 format with type as string works', () {
        final Map<String, dynamic> jsonData = {
          'message': 'Error',
          'choices': [],
          'offset': 0,
          'length': 1,
          'type': 'grammar', // New string format
        };

        final PangeaMatch match = PangeaMatch.fromJson(jsonData);

        expect(match.isGrammarMatch, true);
      });
    });
  });
}
