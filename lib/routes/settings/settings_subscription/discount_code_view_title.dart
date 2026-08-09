import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/settings/settings_subscription/discount_code_view_model.dart';

class DiscountCodeViewTitle extends StatelessWidget {
  final DiscountCodeViewModel viewModel;
  final TextStyle? style;
  final TextAlign textAlign;

  const DiscountCodeViewTitle({
    super.key,
    required this.viewModel,
    this.style,
    this.textAlign = TextAlign.center,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: viewModel.loader,
      builder: (context, state, _) => Text(
        viewModel.title(L10n.of(context)),
        style: style,
        textAlign: textAlign,
      ),
    );
  }
}
