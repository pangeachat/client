import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/features/subscription/subscription_constants.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/routes/settings/settings_subscription/discount_code_view_content.dart';
import 'package:fluffychat/routes/settings/settings_subscription/discount_code_view_model.dart';
import 'package:fluffychat/routes/settings/settings_subscription/discount_code_view_title.dart';
import 'package:fluffychat/routes/settings/settings_subscription/payment_page_mixin.dart';
import 'package:fluffychat/widgets/matrix.dart';

class DiscountCodePage extends StatefulWidget {
  final Widget closeButton;

  /// The code a gift link carried in, validated at once with no field shown
  /// (subscriptions.instructions.md § Gift link).
  final String? linkCode;

  /// Whether the learner may type a code on this page. Never on iOS, where
  /// App Review rejects the field (Apple 3.1.1, #9316); a rejected link code
  /// then falls back to the plan page instead of offering the field.
  final bool allowManualEntry;

  const DiscountCodePage({
    super.key,
    required this.closeButton,
    this.linkCode,
    this.allowManualEntry = true,
  });

  @override
  DiscountCodePageState createState() => DiscountCodePageState();
}

class DiscountCodePageState extends State<DiscountCodePage>
    with PaymentPageMixin {
  late final DiscountCodeViewModel _viewModel = DiscountCodeViewModel(
    userID: Matrix.of(context).client.userID!,
    initialCode: widget.linkCode,
  );

  bool _watchingLinkCode = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_watchingLinkCode || widget.allowManualEntry) return;
    _watchingLinkCode = true;
    _viewModel.loader.addListener(_fallBackOnRejectedLinkCode);
  }

  @override
  void dispose() {
    if (_watchingLinkCode) {
      _viewModel.loader.removeListener(_fallBackOnRejectedLinkCode);
    }
    _viewModel.dispose();
    super.dispose();
  }

  /// With no field to retype into, a link code that fails validation shows
  /// the usual error and leaves for the plan page, as the bare discount deep
  /// link does on this platform.
  void _fallBackOnRejectedLinkCode() {
    final rejected = switch (_viewModel.loader.value) {
      AsyncError() => true,
      AsyncLoaded(value: final response) => response.valid != true,
      _ => false,
    };
    if (!rejected || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(L10n.of(context).invalidDiscountCode)),
    );
    context.go(
      WorkspaceNav.openSettings(
        GoRouterState.of(context).uri,
        page: 'subscription',
        seatMenu: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
          SingleChildScrollView(
            child: Container(
              alignment: Alignment.topCenter,
              child: Container(
                padding: EdgeInsets.only(left: 16.0, right: 16.0, bottom: 16.0),
                constraints: BoxConstraints(maxWidth: 400),
                child: DiscountCodeViewContent(
                  viewModel: _viewModel,
                  onSubscribe: processCheckoutRequest,
                  allowManualEntry: widget.allowManualEntry,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
