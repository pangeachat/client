import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';

/// The degradation reason to surface in [DegradationBanner], mounted above
/// [RecordingInputRow]'s controls while the streaming-STT pilot is degraded,
/// or [none] when nothing has degraded (or the reason was dismissed this
/// recording). See `RecordingViewModelState.degradationBanner`.
enum DegradationBannerKind {
  /// Nothing to show — the banner does not mount.
  none,

  /// The relay's PRIMARY provider failed and a runner-up is now serving;
  /// streaming stays fully live (H9b `{"type":"provider","degraded":true}`).
  degradedLive,

  /// The whole streaming chain failed (relay `all_providers_down`) or the
  /// session hit any other unexpected post-`ready` terminal (B4); the
  /// retained audio was (or is being) sent through today's BATCH
  /// transcription path instead.
  degradedToBatch,

  /// Client-local: the gate does not route the recording's language at all
  /// (D11) — no server round-trip ever happens.
  languageUnsupported,
}

/// Small dismissible notice mounted ABOVE the voice input row's controls
/// (delete / pause / waveform / send) when the streaming-STT pilot degrades.
/// Purely presentational — `RecordingViewModelState.degradationBanner` owns
/// the state; [onDismiss] should call
/// `RecordingViewModelState.dismissDegradationBanner`. Additive UI only: it
/// never gates the voice tile, edit-diff, read-aloud, or send controls
/// beneath it.
class DegradationBanner extends StatelessWidget {
  final DegradationBannerKind kind;
  final VoidCallback onDismiss;

  const DegradationBanner({
    required this.kind,
    required this.onDismiss,
    super.key,
  });

  String? _message(BuildContext context) {
    switch (kind) {
      case DegradationBannerKind.degradedLive:
        return L10n.of(context).streamingSttDegradedLiveBanner;
      case DegradationBannerKind.degradedToBatch:
        return L10n.of(context).streamingSttDegradedToBatchBanner;
      case DegradationBannerKind.languageUnsupported:
        return L10n.of(context).streamingSttLanguageUnsupportedBanner;
      case DegradationBannerKind.none:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final message = _message(context);
    if (message == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      // Float the notice inset from the input-row edges and lift it with a soft shadow so
      // its edges read as a distinct card on ANY background (the near-white chat surface
      // barely separates a white card + hairline border on its own).
      margin: const EdgeInsets.fromLTRB(6.0, 4.0, 6.0, 8.0),
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: isDark ? theme.colorScheme.surfaceContainerHigh : Colors.white,
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.08),
            blurRadius: 8.0,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            Icons.info_outline,
            size: 18.0,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8.0),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 4.0),
          IconButton(
            tooltip: L10n.of(context).close,
            icon: const Icon(Icons.close, size: 18.0),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 32.0, minHeight: 32.0),
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}
