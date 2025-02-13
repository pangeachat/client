"""
Prerequiresite:
- Ensure you have an up-to-date `needed-translations.txt` file should you wish to translate only the missing translation keys. To generate an updated `needed-translations.txt` file, run `flutter gen-l10n`. Generating the file is not necessary if you wish to translate all translation keys.
- Ensure you have python `openai` package installed. If not, run `pip install openai`.
- Ensure you have an OpenAI API key set in your environment variable `OPENAI_API_KEY`. If not, you can set it by running `export OPENAI_API_KEY=your-api-key` on MacOS/Linux.

Usage:
python scripts/translate.py
"""


def load_needed_translations() -> dict[str, list[str]]:
    import json
    from pathlib import Path

    path_to_needed_translations = (
        Path(__file__).parent.parent / "needed-translations.txt"
    )
    if not path_to_needed_translations.exists():
        raise FileNotFoundError(
            f"File not found: {path_to_needed_translations}. Please run `flutter gen-l10n` to generate the file."
        )
    with open(path_to_needed_translations) as f:
        needed_translations = json.loads(f.read())

    return needed_translations


def load_translations(lang_code: str) -> dict[str, str]:
    import json
    from pathlib import Path

    path_to_translations = (
        Path(__file__).parent.parent / "assets" / "l10n" / f"intl_{lang_code}.arb"
    )
    if not path_to_translations.exists():
        raise FileNotFoundError(
            f"File not found: {path_to_translations}. Please run `flutter gen-l10n` to generate the file."
        )

    with open(path_to_translations) as f:
        translations = json.loads(f.read())

    return translations


def save_translations(lang_code: str, translations: dict[str, str]) -> None:
    import json
    from pathlib import Path
    from datetime import datetime
    from collections import OrderedDict

    path_to_translations = (
        Path(__file__).parent.parent / "assets" / "l10n" / f"intl_{lang_code}.arb"
    )

    translations["@@locale"] = lang_code
    translations["@@last_modified"] = str(
        datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")
    )

    # Load the existing file to preserve key order if available.
    if path_to_translations.exists():
        with open(path_to_translations, "r") as f:
            try:
                existing_data = json.load(f, object_pairs_hook=OrderedDict)
            except json.JSONDecodeError:
                existing_data = OrderedDict()
    else:
        existing_data = OrderedDict()

    # Merge: update values for keys that exist; append new keys to the bottom.
    merged = OrderedDict()
    for key in existing_data.keys():
        if key in translations:
            merged[key] = translations[key]
    for key in translations:
        if key not in merged:
            merged[key] = translations[key]

    with open(path_to_translations, "w") as f:
        f.write(json.dumps(merged, indent=2, ensure_ascii=False))


def reconcile_metadata(lang_code: str) -> None:
    """
    There are translations that are missing its metadata.
    This function will add metadata to those translations.
    """
    import re

    translations = load_translations(lang_code)

    # Find translations keys
    translation_keys = []
    for key in translations.keys():
        if not key.startswith("@"):
            translation_keys.append(key)

    # Add metadata to missing translations
    for key in translation_keys:
        translation = translations[key]
        assert isinstance(translation, str)

        # Case 1: basic translations, no placeholders
        if "{" not in translation:
            translations[f"@{key}"] = {
                "type": "text",
                "placeholders": {"type": "text", "placeholders": {}},
            }

        # Case 2: translations with placeholders
        elif (
            "{" in translation
            and "plural," not in translation
            and "other{" not in translation
        ):
            # Find placeholders
            placeholders = {}
            for placeholder in translation.split("{")[1:]:
                placeholder_name = placeholder.split("}")[0]
                placeholders[placeholder_name] = {"type": "String"}
            translations[f"@{key}"] = {"type": "text", "placeholders": placeholders}
        # Case 3: translations with pluralization
        elif (
            "{" in translation and "plural," in translation and "other{" in translation
        ):
            # Extract all placeholders that appear before the plural part
            prefix = translation.split("plural,")[0].split("{")[1]
            placeholders_list = prefix.split(",")
            placeholders_list = [p.strip() for p in placeholders_list]
            placeholders_list = [p for p in placeholders_list if p != ""]
            placeholders = {ph: {} for ph in placeholders_list}
            translations[f"@{key}"] = {"type": "text", "placeholders": placeholders}

    save_translations(lang_code, translations)


def reconcile_invalid_metadata_type(lang_code: str) -> None:
    """
    There exists some translations with invalid metadata type.
    This function will reconcile them by coercing invalid types to "text".
    """
    translations = load_translations(lang_code)

    for key in translations.keys():
        if key.startswith("@"):
            metadata = translations[key]
            if "type" not in metadata:
                continue
            assert isinstance(metadata["type"], str)
            # Valid types are "text", "image", "css"
            if metadata["type"] not in ["text", "image", "css"]:
                # Default to text if invalid type
                metadata["type"] = "text"
                translations[key] = metadata

    save_translations(lang_code, translations)


def reconcile_empty_metadata(lang_code: str) -> None:
    """
    There exists some translations with empty metadata but with placeholders.
    Emptyy metadata should not have placeholders.
    This function will reconcile them by removing the placeholders and replace
    it with an empty dictionary.
    """
    translations = load_translations(lang_code)

    for key in translations.keys():
        if key.startswith("@"):
            translation_key = key[1:]
            if translation_key not in translations:
                continue
            translation = translations[translation_key]
            assert isinstance(translation, str)
            if "{" in translation:
                continue  # not a translation without placeholders
            translations[key] = {}

    save_translations(lang_code, translations)


