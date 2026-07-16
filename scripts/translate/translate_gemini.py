"""Translate one locale's `intl_<lang>.arb` from `intl_en.arb` using Gemini
2.5 Pro on Vertex AI, preserving ICU placeholders/plurals and validating every
value before writing.

Design: see client/.github/instructions/localization.instructions.md and the
cross-repo language-list doc (L1 = LLM-supported). This is the canonical
translator (it replaced the legacy OpenAI / DeepL scripts).

Auth — Vertex AI (SA / ADC, Cloud Billing), NOT the deprecated AI Studio
API-key path (its prepaid pool depletes silently). Set:
  GOOGLE_APPLICATION_CREDENTIALS  path to a cloud-platform-scoped SA JSON
                                  (or run `gcloud auth application-default login`)
  VERTEX_PROJECT   GCP project (default: the SA's own project)
  VERTEX_LOCATION  Vertex region (default: "global", serves all Gemini GA models)

Usage:
  python scripts/translate/translate_gemini.py --lang af --name Afrikaans
  # optional: --l10n <dir> (default lib/l10n), --limit N (smoke test), --dry
"""

import argparse
import json
import os
import re
import sys
import time
from datetime import datetime
from pathlib import Path

from google import genai
from google.genai import errors as genai_errors
from google.genai import types

BATCH = 80
# Translation needs no reasoning. Flash allows thinking_budget=0 (fastest);
# Pro forbids 0, so it gets its floor (128). Flash is ~4x faster with
# near-identical quality on short UI strings — the default for bulk backfill;
# use Pro (--model gemini-2.5-pro) when a locale warrants the extra quality.
_THINKING_FLOOR = {"gemini-2.5-pro": 128}

# Bare variable references like {homeserver}, {count} — NOT ICU sub-messages
# ({var, plural, ...} has a comma; =1{...} has spaces/digits inside).
VAR_RE = re.compile(r"\{(\w+)\}")

PROMPT = """You are a professional software-localization translator. Translate the VALUES of the following JSON object from English into {name}. This is UI text for a language-learning chat app.

Rules — follow exactly:
- Return ONLY a JSON object mapping each original key to its translated value. No prose, no markdown fences.
- Keep every key unchanged.
- Preserve ICU placeholders EXACTLY: tokens in curly braces like {{username}}, {{count}}, {{homeserver}} must appear verbatim, untranslated, in the same positions.
- Preserve ICU plural/select syntax EXACTLY, e.g. `{{count, plural, =1{{...}} other{{...}}}}` — do not translate the keywords `plural`, `select`, `one`, `other`, `=1`, or the variable name; translate ONLY the human-readable text inside each branch.
- Do not add, drop, or reorder placeholders. Leave non-text literal values (e.g. "true"/"false") unchanged.
- Use natural, native-quality {name}; match the app's friendly, concise tone.

JSON to translate:
{payload}"""


def var_set(s: str) -> set:
    return set(VAR_RE.findall(s))


def is_icu(s: str) -> bool:
    return "plural," in s or "select," in s


def validate(en_val: str, tr_val: str) -> str | None:
    """Return an error string if the translation is structurally wrong, else None."""
    if not isinstance(tr_val, str) or not tr_val.strip():
        return "empty"
    if var_set(en_val) != var_set(tr_val):
        return f"placeholder mismatch en={sorted(var_set(en_val))} tr={sorted(var_set(tr_val))}"
    if is_icu(en_val) != is_icu(tr_val):
        return "ICU plural/select structure lost"
    if is_icu(en_val):
        for kw in ("plural,", "select,", "other{"):
            if en_val.count(kw) != tr_val.count(kw):
                return f"ICU keyword count differs for {kw!r}"
    if "```" in tr_val:
        return "markdown fence leaked into value"
    return None


def vertex_client() -> genai.Client:
    import google.auth

    creds, default_project = google.auth.default(
        scopes=["https://www.googleapis.com/auth/cloud-platform"]
    )
    project = os.environ.get("VERTEX_PROJECT") or default_project
    location = os.environ.get("VERTEX_LOCATION", "global")
    print(f"Vertex: project={project} location={location}")
    return genai.Client(vertexai=True, project=project, location=location, credentials=creds)


def translate_batch(client: genai.Client, model: str, name: str, batch: dict) -> dict:
    prompt = PROMPT.format(name=name, payload=json.dumps(batch, ensure_ascii=False, indent=2))
    thinking = _THINKING_FLOOR.get(model, 0)
    for attempt in range(6):
        try:
            resp = client.models.generate_content(
                model=model,
                contents=prompt,
                config=types.GenerateContentConfig(
                    temperature=0.2,
                    response_mime_type="application/json",
                    thinking_config=types.ThinkingConfig(thinking_budget=thinking),
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
        except json.JSONDecodeError as e:
            print(f"    JSON parse fail (attempt {attempt + 1}): {e}; retrying")
            time.sleep(2)
    raise RuntimeError("batch failed to parse after retries")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--lang", required=True, help="target locale code, e.g. af")
    ap.add_argument("--name", required=True, help="English display name, e.g. Afrikaans")
    ap.add_argument("--l10n", default="lib/l10n", help="l10n dir (default lib/l10n)")
    ap.add_argument("--limit", type=int, default=0, help="translate only first N keys (smoke test)")
    ap.add_argument("--dry", action="store_true", help="validate but do not write the arb")
    ap.add_argument(
        "--model", default="gemini-2.5-flash",
        help="Gemini model (default gemini-2.5-flash; use gemini-2.5-pro for higher quality)",
    )
    args = ap.parse_args()

    l10n = Path(args.l10n)
    en = json.loads((l10n / "intl_en.arb").read_text(encoding="utf-8"))
    keys = [k for k in en if not k.startswith("@")]
    if args.limit:
        keys = keys[: args.limit]

    client = vertex_client()
    out: dict[str, str] = {}
    errors: list[str] = []
    for i in range(0, len(keys), BATCH):
        chunk = keys[i : i + BATCH]
        tr = translate_batch(client, args.model, args.name, {k: en[k] for k in chunk})
        for k in chunk:
            if k not in tr:
                errors.append(f"{k}: MISSING from response")
                continue
            err = validate(en[k], tr[k])
            if err:
                errors.append(f"{k}: {err} | en={en[k]!r} tr={tr[k]!r}")
            out[k] = tr[k]
        print(f"  {min(i + BATCH, len(keys))}/{len(keys)} translated")

    print(f"\nTranslated {len(out)}/{len(keys)} keys, {len(errors)} validation errors")
    for e in errors[:40]:
        print("  ERR", e)

    if args.dry:
        print("(dry run — not writing)")
        return
    if errors:
        sys.exit("Refusing to write arb with validation errors. Fix and retry.")

    doc = {"@@locale": args.lang, "@@last_modified": datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")}
    doc.update(out)
    (l10n / f"intl_{args.lang}.arb").write_text(
        json.dumps(doc, indent=4, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    print(f"wrote intl_{args.lang}.arb ({len(out)} keys)")

    prov_path = l10n / "ai-translated-keys.json"
    prov = json.loads(prov_path.read_text(encoding="utf-8")) if prov_path.exists() else {}
    prov[args.lang] = keys
    prov_path.write_text(json.dumps(prov, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
