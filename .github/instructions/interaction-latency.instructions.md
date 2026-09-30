---
applyTo: ""
description: "How quickly the client must respond to a learner's action, what the learner sees while waiting, and how developers and QA testers check it."
---

# Interaction Latency (Client)

A learner who taps and sees nothing assumes the tap failed. They tap again or give up. This doc sets how quickly the app responds to an action and what it shows while work is in progress. The thresholds follow industry standards: Nielsen's response-time limits (0.1 s, 1 s, 10 s), and Google's RAIL model and INP guidance for the web.

## Response targets

These are defaults. A feature doc may set a different budget for its own surface, as long as it says why.

| The learner… | Target | What they see |
|---|---|---|
| taps, types, drags or toggles | under 100 ms | The control's own response: the pressed state, the typed character, the switch flipping, the menu opening |
| opens a screen, panel or sheet | first frame under 1 s | The layout, with a placeholder wherever data is still loading |
| waits on the network or an AI call | indicator between 400 ms and 1 s | A spinner or shimmer. It appears only after about 400 ms, so a fast response doesn't flash one, and never later than 1 s |
| waits more than 10 s | n/a | What is happening (for example "Generating your activity…") and a way to leave |
| scrolls or watches an animation | 60 frames per second | Smooth motion with no stutter or freeze |

For AI features, model latency is mostly outside the client's control. The targets above apply to the feedback, not to when the result arrives. The feature's own doc owns the result's time budget.

## Rules for every wait

- **Feedback never waits on the request.** The control responds to the tap immediately. Only the result waits on the network.
- **Placeholders hold their space.** A placeholder is the same size as what replaces it, so the page doesn't jump when content arrives.
- **A wait always ends.** Every loading state ends in the result, an error the learner can read, or a timeout path. A spinner never runs forever. The 10-second rules in [activities](activities.instructions.md) and [session-lifetime](session-lifetime.instructions.md) follow this. How errors surface is owned by [repos-and-error-handling](repos-and-error-handling.instructions.md).
- **Loading is announced, not just shown.** See [accessibility](accessibility.instructions.md#quick-habits-for-anyone-building-ui).

## Who checks

**The developer**, before the PR, whenever a change affects something a learner taps or waits on. Run the flow in a profile or release build, since debug builds are too slow to judge. Throttle the network to a slow mobile connection and compare against the targets above. The PR template carries a checkbox for this.

**The QA tester**, on every client issue. Each issue gets a standing responsiveness item next to its testing-platform checklist (see [qa-labeling](qa-labeling.instructions.md#the-responsiveness-item)). The tester checks it while running the TO TEST steps. Seeing any of the following is a failure, handled like any other failed TO TEST step:

- a tap with no visible response
- a blank or frozen screen with no loading indicator
- content jumping as it loads
- stutter while scrolling or animating

Testers judge by feel, not with a stopwatch. The millisecond targets are the developer's check.
