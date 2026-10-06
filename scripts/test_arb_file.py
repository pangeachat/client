"""Run with: python3 -m unittest discover -s scripts -p 'test_arb_file.py'"""

import tempfile
import unittest
from pathlib import Path

from arb_file import remove_entries, translation_keys

ARB = """{
    "@@locale": "en",
    "keep": "Keep",
    "@keep": {"type": "String", "placeholders": {}},
    "drop": "Drop {name}",
    "@drop": {
        "placeholders": {
            "name": {"type": "String"}
        }
    },
    "last": "Last"
}
"""


class RemoveEntriesTest(unittest.TestCase):
    def setUp(self) -> None:
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.path = Path(directory.name) / "intl_en.arb"
        self.path.write_text(ARB, encoding="utf-8")

    def test_removes_entry_and_metadata_leaving_other_lines_byte_identical(self) -> None:
        self.assertEqual(remove_entries(self.path, {"drop", "@drop"}), ["drop", "@drop"])
        self.assertEqual(
            self.path.read_text(encoding="utf-8"),
            '{\n    "@@locale": "en",\n    "keep": "Keep",\n'
            '    "@keep": {"type": "String", "placeholders": {}},\n'
            '    "last": "Last"\n}\n',
        )

    def test_removing_the_last_entry_drops_its_leading_comma(self) -> None:
        remove_entries(self.path, {"last"})
        self.assertTrue(self.path.read_text(encoding="utf-8").endswith('\n        }\n    }\n}\n'))

    def test_removing_the_first_entry_keeps_the_next_one_first(self) -> None:
        remove_entries(self.path, {"@@locale"})
        self.assertTrue(self.path.read_text(encoding="utf-8").startswith('{\n    "keep": "Keep",\n'))

    def test_absent_names_leave_the_file_unwritten(self) -> None:
        before = self.path.stat().st_mtime_ns
        self.assertEqual(remove_entries(self.path, {"missing"}), [])
        self.assertEqual(self.path.stat().st_mtime_ns, before)


class TranslationKeysTest(unittest.TestCase):
    def test_skips_metadata_at_any_indentation(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "intl_en.arb"
            path.write_text('{\n  "@@locale": "en",\n\t"a": "A",\n"@a": {},\n        "b": "B"\n}\n', encoding="utf-8")
            self.assertEqual(translation_keys(path), ["a", "b"])


if __name__ == "__main__":
    unittest.main()
