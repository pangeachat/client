---
applyTo: "lib/features/user/user_model.dart, lib/features/user/user_controller.dart, lib/features/user/public_profile_model.dart, lib/features/user/analytics_profile_model.dart, lib/features/bot/bot_client_extension.dart, lib/features/bot/bot_options_model.dart, lib/features/bot/bot_room_extension.dart, lib/features/bot/widgets/bot_chat_settings_dialog.dart, lib/routes/settings/settings_learning/**, lib/routes/onboarding/onboarding_step_views/pick_language_step_view.dart, lib/pangea/common/controllers/pangea_controller.dart, lib/routes/profile/user_home_page.dart, lib/widgets/users/about_me_display.dart, lib/widgets/users/country_display.dart, lib/widgets/users/level_display_name.dart, lib/features/analytics_access/join_room_analytics_access_extension.dart"
description: "What a learner's profile stores and what each setting does, where and when it is created and changed (including switching language from context, syncing across devices and updating the public copy), and what other people can read."
---

# Profile Settings

A learner's profile has two parts: private settings that only the learner sees, and a public profile that other people can read. This doc says what each part holds, how and when it changes, and who can read what. It runs past the 800-word budget because each line left is a decision someone could disagree with.

## What the profile stores

### Private settings

One record per account, kept with the learner's Matrix account and seen only by them.