def translate(
    lang_code: str, lang_display_name: str, translate_all: bool = False
) -> None:
    """
    Translate the needed translations from English to the target language.
    If `translate_all` is set to True, all translation keys will be translated,
    otherwise keys in `needed-translations.txt` will be translated.
    """
    import json
    import random
    from openai import OpenAI

    if not translate_all:
        needed_translations = load_needed_translations()
        needed_translations = needed_translations.get(lang_code, [])
    else:
        needed_translations = [
            k for k in load_translations("en").keys() if not k.startswith("@")
        ]
    english_translations_dict = load_translations("en")
    vietnamese_translations_dict = load_translations("vi")

    # there are 3 types of translation keys: basic, with placeholders, with pluralization. Read more: TRANSLATORS_GUIDE.md

    basic_translation_keys = [
        k
        for k in english_translations_dict.keys()
        if not k.startswith("@") and not english_translations_dict[k].startswith("{")
    ]
    example_basic_translation_keys = (
        random.sample(basic_translation_keys, 2)
        if len(basic_translation_keys) > 2
        else basic_translation_keys
    )

    placeholder_translation_keys = [
        k
        for k in english_translations_dict.keys()
        if not k.startswith("@")
        and "{" in english_translations_dict[k]
        and "plural," not in english_translations_dict[k]
        and "other{" not in english_translations_dict[k]
    ]
    example_placeholder_translation_keys = (
        random.sample(placeholder_translation_keys, 2)
        if len(placeholder_translation_keys) > 2
        else placeholder_translation_keys
    )
    plural_translation_keys = [
        k
        for k in english_translations_dict.keys()
        if not k.startswith("@")
        and "{" in english_translations_dict[k]
        and "plural," in english_translations_dict[k]
        and "other{" in english_translations_dict[k]
    ]
    example_plural_translation_keys = (
        random.sample(plural_translation_keys, 2)
        if len(plural_translation_keys) > 2
        else plural_translation_keys
    )

    # build example translations
    example_english_translations = {}
    for key in example_basic_translation_keys:
        example_english_translations[key] = english_translations_dict[key]
    for key in example_placeholder_translation_keys:
        example_english_translations[key] = english_translations_dict[key]
    for key in example_plural_translation_keys:
        example_english_translations[key] = english_translations_dict[key]

    example_vietnamese_translations = {}
    for key in example_basic_translation_keys:
        example_vietnamese_translations[key] = vietnamese_translations_dict[key]
    for key in example_placeholder_translation_keys:
        example_vietnamese_translations[key] = vietnamese_translations_dict[key]
    for key in example_plural_translation_keys:
        example_vietnamese_translations[key] = vietnamese_translations_dict[key]

    new_translations = {}
    progress = 0
    for i in range(0, len(needed_translations), 20):
        chunk = needed_translations[i : i + 20]
        translation_requests = {}
        for key in chunk:
            translation_requests[key] = english_translations_dict[key]

        prompt = f"""
        Please translate the following text from English to {lang_display_name}.
        Example:
        req: {json.dumps(example_english_translations, indent=2)}
        res: {json.dumps(example_vietnamese_translations, indent=2)}
        ========================
        req: {json.dumps(translation_requests, indent=2)}
        res:
        """

        client = OpenAI()
        chat_completion = client.chat.completions.create(
            messages=[
                {
                    "role": "system",
                    "content": "You are a translator that will only response to translation requests in json format without any additional information.",
                },
                {
                    "role": "user",
                    "content": prompt,
                },
            ],
            model="gpt-4o-mini",
            temperature=0.0,
        )
        response = chat_completion.choices[0].message.content
        _new_translations = json.loads(response)
        new_translations.update(_new_translations)
        print(f"Translated {progress + len(chunk)}/{len(needed_translations)}")
        progress += len(chunk)

    current_translations = load_translations(lang_code)
    current_translations.update(new_translations)
    save_translations(lang_code, current_translations)


"""Example usage:
python scripts/translate.py
"""
if __name__ == "__main__":
    import os

    lang_code = input("Enter the language code (e.g. vi, en): ").strip()
    lang_display_name = input(
        "Enter the language display name (e.g. Vietnamese, English): "
    )
    translate_all = (
        input(
            "Do you want to translate all translation keys? The alternative is to translate all the keys in `needed-translations.txt`. (y/n): "
        )
        .strip()
        .lower()
        == "y"
    )
    if os.environ.get("OPENAI_API_KEY") is None:
        os.environ["OPENAI_API_KEY"] = input(
            "It seems like you haven't set OPENAI_API_KEY environment variable. That's ok, you can enter it here: "
        ).strip()

    # Ensure English is reconciled before perfomirng translation since
    # it is the base example language.
    reconcile_metadata("en")
    reconcile_invalid_metadata_type("en")
    reconcile_empty_metadata("en")

    # Translate the target language
    translate(
        lang_code=lang_code,
        lang_display_name=lang_display_name,
        translate_all=translate_all,
    )

    # Reconcile the target language
    reconcile_metadata(lang_code)
    reconcile_invalid_metadata_type(lang_code)
    reconcile_empty_metadata(lang_code)
