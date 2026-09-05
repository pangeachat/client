---
applyTo: "lib/pangea/choreographer/**"
---

# Writing Assistance — Design & Architecture

Writing assistance is a friendly, non-judgmental helper that quietly reviews what the user types and offers suggestions. It must never feel like error correction — it's a learning companion.

> **⚠️ IT (Interactive Translation) is deprecated.** Do not add new IT functionality. Translation will become a match type within writing assistance.

## Design Intent

### Core Principle: Helper, Not Judge

Playtest feedback consistently shows users perceive writing corrections as errors or punishments. The redesign addresses this by:

1. **Removing all accept/reject language** — no "Ignore" or "Replace" buttons. The user simply views suggestions and optionally taps a choice.
2. **Using warm, varied colors** — each match type gets a distinct, fun color (not red/orange "error" tones). Colors signal category, not severity.
3. **Making interaction optional** — viewing a suggestion is enough. The user can send their message at any point, even with unviewed suggestions.
4. **Reusing a single popup** — one persistent span card that updates its content as the user navigates between matches, eliminating the jitter of opening/closing overlays.

### Target User Perception

> "Oh, my writing assistant noticed a few things. Let me take a look… ah, I see. Cool."

Not:

> "I made 3 errors and need to fix them before I can send."

---

## Assistance Ring (replaces StartIGCButton)

The current `StartIGCButton` is updated to display a **segmented ring**, indicating match states.

### Ring Behavior

- The ring's outer edge divides into **one segment per match** returned by the server.
- Each segment's **color** corresponds to its match's `ReplacementTypeEnum` color category.
- Segments have two opacity states:
  - **Bright (full opacity)** — match not yet viewed.
  - **Muted (low opacity)** — match has been viewed (or was auto-applied).
- **AutocorrectPopup retained** — when surface corrections are auto-applied, the existing `AutocorrectPopup` briefly appears to draw attention to the change. This ensures auto-applied edits aren't silently swallowed. The popup is the same toast-like overlay currently used.
- The ring is a **status indicator only** — tapping it does not navigate between matches. Users navigate by tapping highlighted text in the input field.

### Icon States

| State           | Icon Behavior                                  |
| --------------- | ---------------------------------------------- |
| Idle / no text  | Grey check icon with 5 grey segments                       |
| Fetching        | Segments spin, check is hidden                    |
| Matches present | Ring segments visible |
| Zero matches    | Check visible, **solid green ring**  |
| Input cleared   | Ring **animates out**, returns to idle          |
| Re-fetch        | Icon **spins again**, old segments cleared      |
| Error           | error indicator (TBD) |

The ring **animates in** when segments first appear and **animates out** when the input field is cleared. When the user edits text and triggers a re-fetch, the icon spins again and old segments are discarded — the new response rebuilds the ring from scratch.

### What We're Removing

- The `autorenew` spinning icon
- The elevation/shadow changes based on state

---

## Text Highlighting

Matched text in the input field uses **background highlights** (not just underlines) with the same color system as the ring segments.

### Highlight Behavior

- **Unviewed matches**: Highlighted with **bright (full opacity)** background in the match's category color.
- **Viewed matches**: Highlighted with **muted (low opacity)** background after the user has opened and navigated away from the span card for that match.
- **Accepted matches**: Text is replaced. The highlight remains bright. The user can tap it again to revisit and undo.
- **Auto-applied matches**: Text already replaced. Highlighted bright immediately.

### Color Palette

Each `ReplacementTypeEnum` category gets a distinct, friendly color. Colors should feel varied and playful — not a gradient from "fine" to "bad." Examples of the spirit (exact values TBD in implementation):

| Category             | Color Spirit      |
| -------------------- | ----------------- |
| Grammar              | Coral / warm pink |
| Word choice          | Sky blue          |
| Style / fluency      | Lavender          |
| Surface (auto-apply) | Mint green        |
| Translation          | Amber             |

---

## Span Card (Redesigned)

A single, persistent popup that changes content as the user taps different highlighted matches. No open/close animation between matches — the card stays in place and its content transitions smoothly.

### Positioning

