---
applyTo: "lib/routes/chat/choreographer/**"
description: "What writing assistance decides: the ring, the marked words, the card and its Listen First mode, and what a sent message keeps."
---

# Writing Assistance

## Purpose

Writing assistance checks what a learner types in chat and offers suggestions they may take. It is a helper, not error correction: the learner should think "my assistant noticed a few things", not "I made three errors and must fix them before I can send". Redesign: [#5655](https://github.com/pangeachat/client/issues/5655).

## The experience

1. Soon after the learner stops typing, the ring beside send spins while the message is checked.
2. Each thing the check noticed, a match, gets a ring segment and a mark on its words; with none, the ring turns green. Punctuation, accents and capitals are already fixed.
3. Tapping marked words opens the card above the composer: category, hint, choices. Tapping another mark changes what it shows.
4. A right choice goes into the message and the card moves to the next undecided match, closing after the last. Any changed match, not only the latest, reopens with an undo.
5. In activities, an empty composer may offer a suggested next message under a lightbulb named "Suggestion".

## Decisions

- No accept or reject language or buttons; viewing is enough, and matches on screen never stop a send, since playtests showed learners read corrections as errors or punishment. Unassigned.
- With Autocheck on send, sending unchecked text checks it first and opens the card on any match; the next press sends. Unassigned.
- Colour follows the [design tokens](design-tokens.instructions.md): red where the card holds a wrong choice to avoid, the primary colour where every choice is right, green once resolved. Unassigned.
- A match is bright until the card has shown it, then faint; on the ring, accepted and fixed matches stay bright green to show progress. Unassigned.
- One card, in one slot above the composer that the suggestion card shares; switching matches slides its content, so one thing changes instead of popups opening and closing. Unassigned.
- The ring is a shortcut as well as a status: a tap checks the message, opens the first undecided match or the suggestion, re-checks after a clean result, or explains an error or the paywall. It lifts when tappable. Unassigned.
- Punctuation, accents and capitals fix themselves; spelling stays a suggestion, since fixing it automatically was too helpful. A fixed word stays marked, so no edit is silent, and tapping it shows the original and an undo. Unassigned.
- Best and alternative choices go in on the first tap, in green; a distractor turns red, and a second tap applies it anyway. [#9423](https://github.com/pangeachat/client/issues/9423) would change this. Unassigned.
- A match counts as viewed once the card shows it; after a choice, the card moves to the next undecided match, even one already seen. Unassigned.
- With no hint from the server, the card asks for the best replacement. Unassigned.
- A report is free text, which reruns the check; there is no score. Unassigned.
- Any typed edit clears the matches and re-checks the whole message; partial re-checking is not worth its complexity. Unassigned.
- Typing withdraws a suggestion, so its choices never sit over a message the learner chose to write; an accepted one confirms, then closes. Unassigned.
- Listen First: one tap plays a choice and a second tap on the same one selects it, for learners who know a language by ear; a slip costs a replay, never a wrong word. Unassigned.
- Listen First is off until turned on, then remembered: it belongs to the learner, not one correction. It appears only where writing assistance offers choices, and hearing a choice changes nothing. Unassigned.
- Listen First is the header's only button, since it is flipped while reading; actions leaving the card sit in a menu, which Listen First joins when a long category name needs room. Unassigned.
- Listen First is one setting, reached from the card or learning settings; with choice audio off it [says why](word-text-to-speech.instructions.md) it cannot turn on. Its explainer shows once. Unassigned.
- Everything writing assistance puts in the composer, pastes and accepted suggestions included, is saved with the message, or later scores as self-written. Unassigned.
- A message moderation refuses returns to the composer, with a dialog saying why, unless the learner has started another. [Server side](../../../synapse-pangea-chat/.github/instructions/moderation.instructions.md). Unassigned.
- Analytics counts only translation matches as translation and the rest as grammar correction, a known gap for word choice and style ([.github#479](https://github.com/pangeachat/.github/issues/479)); older messages keep their scores. Unassigned.
- Interactive translation is retired, not to be extended: translation is a match type, and old messages carrying its steps are still read. Unassigned.
