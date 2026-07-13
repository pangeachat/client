import 'package:flutter/material.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat_list/chat_list.dart';

/// The chat list's search FIELD row, extracted so two hosts can render it:
/// the legacy [PangeaChatListHeader] (always-on when the list is long) and
/// the panel header's expanding search toggle (mounted on demand with
/// [autofocus] so opening search lands the keyboard in the field, and
/// [onClose] so the field's close control also collapses the row).
class PangeaChatListSearchField extends StatelessWidget {
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

  void _close() {
    controller.cancelSearch();
    onClose?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: AnimatedSize(
        duration: FluffyThemes.animationDuration,
        child: TextField(
          controller: controller.searchController,
          focusNode: controller.searchFocusNode,
          autofocus: autofocus,
          textInputAction: TextInputAction.search,
          onChanged: (text) =>
              controller.onSearchEnter(text, globalSearch: globalSearch),
          decoration: InputDecoration(
            filled: true,
            fillColor: theme.colorScheme.secondaryContainer,
            border: OutlineInputBorder(
              borderSide: BorderSide.none,
              borderRadius: BorderRadius.circular(99),
            ),
            contentPadding: EdgeInsets.zero,
            hintText: L10n.of(context).search,
            hintStyle: TextStyle(
              color: theme.colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.normal,
            ),
            floatingLabelBehavior: FloatingLabelBehavior.never,
            // With a host-owned close ([onClose]) the leading control always
            // dismisses: it clears any active search AND collapses the row.
            // Legacy hosts keep the search-vs-cancel toggle.
            prefixIcon: onClose != null
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
                : IconButton(
                    tooltip: L10n.of(context).search,
                    onPressed: controller.startSearch,
                    icon: Icon(
                      Icons.search_outlined,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
          ),
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
