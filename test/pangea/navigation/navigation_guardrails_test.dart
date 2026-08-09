import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Repo guardrails for the token routing model (routing.instructions.md):
/// internal navigation never emits retired path shapes, never hand-edits the
/// workspace query outside the navigation layer, and never writes the retired
/// `?m=course:` context spelling. Comment lines are skipped so retired
/// examples in docs/dead code don't trip the guard.
void main() {
  final dartFiles = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  Iterable<({String file, int line, String text})> codeLines() sync* {
    for (final file in dartFiles) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final text = lines[i];
        if (text.trimLeft().startsWith('//')) continue;
        yield (file: file.path, line: i + 1, text: text);
      }
    }
  }

  test('no navigation to retired path shapes', () {
    // The fork utility pages and Completer/preview flows are the only
    // legitimate path destinations (routing.instructions.md).
    const allowedFragments = [
      '/rooms/archive/',
      '/rooms/newprivatechat',
      '/courses/own/',
      '/addcourse/',
      '/preview/',
    ];
    // Catch every navigation entry point (go/push/pushNamed/pushReplacement)
    // and either quote style, so a retired path literal can't slip past under a
    // call shape the guard didn't anticipate.
    final retired = RegExp(
      r'''\.(?:go|push|pushNamed|pushReplacement)\(\s*['"]'''
      r'(/rooms/|/courses|/chats|/settings|/analytics|/profile)',
    );
    final offenders = [
      for (final l in codeLines())
        if (retired.hasMatch(l.text) && !allowedFragments.any(l.text.contains))
          '${l.file}:${l.line}  ${l.text.trim()}',
    ];
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('WorkspaceQuery stays inside the navigation layer', () {
    final offenders = [
      for (final l in codeLines())
        if (l.text.contains('WorkspaceQuery.') &&
            !l.file.contains('lib/features/navigation/'))
          '${l.file}:${l.line}',
    ];
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('nothing writes the retired m=course context spelling', () {
    final offenders = [
      for (final l in codeLines())
        if (l.text.contains("'m=course") || l.text.contains('"m=course'))
          '${l.file}:${l.line}',
    ];
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
