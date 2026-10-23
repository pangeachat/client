---
applyTo: "lib/features/notifications/notification_tap_utils.dart,lib/features/bot/bot_event_extension.dart,lib/routes/chat/bot_notice_widget.dart"
description: "How the client opens an engagement notice, from its push or from the notice in the bot DM, and how a notice shows in the bot DM."
---

# Notices in the client

A notice is a message the engagement runner sends a learner under the bot's identity. It arrives as a `p.room.notice` event in the learner's bot DM, often with a push or an email as well ([engagement notices](../../../engagement/.github/instructions/notices.instructions.md)). When the learner taps a notice, on its push or in the DM, the client takes them to the place the notice names. [deep-linking](../../../.github/.github/instructions/deep-linking.instructions.md#the-botclient-structured-content-deep-link) owns the cross-repo contract: which keys a notice carries and which key wins when there are two. This doc owns what the client shows and the checks it adds.

## Where a notice opens

- **A notice that names a session** opens that session if the learner is still in it. If they have left it, the activity's page opens with that session attached. No course opens, because the notice names no course.
- **A notice with an app path** opens that path the same way a URL typed in the address bar opens. So a short link such as `/<activityId>` becomes its activity token in the same way. A join-course notice names a course the learner is not in, so its path lands on that course's preview, where the learner joins ([routing.instructions.md § The course context](routing.instructions.md#the-course-context)).
- **A notice with neither** has a destination outside the app, so its push opens the bot DM, where the notice shows.

The client follows an app path only from the bot: the notice must be in the learner's bot DM (`isBotDM`), and its sender must be the bot account. This is because some paths do more than open a page (a join-code link submits the join), and any Matrix user can put these keys into an event they send. `isBotDM` alone is not enough. It also accepts a room whose bot settings say direct chat, and any member who can change that room's settings can write that. The client ignores a path from any other sender or room, and the tap opens the room as usual.

## The notice in the bot DM

- **Which notices show.** Every notice the bot sent into the bot DM shows, except `suggest_topic`. When the learner reads a `suggest_topic` notice, pangea-bot posts the topic as a normal bot message ([pangea-bot notices](../../../pangea-bot/.github/instructions/engagement.instructions.md)), so showing the notice as well would show the topic twice. Notices in other rooms stay hidden. Notices that pangea-bot sent before the engagement runner took over also show, in the DM's history at their original times. This is expected.
- **What it looks like.** The notice's `body` shows as a plain message from the bot ([`BotNoticeWidget`](../../lib/routes/chat/bot_notice_widget.dart)), with no toolbar, reading assistance or other message tools. A notice with a destination has an Open button under the text. Tapping it goes where the notice's push tap goes.
- **Chat list.** A notice never becomes the DM's preview line in the chat list.

## The opened record

A push tap and the Open button write the same opened record. That record is the Matrix opened event (`p.room.notice.opened`, with the notice's `check_in_type`) and the GA notification-open event ([analytics contract](../../../engagement/.github/instructions/analytics.instructions.md)). Each tap writes a record, so two taps on Open record two opens.