The card positions itself relative to the currently selected match's highlighted text. When the user taps a different match, the card **animates smoothly** to the new position (slide + content crossfade) rather than jumping. The animation should feel fluid and natural — not snapping or teleporting. If the message is short and all highlights are close together, the movement will be subtle. For long messages where highlights are far apart, the card glides to follow.

### Layout

```
┌─────────────────────────────────┐
│  ✕   Edit Category Title  🎧 ⋮ │  ← Header: close, category name (e.g. "Verb Conjugation"), Listen First, menu
│                                 │
│  🤖  Hint text explaining the   │  ← Bot face left-aligned, hint text beside it
│      suggestion in detail       │
│                                 │
│  ┌──────┐ ┌──────┐ ┌──────┐    │  ← Choices: horizontal if they fit,
│  │ word │ │ word │ │ undo │    │     vertical if not. Undo action at end.
│  └──────┘ └──────┘ └──────┘    │
│                                 │
│  💡 Listen First explainer   ✕  │  ← Only while Listen First is on, until dismissed
└─────────────────────────────────┘
```

**When the header runs out of room**, Listen First folds into the menu too, so the category name keeps its full width:

```
┌─────────────────────────────────┐
│  ✕   Subject Verb Agreement  ⋮  │  ← Listen First joins the menu
└─────────────────────────────────┘
```

**When revisiting an already-accepted match**, the choices row is replaced with a compact diff view:

```
┌─────────────────────────────────┐
│  ✕       Edit Category Title   🚩 │
│                                 │
│  🤖  Hint text                   │
│                                 │
│  original → replacement    ↩    │  ← Shows what changed + undo icon
└─────────────────────────────────┘
```

### Interaction Model

1. **User taps highlighted text** → Span card appears (or updates content if already open) showing that match's hint and choices.
2. **User reads the suggestion** → Once they navigate away (tap different text, tap close, or tap outside), the match is marked **viewed**. Its highlight and ring segment become bright.
3. **User taps a choice** → If the choice is the best replacement, the text is replaced, the match is marked **accepted**, and the card advances to the next unviewed match (or closes if none remain). If not, the choice is marked as selected and the user gets the feedback of the color change of the choice. They can click it again to do it anyway. "alt" choices should appear as a lighter green. "distractors" should appear as red.
4. **User taps the undo action** → Reverts to the original text for that match. The match returns to `viewed` status (bright, but choices shown again instead of diff view). Undo is available per-match (not just most-recent) because **spans never overlap** — each match targets a unique, non-overlapping substring.
5. **User taps an already-accepted match's text** → Span card reopens showing `original → replacement` with an undo icon, instead of the choices row. Tapping undo reverts the text and restores the full choices view. This is identical for auto-applied matches — tapping a bright auto-applied highlight opens the same diff view with undo.
6. **User taps close (✕)** → Card closes. Match is marked viewed.

> **Open question — auto-advance viewing**: When the user accepts a choice and the card auto-advances to the next match, does that brief display count as "viewed"? Try the current behavior in practice and adjust if users feel they're missing content.

> **Open question — text re-editing**: If the user edits text after matches have been returned (e.g., types more, backspaces into a matched region), what happens to existing matches? Current behavior is to re-fetch. Consider whether partial invalidation is worth the complexity or if a full re-fetch on significant edits is acceptable.

### Hearing a choice

Learners who know a language by ear before they know its script cannot tell the choices apart on sight, and the only way to hear one is to tap it — which also answers with it. **Listen First** is the mode that separates the two. While it is on, one tap on a choice plays it and changes nothing; a second tap on the **same** choice, inside the platform double-tap window, selects it. With it off, a tap selects as it always has.

The mode is an icon-only toggle in the card header, next to the flag — on or off, no third state, off until the learner turns it on.

