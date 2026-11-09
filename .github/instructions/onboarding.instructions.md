---
applyTo: "lib/routes/onboarding/**,lib/routes/registration/**"
description: "What a new user sees and does between signing up and reaching the main app, and where they land afterward."
---

# Onboarding (Client)

## Purpose

Onboarding asks a new user what the app needs to know about them: whether they teach or learn, the language they speak, the language they are learning or teaching, and their CEFR level. If they have a class link or code, it also joins them to that course. A teacher with no course can instead request one.

## The experience

Onboarding is a series of pages:

1. **Profile.** A display name and an avatar. The avatar starts as a random pick from a preset list; they can choose another or upload a picture.
2. **Role.** Learner or teacher.
3. **Class code.** Asks the user if they have a code. Yes opens a field; No moves on. If someone opened a class link before signing up, and that join succeeds, they skip this page.
4. **Languages.** The language they learn or teach, and the one they already speak, which starts on the device's language. The two must differ. Skipped when a joined course supplies them.
5. **Level.** Their CEFR level, or the level they teach. Skipped when a joined course supplies it.
6. **Course:**
   - Someone who joined a course sees a welcome page for it.
   - A teacher in no course can request a course built on their textbook, or skip.
7. **Trial.** For an account inside its [trial window](subscriptions.instructions.md#trial-window), a last page says their free trial is running and, at the top, that no credit card is required. It shows once, and its button just closes the page.

They land in their course if they joined one; otherwise on the world map, where the first tutorial starts, rather than the chat list, which would show a new person an empty list.

## Behavior

### What onboarding reads and saves

Choices carry over from page to page, so a later page can use an earlier one. Unsaved choices are lost if the person leaves; saved ones stay on their account.

#### What it reads

Besides the user's input, onboarding reads:

- The device's language, which is always the user's initial L1, including after a course join.
- Their account's saved role, languages, level, name, and avatar, which the pages show initially before the user makes changes.

#### What it saves

The name, avatar, role, languages and level, including any a joined course supplies, are saved to the person's account when they move forward, as is whether the trial page was shown. A class code is kept on this device ([joining-courses § Route 2 — Class Code](joining-courses.instructions.md#route-2--class-code)), and a course request goes to our servers to be fulfilled.

When a save fails, the page shows the error and stays where it is until the Next button works; offline, the error says so and asks them to try again once they're back online. The class-code and course request pages can also be skipped, and Setup has its own way out (below). The profile, role and trial pages are the exceptions: a failed save there does not stop the person, the old name or picture stays, and the role is saved again with their languages.

Saving the L2 marks onboarding as done. A signed-in account with no L2 is always sent to onboarding. Someone who leaves before then starts a new run, with only what was saved to their account.

### Setup

Before the profile page, a loading page sets the account up. This page adds a creation date to the user's account if not already set. It also requests the user’s free trial if they are eligible.

If the creation date cannot be saved, the page says setup did not finish: Try again repeats it, and Log out signs the person out so they can come back later.

### Joining a course during onboarding

Joining a course and loading its content are separate outcomes: a course can be joined while its content fails to load.

Onboarding takes the user's L2 and CEFR level from the joined course's content, and their L1 from the device, never from the course. When the content fails to load, the L2 comes from the course's own record, the level page is shown, and the welcome page shows only the course's name, picture and teacher. Either way, if the course records no L2 or teaches the device's language (because a user's L1 and L2 cannot match), the languages and level pages are shown.

### The course request

A teacher gives their name, institution, and textbook or curriculum. Submitting it files the same request as the [website's educator form](../../../website/.github/instructions/course-request.instructions.md).

## Open questions

- Can the choreographer allow a user's L1 and L2 to match?

## Future work

- Resume an unfinished onboarding from what's saved to the account, for runs that start after this ships, and never trap the person in onboarding when a save fails.
- A role option in learning settings, and a popup on app open for an account with no role until it chooses one.
- Keep choices on the device when a save fails offline, and save them to the account once back online.
- Offer a learner with no class code or link their L2's central course, or a course of their own if they decline, so every learner lands in a course. Teachers aren't offered one.
