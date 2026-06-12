import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/error_indicator.dart';
import 'package:fluffychat/pangea/download/download_type_enum.dart';

class DownloadDialog extends StatelessWidget {
  final bool downloading;
  final bool downloaded;
  final bool enableDownload;
  final DownloadType selectedDownloadType;
  final String? description;
  final List<DownloadType> downloadableTypes;

  final void Function(DownloadType) setDownloadType;
  final Future<void> Function() download;

  final String? error;
  final Widget? content;

  const DownloadDialog({
    required this.downloading,
    required this.downloaded,
    required this.enableDownload,
    required this.selectedDownloadType,
    required this.downloadableTypes,
    required this.setDownloadType,
    required this.download,
    this.description,
    this.error,
    this.content,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final error = this.error;
    final content = this.content;

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 2.5, sigmaY: 2.5),
      child: Dialog(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20.0),
        ),
        child: Container(
          padding: const EdgeInsets.all(12.0),
          constraints: const BoxConstraints(maxWidth: 325.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 40.0, height: 40.0),
                  Expanded(
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 40.0),
                      alignment: Alignment.center,
                      child: Text(
                        L10n.of(context).fileType,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              if (description != null)
                Text(description!, textAlign: TextAlign.center),
              SizedBox(height: 16.0),
              SegmentedButton<DownloadType>(
                selected: {selectedDownloadType},
                onSelectionChanged: downloading
                    ? null
                    : (c) => setDownloadType(c.first),
                segments: [
                  ...downloadableTypes.map(
                    (t) =>
                        ButtonSegment(value: t, label: Text(t.copy(context))),
                  ),
                ],
              ),
              SizedBox(height: 16.0),
              ?content,
              AnimatedSize(
                duration: FluffyThemes.animationDuration,
                child: Builder(
                  builder: (context) {
                    if (error != null) {
                      return Padding(
                        padding: EdgeInsetsGeometry.only(bottom: 16.0),
                        child: ErrorIndicator(message: error),
                      );
                    } else if (downloaded) {
                      if (kIsWeb) {
                        return Padding(
                          padding: EdgeInsetsGeometry.only(bottom: 16.0),
                          child: Text(
                            L10n.of(context).webDownloadPermissionMessage,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Theme.of(context).disabledColor,
                            ),
                          ),
                        );
                      }
                    } else if (downloading) {
                      return Padding(
                        padding: EdgeInsetsGeometry.only(bottom: 16.0),
                        child: Text(L10n.of(context).downloading),
                      );
                    }

                    return SizedBox();
                  },
                ),
              ),
              OutlinedButton(
                onPressed: enableDownload ? download : null,
                child: enableDownload
                    ? Text(L10n.of(context).download)
                    : const SizedBox(
                        height: 10,
                        width: 100,
                        child: LinearProgressIndicator(),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
