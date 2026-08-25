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

**A multi-target step ends only when every target is gone.** The overlay follows its targets each frame and tears down when a target unmounts — right for one target, wrong for a set of map pins that re-rank continuously. It repositions when any target moves, ends only when all are gone, and anchors the tooltip to the group rather than the first target so it never lands on top of something it lit.

## Prep belongs to the step, not the host

A step that needs UI state prepared — a panel open, a toolbar shown, a message selected — carries that preparation itself and gates its own advance on the preparation having worked. A host must not grow a "when the sequence reaches tutorial X, rebuild state Y" branch: that pattern is why today's step definitions are spread across three files with hand-rolled per-widget delays, and each new tutorial makes it more complicated.

**A step that opens a panel navigates through the workspace URL**, exactly as the learner would, then checks that it opened. The URL is the single source of truth for which panels are open ([routing](routing.instructions.md)); a step must never reach past it into panel state.

**A step whose target is not on screen is skipped, not stalled.** Two cases, one rule. The wide nav rail and the narrow bottom nav are different widget trees for the same destinations, so a step names the destination and whichever tree is mounted answers it. And a step can be skipped by the learner's path rather than their screen size — joining an already-open session goes straight to the chat, so the waiting-screen step of the activity tutorial has no target and the tutorial simply starts at its next step.

## Who is offered a tutorial

A tutorial is offered when it is unseen, its trigger fires, and its gate passes.

- **Orientation tutorials are exempt from the subscription gate.** They teach the app, and a learner who cannot find their way around will not convert. This includes the app-tour steps that point at paid surfaces: those panels open for an unsubscribed learner and show their own unlock page, so the step completes and the tour doubles as a preview of what a subscription buys.
- **Feature tutorials stay subscription-gated.** They teach paid tools; teaching one to someone who cannot use it is a dead end.
- **A tutorial never fires onto an empty or still-loading surface.** An orientation step pointing at nothing is worse than no orientation.

## The catalog

| Tutorial | Kind | Offered when |
|---|---|---|
| `welcome` | Orientation | first arrival at **either** the world map or a course plan — once ever, whichever comes first |
| `worldMap` | Orientation | first world map with pins actually rendered |
| `coursePlan` | Orientation | first course plan with its activities rendered |
| `activityInvite` | Orientation | first confirmed role, on the waiting room |
| `activityGoals` | Orientation | first activity chat showing a goal header |
| `appTour` | Orientation | next arrival at a map after the learner's first finished activity |
| the chat sequence — `readingAssistance`, `selectModeButtons`, `writingAssistance` | Feature | the learner's first L2 message containing a word new to them, while scrolled to the bottom |

### Every learner sees both surface tutorials

`worldMap` and `coursePlan` teach two different things — the world map holds every activity in the learner's L2; a course is a *plan* through them with people to play it with — so neither substitutes for the other and **both fire**, each when the learner first reaches its surface. Only the greeting is once-ever: `welcome` is prepended to whichever surface tutorial runs first and is simply gone from the second, because a sequence is built over only the tutorials the learner hasn't seen.

That yields two paths, and no learner is ever taught the same thing twice:

| Arrives | Sees, in order |
|---|---|
| **with no course code** | `welcome` + `worldMap` → `activityInvite` then `activityGoals` on their first activity → `appTour` after their first finished activity → `coursePlan` whenever they later join a course |
| **by course code** | `welcome` + `coursePlan` → `activityInvite` then `activityGoals` → `appTour`, whose last step is the **World** icon → `worldMap` on the map it opens |

The app tour ending on World is what closes the second path: a course-code learner may never have opened the world map, so the tour hands them to it, and the world tutorial picks up from there.

### welcome

One step, no target: the bot introduces itself and greets the learner in their **L2** — plain styled text, not tappable — over the darkened screen. It says nothing about the map or the course, because it fires on whichever the learner landed on. Tapping hands straight to that surface's tutorial with no scrim blink between them.

