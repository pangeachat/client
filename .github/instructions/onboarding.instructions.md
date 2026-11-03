---
applyTo: "lib/routes/onboarding/**,lib/routes/registration/**"
description: "What a new user sees and does between signing up and reaching the main app, and where they land afterward."
---

# Onboarding (Client)

## Purpose

Onboarding asks a new user what the app needs to know about them: whether they teach or learn, the language they speak, the language they are learning or teaching, and their CEFR level. If they have a class link or code, it also joins them to that course. A teacher with no course can instead request one.

The screens before sign-up are in [signup-and-login](signup-and-login.instructions.md); the tutorials that follow are in [tutorials](tutorials.instructions.md); focus between pages follows [accessibility § Focus after an in-place content swap](accessibility.instructions.md#focus-after-an-in-place-content-swap).

## The experience

Choices on one page can change which pages come after it.

1. **Profile.** A display name and an avatar. The avatar starts as a random pick from a preset list; they can choose another or upload a picture.
2. **Role.** Learner or teacher.
3. **Class code.** "Do you have a course invite code?" Yes opens a field; No moves on. Someone who opened a class link before signing up is joined to that course instead and skips this page; if that join fails, they see this page with no code filled in.
4. **Languages.** The language they learn or teach, and the one they already speak, which starts on the device's language. The two must differ. Skipped when a joined course supplies them.
5. **Level.** Their CEFR level, or the level they teach. Skipped when a joined course supplies it.
6. **Then it branches:**
   - Someone who joined a course sees a welcome page for it.
   - A teacher in no course can request a course built on their textbook, or skip.
7. **Trial.** For an account inside its trial window, a last page says their free trial is running, once. Its button just closes the page; the trial needs no action and no card.

They land in their course if they joined one, even when the trial page comes last; otherwise on the world map, where the first tutorial starts, rather than the chat list, which would show a new person an empty list.

Back returns to earlier pages, with the choices made there kept.

## Behavior

### What onboarding reads and saves

Choices are kept for the run as soon as they are made, and every page reads them from there. An unsaved choice is kept when the person goes back. Unsaved choices are lost if the person leaves onboarding; saved ones stay on their account, on any device.

#### What it reads

Besides the person's choices, onboarding reads:

- The device's language: the languages page first selects it as their L1, and it becomes their L1 when a joined course's content does not load.
- Their account's saved role, languages and level, which those pages show when the run has none, and display name and avatar, which the profile page shows and compares before saving. If the name and avatar cannot be read when Next is pressed, the page shows the error.

#### What it saves

Each page saves its choices to the person's account when they move on, unless the table says otherwise.

| Page | What is saved | If the save fails |
| --- | --- | --- |
| Setup | The creation date, if there is none yet | Setup stops, with Try again and Log out |
| Profile | Display name and avatar, which other people see | Onboarding moves on, and the old name or picture stays |
| Role | The role | Onboarding moves on, and the role is saved again with the L2 (below) |
| Class code | The code, on this device only, as every code join does ([joining-courses § Route 2 — Class Code](joining-courses.instructions.md#route-2--class-code)); the person is joined to the course | The page shows the error |
| Languages | Both languages, and the role again; a joined course saves the ones it supplies, and its level when its content loads, right after the join | The page shows the error |
| Level | The level | The page shows the error |
| Course request | The request, sent to the team | The page shows the error |
| Trial | That the page was shown | Onboarding moves on |

A page that shows an error stays where it is, and pressing Next again retries. Two of those pages can also be skipped: the class-code page and the course request page. Otherwise, the person moves forward only once the save works. The profile, role and trial pages are the exceptions: a failed save there does not stop the person, and the role is saved again with their languages.

A signed-in account with no L2 is sent to onboarding, whatever link it opened, and saving the L2 marks onboarding as done. Someone who leaves before then starts a new run, with only what was saved to their account. The profile page fills in their saved display name and avatar, and the role page their saved role.

### Setup

Before the profile page, a loading page sets the account up. The account can get its free trial only in a set number of days after its creation date, its trial window. The app asks the server for the trial if the account can still get one ([subscriptions](subscriptions.instructions.md)); if that request fails, onboarding goes on without a trial, and the app asks again each time it opens inside the window. If the creation date cannot be saved, the page says setup did not finish: Try again repeats it, and Log out signs the person out so they can come back later.

### Joining a course during onboarding

Users are encouraged to join a course during onboarding. They can do this by launching the app via a join link, which automatically joins the user to the course, or by entering a course code.

If a link join fails, the person gets the class-code page and can type the code themselves.

Joining a course and loading its content are separate outcomes: a course can be joined while its content fails to load. The person is a member either way. Right after a join, onboarding waits up to 10 seconds for the course's record to arrive before treating its content as unavailable, so the page can take that long to move on.

- **The content loads.** The languages and level pages are skipped, and the welcome page shows the full course card.
- **It does not.** Only the level is asked, unless the course records no language or teaches the device's language; then the languages page appears too. The welcome page shows the course's name, picture and teacher.

Onboarding does not repair a course whose content fails to load.

### The course request

A teacher gives their name, institution, and textbook or curriculum. Submitting files the same request as the [website's educator form](../../../website/.github/instructions/course-request.instructions.md), which the team builds and delivers. Skip for now moves on without a request.

## Open questions

- Someone who leaves once their L2 is saved skips the rest: the level, course request and trial pages. Should onboarding resume where they left off?
- Some older or corrupted account have no role. When and how should they be asked to set it?
- When a save keeps failing, for example offline, the profile, languages and level pages, and the role page after a class-link join, offer only Next, often with an unclear error. Should onboarding let the person move on and save later, explain connection problems ([connection status](connection-status.instructions.md)), or offer a way out like Setup's Log out?
