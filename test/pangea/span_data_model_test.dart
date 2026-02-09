import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/choreographer/igc/replacement_type_enum.dart';
import 'package:fluffychat/pangea/choreographer/igc/span_data_model.dart';

void main() {
  test('SpanData.fromJson handles legacy correction type (maps to grammar)',
      () {
    final Map<String, dynamic> legacyJson = {
      'message': null,
      'short_message': null,
      'choices': <dynamic>[],
      'offset': 0,
      'length': 4,
      'full_text': 'Test',
      'type': {
        'type_name': 'correction',
      },
    };

    expect(() => SpanData.fromJson(legacyJson), returnsNormally);
    final SpanData span = SpanData.fromJson(legacyJson);
    // 'correction' is mapped to 'grammar' for backward compatibility
    expect(span.type, ReplacementTypeEnum.grammar);
  });

  test('SpanData.fromJson handles legacy typeName object', () {
    final Map<String, dynamic> legacyJson = {
      'message': null,
      'short_message': null,
      'choices': <dynamic>[],
      'offset': 0,
      'length': 4,
      'full_text': 'Test',
      'type': {
        'typeName': 'itStart',
      },
    };

    expect(() => SpanData.fromJson(legacyJson), returnsNormally);
    final SpanData span = SpanData.fromJson(legacyJson);
    expect(span.type, ReplacementTypeEnum.itStart);
  });

  test('SpanData.fromJson handles did_you_mean string', () {
    final Map<String, dynamic> jsonData = {
      'message': null,
      'short_message': null,
      'choices': <dynamic>[],
      'offset': 0,
      'length': 4,
      'full_text': 'Test',
      'type': 'did_you_mean',
    };

    expect(() => SpanData.fromJson(jsonData), returnsNormally);
    final SpanData span = SpanData.fromJson(jsonData);
    expect(span.type, ReplacementTypeEnum.didYouMean);
  });

  test('SpanData.fromJson handles legacy vocabulary type (maps to wordChoice)',
      () {
    final Map<String, dynamic> legacyJson = {
      'message': null,
      'short_message': null,
      'choices': <dynamic>[],
      'offset': 0,
      'length': 4,
      'full_text': 'Test',
      'type': 'vocabulary',
    };

    expect(() => SpanData.fromJson(legacyJson), returnsNormally);
    final SpanData span = SpanData.fromJson(legacyJson);
    // 'vocabulary' is mapped to 'wordChoice' for backward compatibility
    expect(span.type, ReplacementTypeEnum.wordChoice);
  });

  test('SpanData.fromJson handles new grammar type directly', () {
    final Map<String, dynamic> jsonData = {
      'message': null,
      'short_message': null,
      'choices': <dynamic>[],
      'offset': 0,
      'length': 4,
      'full_text': 'Test',
      'type': 'grammar',
    };

    expect(() => SpanData.fromJson(jsonData), returnsNormally);
    final SpanData span = SpanData.fromJson(jsonData);
    expect(span.type, ReplacementTypeEnum.grammar);
  });

  test('SpanData.fromJson handles translation type', () {
    final Map<String, dynamic> jsonData = {
      'message': null,
      'short_message': null,
      'choices': <dynamic>[],
      'offset': 0,
      'length': 4,
      'full_text': 'Test',
      'type': 'translation',
    };

    expect(() => SpanData.fromJson(jsonData), returnsNormally);
    final SpanData span = SpanData.fromJson(jsonData);
    expect(span.type, ReplacementTypeEnum.translation);
  });

  group('SpanData.fromJson fullText fallback', () {
    test('uses full_text from JSON when present', () {
      final Map<String, dynamic> jsonData = {
        'message': null,
        'short_message': null,
        'choices': <dynamic>[],
        'offset': 0,
        'length': 4,
        'full_text': 'Text from span',
        'type': 'grammar',
      };

      final SpanData span = SpanData.fromJson(
        jsonData,
        parentFullText: 'Text from parent',
      );
      expect(span.fullText, 'Text from span');
    });

    test('uses parentFullText when full_text not in JSON', () {
      final Map<String, dynamic> jsonData = {
        'message': null,
        'short_message': null,
        'choices': <dynamic>[],
        'offset': 0,
        'length': 4,
        // Note: no full_text field
        'type': 'grammar',
      };

      final SpanData span = SpanData.fromJson(
        jsonData,
        parentFullText: 'Text from parent',
      );
      expect(span.fullText, 'Text from parent');
    });

    test('uses empty string when neither full_text nor parentFullText present',
        () {
      final Map<String, dynamic> jsonData = {
        'message': null,
        'short_message': null,
        'choices': <dynamic>[],
        'offset': 0,
        'length': 4,
        'type': 'grammar',
      };

      final SpanData span = SpanData.fromJson(jsonData);
      expect(span.fullText, '');
    });

    test('prefers sentence over full_text (legacy field name)', () {
      final Map<String, dynamic> jsonData = {
        'message': null,
        'short_message': null,
        'choices': <dynamic>[],
        'offset': 0,
        'length': 4,
        'sentence': 'Text from sentence field',
        'full_text': 'Text from full_text field',
        'type': 'grammar',
      };

      final SpanData span = SpanData.fromJson(jsonData);
      expect(span.fullText, 'Text from sentence field');
    });
  });
}
