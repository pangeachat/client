import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/morphs/default_morph_mapping.dart';
import 'package:fluffychat/pangea/morphs/morph_meaning/default_morph_info_response.dart';

void main() {
  group('defaultMorphInfoResponse', () {
    test('every (feature, tag) in defaultMorphMapping has English copy', () {
      final missing = <String>[];

      for (final feature in defaultMorphMapping.features) {
        final defaultFeature = defaultMorphInfoResponse.getFeatureByCode(
          feature.feature,
        );
        if (defaultFeature == null) {
          missing.add('feature "${feature.feature}"');
          continue;
        }
        if (defaultFeature.l1Title.isEmpty) {
          missing.add('feature "${feature.feature}" has empty l1_title');
        }
        for (final tag in feature.tags) {
          final defaultTag = defaultFeature.getTagByCode(tag);
          if (defaultTag == null) {
            missing.add('tag "${feature.feature}/$tag"');
            continue;
          }
          if (defaultTag.l1Title.isEmpty) {
            missing.add('tag "${feature.feature}/$tag" has empty l1_title');
          }
          if (defaultTag.l1Description.isEmpty) {
            missing.add(
              'tag "${feature.feature}/$tag" has empty l1_description',
            );
          }
        }
      }

      expect(missing, isEmpty, reason: 'Missing English defaults:\n${missing.join('\n')}');
    });

    test('userL1 and userL2 are "en"', () {
      expect(defaultMorphInfoResponse.userL1, 'en');
      expect(defaultMorphInfoResponse.userL2, 'en');
    });

    test('roundtrips through toJson/fromJson', () {
      final json = defaultMorphInfoResponse.toJson();
      expect(json['features'], isNotEmpty);
      expect(json['user_l1'], 'en');
    });
  });
}
