import 'package:collection/collection.dart';

import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_target.dart';

/// Which blank message practice moves the learner to next. Practice opens on
/// the first unanswered blank and, after each right answer, moves on to the
/// next one by itself, so the learner never has to hunt across the message
/// for where to go (#6259).
class PracticeSlotOrder {
  /// A match target's words in the order they are read. Selection shuffles
  /// them, so the list order would send the learner hopping around the
  /// message.
  static List<PangeaToken> tokensInReadingOrder(PracticeTarget target) =>
      target.tokens.sortedBy<num>((token) => token.text.offset);

  /// Grammar targets in the order their words are read. A word with several
  /// features keeps them in selection order.
  static List<PracticeTarget> targetsInReadingOrder(
    List<PracticeTarget> targets,
  ) => targets.sortedBy<num>((target) => target.tokens.first.text.offset);

  /// The first item after [after] that isn't done, wrapping round to earlier
  /// ones the learner skipped; null once every item is done. With no [after],
  /// the first item that isn't done.
  static T? nextOpen<T>(
    List<T> inOrder,
    bool Function(T item) isDone, {
    T? after,
  }) {
    final start = after == null ? 0 : inOrder.indexOf(after) + 1;
    for (var i = 0; i < inOrder.length; i++) {
      final item = inOrder[(start + i) % inOrder.length];
      if (!isDone(item)) return item;
    }
    return null;
  }
}
