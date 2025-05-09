import 'package:flutter/material.dart';

import 'package:flutter_gen/gen_l10n/l10n.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:fluffychat/pangea/analytics_downloads/analytics_dowload_dialog.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';

class DownloadAnalyticsButton extends StatelessWidget {
  final ConstructTypeEnum type;
  const DownloadAnalyticsButton({
    super.key,
    required this.type,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: L10n.of(context).download,
      icon: const Icon(Symbols.download),
      onPressed: () => showDialog<AnalyticsDownloadDialog>(
        context: context,
        builder: (context) => AnalyticsDownloadDialog(type: type),
      ),
    );
  }
}
