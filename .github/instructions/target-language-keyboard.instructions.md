---
applyTo: "lib/features/keyboards/**,lib/routes/chat/chat_input_bar.dart,lib/routes/chat/composer_keyboard_context.dart,lib/routes/chat/input_bar.dart,lib/routes/chat/keyboard_prompt_banner.dart,lib/routes/settings/settings_learning/enable_autocorrect_dialog.dart,lib/routes/settings/settings_learning/autocorrect_settings_tile.dart,pangea_packages/keyboard_languages/**,pangea_packages/text_input_context/**"
description: "Getting the learner typing in their target language — how each platform's keyboard is pointed at the L2, what we can detect about the learner's keyboards, and the two-step prompt for a missing or unused one."
---

# Target Language Keyboard (Client)

A learner typing their target language on a first-language keyboard gets their L2 quietly turned into misspellings by autocorrect. Two things have to be true to prevent that: the keyboard has to be pointed at the target language, and the learner has to actually have — and be using — a keyboard for it. This doc covers both.

The autocorrect setting itself, and how the learner's choice syncs across devices, is owned by [profile.instructions.md](profile.instructions.md).

## Pointing the keyboard at the target language

Neither platform lets an app choose the keyboard language outright, so each gets the closest thing it offers.

- **Android** — the composer tells the keyboard which language the learner is writing in, and the keyboard switches and corrects in it automatically. Nothing is asked of the learner.
- **iOS** — no equivalent exists, so we use memory instead of instruction. iOS restores the keyboard language a learner last chose for a text field it recognises, and the composer is given an identity it recognises, keyed per target language and persisting across chats and app launches. The learner switches keyboards once, by hand; every later visit to the composer comes back in that language. Switching target language starts a fresh memory rather than inheriting the previous language's keyboard.

That identity is scoped to the composer alone, so search, display name, and password fields keep the device default. It is also fragile in one specific way: iOS discards the memory for any field whose input mode the app sets directly, so the composer's input mode is **read, never assigned**.

The consequence that shapes everything below: on Android a learner with the right language pack is done automatically, while on iOS they must make one manual switch before the memory has anything to remember.

## What each platform tells us

| | Which keyboards the learner has | Which keyboard is live right now | Sending them to keyboard settings |
| --- | --- | --- | --- |
| **Android** | Yes — each enabled keyboard and the language packs within it, so we can tell a learner has Gboard but not its Spanish pack. | Not needed; the composer redirects the keyboard itself. | Yes — a public system intent opens keyboard settings, and a second opens the language list for one keyboard. |
| **iOS** | Yes — every keyboard the learner has enabled, each tagged with a language. | Yes — the keyboard attached to the focused composer, and a system signal when the learner switches with the globe key. | No. Apple offers no public link into keyboard settings, and the private one risks App Store rejection. We open the Settings app and print the path, matching the [read-aloud voice popup](message-read-aloud.instructions.md). |
| **Web** | Not applicable — autocorrect never runs on web. | — | — |

Detection is **advisory**. It exists to suppress a prompt the learner doesn't need, never to gate typing. Where a platform reports nothing usable, treat the learner as already equipped and stay silent — a missed prompt costs one learner some autocorrect, while a wrong prompt nags every learner on every device we misread.

A learner with a Latin-American Spanish keyboard and a target language of Spanish is equipped, so matching compares only the **primary language subtag** and ignores region and script. Emoji and dictation entries are reported alongside real keyboards and are filtered out first. The answer changes while the app is backgrounded — that is the point, since we send the learner to Settings and they come back — so the check re-runs on resume rather than being cached for the session.

## The prompt ladder

Getting equipped is two steps on iOS and one on Android, and each step is shown only to a learner who has not already completed it.

| What we can see | Android | iOS |
| --- | --- | --- |
| No keyboard matching the target language | **Add the keyboard** | **Add the keyboard** |
| Has the keyboard, composer not using it | Nothing — the composer redirects automatically | **Switch to it with the globe key** |
| Composer running a target-language keyboard | — | Nothing. Resolved. |

A learner who already owns the keyboard never sees the first step, and one who has already switched sees nothing at all. The second step clears itself the moment the learner switches, so it needs no dismissal to go away.

**Delivery.** Each step appears as a dismissible inline tooltip directly above the composer, using the same instruction-tooltip treatment as the rest of the app, from the first time the learner focuses a composer that targets their L2. The chat input row gains nothing — it is the most contested space on a narrow screen. **A modal never opens on its own**; the tooltip carries an action, and only tapping it opens the dialog that walks the learner the rest of the way. Dismissal is remembered per target language, so changing L2 asks again.

The autocorrect toggle in learning settings keeps its own dialog as the deliberate path, for a learner who goes looking, but it is no longer how anyone is expected to find this. Android defaults autocorrect on, so that dialog only ever fires for a learner who turns the setting off and back on — the people who most need it are the ones who never see it.

## When autocorrect turns on

On Android, autocorrect is safe by default: even with no language pack, the composer points the keyboard at the L2. On iOS there is no such redirect, so autocorrect with an English-only keyboard is worse than no autocorrect at all — it corrects the learner's Spanish into English. Being shown a prompt is not evidence the learner acted on it.

So iOS autocorrect stays off until we have **observed the composer running a target-language keyboard**, and turns on then. Where that observation is unavailable, it stays off and the ladder still runs — the learner can switch it on themselves once they are equipped.

Changing target language clears the stored choice rather than carrying it over, returning the setting to its platform default so the ladder is free to run again. A learner equipped for Spanish is not necessarily equipped for Japanese, and a choice made about one language says nothing about the next.
