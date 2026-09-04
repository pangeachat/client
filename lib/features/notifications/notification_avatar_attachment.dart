import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:matrix/matrix.dart';

/// iOS draws no image in a local notification unless one is attached as a file,
/// so the room avatar Android already puts in its large icon needs writing to
/// disk before the notification is shown (#8809). For a course ping or a course
/// invite that avatar is the course's own.
class NotificationAvatarAttachment {
  /// [avatarFile] is null wherever the avatar cannot be downloaded — a course
  /// carrying an assets-bucket (non-`mxc`) avatar included — and such a
  /// notification stays image-less rather than falling back to anything.
  static Future<List<DarwinNotificationAttachment>> forRoom(
    Uint8List? avatarFile, {
    required String roomId,
  }) async {
    if (avatarFile == null) return const [];
    try {
      // iOS moves an attached file into its own store, so the path is free
      // again by the next notification for this room; overwrite either way.
      final file = File(
        '${Directory.systemTemp.path}/notification_avatar_${roomId.hashCode}.png',
      );
      await file.writeAsBytes(avatarFile);
      return [DarwinNotificationAttachment(file.path)];
    } catch (e, s) {
      // Cosmetic: the notification still shows, without the avatar.
      Logs().e('Unable to write notification avatar attachment', e, s);
      return const [];
    }
  }
}
