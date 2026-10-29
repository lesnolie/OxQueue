import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import release


class ReleaseTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        for folder in ("OxQueue", "tools", "tests"):
            (self.root / folder).mkdir()
        (self.root / "AGENTS.md").write_text("Record changes.\n")
        (self.root / "OxQueue/OxQueue.toc").write_text("## Version: 1.0.1\n")
        (self.root / "OxQueue/OxQueue.lua").write_text('local VERSION = "1.0.1"\n')
        (self.root / "CHANGELOG.json").write_text("[]\n")

    def record(self):
        return release.record(self.root, ["按专精保存。"], ["Save per spec."], ["Mock tests passed."])

    def test_source_change_blocks_release_until_recorded(self):
        self.record()
        file = self.root / "OxQueue/OxQueue.lua"
        file.write_text(file.read_text() + "-- changed\n")
        with self.assertRaisesRegex(ValueError, "without a matching changelog"):
            release.check(self.root)
        self.record()
        self.assertEqual(release.check(self.root)["version"], "1.0.1")
        self.assertEqual(len(json.loads((self.root / "CHANGELOG.json").read_text(encoding="utf-8"))), 2)

    def test_new_file_is_a_change(self):
        self.record()
        (self.root / "OxQueue/New.lua").write_text("-- new\n")
        with self.assertRaisesRegex(ValueError, "without a matching changelog"):
            release.check(self.root)

    def test_tools_and_tests_are_also_logged(self):
        self.record()
        (self.root / "tools/helper.py").write_text("# changed\n")
        with self.assertRaisesRegex(ValueError, "without a matching changelog"):
            release.check(self.root)

    def test_generated_notes_cannot_diverge(self):
        self.record()
        (self.root / "CHANGELOG.md").write_text("stale\n")
        with self.assertRaisesRegex(ValueError, "differs"):
            release.check(self.root)

    def test_version_mismatch_blocks_release(self):
        (self.root / "OxQueue/OxQueue.toc").write_text("## Version: 1.0.2\n")
        with self.assertRaisesRegex(ValueError, "versions must match"):
            self.record()


if __name__ == "__main__":
    unittest.main(verbosity=2)
