import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/subscription/subscription_constants.dart';
import 'package:fluffychat/routes/settings/settings_subscription/discount_code_view_content.dart';
import 'package:fluffychat/routes/settings/settings_subscription/discount_code_view_model.dart';
import 'package:fluffychat/routes/settings/settings_subscription/discount_code_view_title.dart';
import 'package:fluffychat/routes/settings/settings_subscription/payment_page_mixin.dart';
import 'package:fluffychat/widgets/matrix.dart';

class DiscountCodePage extends StatefulWidget {
  final Widget closeButton;
  const DiscountCodePage({super.key, required this.closeButton});

  @override
  DiscountCodePageState createState() => DiscountCodePageState();
}

class DiscountCodePageState extends State<DiscountCodePage>
    with PaymentPageMixin {
  late final DiscountCodeViewModel _viewModel = DiscountCodeViewModel(
    userID: Matrix.of(context).client.userID!,
  );

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isColumnMode = FluffyThemes.isColumnMode(context);
    return Scaffold(
      appBar: AppBar(
        leading: Center(child: widget.closeButton),
        title: DiscountCodeViewTitle(
          viewModel: _viewModel,
          style: isColumnMode
              ? Theme.of(context).textTheme.titleLarge
              : Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        centerTitle: false,
        titleSpacing: 0,
      ),
      body: Stack(
        children: [
          SizedBox.expand(
            child: ExcludeSemantics(
              child: CachedNetworkImage(
                imageUrl:
                    "${AppConfig.assetsBaseURL}/${SubscriptionConstants.starBackground}",
                fit: BoxFit.cover,
                alignment: Alignment.center,
                placeholder: (context, url) => const SizedBox(),
                errorWidget: (context, url, error) => const SizedBox(),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              child: Container(
                alignment: Alignment.topCenter,
                child: Container(
                  padding: EdgeInsets.only(
                    left: 16.0,
                    right: 16.0,
                    bottom: 16.0,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(24.0),
                  ),
                  constraints: BoxConstraints(maxWidth: 400),
                  child: DiscountCodeViewContent(
                    viewModel: _viewModel,
                    onSubscribe: processCheckoutRequest,
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
