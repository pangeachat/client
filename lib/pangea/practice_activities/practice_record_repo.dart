import 'package:fluffychat/pangea/practice_activities/practice_record.dart';
import 'package:fluffychat/pangea/practice_activities/practice_target.dart';

class _PracticeRecordCacheEntry {
  final PracticeRecord record;
  final DateTime timestamp;

  _PracticeRecordCacheEntry({required this.record, required this.timestamp});

  bool get isExpired => DateTime.now().difference(timestamp).inMinutes > 15;
}

/// Controller for handling activity completions.
class PracticeRecordRepo {
  static final Map<String, _PracticeRecordCacheEntry> _cache = {};

  static PracticeRecord get(PracticeTarget target) {
    final cached = _getCached(target);
    if (cached != null) return cached;

    final entry = PracticeRecord();
    _setCached(target, entry);

    return entry;
  }

  static void set(PracticeTarget selection, PracticeRecord entry) =>
      _setCached(selection, entry);

  static PracticeRecord? _getCached(PracticeTarget target) {
    final keys = List.from(_cache.keys);
    for (final k in keys) {
      final item = _cache[k]!;
      if (item.isExpired) {
        _cache.remove(k);
      }
    }

    return _cache[target.storageKey]?.record;
  }

  static void _setCached(PracticeTarget target, PracticeRecord entry) {
    _cache[target.storageKey] = _PracticeRecordCacheEntry(
      record: entry,
      timestamp: DateTime.now(),
    );
  }
}
