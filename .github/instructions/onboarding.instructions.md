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
6. **Then it branches:**
   - Someone who joined a course sees a welcome page for it.
   - A teacher in no course can request a course built on their textbook, or skip.
7. **Trial.** For an account inside its [trial window](subscriptions.instructions.md#trial-window), a last page says their free trial is running, once. Its button just closes the page; the trial needs no action and no card.

They land in their course if they joined one; otherwise on the world map, where the first tutorial starts, rather than the chat list, which would show a new person an empty list.

## Behavior

### What onboarding reads and saves

Choices carry over from page to page, so a later page can use an earlier one. Unsaved choices are lost if the person leaves; saved ones stay on their account.

#### What it reads

Besides the user's input, onboarding reads:

- The device's language to determine the user's initial L1 (unless it is set by a joined course).
- Their account's saved role, languages, level, name, and avatar, which the pages show initially before the user makes changes.

#### What it saves

The name, avatar, role, languages and level, including any a joined course supplies, are saved to the person's account when they move forward, as is whether the trial page was shown. A class code is kept on this device ([joining-courses § Route 2 — Class Code](joining-courses.instructions.md#route-2--class-code)), and a course request goes to our servers to be fulfilled.

When a save fails, the page shows the error and stays where it is until Next works; the class-code and course request pages can also be skipped, and Setup has its own way out (below). The profile, role, level and trial pages are the exceptions: a failed save there does not stop the person, the old name, picture or level stays, and the role is saved again with their languages.

The account is marked when an onboarding run starts, when its name and picture are saved, when its level is saved, and when it ends. A run that started and did not end resumes the next time the app opens, on the first page whose choices are not saved: the profile page when nothing is saved yet, the role page with no role, the class-code page with no languages, the level page with no level, and otherwise the page after it, with the earlier pages behind Back. Choices that are not saved to the account do not come back: a teacher sees the course request again, and someone who joined a course lands on the map. If the end mark fails to save, the person still goes into the app, and onboarding resumes next time.

A signed-in account with no L2 is sent to onboarding, whatever link it opened. An account that saved its L2 before the marks existed has neither mark and counts as finished.

An account with no role, such as one that signed up before onboarding asked for it, is asked for one when the app opens, and any account can change its role in learning settings ([profile](profile.instructions.md)).

### Setup

Before the profile page, a loading page sets the account up. This page adds a creation date to the user's account if not already set. It also requests the user’s free trial if they are eligible.

If the creation date cannot be saved, the page says setup did not finish: Try again repeats it, and Log out signs the person out so they can come back later.

### Joining a course during onboarding

Joining a course and loading its content are separate outcomes: a course can be joined while its content fails to load.

Onboarding takes the user's L1, L2 and CEFR level from the joined course's content. When the content fails to load, the level page is shown, and the L2 comes from the course's own record, with the device's language as the L1; if the course records no language, or teaches the device's language, the languages page is shown too. The welcome page then shows only the course's name, picture and teacher.

### The course request

A teacher gives their name, institution, and textbook or curriculum. Submitting files the same request as the [website's educator form](../../../website/.github/instructions/course-request.instructions.md), which the team builds and delivers.

## Open questions

- Repeated save failures leave users unable to move forward, with an unclear error. How should onboarding handle this?
