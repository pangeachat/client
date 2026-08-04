---
name: triage-and-dispatch-backlog
description: >-
  Use when asked to triage the open ticket backlog by agent-actionability
  and/or spin up parallel agent sessions to work the actionable tickets.
  Defaults to this repo (pangeachat/client).
---

## Step One: Gather the backlog

- **Default to `pangeachat/client`** unless the user names another repo.
- **Apply the user's exclusions.** The user may exclude labels (commonly `QA` and `needs design`) and/or assignees. Fetch open issues with `gh issue list --json number,title,labels,assignees` and filter both out. If no exclusions are given, ask before assuming any.
- **Resolve assignee names to real logins.** Users often type approximate usernames (e.g. "bbatvik" for `bbsatvik01`). Match against the actual assignee logins in the result set, state the assumption you made, and flag anything that matched nothing.

## Step Two: Categorize by actionability

Read every remaining issue's body and its comments — then assign each to exactly one category:

1. **Can move forward easily without much input.** Concrete spec or reproduction, clear expected behavior, work is contained to the repo, and the agent can implement and verify it locally.
2. **Can move forward given moderate input.** One of: an explicit open decision in the ticket (pick option A or B, default on/off), a needed asset or approval, a diagnosis that may cross into another service, or verification the agent can't do alone (multi-account staging flows, physical devices, screen readers).
3. **Cannot move forward.** Genuinely blocked: missing replication steps, blocked on assets or a person, an umbrella/tracking ticket rather than a unit of work, or an unresolved dependency. **Every category-3 ticket gets a one-line explanation of the blocker.**

Present the three lists with a short reason per ticket, ordered as returned (most recent first). Category boundaries are judgment calls — when torn, prefer 2 over 1 (don't overpromise autonomy) and 2 over 3 (don't call something blocked if input would unblock it).

## Step Three: Dispatch on request

- The user picks a count and a category ("start the first 5 in category 1") or names specific tickets. Take them in list order unless told otherwise.
- For each selected ticket, create one background-task chip (`spawn_task`) whose prompt is exactly:

  `Work on client issue [ISSUE NUMBER] in a git worktree and open a PR once finished`

  (Substitute the repo name if triaging a repo other than client.) Each chip launches an independent session; the spawned session picks up `triage-single-issue` and owns the ticket end to end.
- **Chips require a click** — tell the user the sessions start when they click, and that they can stagger launches to review PRs as they land.
- **Category-2 dispatches:** before spawning, surface the ticket's needed input to the user; if they resolve it, record the decision as a comment on the issue (see `comment-on-github-issue`) so the spawned session finds it there. Don't bake the decision into the spawn prompt — the prompt stays exactly as written above.
- If the session-spawning tool isn't available in the current harness, fall back to printing the prompts for the user to paste into new chats themselves.
