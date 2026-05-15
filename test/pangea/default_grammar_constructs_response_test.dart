import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/morphs/grammar_constructs/default_grammar_constructs_response.dart';

void main() {
  group('defaultGrammarConstructsResponse', () {
    // Choreo source of truth:
    // 2-step-choreographer/app/handlers/grammar_constructs/router.py
    //   GrammarConstructsJoinedResponse
    //     target_language: str
    //     user_l1: str
    //     source_l1: str
    //     features: list[JoinedFeature]
    //   JoinedFeature
    //     feature: str
    //     feature_title: str
    //     values: list[JoinedFeatureValue]
    //   JoinedFeatureValue
    //     value: str
    //     display: bool
    //     sequence_position: float (1.0-6.0)
    //     example: str
    //     title: str
    //     description: str

    test('has top-level keys matching GrammarConstructsJoinedResponse', () {
      expect(defaultGrammarConstructsResponse['target_language'], isA<String>());
      expect(defaultGrammarConstructsResponse['user_l1'], isA<String>());
      expect(defaultGrammarConstructsResponse['source_l1'], isA<String>());
      expect(defaultGrammarConstructsResponse['features'], isA<List>());
    });

    test('every feature has feature, feature_title, values', () {
      final features = defaultGrammarConstructsResponse['features'] as List;
      expect(features, isNotEmpty);
      final bad = <String>[];
      for (final f in features) {
        final feature = f as Map;
        if (feature['feature'] is! String || (feature['feature'] as String).isEmpty) {
          bad.add('${feature['feature']}: missing feature');
        }
        if (feature['feature_title'] is! String ||
            (feature['feature_title'] as String).isEmpty) {
          bad.add('${feature['feature']}: missing feature_title');
        }
        if (feature['values'] is! List || (feature['values'] as List).isEmpty) {
          bad.add('${feature['feature']}: missing values');
        }
      }
      expect(bad, isEmpty, reason: bad.join('\n'));
    });

    test('every value has all six JoinedFeatureValue keys with correct types', () {
      final features = defaultGrammarConstructsResponse['features'] as List;
      final bad = <String>[];
      for (final f in features) {
        final feature = f as Map;
        final featureName = feature['feature'];
        for (final v in feature['values'] as List) {
          final value = v as Map;
          final valueName = value['value'];
          final ctx = '$featureName/$valueName';

          if (value['value'] is! String || (value['value'] as String).isEmpty) {
            bad.add('$ctx: bad value');
          }
          if (value['display'] is! bool) {
            bad.add('$ctx: display must be bool, got ${value['display'].runtimeType}');
          }
          final pos = value['sequence_position'];
          if (pos is! num || pos < 1.0 || pos > 6.0) {
            bad.add('$ctx: sequence_position must be in [1.0, 6.0], got $pos');
          }
          if (value['example'] is! String || (value['example'] as String).isEmpty) {
            bad.add('$ctx: missing example');
          }
          if (value['title'] is! String || (value['title'] as String).isEmpty) {
            bad.add('$ctx: missing title');
          }
          if (value['description'] is! String ||
              (value['description'] as String).isEmpty) {
            bad.add('$ctx: missing description');
          }
        }
      }
      expect(bad, isEmpty, reason: bad.join('\n'));
    });

    test('has at least one display: true value (sanity check)', () {
      final features = defaultGrammarConstructsResponse['features'] as List;
      final displayedCount = features
          .expand<dynamic>((f) => (f as Map)['values'] as List)
          .where((v) => (v as Map)['display'] == true)
          .length;
      expect(displayedCount, greaterThan(0));
    });
  });
}