### worldMap

1. **The map.** Every activity in the learner's target language lives here — that is what the world map *is*, and the reason to come back to it.
2. **Every visible two-role activity, lit at once.** "Try one to start." Armed — the learner opens the activity themselves, and may ignore the suggestion and come back to it. When no two-role activity is in view, the step carries the same *widen search* / *zoom out* remedy the map's own empty-view card would offer, read from the same diagnosis so the two can never disagree.

Two-role activities are the target because the bot fills exactly one seat, so they are the only ones a friendless new learner can start alone — the same reason the map already demotes 3+ role activities for them ([world map](world-map.instructions.md)).

### coursePlan

1. **The course plan.** A course lays out a **plan of Missions** to work through, with the people in the course to play them with; earning **stars** moves the learner along it. A star is one orchestrator-awarded activity goal and a Mission is a learning objective — [quests](quests.instructions.md) owns both.
2. **The course's two-role activity cards, lit at once.** Armed, exactly as on the map: the learner opens one themselves.

Its armed step is the same beat as `worldMap`'s over a different target, so the pair is defined once and its copy parameterized rather than duplicated.

### activityInvite and activityGoals

Two beats around the moment a learner first holds a role, one per surface:

- **`activityInvite`** lights the invite and play-with-the-bot controls on the confirmed-role waiting room. "You can play with me any time, or invite a friend." This is where the two-person nature of the app is taught, once — playtesters repeatedly asked whether the app could be used with other people, and this is the first moment the answer is concrete.
- **`activityGoals`** lights the goal header once the chat opens. Playing your role and completing goals earns stars, and stars move you through a course's Missions. Tapping expands the goal list, so the learner ends the step looking at the goals they are about to play for.

**Two tutorials rather than one with two steps**, because their surfaces have different owners and a learner who joins an already-running session never sees a waiting room at all. As one tutorial, that learner's sequence would stall behind a step whose screen never appears; as two, the first simply never fires and the second runs on its own. It is also why the waiting-room one keeps its own seen flag: a learner who skipped it that way is still offered it at their next activity that does have a waiting room.

It stops there deliberately. Nothing later in an activity — completing every goal, finishing for credit — gets a step: those surfaces already explain themselves, and a third interruption inside the learner's first activity costs more attention than it returns.

The chat sequence may fire in the same activity, on the learner's first L2 message containing a new word. They stay **separate sequences with separate counters** — the learner sees two short progress bars, not one long one — and whichever asks for the overlay second queues behind the first.

### appTour

Offered on the next arrival at a map after the first finished activity — never mid-activity, never on the summary screen. Each step opens its own panel and gates on it having opened.

0. **Branch.** "Great job finishing your first activity — want a tour?" *Explore myself* ends the tour and marks it seen; that is the only exit.
1. **Chats.** 2. **Courses** — copy varies on whether the learner has joined any. 3. **Analytics.** 4. **Practice.** 5. **World.**

The branch counts as a step, so the tour reads 1/6 through 6/6. Naming its length up front is honest, and a display total that differs from the real step count would re-introduce exactly the drift one step-count declaration removes.

Practice opens from **inside** analytics and shares a slot with the vocab and grammar details ([routing](routing.instructions.md)), so step 4's preparation has to leave step 3's panel intact rather than closing what it just opened.

## Analytics

Every forward advance emits the tutorial's name and step index ([product analytics](google-analytics.instructions.md)). The app tour's branch outcome — tour or explore-myself — is the most useful signal in the feature, so it is captured as a step of its own rather than inferred from a missing event.

## Accessibility

The overlay hides everything under it from assistive tech, so anything it adds has to stand on its own: branch choices are real labelled buttons, and a multi-target step names the group it lit rather than leaving a screen-reader user with an unexplained scrim. A tutorial that traps a screen-reader user is a launch blocker ([accessibility](accessibility.instructions.md)).
