---
applyTo: ""
description: "How a client issue's testing platforms are chosen — the platform checklist, who fills it in, and how it becomes needs-testing labels at close."
---

# QA Platform Labeling (Client)

Extends the org-wide [qa-testing-process](../../../.github/instructions/qa-testing-process.instructions.md), which owns the label vocabulary, the tested-on-staging flip, and the QA-complete definition that gates a release. This doc covers one client-specific thing: **which** of the four platform labels an issue gets, rather than always getting all four.

Client issues carried all four since the auto-labeling workflow was introduced. Only 47 of 1,235 files under `lib/` contain platform-conditional code, so most changes were being verified four times against identical code paths, and the queue grew faster than it could drain. This narrows the set to what a change can actually break.

## The platform section

Every client issue carries a testing-platform checklist in its **description**:

```markdown
<!-- pangea-qa-platforms -->
---
**TESTING PLATFORMS**
> Filled in by the developer whose PR closes this issue — not by the issue author.
- [ ] **Evaluated** — I have determined which platforms this needs testing on
- [ ] Web
- [ ] Android
- [ ] iOS
- [ ] iPad
```

A workflow appends it on `issues: opened` and re-appends it on `issues: edited` when the marker is gone, so it survives someone editing it out of the description, and it is present on issues opened from any template or none.

The `<!-- pangea-qa-platforms -->` marker is what both workflows key on. **NEVER remove or repurpose it** — the close-time rule finds the section by that marker, and an issue without it falls back to all four labels.

The section deliberately does **not** live in `.github/ISSUE_TEMPLATE/`. Those three templates are canonically owned by `pangeachat/workflows` and re-synced weekly, so a local edit would reopen a drift PR every Monday.

## Who fills it in, and when

Filling in the checklist is the responsibility of **the developer who opens the PR that closes the issue** — not the issue author, who usually cannot know the implementation. Do it before the PR merges, alongside the linked issue and the Conventional Commits title.

A non-blocking `qa_scope` check on the PR warns when a linked issue's **Evaluated** box is unticked. It never blocks a merge: merging past the warning falls back to all four labels, which is the safe outcome rather than a broken one.

Known limitation: the check reads the *issue* body, so ticking the boxes does not re-run it. The stale red is cosmetic — re-run the check manually if you want it green.

## What the labels become at close

Evaluated in order; first match wins:

| Condition | Labels applied |
|---|---|
| Closed as `not planned` or `duplicate` | None *(pre-existing behavior)* |
| Body contains `No client testing needed` | None *(pre-existing behavior)* |
| No `<!-- pangea-qa-platforms -->` marker | All four |
| **Evaluated** unticked | All four |
| **Evaluated** ticked, ≥1 platform ticked | Exactly the ticked platforms |
| **Evaluated** ticked, 0 platforms ticked | `does not need testing` |

The last row is an explicit statement that the change needs no human verification, and the issue's edit history records who made it. See [Exemptions](../../../.github/instructions/qa-testing-process.instructions.md#exemptions) for the accountability that carries.

**INVARIANT: every unclear case resolves to all four labels.** A missing section, an unticked box, a body the parser cannot read — all fail toward more testing. NEVER change this so that ambiguity yields fewer labels than today.

## Choosing platforms

Default to **web alone**, then add only what the change can actually break.

| If the change touches… | Test on |
|---|---|
| Layout, spacing, responsive breakpoints, fonts, text scaling | Web, iPad, **and one phone** — tick either Android or iOS |
| Touch gestures, scroll physics, keyboard / IME, text input | All four |
| Mic, audio, camera, file picker, OS permissions | All four |
| Push notifications | Android, iOS, iPad |
| Deep links | All four |
| Login, session, local storage or persistence | All four |
| Paywall display, entitlement gating, billing management UI | All four |
| Any file containing `kIsWeb`, `Platform.is`, or `defaultTargetPlatform` | All four |

Web is the default because platform cannot matter for a change that isn't in this table, so the cheapest verifier is the right one. The moment it *could* matter, the table has already moved you off web.

Notes on individual rows:

- **Layout** — the phone is a genuine either/or: tick Android **or** iOS, not both. Phone-form-factor layout bugs reproduce on either, so a second phone buys little over the iPad and web coverage already required.
- **Push notifications** — iPad is listed for notification *handling* and its distinct form factor, not for delivery. Delivery is APNs-identical to iOS, which is why the org doc's sygnal row says web and iPad don't apply there.
- **Deep links** — web is included because [routing.instructions.md](routing.instructions.md) makes the URL the source of truth for panel state, so a link change exercises the shared route parser plus three separate registration paths (web history, iOS universal links, Android app links).
- **Paywall and entitlements** — purchases run on a single Stripe rail and checkout happens on web, but paywall display, entitlement gating, and billing management render on every platform.

Absence of `kIsWeb` does not prove a change renders identically everywhere: Flutter branches beneath us on font metrics, safe areas, scroll physics, and IME behavior, and this repo has shipped bugs in exactly that class. Treat the table as strong for logic changes and weaker for visual ones. When genuinely unsure, tick more boxes — over-testing costs a tester an hour, under-testing costs a production bug during a research study.

## Implementation

| Piece | File |
|---|---|
| Injects and re-injects the section | [`qa_platforms_section.yml`](../workflows/qa_platforms_section.yml) — `issues: [opened, edited]`, no-ops when the marker is present so the bot's own edit terminates the loop |
| Merge-time warning | [`qa_scope.yml`](../workflows/qa_scope.yml) — `pull_request: [opened, edited, reopened, synchronize]` |
| Close-time mapping | [`issue_to_test_check.yaml`](../workflows/issue_to_test_check.yaml) — a `compute` job parses the section and passes the result to the reusable workflow's `needs_testing_labels` input |

`qa_scope.yml` must always run and exit 0 when it does not apply; a job skipped by a job-level `if:` never reports its check, which would strand any PR if the check were ever promoted to required. The reusable workflow in `pangeachat/workflows` is unchanged — it applies whatever label list it is handed.