- **It is remembered, per learner, across matches and sessions.** Knowing a language by ear is a property of the learner, not of one correction; resetting it per match made them re-arm it on every highlighted word. The visible header toggle is what keeps a remembered mode from being an invisible one.
- **Only the same choice arms.** The second tap has to land on the choice the first one played — tapping a different choice plays that one instead and arms nothing — and a tap after the window has closed replays rather than selects. Both failures cost a replay, never a wrong word in the message, which is the direction this mode exists to fail in.
- **The mode only appears where there are choices to hear.** An accepted match shows a diff and an undo, so the header drops the toggle rather than offering a mode that applies to nothing.
- Listening never changes a match's status. A match still becomes `viewed` by being opened and navigated away from.
- The explainer under the choices is a **dismissable instruction tooltip** ([`InstructionsEnum.listenFirst`](../../lib/features/instructions/instructions_enum.dart)) — it teaches the one-click/double-click split once and then stays gone, rather than taxing the card's height for every learner who already knows.
- With choice audio switched off in learning settings, the toggle opens the same "audio is off" popup other explicit audio buttons do, pointing at the setting, rather than entering a mode that plays nothing — and stores nothing, since being told why you can't have the mode is not choosing it. See [word-text-to-speech.instructions.md](word-text-to-speech.instructions.md).
- Only writing assistance gets the mode. The choices row is shared with practice and activity surfaces; their behaviour is unchanged.

**Where it is set.** Two surfaces write one stored value (`ToolSetting.listenFirst`), so they cannot disagree: the card's header toggle, and a row in the **Audio** section of learning settings, next to the Choices audio it sequences. The settings row is disabled, with the reason in place of its description, whenever Choices audio is off — from settings there is no popup to open, so the tile carries the dependency itself rather than flipping into silence.

### Header actions and width

The header carries the category name and, on the right, the Listen First toggle and a `⋮` overflow menu.

**Listen First is the only action with a place in the header itself.** It is the one a learner flips *while reading this card*, so it has to be one tap away. Everything else the card offers is a trip out of it — turn the whole feature off, report this content, open the settings page — and a trip can afford a menu. The menu is always present; there is no flag icon in the header any more, and reporting is one of its entries.

The menu holds, in order:

| Entry | Kind |
| --- | --- |
| **Listen first** | Mode, checked when on — present only when it has folded in from the header, and only on a match that has choices |
| **Enable writing assistance** | Mode, checked when on — the same `autoIGC` toggle learning settings owns, so a learner handed a card they did not want can stop it from where they are |
| **Report content issue** | Action — the feedback dialog |
| **Learning settings** | Action — opens the learning settings page |

The name is what the learner opened the card to read and it is the part that grows — "Subject Verb Agreement" leaves no room for the toggle on a phone where "Spelling" leaves plenty — so **the toggle yields to the title, not the reverse**: when the measured title cannot sit beside both the toggle and the menu, Listen First folds into the menu.

The trigger is the measured width of this title in this card at this text scale, not a device breakpoint. A fixed breakpoint gets both cases wrong at once — it hides the toggle on a short title that had room, and keeps it on a long one that didn't — and a learner scaling their text up moves the line again.

**The anchor id is per match.** The "audio is off" popup positions itself against a `GlobalKey` that [`PangeaAnyState`](../../lib/features/overlay/any_state_holder.dart) caches by id and never evicts, so a constant id is claimed by every header that ever mounts — and two are mounted at once whenever one card is torn down while its replacement builds. That is a duplicate-`GlobalKey` throw on every rebuild, which the learner sees as a flashing red screen. Whichever control currently shows Listen First holds the anchor; never both.

### What We're Removing

- "Ignore in this text" button
- "Replace" button
- The entire bottom button row
- Per-match overlay creation/destruction (single reusable card instead)

### What We're Keeping

- Close button (✕)
- Bot face icon (now left-aligned next to hint text)
- Edit category as header title (e.g. "Verb Conjugation", "Word Choice")
- Flag button (feedback)
- Choices array (with responsive horizontal/vertical layout)
- Hint/explanation text

---

## Match Lifecycle

Matches no longer require explicit accept/ignore. The lifecycle simplifies to:

| Status      | Meaning                                                 | Ring/Highlight        |
| ----------- | ------------------------------------------------------- | --------------------- |
| `automatic` | Auto-applied on arrival (punct, diacritics, spell, cap) | Bright immediately    |
| `open`      | Server-returned, not yet viewed                         | Muted                 |
| `viewed`    | User opened the span card and navigated away            | Bright                |
| `accepted`  | User tapped a choice, text replaced                     | Bright                |
| `undone`    | User reverted an accepted match                         | Bright (still viewed) |

The `ignored` status is removed — viewing is sufficient. The message is sendable at any point regardless of match status.

---

## Sending

