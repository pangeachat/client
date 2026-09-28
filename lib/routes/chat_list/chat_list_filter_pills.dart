import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/filter_pill_row.dart';
import 'package:fluffychat/routes/chat_list/chat_list.dart';

/// The filter pill row under the chat list's search bar. "All" is always the
/// default selection so no chat is hidden without an explicit filter choice.
class ChatListFilterPills extends StatelessWidget {
  final ChatListController controller;

  const ChatListFilterPills({required this.controller, super.key});

  static const List<ActiveFilter> _filters = [
    ActiveFilter.allChats,
    ActiveFilter.messages,
    ActiveFilter.groups,
    ActiveFilter.activities,
  ];

  String _tooltip(BuildContext context, ActiveFilter filter) {
    final l10n = L10n.of(context);
    switch (filter) {
      case ActiveFilter.allChats:
        return l10n.allFilterTooltip;
      case ActiveFilter.messages:
        return l10n.dmsFilterTooltip;
      case ActiveFilter.groups:
        return l10n.groupsFilterTooltip;
      case ActiveFilter.activities:
        return l10n.activitiesFilterTooltip;
      case ActiveFilter.unread:
      case ActiveFilter.spaces:
        return filter.toLocalizedString(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FilterPillRow<ActiveFilter>(
      semanticsLabel: L10n.of(context).chatListFiltersLabel,
      filters: _filters,
      selected: controller.activeFilter,
      onSelected: controller.setActiveFilter,
      labelOf: (filter) => filter.toLocalizedString(context),
      tooltipOf: (filter) => _tooltip(context, filter),
    );
  }
}
