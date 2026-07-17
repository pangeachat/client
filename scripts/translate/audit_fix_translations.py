"""Audit and fix an existing locale's `intl_<lang>.arb` with Gemini 2.5 Pro.

Unlike `translate_gemini.py` (which translates from scratch), this REVIEWS each
existing translation against the English source and changes it only when it is
genuinely wrong — mistranslated, incomplete, left untranslated, or with broken
ICU placeholders. Correct, idiomatic, and legitimately-shared translations are
kept verbatim, so high-quality community (Weblate) translations are preserved.

Use it to catch drift/quality issues in existing locales without the downgrade
risk of blind re-translation. Design: client/.github/instructions/localization.instructions.md.

Auth: Vertex AI, same as translate_gemini.py (GOOGLE_APPLICATION_CREDENTIALS,
VERTEX_PROJECT, VERTEX_LOCATION).

Usage:
  python scripts/translate/audit_fix_translations.py --lang de --name German
  # --dry reports proposed changes without writing; --limit N reviews first N keys
"""

import argparse
import json
import os
import re
import time
from datetime import datetime
from pathlib import Path

from google import genai
from google.genai import errors as genai_errors
from google.genai import types

MODEL = "gemini-2.5-pro"
BATCH = 50
VAR_RE = re.compile(r"\{(\w+)\}")
PIVOT_RE = re.compile(r"\{(\w+),\s*(?:plural|select)")


def refs(s: str) -> set:
    """Placeholder names referenced, as {name} or as an ICU pivot `name, plural`."""
    if not isinstance(s, str):
        return set()
    return set(VAR_RE.findall(s)) | set(PIVOT_RE.findall(s))


def validate(en_val: str, tr_val: str) -> str | None:
    if not isinstance(tr_val, str) or not tr_val.strip():
        return "empty"
    dropped = refs(en_val) - refs(tr_val)
    invented = refs(tr_val) - refs(en_val)
    if dropped:
        return f"dropped placeholder(s) {sorted(dropped)}"
    if invented:
        return f"invented placeholder(s) {sorted(invented)}"
    if "```" in tr_val:
        return "markdown fence leaked into value"
    return None


PROMPT = """You are auditing existing UI translations into {name} for a language-learning chat app. Each entry gives the key, the English source, and the current {name} translation (or null if missing).

Return the correct FINAL {name} translation for every key as a JSON object (key → value), nothing else.

Most of this copy is human community translation. Your job is to catch genuine errors, NOT to improve or restyle it. Return every value UNCHANGED unless it meets one of the four Fix Conditions below.

Fix Conditions — change a value ONLY if it is:
1. A mistranslation — the current translation means something different from the English.
2. Untranslated — still in English (or another wrong language) when it should be translated. Legitimately-shared terms and brand names (e.g. "Chat", "Homeserver", "FluffyChat", "Matrix", "Emoji", proper nouns) do NOT count as untranslated — keep them.
3. Incomplete — missing part of the meaning.
4. Broken placeholder/ICU — a `{{placeholder}}` is missing, extra, renamed, or the plural/select structure is malformed.

DO NOT change a value for any other reason. Specifically, NEVER change:
- punctuation, spacing, capitalization, or whitespace (e.g. "…" vs "...", a space before an ellipsis);
- one word for a synonym when the current word is correct (e.g. do not swap "Analytik"→"Analyse");
- formality or register (e.g. formal vs informal address, imperative vs infinitive);
- an already-understandable borrowed or playful term into a more "native" one.

When in doubt, KEEP the existing copy. Preserve ICU plural/select structure; translate only human-readable text; never drop or invent placeholders.

Entries:
{payload}"""


def vertex_client() -> genai.Client:
    import google.auth

    creds, default_project = google.auth.default(
        scopes=["https://www.googleapis.com/auth/cloud-platform"]
    )
    project = os.environ.get("VERTEX_PROJECT") or default_project
    location = os.environ.get("VERTEX_LOCATION", "global")
    print(f"Vertex: project={project} location={location} model={MODEL}")
    return genai.Client(vertexai=True, project=project, location=location, credentials=creds)


def review_batch(client, name, items: dict) -> dict:
    prompt = PROMPT.format(name=name, payload=json.dumps(items, ensure_ascii=False, indent=2))
    for attempt in range(6):
        try:
            resp = client.models.generate_content(
                model=MODEL,
                contents=prompt,
                config=types.GenerateContentConfig(
                    temperature=0.1,
                    response_mime_type="application/json",
                    thinking_config=types.ThinkingConfig(thinking_budget=128),
                ),
            )
        except genai_errors.APIError as e:
            if getattr(e, "code", None) in (429, 500, 503) and attempt < 5:
                time.sleep(2 ** attempt)
                continue
            raise
        text = (resp.text or "").strip()
        if text.startswith("```"):
            text = re.sub(r"^```\w*\n?|\n?```$", "", text).strip()
        try:
            return json.loads(text)
        except json.JSONDecodeError:
            time.sleep(2)
    raise RuntimeError("batch failed to parse after retries")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--lang", required=True)
    ap.add_argument("--name", required=True)
    ap.add_argument("--l10n", default="lib/l10n")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--dry", action="store_true", help="report proposed changes, don't write")
    args = ap.parse_args()

    l10n = Path(args.l10n)
    en = json.loads((l10n / "intl_en.arb").read_text(encoding="utf-8"))
    cur = json.loads((l10n / f"intl_{args.lang}.arb").read_text(encoding="utf-8"))
    keys = [k for k in en if not k.startswith("@")]
    if args.limit:
        keys = keys[: args.limit]

    client = vertex_client()
    final: dict[str, str] = {}
    errors: list[str] = []
    for i in range(0, len(keys), BATCH):
        chunk = keys[i : i + BATCH]
        items = {k: {"english": en[k], "current": cur.get(k)} for k in chunk}
        out = review_batch(client, args.name, items)
        for k in chunk:
            v = out.get(k)
            err = validate(en[k], v)
            if err:
                errors.append(f"{k}: {err} | value={v!r}")
            final[k] = v if v is not None else cur.get(k, en[k])
        print(f"  reviewed {min(i + BATCH, len(keys))}/{len(keys)}")

    changed = {k: (cur.get(k), final[k]) for k in keys if cur.get(k) != final[k]}
    print(f"\n{args.lang}: {len(changed)} keys changed, {len(errors)} validation errors")
    for k, (old, new) in list(changed.items())[:30]:
        print(f"  ~ {k}\n      old: {old!r}\n      new: {new!r}")
    for e in errors[:20]:
        print("  ERR", e)

    if args.dry:
        print("(dry run — not writing)")
        return
    if errors:
        print("Refusing to write with validation errors. Fix and retry.")
        return

    out_doc = {k: v for k, v in cur.items() if k.startswith("@")}
    out_doc["@@locale"] = args.lang
    out_doc["@@last_modified"] = datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")
    for k in keys:
        out_doc[k] = final[k]
    # keep any non-en keys that already existed (don't silently drop), except metadata rewritten above
    for k, v in cur.items():
        if k not in out_doc and not k.startswith("@"):
            out_doc[k] = v
    (l10n / f"intl_{args.lang}.arb").write_text(
        json.dumps(out_doc, indent=4, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    print(f"wrote intl_{args.lang}.arb ({len(changed)} keys changed)")


if __name__ == "__main__":
    main()
