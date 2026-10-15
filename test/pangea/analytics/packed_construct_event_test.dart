import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/features/analytics/packed_construct_event.dart';
import '../analytics_data/analytics_fixtures.dart';

/// Each event carries whole batches where it can, so the server accepting an
/// event settles whole batches and a failed upload never leaves a batch half
/// sent (#9511).
void main() {
  OneConstructUse smallUse(int i) => use(lemma: 'word$i', ts: at(i));

  /// A use whose JSON is a little over a third of the event size cap, so two
  /// fit in one event and three do not.
  OneConstructUse thirdOfCapUse(int i) =>
      use(lemma: '$i${'x' * (PackedConstructEvent.maxBytes ~/ 6)}', ts: at(i));

  int contentBytes(PackedConstructEvent event) => utf8
      .encode(jsonEncode(ConstructAnalyticsModel(uses: event.uses).toJson()))
      .length;

  test('small batches share one event', () {
    final batches = [
      [smallUse(0), smallUse(1)],
      [smallUse(2)],
      [smallUse(3), smallUse(4)],
    ];

    final events = PackedConstructEvent.pack(batches);

    expect(events, hasLength(1));
    expect(events.single.uses, batches.expand((b) => b).toList());
    expect(events.single.completedBatchCount, 3);
  });

  test('a batch that fits in an event of its own is not split', () {
    final batches = [
      [thirdOfCapUse(0)],
      [thirdOfCapUse(1), thirdOfCapUse(2)],
    ];

    final events = PackedConstructEvent.pack(batches);

    expect(events.map((e) => e.uses), [batches[0], batches[1]]);
    expect(events.map((e) => e.completedBatchCount), [1, 2]);
  });

  test('a batch over the cap is split and complete only with its last '
      'event', () {
    final small = smallUse(0);
    final oversized = List.generate(5, thirdOfCapUse);
    final batches = [
      [small],
      oversized,
    ];

    final events = PackedConstructEvent.pack(batches);

    expect(events.expand((e) => e.uses), [small, ...oversized]);
    expect(events.length, greaterThan(1));
    expect(
      events.map((e) => e.completedBatchCount),
      [...List.filled(events.length - 1, 1), 2],
      reason: 'only the oversized batch is spread across events',
    );
    for (final event in events) {
      expect(contentBytes(event), lessThan(maxPDUSize));
    }
  });

  test('empty batches complete with the events around them', () {
    final batches = [
      <OneConstructUse>[],
      [smallUse(0)],
      <OneConstructUse>[],
    ];

    final events = PackedConstructEvent.pack(batches);

    expect(events, hasLength(1));
    expect(events.single.completedBatchCount, 3);
  });
}
