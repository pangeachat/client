import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/utils/account_config.dart';
import 'get_test_client.dart';

/// #9629 — a chat open beside Settings › Style redraws its wallpaper when the
/// learner changes it there, by listening to these updates.
void main() {
  sqfliteFfiInit();

  late Client client;

  setUp(() async {
    client = await getTestClient();
  });

  tearDown(() => client.dispose());

  Future<void> syncAccountData(String nextBatch, List<BasicEvent> events) =>
      client.handleSync(SyncUpdate(nextBatch: nextBatch, accountData: events));

  test('a sync that changes the config delivers the new config', () async {
    final wallpaperUrl = Uri.parse('mxc://example.com/wallpaper');
    final update = client.applicationAccountConfigUpdates.first;

    await syncAccountData('config', [
      BasicEvent(
        type: ApplicationAccountConfigExtension.accountDataKey,
        content: ApplicationAccountConfig(
          wallpaperUrl: wallpaperUrl,
          wallpaperOpacity: 0.3,
          wallpaperBlur: 4,
        ).toJson(),
      ),
    ]);

    final config = await update;
    expect(config.wallpaperUrl, wallpaperUrl);
    expect(config.wallpaperOpacity, 0.3);
    expect(config.wallpaperBlur, 4);
  });

  test('a sync that leaves the config alone delivers nothing', () async {
    final updates = <ApplicationAccountConfig>[];
    final subscription = client.applicationAccountConfigUpdates.listen(
      updates.add,
    );
    addTearDown(subscription.cancel);

    await syncAccountData('other', [
      BasicEvent(
        type: 'im.vector.setting.breadcrumbs',
        content: {'recent_rooms': <String>[]},
      ),
    ]);
    await client.handleSync(SyncUpdate(nextBatch: 'empty'));
    await pumpEventQueue();

    expect(updates, isEmpty);
  });
}