The user can send at any time. There is no gate on unresolved matches.

- **Send button** remains separate from the assistance ring (to the right of it in the input row).
- On send, the choreographer tokenizes the final text and saves a `ChoreoRecordModel` with the message, recording which matches were viewed, accepted, or left open.

---

## Feedback System

Unchanged from current design. When the user taps the flag (🚩) on the span card:

- They can submit feedback text and a score (thumbs up/down maps to 10/0).
- The server audits the suggestion, escalates the model if rejected, and persists the judgment for fine-tuning.
- Native speaker approval (score 9–10) caches the response without regeneration.

---

## Match Type Categories

Categories returned by `/grammar_v2`. Each gets a distinct color in the ring and text highlights:

| Category                | Types                                                                                                                                                                                                                                                           | Behavior                                                 |
| ----------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------- |
| **Grammar** (~21 types) | verb conjugation/tense/mood, agreement (subject-verb, gender, number, case), article, preposition, pronoun, word order, negation, question formation, relative clause, connector, possessive, comparative, passive voice, conditional, infinitive/gerund, modal | Highlight + ring segment, user-viewable                  |
| **Surface**             | punct, diacritics, spell, cap                                                                                                                                                                                                                                   | **Auto-applied**, bright immediately, undo via span card. Hint text displayed only if server provides one (non-null) — omitted for obvious corrections, included when pedagogically useful (e.g. explaining an accent rule). |
| **Word choice**         | false cognate, L1 interference, collocation, semantic confusion                                                                                                                                                                                                 | Highlight + ring segment, user-viewable                  |
| **Style / fluency**     | style, fluency, didYouMean, transcription, translation, other                                                                                                                                                                                                   | Highlight + ring segment, user-viewable                  |

---

## Architecture

```
Choreographer (ChangeNotifier)
├── PangeaTextController           ← Extended TextEditingController (tracks edit types)
├── IgcController                   ← Grammar check matches (primary flow)
├── ChoreographerErrorController    ← Error state + backoff
└── ChoreographerStateExtension     ← AssistanceStateEnum derivation
```

### Flow Summary

1. User types → debounce → `/grammar_v2` request
2. Response returns matches → auto-apply surface corrections, display the rest
3. Ring segments and text highlights appear (muted)
4. User taps highlights to view suggestions, optionally accepts choices
5. Viewed matches become bright
6. User sends when ready — no gate on unresolved matches
7. On send: tokenize final text, save `ChoreoRecordModel` with match history

### API Endpoints

| Endpoint                        | Status                                   |
| ------------------------------- | ---------------------------------------- |
| `/choreo/grammar_v2`            | ✅ Active — primary writing-assistance endpoint |
| `/choreo/tokenize`              | ✅ Active — tokenizes final text on send |
| `/choreo/span_details`          | ❌ Dead code — remove                    |
| `/choreo/it_initialstep`        | ⚠️ Deprecated — remove with IT           |
| `/choreo/contextual_definition` | ⚠️ Deprecated — remove with IT           |

---

## Deprecated: Interactive Translation (IT)

> **Do not extend. Scheduled for removal.**

The `it/` directory, `ITController`, and all IT-related code (`it_bar.dart`, `it_feedback_card.dart`, `word_data_card.dart`, `choreo_mode_enum.dart`) will be removed. Translation will become a match type within writing assistance.

---

## Future Work

- **Cycling placeholder text** in the input bar ("Type in English or Spanish…") to teach users they can write in L1 ([#5653](https://github.com/pangeachat/client/issues/5653))
- **Color palette finalization** — exact hue/opacity values for each match category
- **Ring animate in/out** — entrance animation when segments appear, exit when input cleared
- **Ring segment muted→bright transition** — per-segment animation when a match is viewed
- **Span card slide animation** — fluid positional slide + content crossfade when switching between matches
- **Accessibility badge** — small unviewed-count badge on the Pangea Chat icon
- **Analytics events** — track span card views, choice selections, and undo actions in Firebase Analytics
- **`to_replace` migration** — the current offset-based span targeting is more brittle than the server's unique `to_replace` substring system. Consider migrating the client to identify spans by `to_replace` text rather than character offsets. This is a large change because legacy span data stored in saved JSON events would need `fromJson` migration.
