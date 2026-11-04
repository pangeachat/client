---
applyTo: "lib/features/user/user_model.dart, lib/features/user/user_controller.dart, lib/features/user/public_profile_model.dart, lib/features/user/analytics_profile_model.dart, lib/features/bot/bot_client_extension.dart, lib/features/bot/bot_options_model.dart, lib/features/bot/bot_room_extension.dart, lib/features/bot/widgets/bot_chat_settings_dialog.dart, lib/routes/settings/settings_learning/**, lib/routes/onboarding/onboarding_step_views/pick_language_step_view.dart, lib/pangea/common/controllers/pangea_controller.dart, lib/routes/profile/user_home_page.dart, lib/widgets/users/about_me_display.dart, lib/widgets/users/country_display.dart, lib/widgets/users/level_display_name.dart, lib/features/analytics_access/join_room_analytics_access_extension.dart"
description: "Where a learner changes their profile settings, how they switch language from the content in front of them, how a change reaches their devices and the bot, and what other people can see."
---

# Profile Settings

A learner's profile holds their learning settings (languages, self-reported level, gender, voice, country, bio and tool switches) and a public part other people see. This doc decides where the settings change, how a learner switches language from context, and what reaches the bot and other people. It runs past the 800-word budget because it still holds the public profile, which could be a doc of its own.

## Where settings are changed

Learning settings open from four places, each showing the same settings and saving them the same way:

1. **Settings → Learning**, as a full page.
2. **A long press on the writing-assistance button**, as a dialog.
3. **The gear icon on the interactive translation bar**, as a dialog.
4. **The language-pair chip** ("EN → ES") on the learning progress widget, as a dialog.

Inside a room, one more place changes the same profile:

5. **The bot's settings**, opened from the bot's member profile, apply in that room at once.

### Changing the base language

The app's menus and buttons are shown in the base language, so a new base language that would switch them asks first: "Change base language?", naming the language they will switch to, with Cancel and Change. Nothing changes until the learner taps Change. Learning settings and the onboarding language step both ask, and only when the menus would actually switch, so not while the app is shown in the target language. A target-language switch still takes effect at once ([Switching from context](#switching-from-context)).

## Switching from context

Course and activity content is language-specific, but the learner's language is one setting, so a learner in several courses often meets content in another language. Switching out of that mismatch should be easy and low-stakes, and it happens **from the surface the learner is already looking at**, not from settings.

6. **The language chip is the switch.** Every surface that shows its content's language (the activity start page, a joined or previewed course's info chips, and a running session's [goal header](activity-session.instructions.md#the-goal-header)) draws it as a chip. When it differs from the learner's target, the chip is tinted in the warning colour, caution rather than achievement or failure, and tapping it opens the switcher. Nothing opens unasked: these panels reopen on nearly every move, so an automatic offer would be a notification the learner cannot turn off.
7. **The language switcher** is the same list of every target language that learning settings uses, so it behaves the same wherever it opens. The chip's language and the languages the learner has progress in come first, so the few they move between need no scrolling or search. Picking one switches at once.
8. **The send-time popup** is the backstop. Sending a message in an activity whose language differs from the learner's target offers to switch, at most once per 30 minutes per room so it does not nag, and confirming switches and sends the message. It stays because the chip is deliberately quiet: only this reaches a learner who never noticed the mismatch.
9. **The reading toolbar.** Tapping a message in another language when the chosen mode cannot work there shows a snackbar whose "Learn" button switches to that language.

**Switching to the learner's base language is refused, not attempted.** Every offer knows before it asks, so none of them offers the base language.

**A switch is cheap and loses nothing.** Each language keeps its own progress ([analytics-system.instructions.md](analytics-system.instructions.md#per-language-isolation)), so switching back finds it intact, and every switch takes effect on tap, without confirmation.

## Saving and syncing

A change reaches every device the learner is signed in on. Autocorrect's default differs by device ([target-language-keyboard.instructions.md](target-language-keyboard.instructions.md#when-autocorrect-turns-on)), so each device uses its own until the learner makes a choice, and that choice then applies everywhere.

The bot's settings follow the learner's, in their own chat with the bot first and then in their other one-to-one chats with it; activity rooms keep their own.

## Public vs. private

Only the learner sees their languages, gender, self-reported level, voice and tool settings. Anyone who shares a room with them sees their level and XP in each language, their banked goal total, their country and their bio. That level is computed from their chat activity, never self-reported.

### Ownership and mirroring

- **INVARIANT: NEVER publish a profile under an account other than the one it was loaded for.**
- Country and bio are copied to the public profile on every change, exactly: clearing one removes it.
- A level belongs to a language, not to a regional variant. Every variant of French shares French's one level, shown on French's row only, since a level beside each variant would read as separate progress the learner does not have.
- A published level changes only when the learner earns XP in that language; nothing republishes it at startup. A level left wrong by an earlier bug therefore stays wrong until then, a gap accepted deliberately.
- The banked goal total counts activity goals, drawn as a goal diamond ([quests.instructions.md](quests.instructions.md#stars-and-goal-diamonds)): each activity's best saved run, in the language it was played in. It is not a course total, because what a course total means depends on the course. Only the language being studied is republished; the others stay as they are until the learner studies them again. The total only rises, so a count that comes out low on one device never lowers it. It also keeps the stars from a session room the learner has left, so classmates can see more than the learner's own count. That is accepted: the app offers no way to leave one, and those stars were earned.

## Open questions

- **Entry points 1, 3 and 4 no longer match the app.** All three now open the Learning page in the settings panel; only entry point 2, the long press, still opens a dialog. The interactive translation bar has no gear icon, and the writing-assistance card's menu opens learning settings instead. The progress widget's chip shows the target language's flag, not "EN → ES". Which should this doc say?
- **The reading toolbar's button** reads "Click here to update your target language", not "Learn".
- **Where country and bio live.** They are the only settings that cross from private to public, through a copy that has to stay exact. Keeping them only in the public profile, edited there, would remove the copy and make the boundary explicit.
- **A self-reported level per language.** It is one value while the earned level is per language, so a switch leaves a level asserted for a language the learner never claimed, more often the more we encourage switching.
- **A word on the first switch.** A switch into a language with no history behaves like any other. We may want to say once that it starts at level 1 and the previous language keeps its progress, so an empty progress screen never reads as lost work.
- **Public learning stats.** Vocabulary, grammar progress and completed activities on a public profile would show classmates and teachers what a learner has learned, not just their level.
