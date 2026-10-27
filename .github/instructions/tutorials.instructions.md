---
applyTo: "lib/features/tutorials/**,lib/features/instructions/**"
description: "Which click-through tutorials a learner is offered, in what order and when, and how a tutorial card behaves."
---

# Tutorials (Client)

## Purpose

A tutorial is a short guided overlay: the screen darkens around what is lit, and the bot says one thing per card. Playtesters finished onboarding not knowing what to do ([#8184](https://github.com/pangeachat/client/issues/8184)), so tutorials lead a new learner to a first real action; short and few beats thorough. Orientation tutorials teach the app; feature tutorials teach a paid AI tool when relevant.

## The experience

1. On first reaching the map or a course, the bot greets the learner with one target-language word to tap and collect, once ever.
2. On the world map, one card shows the map, the next lights an easy activity; a tap opens it.
3. In a course, one card welcomes the learner.
4. On an activity's start page, the open-sessions list and role picker each get one card.
5. After a first finished activity, the next map visit offers a tour of Chats, Courses, Analytics, Practice and World; World hands a course-code arrival to the world-map tutorial.
6. In chat, the first target-language message with a new word starts the reading- and writing-assistance tutorials.

## Decisions

By who re-decides them.

### Ava: world map, courses and roles

- **Every learner gets both the world-map and course tutorials.** The map holds every activity in the language; a course is a path through them with classmates.
- **Nothing orients inside the activity chat.** The goals bar explains itself, and a card there interrupted play.
- **The course card shows only on a joined course's page.** A preview has no progress to explain.
- **The world-map card picks the lowest-level two-person activity, preferably not in play, with its pin at least medium-sized.** The bot fills one seat, so only two-person activities start alone; the easiest teaches best; a tiny dot is hard to tap. With none, the card is skipped.
- **The map introduction isn't darkened, and first closes open panels.** Darkening would hide what it describes.
- **The role-picker card leaves the choice to the learner.** Tapping a role picks it and closes the card; tapping elsewhere only closes it. Either way it's seen; re-showing felt repetitive.

### Gabby: chat tools

- **Feature tutorials need a subscription.** A paid tool taught to someone who can't use it is a dead end.

### Unassigned

- **Orientation is free; tour stops at paid screens show their unlock page.** A lost learner won't subscribe.
- **Never on an empty or still-loading screen.** Pointing at nothing is worse than nothing.
- **Veterans skip what they have already lived.** An account with a finished activity at sign-in skips the greeting, map, tour and role tutorials, which annoyed veterans; the rest may be new. Accepted: a reset then sign-out re-skips them; leaving every old activity room makes an account look new.
- **The tour comes before the map introduction, never before the greeting.** The tour answers "what now?", but "great job!" before any hello (after a reset, or on a pre-tutorial account) seems forgetful.
- **Skip ends the whole walkthrough, named beside it.** The learner refused the walkthrough, not the card; the name tells consecutive ones apart.
- **No Skip on a single-card run (skipping is finishing), the greeting (Skip there is ambiguous), or the tour offer (its "no" is the skip).**
- **Walking away keeps the learner's place; only finishing or skipping counts as done.**
- **One walkthrough at a time; later ones wait, even behind a start-page card.** There is one spotlight; a dropped one never appears.
- **A card does what it describes only when plainly wanted; otherwise it just shows.** The tour's Practice stop only shows: Practice unlocks at ten words.
- **If a card's target goes off screen, the card closes and returns with it.**
- **A card sits on the thing it describes.** Centred beside a course panel, it would seem the map's.
- **Accepting the tour clears to the map so every stop shows; declining changes nothing.**
- **The tour offer's answer is recorded:** the feature's best signal.
- **The greeting word is the app's existing, already-translated "Welcome!", above the sentence, not inside it.** It needs no new translation or AI call; inside, it would force English word order.
- **The greeting always shows,** as plain text if the word can't be looked up, styled new only if word analysis says so.
- **The open-sessions card behaves like the role picker's;** tapping a session joins it.

### Accessibility

- **Screen-reader and keyboard users can do everything a tap does.** The message is the continue button (no Next button), and a start-page card leaves its lit target reachable. Trapping a screen-reader user blocks launch ([accessibility](accessibility.instructions.md)). Unassigned.
