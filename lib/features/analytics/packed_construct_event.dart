import 'dart:convert';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/analytics/constructs_model.dart';

/// The uses one `pangea.construct` event carries, cut from batches of local
/// uses so that the server's acceptance of the event settles whole batches.
class PackedConstructEvent {
  final List<OneConstructUse> uses;

  /// How many batches, counted from the first, are fully sent once this event
  /// and every event before it are accepted.
  final int completedBatchCount;

  const PackedConstructEvent(this.uses, this.completedBatchCount);

  /// I tested with using the maxPDUSize constant, but the events were still
  /// too large. 50000 seems to be a safe number of bytes.
  static const int maxBytes = maxPDUSize - 10000;

  /// Packs [batches] in order into events under [maxBytes], keeping each batch
  /// in one event unless the batch alone is over [maxBytes].
  ///
  /// An over-cap batch is split across events and is complete only with its
  /// last event. If an earlier part is accepted and a later part is not, the
  /// next upload sends the whole batch again and the accepted part is stored
  /// twice. That needs a batch over [maxBytes] and a failure inside it.
  static List<PackedConstructEvent> pack(List<List<OneConstructUse>> batches) {
    final events = <PackedConstructEvent>[];
    var uses = <OneConstructUse>[];
    var bytes = 0;

    for (var i = 0; i < batches.length; i++) {
      final sizes = batches[i].map(_byteSize).toList();
      final batchBytes = sizes.fold(0, (sum, size) => sum + size);
      final fitsInFreshEvent = batchBytes <= maxBytes;
      if (uses.isNotEmpty &&
          bytes + batchBytes > maxBytes &&
          fitsInFreshEvent) {
        events.add(PackedConstructEvent(uses, i));
        uses = [];
        bytes = 0;
      }

      for (var j = 0; j < sizes.length; j++) {
        if (uses.isNotEmpty && bytes + sizes[j] > maxBytes) {
          events.add(PackedConstructEvent(uses, i));
          uses = [];
          bytes = 0;
        }
        uses.add(batches[i][j]);
        bytes += sizes[j];
      }
    }

    if (uses.isNotEmpty) {
      events.add(PackedConstructEvent(uses, batches.length));
    }
    return events;
  }

  static int _byteSize(OneConstructUse use) =>
      utf8.encode(jsonEncode(use.toJson())).length;
}
