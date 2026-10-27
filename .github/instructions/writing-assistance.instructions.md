---
applyTo: "lib/routes/chat/choreographer/**"
description: "What writing assistance decides: the ring, the marked words, the card and its Listen First mode, and what a sent message keeps."
---

# Writing Assistance

## Purpose

Writing assistance checks what a learner types in chat and offers suggestions they may take. It is a helper, not error correction: the learner should think "my assistant noticed a few things", not "I made three errors and must fix them before I can send". Redesign: [#5655](https://github.com/pangeachat/client/issues/5655).

## The experience

1. Soon after the learner stops typing, the ring beside send spins while the message is checked.
2. Each match gets a ring segment and a mark on its words; with none, the ring turns green. Small surface fixes are already applied.
3. Tapping marked words opens the card above the composer: category, hint, choices. Tapping another mark changes what it shows; a match left behind counts as viewed.
4. The best choice goes into the message and the card moves on, closing after the last match. Any changed match, not only the latest, reopens with an undo.
5. In activities, an empty composer may offer a suggested next message under a lightbulb named "Suggestion".

## Decisions

- No accept or reject language or buttons; viewing is enough and sending always allowed, since playtests showed learners read corrections as errors or punishment. Unassigned.
- Colour shows a suggestion's kind, never its severity: a warm colour per category, never error red or orange. Unassigned.
- One card, in one slot above the composer that the suggestion card shares, so one thing changes instead of popups opening and closing. Unassigned.
- The ring only shows status; tapping marked words moves between matches. Unassigned.
- Punctuation, accents, capitals and spelling fix themselves, with an undo, a hint only when it teaches, and a brief notice so no edit is silently swallowed. Unassigned.
- A wrong choice first changes colour (alternatives lighter green, distractors red); a second tap applies it anyway. [#9423](https://github.com/pangeachat/client/issues/9423) would change this. Unassigned.
- Typing withdraws a suggestion, so its choices never sit over a message the learner chose to write; an accepted one confirms, then closes. Unassigned.
- Listen First: one tap plays a choice and a second tap on the same one selects it, for learners who know a language by ear; a slip costs a replay, never a wrong word. Unassigned.
- Listen First is off until turned on, then remembered: it belongs to the learner, not one correction. It appears only where writing assistance offers choices, and hearing a choice changes nothing. Unassigned.
- Listen First is the header's only button, since it is flipped while reading; actions leaving the card sit in a menu, which Listen First joins when a long category name needs room. Unassigned.
- Listen First is one setting, reached from the card or learning settings; with choice audio off it [says why](word-text-to-speech.instructions.md) it cannot turn on. Its explainer shows once. Unassigned.
- Everything writing assistance puts in the composer, pastes and accepted suggestions included, is saved with the message, or later scores as self-written. Unassigned.
- A message moderation refuses returns to the composer, with a dialog saying why, unless the learner has started another. [Server side](../../../synapse-pangea-chat/.github/instructions/moderation.instructions.md). Unassigned.
- Analytics counts only translation matches as translation and the rest as grammar correction, a known gap for word choice and style ([.github#479](https://github.com/pangeachat/.github/issues/479)); older messages keep their scores. Unassigned.
- Interactive translation is retired, not to be extended: translation is a match type, and old messages carrying its steps are still read. Unassigned.

## Open questions

Where this doc and the app disagree. Unassigned.

- Brightness: the doc said both that unviewed matches are bright and viewed muted, and the reverse; the app does the first, keeping accepted and fixed words bright on the ring only.
- Colour: the app underlines corrections red, as the design-tokens doc also says, and alternatives and fixes in the primary colour.
- Surface fixes: spelling stopped fixing itself (#5887); the notice shows only when tapped; a fix without a hint gets a generic one.
- Alternatives apply on the first tap, in the best choice's green.
- The card stays above the composer rather than following the selected words, with no bot face or undo beside the choices.
- Moving on: does the card's brief stop on the next match count as viewing it? It also stops on viewed matches.
- Tapping the ring checks the message or opens the first match, the suggestion or an error (whose look was never decided); it still lifts when tappable.
- Reporting takes text, no thumbs up or down.
- With Autocheck on send, sending an unchecked message first checks it, opening the card on any match.
- Editing re-checks the whole message; is partial re-checking worth it?
