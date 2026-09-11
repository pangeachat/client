import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';

enum L2SupportEnum {
  na,
  alpha,
  beta,
  full;

  String get storageString {
    switch (this) {
      case L2SupportEnum.na:
        return 'na';
      case L2SupportEnum.alpha:
        return 'alpha';
      case L2SupportEnum.beta:
        return 'beta';
      case L2SupportEnum.full:
        return 'full';
    }
  }

  L2SupportEnum fromStorageString(String storageString) {
    switch (storageString) {
      case 'na':
      case 'L2SupportEnum.na':
        return L2SupportEnum.na;
      case 'alpha':
      case 'L2SupportEnum.alpha':
        return L2SupportEnum.alpha;
      case 'beta':
      case 'L2SupportEnum.beta':
        return L2SupportEnum.beta;
      case 'full':
      case 'L2SupportEnum.full':
        return L2SupportEnum.full;
      default:
        throw Exception('Unknown L2SupportEnum storage string: $storageString');
    }
  }

  String toLocalizedString(BuildContext context) {
    final l10n = L10n.of(context);

    switch (this) {
      case L2SupportEnum.na:
        return l10n.l2SupportNa;
      case L2SupportEnum.alpha:
        return l10n.l2SupportAlpha;
      case L2SupportEnum.beta:
        return l10n.l2SupportBeta;
      case L2SupportEnum.full:
        return l10n.l2SupportFull;
    }
  }

  /// One hue, four steps: grey for no support, then a lavender that deepens
  /// with the tier, so a fully supported language is the emphasised one.
  /// Each step is a fill with its own ink.
  Badge toBadge(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (this) {
      L2SupportEnum.na => scheme.surfaceContainerHighest,
      L2SupportEnum.alpha => scheme.secondaryContainer,
      L2SupportEnum.beta => scheme.primaryFixedDim,
      L2SupportEnum.full => scheme.primaryContainer,
    };
    final ink = switch (this) {
      L2SupportEnum.na => scheme.onSurfaceVariant,
      L2SupportEnum.alpha => scheme.onSecondaryContainer,
      L2SupportEnum.beta => scheme.onPrimaryFixedVariant,
      L2SupportEnum.full => scheme.onPrimaryContainer,
    };

    return Badge(
      label: Text(
        toLocalizedString(context),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: ink,
          fontWeight: FontWeight.w500,
        ),
      ),
      backgroundColor: color,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      smallSize: 20, // A smaller badge for subtlety
    );
  }
}
