---
applyTo: "lib/pangea/common/network/**,lib/pangea/common/utils/base_repo.dart,lib/pangea/common/utils/error_handler.dart,**/*_repo.dart"
description: "Client repo layer and error contract — repos own network access, reporting, and severity; callers own UI. What Requests throws, what repos return, who reports to Sentry, and what each status means."
---

# Client Repos & Error Handling

A **repo** is the only place the client talks to a backend. It owns the request, the failure, and the Sentry report. A **caller** — route, controller, widget — receives a value or an error and decides only what the user sees.

The split exists because the alternative was tried and did not hold. Reporting spread across 241 call sites at whatever altitude the author happened to be at, and the same 404 arrived in Sentry at two different severities depending on which repo shape the author had picked.

## The contract

- **Repos return `Result<T>`.** Not a bare `T`, not `T?`, not an empty list standing in for an error, not a raw `Response`. A caller must be able to tell "no data" from "failed" without inspecting a sentinel.
- **The repo reports; the caller does not.** A repo captures each failure to Sentry exactly once, then returns `Result.error`. Callers do not call `ErrorHandler.logError` on an error a repo already returned — that double-reports and re-severitizes.
- **Callers may escalate, not re-report.** When a caller has context the repo lacks — a failure that is routine on a background refresh but user-visible on a tap — it may raise the level on the error it received. It does not create a second event.
- **Repos never return an error the user cannot be told about.** If a failure is expected and non-actionable, the repo returns a successful empty value and documents why; it does not return an error that every caller then swallows.

Prefer `BaseRepo` for anything cached or request-shaped — it implements this contract. A repo that bypasses it re-implements timeout, cache, and severity by hand, and historically gets severity wrong.

## What `Requests` throws

`Requests` throws `PangeaHttpException` for any response ≥ 400 — never the raw `http.Response`. The exception carries status, method, normalized path, and the parsed `detail`, and its `toString()` renders them.

This is not a style preference. A thrown `http.Response` has no `toString()` override, so every failure across every endpoint arrives in Sentry titled `Instance of 'Response'` — 66 issues and 3,386 events in a single 14-day window, none diagnosable without opening an individual event.

- **Never put a response body in the exception.** Only the `detail` field, length-capped. Bodies carry learner content; Sentry is not where that belongs.
- Paths are normalized (opaque id segments → `{id}`) so titles group and read cleanly.
- `UnsubscribedException` keeps its own type — it is control flow, not an error, and is never reported.

The rule lives in `Requests` alone. A second copy of it anywhere else drifts.

## Build identity on every event

Every Sentry event the client reports carries three tags saying **which build produced it**. Without them a local build and a deployed one are indistinguishable: the SDK's default release is `<package>@<pubspec version>+<build number>`, and pubspec's `+N` is hand-bumped, so every locally-built app reports the same release string for months at a time. Triage twice could not answer "does the build that produced this event contain the fix?" and had to reason from event timestamps instead.

| Tag | Value | Answers |
| --- | --- | --- |
| `build_channel` | `local` \| `ci` | A developer's machine, or a deployed build? |
| `build_commit` | 8-char commit SHA, `ci` only | Which code is running — does it contain a given fix? |
| `config_override` | `true` \| `false` | Is a persisted `appConfigOverride` redirecting this build away from what its `.env` says? |

The channel derives from `Environment.buildCommitSha`, which every build workflow passes as a `--dart-define` and which is empty on a build with no pushed commit (see [ci.instructions.md](ci.instructions.md)). Nothing new is stamped at build time — the tags read a signal the build already carries.

`config_override` is here because an override persists in local storage and outranks dotenv, so it survives a pull and a rebuild. Without it, "this build is aimed at the production homeserver" and "this build was pointed at production once and never un-pointed" look identical.

These are tags, not environments. The allow-list — only `production` and `staging`, per the org [sentry.instructions.md](../../../.github/.github/instructions/sentry.instructions.md) — is unchanged, and a build that cannot positively identify one still does not report at all.

## Severity policy

Severity is a property of the failure, not of the author's judgment at the call site. One table, applied by the repo layer:

| Condition                  | Level   | Why                                                                       |
| -------------------------- | ------- | ------------------------------------------------------------------------- |
| Timeout                    | warning | Transient; retry is the answer                                            |
| 401                        | warning | Token lifecycle is routine                                                |
| 404, 410                   | warning | The resource is gone — a normal state, e.g. a stale room reference        |
| 429                        | warning | Expected under load                                                       |
| 403                        | error   | We asked for something we should not have — a code bug                    |
| Other 4xx (400, 405, 422)  | error   | We sent something malformed — a code bug                                  |
| 5xx                        | error   | The only signal the client has that a backend is regressing               |

This table leans on what each status actually asserts — 404 meaning the resource is gone, 5xx meaning the lookup itself failed. Those meanings are a contract every Pangea service holds to, not a client-local reading, and they live in [error-handling.instructions.md](../../../.github/.github/instructions/error-handling.instructions.md).

## Adoption

Binding for new repos and for any repo already being modified. Existing repos migrate opportunistically, not in a sweep — a repo touched for other work comes along with the change.