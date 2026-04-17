import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/choreographer/choreo_constants.dart';
import 'package:fluffychat/pangea/choreographer/igc/igc_response_model.dart';
import 'package:fluffychat/pangea/common/constants/model_keys.dart';

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
              ModelKey.offset: 10,
              ModelKey.length: 4,
              // Note: no full_text in match - should use original_input
              'type': 'grammar',
            },
            'status': 'open',
          },
        ],
        ModelKey.userL1: 'en',
        ModelKey.userL2: 'es',
        ChoreoConstants.enableIT: true,
        ChoreoConstants.enableIGC: true,
      };

      final IGCResponseModel response = IGCResponseModel.fromJson(jsonData);

      expect(response.matches.length, 1);
      expect(
        response.matches[0].match.fullText,
        'I want to know the United States',
      );
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
              ModelKey.offset: 0,
              ModelKey.length: 5,
              ModelKey.fullText:
                  'Full text from span', // This should take precedence
              'type': 'grammar',
            },
            'status': 'open',
          },
        ],
        ModelKey.userL1: 'en',
        ModelKey.userL2: 'es',
        ChoreoConstants.enableIT: true,
        ChoreoConstants.enableIGC: true,
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
        ModelKey.userL1: 'en',
        ModelKey.userL2: 'es',
        ChoreoConstants.enableIT: true,
        ChoreoConstants.enableIGC: true,
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
        ModelKey.userL1: 'en',
        ModelKey.userL2: 'es',
        ChoreoConstants.enableIT: true,
        ChoreoConstants.enableIGC: true,
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
                'feedback': 'Use "encantar" for expressing love',
              },
            ],
            ModelKey.offset: 0,
            ModelKey.length: 8,
            'type': 'vocabulary',
          },
        ],
        ModelKey.userL1: 'en',
        ModelKey.userL2: 'es',
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
        ModelKey.userL1: 'en',
        ModelKey.userL2: 'fr',
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
                'feedback': 'Use conjugated form',
              },
            ],
            ModelKey.offset: 7,
            ModelKey.length: 2,
            'type': 'grammar',
          },
          {
            'choices': [
              {'value': 'Voy', 'type': 'bestCorrection'},
            ],
            ModelKey.offset: 0,
            ModelKey.length: 6,
            'type': 'grammar',
          },
        ],
        ModelKey.userL1: 'en',
        ModelKey.userL2: 'es',
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
        ModelKey.userL1: 'en',
        ModelKey.userL2: 'es',
        ChoreoConstants.enableIT: false,
        ChoreoConstants.enableIGC: false,
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
            ModelKey.offset: 8,
            ModelKey.length: 4,
            'type': 'diacritics',
          },
        ],
        ModelKey.userL1: 'en',
        ModelKey.userL2: 'fr',
      };

      final IGCResponseModel response = IGCResponseModel.fromJson(jsonData);

      expect(response.matches.length, 1);
      expect(
        response.matches[0].match.bestChoice?.feedback,
        'Add accent to past participle',
      );
    });
  });
}
