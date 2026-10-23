import 'package:flutter/material.dart';

import 'package:shimmer/shimmer.dart';

import 'package:fluffychat/l10n/l10n.dart';

/// Where a Mission's progress will be while it loads (#9559): one rounded
/// shimmering block the exact size of [child], which is laid out under it
/// invisibly — so the surface keeps its height, nothing reads as zero, and
/// nothing jumps when the real numbers take over. Not pressable meanwhile.
class ProgressShimmer extends StatelessWidget {
  final Widget child;

  const ProgressShimmer({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: L10n.of(context).loadingPleaseWait,
      child: Stack(
        children: [
          IgnorePointer(
            child: ExcludeSemantics(child: Opacity(opacity: 0.0, child: child)),
          ),
          Positioned.fill(
            child: ExcludeSemantics(
              child: Shimmer.fromColors(
                baseColor: scheme.surfaceContainerHigh,
                highlightColor: scheme.surfaceContainerHighest,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: const BorderRadius.all(Radius.circular(12.0)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
