import 'package:flutter/material.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/common/utils/map_tiles.dart';

void main() {
  tearDown(dotenv.clean);

  test('each theme gets its own Stadia style', () {
    expect(
      MapTiles.urlTemplate(Brightness.light),
      contains('/alidade_smooth/'),
    );
    expect(
      MapTiles.urlTemplate(Brightness.dark),
      contains('/alidade_smooth_dark/'),
    );
  });

  // Tests run on the VM, so this is the native path.
  test('native requests carry the key in a header, not the URL', () {
    dotenv.testLoad(fileInput: 'STADIA_MAPS_API_KEY=test-key');
    expect(MapTiles.headers, {'Authorization': 'Stadia-Auth test-key'});
    expect(MapTiles.urlTemplate(Brightness.light), isNot(contains('api_key')));
  });

  test('no key configured sends no auth header', () {
    expect(MapTiles.headers, isEmpty);
    dotenv.testLoad(fileInput: 'OTHER=1');
    expect(MapTiles.headers, isEmpty);
  });
}
