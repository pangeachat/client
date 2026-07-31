<!-- consumed by: the shared pretooluse-reminders.sh (pangeachat/.github), which reads this -->
<!-- repo-local table after the org table — harness-sync.instructions.md § Repo-specific hooks. -->
<!-- format: blank-line-separated pairs — line 1 an extended-regex pattern matched against the -->
<!-- about-to-run command, remaining lines the message. Every matching row fires, once per -->
<!-- session per pattern (` [always]` suffix repeats every time). -->

scripts/translate/|flutter gen-l10n
Client l10n tooling — if the backfill-l10n skill isn't already in context, read .github/skills/backfill-l10n/SKILL.md first: which script fits (new keys vs new locale vs one locale), the `uv run` invocations, and the required post-run steps. localization.instructions.md governs.

gh pr create [always]
Does this change warrant a `pubspec.yaml` version bump? Most PRs need none — bump when this is the thing a future force-upgrade floor would target, or when cutting a release. Decide the level by asking "would we ever force someone onto this?": no → patch (the default), a feature or migration you may later force → minor, a protocol/stored-data break or fleet cutover → major. See deployment.instructions.md § Versioning. State your call before proceeding.