- **Target language** (what they are learning) and **base language** (what they already speak). The base language is also the language of the app's menus and buttons, unless **app in target language** is on, which shows the menus in the target language instead.
- **Self-reported level.** The bot and the AI tools pitch their language to it.
- **Gender.** The bot and the AI tools use it to address the learner correctly.
- **Teacher or learner role**, chosen by the person (see [The teacher or learner role](#the-teacher-or-learner-role)).
- **Country and bio**, shown on their profile page and copied to the public profile.
- **Find me in search.** The "Allow my profile to be found in search" switch on the profile page. When it is off, or was never set, the account appears in other people's name searches, for a new chat or an invite, only if they already share a room with it ([finding-people.instructions.md](finding-people.instructions.md#who-is-findable-under-public)). It is separate from the public profile: it decides who can find the account, not what they see.
- **The date the account was created**, which sets the free-trial window.
- **Tool settings:**
  - Check a message for mistakes on send; when off, the learner taps the writing-assistance button to check.
  - Play a word's audio when it is tapped, and play audio for answer choices in practice.
  - Listen First: one tap plays a choice's audio and a second selects it ([writing-assistance.instructions.md](writing-assistance.instructions.md)).
  - Hear it first: play the sentence before the learner records in read-aloud practice.
  - Read new messages aloud, and read a message aloud when it is tapped ([message-read-aloud.instructions.md](message-read-aloud.instructions.md)).
  - Device autocorrect ([target-language-keyboard.instructions.md](target-language-keyboard.instructions.md#when-autocorrect-turns-on)).
  - Developer options, which show extra tools in settings.
- **Tutorials:** which tips the learner has dismissed, and how far they are through each tutorial ([tutorials.instructions.md](tutorials.instructions.md)).

### Public profile

Kept on the learner's Matrix user profile, published by the app from the private settings and the learner's progress.

- **Per language:** their level, the XP offset that keeps a level they have seen from dropping ([analytics-system.instructions.md](analytics-system.instructions.md#level-protection)), their banked goal total, and the id of that language's analytics room.
- **Their current target and base language.**
- **Country and bio.**

## How it is created and changed

Signing up creates the profile, and onboarding fills in the languages, level and role ([onboarding.instructions.md](onboarding.instructions.md)).

### Where settings are changed

Learning settings open from four places, each showing the same settings and saving them the same way:

1. **Settings → Learning**, the Learning page in the settings panel.
2. **A long press on the writing-assistance button**, which opens the settings as a dialog.
3. **Learning settings in the writing-assistance card's ⋮ menu**, which opens the same settings-panel page.
4. **The target-language flag beside the learner's avatar on the map**, which opens the same settings-panel page.

Inside a room, one more place changes the same profile:

5. **The bot's settings**, opened from the bot's member profile, apply in that room at once.

Country, bio and the find-me-in-search switch are changed on the profile page.

### Changing the base language

The app's menus and buttons are shown in the base language, so a new base language that would switch them asks first: "Change base language?", naming the language they will switch to, with Cancel and Change. Nothing changes until the learner taps Change. Learning settings and the onboarding language step both ask, and only when the menus would actually switch, so not while the app is shown in the target language. A target-language switch still takes effect at once ([Switching from context](#switching-from-context)).

### The teacher or learner role

The self-identified role, teacher or learner, is chosen in onboarding ([onboarding](onboarding.instructions.md)), and any account can set or change it in learning settings. Outreach outside the app reads it to tell teachers from learners, so an account that did not choose one has no role rather than counting as a learner.

When the app opens, an account with no role is asked for one, at most once a day, until it picks one. Skip for now waits until the next day. The question is never asked during onboarding, and it waits for the world-map greeting if that is still to come; an app open where it waits does not count as that day's question.

### Switching from context

Course and activity content is language-specific, but the learner's language is one setting, so a learner in several courses often meets content in another language. Switching out of that mismatch should be easy and low-stakes, and it happens **from the surface the learner is already looking at**, not from settings.

6. **The language chip is the switch.** Every surface that shows its content's language (the activity start page, a joined or previewed course's info chips, and a running session's [goal header](activity-session.instructions.md#the-goal-header)) draws it as a chip. When it differs from the learner's target, the chip is tinted in the warning colour, caution rather than achievement or failure, and tapping it opens the switcher. Nothing opens unasked: these panels reopen on nearly every move, so an automatic offer would be a notification the learner cannot turn off.
7. **The language switcher** is the same list of every target language that learning settings uses, so it behaves the same wherever it opens. The chip's language and the languages the learner has progress in come first, so the few they move between need no scrolling or search. Picking one switches at once.
8. **The send-time popup** is the backstop. Sending a message in an activity whose language differs from the learner's target offers to switch, at most once per 30 minutes per room so it does not nag, and confirming switches and sends the message. It stays because the chip is deliberately quiet: only this reaches a learner who never noticed the mismatch.
9. **The reading toolbar.** Tapping a message in another language when the chosen mode cannot work there shows a snackbar saying learning tools are off for messages not in the target language, with a "Click here to update your target language" link that switches to that language. The link is left out when the message is in the learner's base language.

**Switching to the learner's base language is refused, not attempted.** Every offer knows before it asks, so none of them offers the base language.

**A switch is cheap and loses nothing.** Each language keeps its own progress ([analytics-system.instructions.md](analytics-system.instructions.md#per-language-isolation)), so switching back finds it intact, and every switch takes effect on tap, without confirmation.

### Saving and syncing

A change reaches every device the learner is signed in on. Autocorrect's default differs by device, so each device uses its own until the learner makes a choice, and that choice then applies everywhere.

The bot's settings follow the learner's, in their own chat with the bot first and then in their other one-to-one chats with it; activity rooms keep their own.

### How the public profile stays in sync

The public profile is a copy the app publishes from the learner's own settings and progress so that other people can see it. The learner's own numbers always come from their device, and the published copy can lag behind them.

- **INVARIANT: NEVER publish a profile under an account other than the one it was loaded for.**
- **Country and bio** are copied on every settings change, exactly: clearing one removes it.
- **Level** is published for a language when the learner earns XP in it. The one exception is startup: when the published copy has no level data, the current language's level is worked out on this device and published. Otherwise nothing republishes a level at startup, so a level left wrong by an earlier bug stays wrong until the learner next earns XP in that language, a gap accepted deliberately. A level belongs to the language, not to a regional variant: every variant of French shares French's one level, shown on French's row only, since a level beside each variant would read as separate progress the learner does not have.
- **The banked goal total** counts activity goals, drawn as a goal diamond ([quests.instructions.md](quests.instructions.md#stars-and-goal-diamonds)): each activity's best saved run, in the language it was played in. It is not a course total, because what a course total means depends on the course. It is republished for the language being studied; the others stay as they are until the learner studies them again. It only rises, so a count that comes out low on one device never lowers it. It also keeps the stars from a session room the learner has left, so classmates can see more than the learner's own count. That is accepted: the app offers no way to leave one, and those stars were earned.

## What other people can see

Only the learner sees their private settings. Anyone who shares a room with them can read the whole public profile: their level and XP in each language, their banked goal total, their country and bio, their current languages and their analytics room ids. The level is the one computed from their activity, never the self-reported one.

Someone who does not share a room with the learner can find them by name, to start a chat or send an invite, only if the learner turned on find me in search.

## Open questions

- **The startup level publish.** The published copy counts as having no level data when it lacks the learner's base or target language, even if levels are already published, so the startup publish can replace a real level with one from this device, which may have incomplete data. Should it publish only when that language truly has no level?
