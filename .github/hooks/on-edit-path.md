<!-- consumed by: the shared pretooluse-edit-path.sh (pangeachat/.github), which checks this -->
<!-- repo-local table BEFORE the org table — harness-sync.instructions.md § Repo-specific hooks. -->
<!-- format: blank-line-separated pairs — line 1 an extended-regex pattern matched against the -->
<!-- FILE PATH being edited, remaining lines the message. First match wins; rows fire once per -->
<!-- session per pattern (` [always]` suffix repeats every time). -->

lib/l10n/intl_en\.arb$
Adding UI string keys? Every new key in intl_en.arb must be translated into ALL locales before merge — the l10n-sync CI gate blocks otherwise. Remediation is the backfill-l10n skill: `uv run scripts/translate/translate_new_keys.py`, then `flutter gen-l10n`. localization.instructions.md governs.
