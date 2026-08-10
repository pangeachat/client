import 'package:flutter/material.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat_list/chat_list.dart';
import 'package:fluffychat/widgets/pangea_search_bar.dart';

/// The chat list's search FIELD row, extracted so two hosts can render it:
/// the legacy [PangeaChatListHeader] (always-on when the list is long) and
/// the panel header's expanding search toggle (mounted on demand with
/// [autofocus] so opening search lands the keyboard in the field, and
/// [onClose] so the field's close control also collapses the row).
class PangeaChatListSearchField extends StatefulWidget {
  final ChatListController controller;
  final bool globalSearch;
  final bool autofocus;
  final VoidCallback? onClose;

  const PangeaChatListSearchField({
    super.key,
    required this.controller,
    this.globalSearch = true,
    this.autofocus = false,
    this.onClose,
  });

  @override
  State<PangeaChatListSearchField> createState() =>
      _PangeaChatListSearchFieldState();
}

class _PangeaChatListSearchFieldState extends State<PangeaChatListSearchField> {
  @override
  void initState() {
    super.initState();
    // TextField.autofocus is a no-op when the surrounding scope already has
    // a focused node — which it does right after the user taps the search
    // toggle — so request focus explicitly once the field is mounted.
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.controller.searchFocusNode.requestFocus();
      });
    }
  }

  void _close() {
    widget.controller.cancelSearch();
    widget.onClose?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = widget.controller;
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: AnimatedSize(
        duration: FluffyThemes.animationDuration,
        child: PangeaSearchBar(
          controller: controller.searchController,
          onChanged: (text) =>
              controller.onSearchEnter(text, globalSearch: widget.globalSearch),
          labelText: L10n.of(context).searchChatsHint,
          focusNode: controller.searchFocusNode,
          autofocus: widget.autofocus,
          suffixIcon: widget.onClose != null
              ? IconButton(
                  tooltip: L10n.of(context).cancel,
                  icon: const Icon(Icons.close_outlined),
                  onPressed: _close,
                  color: theme.colorScheme.onPrimaryContainer,
                )
              : controller.isSearchMode
              ? IconButton(
                  tooltip: L10n.of(context).cancel,
                  icon: const Icon(Icons.close_outlined),
                  onPressed: controller.cancelSearch,
                  color: theme.colorScheme.onPrimaryContainer,
                )
              : null,
        ),
      ),
    );
  }
}

class PangeaChatListHeader extends StatelessWidget
    implements PreferredSizeWidget {
  final ChatListController controller;
  final bool globalSearch;
  final bool showSearch;

  const PangeaChatListHeader({
    super.key,
    required this.controller,
    required this.showSearch,
    this.globalSearch = true,
  });

  @override
  Widget build(BuildContext context) {
    return SliverList(
      delegate: SliverChildListDelegate([
        showSearch
            ? PangeaChatListSearchField(
                controller: controller,
                globalSearch: globalSearch,
              )
            : const SizedBox.shrink(),
      ]),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(56);
}
