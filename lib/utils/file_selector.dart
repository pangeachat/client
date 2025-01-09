import 'package:flutter/widgets.dart';

import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart';

import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/app_lock.dart';

Future<List<XFile>> selectFiles(
  BuildContext context, {
  String? title,
  FileSelectorType type = FileSelectorType.any,
  bool allowMultiple = false,
}) async {
  if (!PlatformInfos.isLinux) {
    final result = await AppLock.of(context).pauseWhile(
      FilePicker.platform.pickFiles(
        compressionQuality: 0,
        allowMultiple: allowMultiple,
        type: type.filePickerType,
        allowedExtensions: type.extensions,
      ),
    );
    return result?.xFiles ?? [];
  }

  if (allowMultiple) {
    return await AppLock.of(context).pauseWhile(
      openFiles(
        confirmButtonText: title,
        acceptedTypeGroups: type.groups,
      ),
    );
  }
  final file = await AppLock.of(context).pauseWhile(
    openFile(
      confirmButtonText: title,
      acceptedTypeGroups: type.groups,
    ),
  );
  if (file == null) return [];
  return [file];
}

enum FileSelectorType {
  any([], FileType.any, null),
  images(
    [
      XTypeGroup(
        label: 'JPG',
        extensions: <String>['jpg', 'JPG', 'jpeg', 'JPEG'],
      ),
      XTypeGroup(
        label: 'PNGs',
        extensions: <String>['png', 'PNG'],
      ),
      XTypeGroup(
        label: 'WEBP',
        extensions: <String>['WebP', 'WEBP'],
      ),
    ],
    FileType.image,
    null,
  ),
  zip(
    [
      XTypeGroup(
        label: 'ZIP',
        extensions: <String>['zip', 'ZIP'],
      ),
    ],
    FileType.custom,
    ['zip', 'ZIP'],
  );

  const FileSelectorType(this.groups, this.filePickerType, this.extensions);
  final List<XTypeGroup> groups;
  final FileType filePickerType;
  final List<String>? extensions;
}
