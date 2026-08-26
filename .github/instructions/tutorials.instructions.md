---
applyTo: "lib/features/tutorials/**,lib/features/instructions/**"
description: "Click-through tutorials — the sequence/step/target model, the two state layers, the four step kinds, the one-sequence-at-a-time rule, and the two orientation paths (world-first and course-first) every learner takes."
---

# Tutorials (Client)

A **tutorial** is a short guided overlay: the screen darkens, one or more on-screen targets stay lit, and the bot says one thing per step. They exist because playtesters finish onboarding, land on the map, and cannot tell what to do next ([#8184](https://github.com/pangeachat/client/issues/8184)). So a tutorial's job is to get the learner to their **first real action** — not to explain the app. Short and few beats thorough.

Two kinds, and the distinction decides who is offered them:

- **Orientation** — teaches the app itself: where things are, what to do first.
- **Feature** — teaches one paid AI tool, at the moment it becomes relevant.

## Vocabulary

| Term | Meaning |
|---|---|
| **Step** | One tooltip over one lit target. |
| **Tutorial** | An ordered list of steps under one persisted "seen" flag ([`TutorialEnum`](../../lib/features/tutorials/tutorial_enum.dart)). |
| **Sequence** | An ordered list of tutorials the learner walks as one run, under one progress counter ([`TutorialSequences`](../../lib/features/tutorials/tutorial_sequences.dart)). |
| **Target** | An on-screen widget addressed by a string id. The widget registers the id; the overlay punches the spotlight there and anchors the tooltip to it. |

Target ids are named constants beside the widget that registers them, never inline strings, so a step and its target are findable from each other. A step may have **no** target: the welcome message is about the app rather than about anything on screen, so it renders as a centered bot card over the darkened screen with no spotlight punched at all.

**A tutorial's step count is derived from its steps, in one place.** It used to be declared three times — the enum, the tooltip sizes, the copy list — and had already drifted: the writing-assistance tutorial carried a second step that could never run. Four new tutorials are four more chances to drift, so there is one declaration.

## Two layers of state

- **Runtime** — [`TutorialOverlayStateMachine`](../../lib/features/tutorials/tutorial_overlay_controller.dart) holds which tutorial and step is showing and whether a step is mid-transition, and moves only through dispatched events. It is built over **only the tutorials this learner will actually see**, so the `n / total` counter never promises steps that are already seen.
- **Persisted** — per tutorial, a **seen** flag and a **resume step**, on the learner's Pangea profile ([`InstructionSettings`](../../lib/features/instructions/instruction_settings.dart)). Each forward advance saves the next step; reaching the end sets seen and clears the resume point.

**Abandonment keeps progress but not completion.** A tutorial the learner walks away from — navigating off, closing the screen — resets without being marked seen, so it is offered again from the saved step. Only finishing it, or the one explicit exit (the app tour's *Explore myself*), marks it seen. There is no skip control: a tutorial this short is cheaper to walk than to decide about.

## One sequence at a time

The spotlight is a single overlay, and the app refuses to open **any** overlay while a blocking one is up. Two sequences can therefore never share the screen, whatever else changes — so rather than let hosts discover that by fighting over it, **the controller is app-scoped**: one controller, owned where the overlay registry itself lives, running at most one sequence. A request that arrives while another sequence is running is **queued, not dropped**.

A second controller would contend for the same overlay key and the loser would silently fail to launch, which is why there is exactly one. It is also what lets a tutorial outlive the screen it started on — the app tour spans five panels, and the greeting hands off to a surface tutorial without the scrim blinking between them.

**A tutorial is the unit of "one host owns these steps."** Whichever widget owns a step's targets is the only thing that can build that step, so steps on different surfaces belong to different tutorials, sequenced together. A host that goes away gives its sequence up rather than stranding it; progress is already saved, so the next arrival resumes where it left off.

## The four step kinds

| Kind | Advances when | Holds the screen? |
|---|---|---|
| **Tap** | the learner taps anywhere; the step then performs whatever it was pointing at | Yes — nothing but the tutorial responds |
| **Armed** | the learner does the thing the step asked for, in the app itself | No — see below |
| **Branch** | the learner picks one of two labelled choices: advance, or end this tutorial and mark it seen | Yes, and a tap outside the choices does nothing — otherwise a tap toward a button would advance past the question |
| **Multi-target** | as its underlying kind, over several lit targets at once | as its underlying kind |

**A tap step acts for the learner.** Tapping anywhere is the whole interaction; the step itself then opens the toolbar, expands the goal list, or opens the panel it was describing, and gates its advance on that having worked. Most steps are tap steps, because most of what a tutorial does is *show*.

**An armed step hands the screen back.** Where the point of the step is that the learner does it themselves — "try a two-player activity" — the tutorial cannot absorb their taps. The highlight and tooltip stay, but the learner drives: a tap on a lit target reaches the app, and a tap anywhere else dismisses the overlay while leaving the tutorial **armed at that step**. It resumes when the learner does the thing, including in a later app session, since the resume step is saved. So an armed step needs no timeout — a learner can never be stuck under the scrim waiting, and can always ignore the suggestion and come back to it.

An armed step also isn't holding the overlay, so another sequence may run in front of it; the armed one resumes afterwards.

**A multi-target step ends only when every target is gone.** The overlay follows its targets each frame and tears down when a target unmounts — right for one target, wrong for a set that re-ranks continuously. It repositions when any target moves, ends only when all are gone, and anchors the tooltip to the group rather than the first target so it never lands on top of something it lit.

**A step may hand its surface over entirely instead of dimming it.** No scrim, no cut-outs, nothing blocked, and no tap dismisses it — just the bot card at the bottom of the screen, while the **surface itself carries the emphasis**. Where the learner has to *use* what the step is describing, darkening it works against the ask; and a cut-out never matches what it lights anyway, since a spotlight is a rounded rectangle and a map pin is an 8px dot or a teardrop. Such a step says for itself when its surface is no longer in front of the learner, because it has no target whose disappearance would say so — otherwise a card that tracks nothing would follow them onto every other screen.

## Prep belongs to the step, not the host

A step that needs UI state prepared — a panel open, a toolbar shown, a message selected — carries that preparation itself and gates its own advance on the preparation having worked. A host must not grow a "when the sequence reaches tutorial X, rebuild state Y" branch: that pattern is why today's step definitions are spread across three files with hand-rolled per-widget delays, and each new tutorial makes it more complicated.

**A step that opens a panel navigates through the workspace URL**, exactly as the learner would, then checks that it opened. The URL is the single source of truth for which panels are open ([routing](routing.instructions.md)); a step must never reach past it into panel state.

**A step whose target is not on screen is skipped, not stalled.** Two cases, one rule. The wide nav rail and the narrow bottom nav are different widget trees for the same destinations, so a step names the destination and whichever tree is mounted answers it. And a step can be skipped by the learner's path rather than their screen size — joining an already-open session goes straight to the chat, so the waiting-screen step of the activity tutorial has no target and the tutorial simply starts at its next step.

## Who is offered a tutorial

A tutorial is offered when it is unseen, its trigger fires, and its gate passes.

- **Orientation tutorials are exempt from the subscription gate.** They teach the app, and a learner who cannot find their way around will not convert. This includes the app-tour steps that point at paid surfaces: those panels open for an unsubscribed learner and show their own unlock page, so the step completes and the tour doubles as a preview of what a subscription buys.
- **Feature tutorials stay subscription-gated.** They teach paid tools; teaching one to someone who cannot use it is a dead end.
- **A tutorial never fires onto an empty or still-loading surface.** An orientation step pointing at nothing is worse than no orientation.

**A trigger keeps asking; it does not conclude from a "no".** Everything a gate reads arrives asynchronously — the profile that records what has been seen, a fetched activity plan, panel focus published a frame late — and an unloaded profile reports every tutorial as *already seen*. So a failed check means "not yet", never "nothing to do", and the only state a trigger may latch on is one it has confirmed from loaded data. Checking once on arrival is how a tutorial silently never appears.

## The catalog

| Tutorial | Kind | Offered when |
|---|---|---|
| `welcome` | Orientation | first arrival at **either** the world map or a course plan — once ever, whichever comes first |
| `worldMap` | Orientation | first world map with pins actually rendered |
| `coursePlan` | Orientation | first joined course whose plan is showing its Up-next Mission |
| `activityGoals` | Orientation | first activity chat showing a goal header |
| `appTour` | Orientation | next arrival at a map after the learner's first finished activity |
| the chat sequence — `readingAssistance`, `selectModeButtons`, `writingAssistance` | Feature | the learner's first L2 message containing a word new to them, while scrolled to the bottom |

### Every learner sees both surface tutorials

`worldMap` and `coursePlan` teach two different things — the world map holds every activity in the learner's L2; a course is a *plan* through them with people to play it with — so neither substitutes for the other and **both fire**, each when the learner first reaches its surface. Only the greeting is once-ever: `welcome` is prepended to whichever surface tutorial runs first and is simply gone from the second, because a sequence is built over only the tutorials the learner hasn't seen.

That yields two paths, and no learner is ever taught the same thing twice:

| Arrives | Sees, in order |
|---|---|
| **with no course code** | `welcome` + `worldMap` → `activityGoals` on their first activity → `appTour` after their first finished activity → `coursePlan` whenever they later join a course |
| **by course code** | `welcome` + `coursePlan` → `activityGoals` → `appTour`, whose last step is the **World** icon → `worldMap` on the map it opens |

The app tour ending on World is what closes the second path: a course-code learner may never have opened the world map, so the tour hands them to it, and the world tutorial picks up from there.

### welcome

One step, no target: the bot introduces itself and greets the learner in their **L2**, over the darkened screen. It says nothing about the map or the course, because it fires on whichever the learner landed on. Tapping hands straight to that surface's tutorial with no scrim blink between them.

**The greeting itself is a word bubble, not text.** It renders as a tappable vocabulary word — the learner's first contact with the mechanic the whole product runs on: words in the L2 are things you can touch, look up, and collect. Tapping opens the **word card** over the scrim and **collects the word**, so the greeting is also the learner's first collected vocabulary.

**Whether it is styled as *new* is the tokenizer's answer, never ours.** The bubble asks the same analytics service every chat token asks, so a learner who already has the word simply sees it uncollected-but-not-new, and a tooltip reset cannot fake a discovery. In practice a greeting usually tags as an **interjection**, which is a function word and so never carries the green new-word underline — accepted, because the point of the bubble is that the word is *touchable*, not that it is new. It still collects, and still opens a card.

**The bubble appears only when a real L2 greeting was resolved.** It needs a tokenized word to be a word at all, so the fallbacks — no target language, no translation of the greeting for that locale, a tokenizer that did not answer — degrade to the plain app-language greeting with no bubble. A greeting in the learner's own language has nothing to teach about their L2.

### worldMap

1. **The map.** Every activity in the learner's target language lives here — that is what the world map *is*, and the reason to come back to it.
2. **Every visible two-role activity, shimmering.** "Tap one to start." The map is handed over — undimmed and fully usable — and the pins wear the same **gold nudge shimmer** the message tutorial uses on the translate button, so the emphasis is on the pins themselves rather than a hole cut around them. It reads clearly at the mid and large tiers and is subtle on an 8px dot, which is accepted: the card carries the instruction. Armed — the learner opens the activity themselves, and may ignore it and come back. The shimmer runs for exactly as long as the ask stands, so panning and tapping around the map do not end it; it stops when they open an activity, or when they leave the map. When no two-role activity is in view, the step carries the same *widen search* / *zoom out* remedy the map's own empty-view card would offer, read from the same diagnosis so the two can never disagree.

Two-role activities are the target because the bot fills exactly one seat, so they are the only ones a friendless new learner can start alone — the same reason the map already demotes 3+ role activities for them ([world map](world-map.instructions.md)).

### coursePlan

Mirrors `worldMap` — an introduction to the surface, then "go start one", with the course's own progress model in between:

1. **A welcome naming the course**, with nothing lit, so it takes over the screen: this course is a learning journey the learner takes with their course mates.
2. **The course progress bar.** Doing activities and earning **stars** is what moves them along the course. A star is one orchestrator-awarded activity goal and a Mission is a learning objective — [quests](quests.instructions.md) owns both.
3. **The Up-next Mission's activity carousel.** Armed, exactly as on the map: the learner opens an activity themselves.

**The carousel, not its individual cards.** A card would need a target id each, and the same activity can appear under more than one Mission, so two cards would contend for one id. Exactly one Mission is ever the anchor, so pointing at its carousel has a single claimant — and it says the more useful thing anyway: *these* are the activities for what you are working on now.

**It runs on the course card's Up-next highlight, not the full-plan subpage.** The subpage is pushed within the card, so both are mounted at once and both have an anchor Mission; the highlight wins, because it is what a learner sees when they open the course. A preview of an unjoined plan runs nothing — there is no learner progress to explain.

**No two-role filter here, unlike the map.** On the world map, two-role activities are singled out because the bot fills one seat and a 3+ role activity is a dead end for a learner with nobody to play with. Inside a course that reasoning inverts: its activities were hand-picked by the course author, so a 3+ role one is a deliberate part of the syllabus — which is why the [world map](world-map.instructions.md) already declines to demote it there. The step points at the Mission's activities and lets the learner choose.

### activityGoals

One step, one tap. It lights the **goal header** once the activity chat is running: playing your role and completing goals earns stars, and stars move you through a course's Missions. Tapping expands the goal list, so the learner ends the step looking at the goals they are about to play for.

**Nothing else inside an activity gets a step.** There was a waiting-room step before this one, pointing at the invite and play-with-the-bot controls — it was removed because it earned too little for an interruption at that moment, and the waiting room already shows both controls plainly. Completing every goal and finishing for credit likewise get nothing: those surfaces explain themselves, and a second interruption inside a learner's first activity costs more attention than it returns.

The chat sequence may fire in the same activity, on the learner's first L2 message containing a new word. They stay **separate sequences with separate counters** — the learner sees two short progress bars, not one long one — and whichever asks for the overlay second queues behind the first.

### appTour

Offered on the next arrival at a map after the first finished activity — never mid-activity, never on the summary screen. Each step opens its own panel and gates on it having opened.

0. **Branch.** "Great job finishing your first activity — want a tour?" *I'll explore* ends the tour and marks it seen; that is the only exit. A tap anywhere but the two buttons does nothing, so a tap that just misses one cannot advance past the question.
1. **Chats.** 2. **Courses** — copy varies on whether the learner has joined any. 3. **Analytics.** 4. **Practice.** 5. **World.**

The branch counts as a step, so the tour reads 1/6 through 6/6. Naming its length up front is honest, and a display total that differs from the real step count would re-introduce exactly the drift one step-count declaration removes.

**The Practice step shows where practice lives; it does not open it.** The Practice button is disabled until the learner has collected ten words, which is exactly where someone stands right after their first activity — so opening it would fail and gating on it would strand the tour for the learner it exists for. Every other step opens its panel and gates on that panel actually being open.

**The tour outranks the map introduction.** When both are due on the same arrival, the tour runs: it is the answer to "what now?" after a first activity, while the map introduction describes a map the learner has by then already used. `worldMap` then runs after the tour hands them to the map — which is what the final World step is for.

## Analytics

Every forward advance emits the tutorial's name and step index ([product analytics](google-analytics.instructions.md)). The app tour's branch outcome — tour or explore-myself — is the most useful signal in the feature, so it is captured as a step of its own rather than inferred from a missing event.

## Accessibility

The overlay hides everything under it from assistive tech, so anything it adds has to stand on its own: branch choices are real labelled buttons, and a multi-target step names the group it lit rather than leaving a screen-reader user with an unexplained scrim. A tutorial that traps a screen-reader user is a launch blocker ([accessibility](accessibility.instructions.md)).
