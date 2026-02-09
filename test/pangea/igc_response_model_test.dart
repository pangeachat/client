import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/choreographer/igc/igc_response_model.dart';

void main() {
  group('IGCResponseModel.fromJson', () {
    test('passes originalInput to matches as fullText fallback', () {
      final Map<String, dynamic> jsonData = {
        'original_input': 'I want to know the United States',
        'full_text_correction': null,
        'matches': [
          {
            'match': {
              'message': 'Grammar error',
              'short_message': 'grammar',
              'choices': [
                {'value': 'learn about', 'type': 'bestCorrection'},
              ],
              'offset': 10,
              'length': 4,
              // Note: no full_text in match - should use original_input
              'type': 'grammar',
            },
            'status': 'open',
          },
        ],
        'user_l1': 'en',
        'user_l2': 'es',
        'enable_it': true,
        'enable_igc': true,
      };

      final IGCResponseModel response = IGCResponseModel.fromJson(jsonData);

      expect(response.matches.length, 1);
      expect(response.matches[0].match.fullText,
          'I want to know the United States');
    });

    test('match full_text takes precedence over originalInput', () {
      final Map<String, dynamic> jsonData = {
        'original_input': 'Original input text',
        'full_text_correction': null,
        'matches': [
          {
            'match': {
              'message': 'Grammar error',
              'short_message': 'grammar',
              'choices': [
                {'value': 'correction', 'type': 'bestCorrection'},
              ],
              'offset': 0,
              'length': 5,
              'full_text': 'Full text from span', // This should take precedence
              'type': 'grammar',
            },
            'status': 'open',
          },
        ],
        'user_l1': 'en',
        'user_l2': 'es',
        'enable_it': true,
        'enable_igc': true,
      };

      final IGCResponseModel response = IGCResponseModel.fromJson(jsonData);

      expect(response.matches.length, 1);
      expect(response.matches[0].match.fullText, 'Full text from span');
    });

    test('handles empty matches array', () {
      final Map<String, dynamic> jsonData = {
        'original_input': 'Clean text with no errors',
        'full_text_correction': null,
        'matches': <dynamic>[],
        'user_l1': 'en',
        'user_l2': 'es',
        'enable_it': true,
        'enable_igc': true,
      };

      final IGCResponseModel response = IGCResponseModel.fromJson(jsonData);

      expect(response.matches.length, 0);
      expect(response.originalInput, 'Clean text with no errors');
    });

    test('handles null matches', () {
      final Map<String, dynamic> jsonData = {
        'original_input': 'Text',
        'full_text_correction': null,
        'matches': null,
        'user_l1': 'en',
        'user_l2': 'es',
        'enable_it': true,
        'enable_igc': true,
      };

      final IGCResponseModel response = IGCResponseModel.fromJson(jsonData);

      expect(response.matches.length, 0);
    });
  });

  group('IGCResponseModel V2 format compatibility', () {
    test('parses V2 response without enable_it and enable_igc', () {
      // V2 response format from /choreo/grammar_v2 endpoint
      final Map<String, dynamic> jsonData = {
        'original_input': 'Me gusta el café',
        'matches': [
          {
            // V2 format: flat SpanData, no "match" wrapper
            'choices': [
              {
                'value': 'Me encanta',
                'type': 'bestCorrection',
                'feedback': 'Use "encantar" for expressing love'
              },
            ],
            'offset': 0,
            'length': 8,
            'type': 'vocabulary',
          },
        ],
        'user_l1': 'en',
        'user_l2': 'es',
        // Note: no enable_it, enable_igc in V2 response
      };

      final IGCResponseModel response = IGCResponseModel.fromJson(jsonData);

      expect(response.originalInput, 'Me gusta el café');
      expect(response.userL1, 'en');
      expect(response.userL2, 'es');
      // Should default to true when not present
      expect(response.enableIT, true);
      expect(response.enableIGC, true);
      expect(response.matches.length, 1);
      expect(response.matches[0].match.offset, 0);
      expect(response.matches[0].match.length, 8);
    });

    test('parses V2 response with empty matches', () {
      final Map<String, dynamic> jsonData = {
        'original_input': 'Perfect sentence with no errors',
        'matches': <dynamic>[],
        'user_l1': 'en',
        'user_l2': 'fr',
      };

      final IGCResponseModel response = IGCResponseModel.fromJson(jsonData);

      expect(response.matches.length, 0);
      expect(response.enableIT, true);
      expect(response.enableIGC, true);
      expect(response.fullTextCorrection, isNull);
    });

    test('parses V2 response with multiple matches', () {
      final Map<String, dynamic> jsonData = {
        'original_input': 'Yo soy ir a la tienda',
        'matches': [
          {
            'choices': [
              {
                'value': 'voy',
                'type': 'bestCorrection',
                'feedback': 'Use conjugated form'
              },
            ],
            'offset': 7,
            'length': 2,
            'type': 'grammar',
          },
          {
            'choices': [
              {'value': 'Voy', 'type': 'bestCorrection'},
            ],
            'offset': 0,
            'length': 6,
            'type': 'grammar',
          },
        ],
        'user_l1': 'en',
        'user_l2': 'es',
      };

      final IGCResponseModel response = IGCResponseModel.fromJson(jsonData);

      expect(response.matches.length, 2);
      expect(response.matches[0].match.offset, 7);
      expect(response.matches[1].match.offset, 0);
    });

    test('V1 format with explicit enable_it=false still works', () {
      final Map<String, dynamic> jsonData = {
        'original_input': 'Test text',
        'full_text_correction': 'Corrected text',
        'matches': <dynamic>[],
        'user_l1': 'en',
        'user_l2': 'es',
        'enable_it': false,
        'enable_igc': false,
      };

      final IGCResponseModel response = IGCResponseModel.fromJson(jsonData);

      expect(response.enableIT, false);
      expect(response.enableIGC, false);
      expect(response.fullTextCorrection, 'Corrected text');
    });

    test('V2 response choice includes feedback field', () {
      final Map<String, dynamic> jsonData = {
        'original_input': 'Je suis alle',
        'matches': [
          {
            'choices': [
              {
                'value': 'allé',
                'type': 'bestCorrection',
                'feedback': 'Add accent to past participle',
              },
            ],
            'offset': 8,
            'length': 4,
            'type': 'diacritics',
          },
        ],
        'user_l1': 'en',
        'user_l2': 'fr',
      };

      final IGCResponseModel response = IGCResponseModel.fromJson(jsonData);

      expect(response.matches.length, 1);
      expect(response.matches[0].match.bestChoice?.feedback,
          'Add accent to past participle');
    });
  });
}
