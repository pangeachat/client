import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/notifications/notification_avatar_attachment.dart';

void main() {
  final avatarBytes = Uint8List.fromList([1, 2, 3, 4]);

  test('no avatar bytes means no attachment', () async {
    expect(
      await NotificationAvatarAttachment.forRoom(null, roomId: '!a:server'),
      isEmpty,
    );
  });

  test(
    'avatar bytes are written to a png the notification can attach',
    () async {
      final attachments = await NotificationAvatarAttachment.forRoom(
        avatarBytes,
        roomId: '!a:server',
      );

      expect(attachments, hasLength(1));
      final file = File(attachments.single.filePath);
      expect(file.path, endsWith('.png'));
      expect(await file.readAsBytes(), avatarBytes);
      await file.delete();
    },
  );

  test('a repeat notification for the same room rewrites its file', () async {
    // iOS MOVES an attached file into its own store, so the file is gone by the
    // time the next notification for this room arrives. Writing must not depend
    // on the previous one still being there, or on it having been cleaned up.
    final first = await NotificationAvatarAttachment.forRoom(
      avatarBytes,
      roomId: '!a:server',
    );
    await File(first.single.filePath).delete();

    final newBytes = Uint8List.fromList([9, 9, 9]);
    final second = await NotificationAvatarAttachment.forRoom(
      newBytes,
      roomId: '!a:server',
    );

    expect(second.single.filePath, first.single.filePath);
    expect(await File(second.single.filePath).readAsBytes(), newBytes);
    await File(second.single.filePath).delete();
  });

  test('different rooms do not share a file', () async {
    final a = await NotificationAvatarAttachment.forRoom(
      avatarBytes,
      roomId: '!a:server',
    );
    final b = await NotificationAvatarAttachment.forRoom(
      avatarBytes,
      roomId: '!b:server',
    );

    expect(a.single.filePath, isNot(b.single.filePath));
    await File(a.single.filePath).delete();
    await File(b.single.filePath).delete();
  });
}
