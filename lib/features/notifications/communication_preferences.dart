import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';

/// The person's refused message categories: the account data that the
/// Synapse module's notice delivery and its emailed unsubscribe link also read
/// and write. The shape must stay the module's.
class CommunicationPreferences {
  static const int version = 1;
  static const String missedMessageCategory = 'missed_message';
  static const String sourceApp = 'app';

  final Set<String> refused;
  final bool allOff;
  final int? updatedTs;
  final String? source;

  const CommunicationPreferences({
    this.refused = const {},
    this.allOff = false,
    this.updatedTs,
    this.source,
  });

  /// The global off never covers missed messages, so only the category's own
  /// refusal counts.
  bool get refusesMissedMessageEmail => refused.contains(missedMessageCategory);

  CommunicationPreferences withMissedMessageEmailRefused(
    bool refuse,
    DateTime now,
  ) {
    final updated = {...refused};
    if (refuse) {
      updated.add(missedMessageCategory);
    } else {
      updated.remove(missedMessageCategory);
    }
    return CommunicationPreferences(
      refused: updated,
      allOff: allOff,
      updatedTs: now.millisecondsSinceEpoch,
      source: sourceApp,
    );
  }

  /// A malformed list reads as nothing refused, as it does in the module:
  /// silencing someone who never asked is the worse failure.
  factory CommunicationPreferences.fromJson(Map<String, Object?> json) {
    final rawRefused = json['refused'];
    if (rawRefused != null && rawRefused is! List) {
      ErrorHandler.logError(
        e: 'Malformed communication preferences refused list',
        data: {'refused_type': rawRefused.runtimeType.toString()},
        level: SentryLevel.warning,
      );
    }
    final updatedTs = json['updated_ts'];
    final source = json['source'];
    return CommunicationPreferences(
      refused: rawRefused is List ? rawRefused.whereType<String>().toSet() : {},
      allOff: json['all_off'] == true,
      updatedTs: updatedTs is int ? updatedTs : null,
      source: source is String ? source : null,
    );
  }

  Map<String, Object?> toJson() => {
    'version': version,
    'refused': refused.toList()..sort(),
    'all_off': allOff,
    'updated_ts': ?updatedTs,
    'source': ?source,
  };
}
