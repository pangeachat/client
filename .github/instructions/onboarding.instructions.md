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

Choices go into memory as soon as they are made, and every page reads them from there. Changing one choice does not clear another, and a choice that has not been saved yet stays in memory even if the person goes back instead of forward.

#### What it reads

Besides the person's choices, onboarding reads:

- **This device:** its language, which the languages page first selects as the user's L1. It is also saved as their L1 when a joined course's content does not load.
- **Account data:** the saved role, languages and level, which those pages show selected when memory has none.
- **Matrix profile:** the display name and avatar, which the profile page shows and compares against before saving. If they cannot be read when Next is pressed, the page shows the error.

#### What it saves

Each page saves its own choices when the person moves on from it, to one of two places: their Matrix profile (the public name and picture other people see) or their account data (settings stored on their account).

A page saves only what has changed since it last saved, so moving forward again over a page with nothing changed saves nothing, joins no course a second time and sends no second course request.

| Page | What is saved, and where | If the save fails |
| --- | --- | --- |
| Setup | The creation date, if there is none yet, to account data | Setup stops, with Try again and Log out |
| Profile | Display name and avatar, to the Matrix profile | Onboarding moves on, and the old name or picture stays |
| Role | The role, to account data | Onboarding moves on, and the role is saved again with the L2 (below) |
| Class code | The code, to this device, as every code join does ([joining-courses § Route 2 — Class Code](joining-courses.instructions.md#route-2--class-code)); the person is joined to the course | The page shows the error |
| Languages | Both languages, and the role again, to account data; a joined course saves the ones it supplies, and its level when its content loads, right after the join | The page shows the error |
| Level | The level, to account data | The page shows the error |
| Course request | The request, sent to the team | The page shows the error |
| Trial | That the page was shown, to account data | Onboarding moves on |

A page that shows an error stays where it is, and pressing Next again retries. Two of those pages can also be skipped: the class-code page with "I don't have a code", and the course request with "Skip for now". The other pages have no skip; the person can go Back, but moves past them only once the save works.

**Why the role is saved twice.** The role page saves the role, and saving the person's languages saves it again. If the first save worked, the second changes nothing. If it failed, the person moves on without an error, and the second save is the one that has to work. The role must be saved before onboarding ends ([profile § Data Model](profile.instructions.md#data-model) says who reads it), because it is only chosen here and onboarding does not come back once the L2 is saved.

A signed-in account with no L2 is sent to onboarding, whatever link it opened, and saving the L2 marks onboarding as done. Someone who leaves before then starts a new run, with nothing in memory. The profile page fills in their saved display name and avatar, and the role page their saved role.

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

- Someone who leaves once their language is saved is not brought back: their level stays at the default, a teacher is not asked for a course request, and the trial page does not show. Should onboarding resume where they left off?
- Some accounts have no saved role: they finished onboarding before the role was saved, or an older app version erased it when saving their profile. How should they be asked for one: a one-time popup when the app opens, or a role setting in their settings?
- A joined course sets the person's L1 differently depending on whether its content loads: to the language the course is taught in when it does, and to the device's language when it does not. Should both cases use the same one?
- When a save keeps failing, for example while the person is offline, the profile, role-page join, languages and level pages leave them with only Next to retry, and the error often does not say what is wrong. Should onboarding let them move on and save later, as it does the role; say when the problem is their connection ([connection status](connection-status.instructions.md)); or offer a way out, like Setup's Log out?
