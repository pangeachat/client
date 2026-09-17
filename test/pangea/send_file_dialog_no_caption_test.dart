import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/send_file_dialog.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/adaptive_dialog_action.dart';
import 'get_test_client.dart';

/// Text sent with an attachment bypasses writing assistance, so the send
/// dialog offers no caption field for any file type — learners send the text
/// as its own message from the composer (#9108).
void main() {
  late Client client;

  // 1x1 transparent PNG.
  final pngBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
  );

  setUp(() async {
    client = await getTestClient();
  });

  tearDown(() async {
    await client.dispose();
  });

  Future<void> pumpDialog(WidgetTester tester, XFile file) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Builder(
          builder: (context) => SendFileDialog(
            room: Room(id: '!1234:fakeServer.notExisting', client: client),
            files: [file],
            outerContext: context,
            threadLastEventId: null,
            threadRootEventId: null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a single image has no caption field', (tester) async {
    await pumpDialog(
      tester,
      XFile.fromData(pngBytes, name: 'photo.png', mimeType: 'image/png'),
    );

    expect(find.byType(AdaptiveDialogAction), findsNWidgets(2));
    expect(find.byType(EditableText), findsNothing);
  });

  testWidgets('a single non-image file has no caption field', (tester) async {
    await pumpDialog(
      tester,
      XFile.fromData(
        utf8.encode('notes'),
        name: 'notes.pdf',
        mimeType: 'application/pdf',
      ),
    );

    expect(find.byType(AdaptiveDialogAction), findsNWidgets(2));
    expect(find.byType(EditableText), findsNothing);
  });
}
