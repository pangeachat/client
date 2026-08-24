import 'package:flutter/material.dart';

import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/announcing_snackbar.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Undoes a block, from either entry point — the deleted-vocab list or a
/// construct's details page.
///
/// Unlike blocking there is no confirmation dialog: restoring *is* the undo of a
/// destructive action and is itself reversible, so a second "are you sure" is
/// pure friction. The announcing snackbar is the receipt, which also matters for
/// a bulk restore, where the only other feedback is rows quietly leaving a list.
mixin ConstructRestorer {
  /// Returns whether the restore actually ran, so a caller can clear its
  /// selection only on success (mirroring `blockSelectedConstructs`).
  Future<bool> restoreConstructs(
    BuildContext context,
    List<ConstructIdentifier> constructs,
  ) async {
    if (constructs.isEmpty) return false;
    final l10n = L10n.of(context);
    final count = constructs.length;

    final result = await showFutureLoadingDialog(
      context: context,
      future: () => Matrix.of(
        context,
      ).analyticsDataService.updateService.unblockConstructs(constructs),
    );
    if (!context.mounted || result.isError) return false;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(
      context,
    ).showSnackBarAnnounced(SnackBar(content: Text(l10n.restoredWords(count))));
    return true;
  }
}
