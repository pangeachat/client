import 'package:flutter/material.dart';

import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_search/search_footer.dart';
import 'package:fluffychat/pangea/navigation/navigation_util.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/url_launcher.dart';
import 'package:fluffychat/widgets/avatar.dart';

class ChatSearchMessageTab extends StatelessWidget {
  final String searchQuery;
  final Room room;
  final List<Event> events;
  final void Function() onStartSearch;
  final bool endReached, isLoading;
  final DateTime? searchedUntil;

  const ChatSearchMessageTab({
    required this.searchQuery,
    required this.room,
    required this.onStartSearch,
    required this.events,
    required this.searchedUntil,
    required this.endReached,
    required this.isLoading,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (events.isEmpty) {
      if (isLoading) {
        return const Center(child: CircularProgressIndicator.adaptive());
      }
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.search_outlined, size: 64),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Text(
              L10n.of(context).searchIn(
                room.getLocalizedDisplayname(MatrixLocals(L10n.of(context))),
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      );
    }

    return SelectionArea(
      child: ListView.separated(
        itemCount: events.length + 1,
        separatorBuilder: (context, _) =>
            Divider(color: theme.dividerColor, height: 1),
        itemBuilder: (context, i) {
          if (i == events.length) {
            return SearchFooter(
              searchedUntil: searchedUntil,
              endReached: endReached,
              isLoading: isLoading,
              onStartSearch: onStartSearch,
            );
          }
          final event = events[i];
          final sender = event.senderFromMemoryOrFallback;
          final displayname = sender.calcDisplayname(
            i18n: MatrixLocals(L10n.of(context)),
          );
          return _MessageSearchResultListTile(
            sender: sender,
            displayname: displayname,
            event: event,
            room: room,
          );
        },
      ),
    );
  }
}

class _MessageSearchResultListTile extends StatelessWidget {
  const _MessageSearchResultListTile({
    required this.sender,
    required this.displayname,
    required this.event,
    required this.room,
  });

  final User sender;
  final String displayname;
  final Event event;
  final Room room;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      title: Row(
        children: [
          // #Pangea
          // Avatar(mxContent: sender.avatarUrl, name: displayname, size: 16),
          Avatar(
            mxContent: sender.avatarUrl,
            name: displayname,
            userId: sender.id,
            size: 16,
          ),
          // Pangea#
          const SizedBox(width: 8),
          // #Pangea
          // Text(displayname),
          // Expanded(
          //   child: Text(
          //     ' | ${event.originServerTs.localizedTimeShort(context)}',
          //     style: const TextStyle(fontSize: 12),
          //   ),
          // ),
          Flexible(
            child: Text(
              displayname,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            ' | ${event.originServerTs.localizedTimeShort(context)}',
            style: const TextStyle(fontSize: 12),
          ),
          // Pangea#
        ],
      ),
      subtitle: Linkify(
        textScaleFactor: MediaQuery.textScalerOf(context).scale(1),
        options: const LinkifyOptions(humanize: false),
        linkStyle: TextStyle(
          color: theme.colorScheme.primary,
          decoration: TextDecoration.underline,
          decorationColor: theme.colorScheme.primary,
        ),
        onOpen: (url) => UrlLauncher(context, url.url).launchUrl(),
        text: event
            .calcLocalizedBodyFallback(
              plaintextBody: true,
              removeMarkdown: true,
              MatrixLocals(L10n.of(context)),
            )
            .trim(),
        maxLines: 7,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        icon: const Icon(Icons.chevron_right_outlined),
        // #Pangea
        // onPressed: () => context.go(
        //   '/${Uri(pathSegments: ['rooms', room.id], queryParameters: {'event': event.eventId})}',
        // ),
        onPressed: () => NavigationUtil.goToSpaceRoute(
          room.id,
          [],
          context,
          queryParams: {'event': event.eventId},
        ),
        // Pangea#
      ),
    );
  }
}
