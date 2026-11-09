import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';

/// The start page's emoji row: for each word, the emoji the learner gave it,
/// else the first in its dictionary entry, fetching the entries this device
/// has not saved (practice-exercises.instructions.md, "Start page"). Until
/// every fetch settles each word holds a slot, so the page does not jump;
/// then the words with no emoji, or one already shown, drop out.
class PracticeStartEmojis extends StatefulWidget {
  final List<ConstructIdentifier> words;

  /// Offline, only saved entries are used.
  final bool offline;

  /// The emoji already on this device for a word, and the fetch for a word
  /// that has none; both default to the real lookups.
  final String? Function(ConstructIdentifier word) savedEmojiOf;
  final Future<String?> Function(ConstructIdentifier word) fetchEmojiOf;

  const PracticeStartEmojis({
    required this.words,
    required this.offline,
    this.savedEmojiOf = _savedEmoji,
    this.fetchEmojiOf = _fetchEmoji,
    super.key,
  });

  static String? _savedEmoji(ConstructIdentifier word) =>
      word.userSetEmoji ?? word.dictionaryEmoji;

  /// The dictionary repo reports a failed fetch itself; the word then shows
  /// no emoji.
  static Future<String?> _fetchEmoji(ConstructIdentifier word) async =>
      (await word.getLemmaInfo(const {})).asValue?.value.emoji.firstOrNull;

  @override
  State<PracticeStartEmojis> createState() => _PracticeStartEmojisState();
}

class _PracticeStartEmojisState extends State<PracticeStartEmojis> {
  static const double _slotSize = 48.0;

  late List<String?> _emojis;
  int _pending = 0;

  /// Bumped when the words change, so a fetch for the old ones is dropped.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(PracticeStartEmojis oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.words, widget.words) ||
        oldWidget.offline != widget.offline) {
      _resolve();
    }
  }

  void _resolve() {
    final generation = ++_generation;
    _emojis = [for (final word in widget.words) widget.savedEmojiOf(word)];
    _pending = 0;
    if (widget.offline) return;
    for (var i = 0; i < _emojis.length; i++) {
      if (_emojis[i] != null) continue;
      _pending++;
      _fetch(i, generation);
    }
  }

  Future<void> _fetch(int index, int generation) async {
    final word = widget.words[index];
    String? emoji;
    try {
      emoji = await widget.fetchEmojiOf(word);
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {'lemma': word.lemma});
    }
    if (!mounted || generation != _generation) return;
    setState(() {
      _emojis[index] = emoji;
      _pending--;
    });
  }

  @override
  Widget build(BuildContext context) {
    final settled = _pending == 0;
    // Each emoji shows once. Until every fetch settles, a word with no emoji
    // yet, or one already shown, keeps a placeholder slot.
    final shown = <String>{};
    final slots = <String?>[
      for (final emoji in _emojis)
        if (emoji != null && shown.add(emoji)) emoji else if (!settled) null,
    ];
    if (slots.isEmpty) return const SizedBox.shrink();
    final placeholderColor = Theme.of(
      context,
    ).colorScheme.surfaceContainerHighest;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20.0),
      child: ExcludeSemantics(
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 12.0,
          runSpacing: 12.0,
          children: [
            for (final emoji in slots)
              SizedBox.square(
                dimension: _slotSize,
                child: Center(
                  child: emoji != null
                      ? Text(emoji, style: const TextStyle(fontSize: 40.0))
                      : Container(
                          width: 24.0,
                          height: 24.0,
                          decoration: BoxDecoration(
                            color: placeholderColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
