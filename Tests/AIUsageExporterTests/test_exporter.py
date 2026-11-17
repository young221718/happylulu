import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[2] / "Sources/AIUsagePlugin/Resources/export-ai-usage.py"


class ExporterTests(unittest.TestCase):
    def run_exporter(self, provider, payload, output):
        return subprocess.run([sys.executable, str(SCRIPT), "--provider", provider,
                               "--output", str(output)], input=json.dumps(payload),
                              text=True, capture_output=True)

    def test_claude_exports_only_allowlisted_quota_and_private_atomic_file(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "usage.json"
            output.write_text("old")
            os.chmod(output, 0o644)
            result = self.run_exporter("claude", {
                "session_id": "private-session", "transcript_path": "/private/chat.jsonl",
                "rate_limits": {"seven_day": {"used_percentage": 41.2, "resets_at": 2000000000,
                                               "secret": "not-for-export"}},
                "context_window": {"used_percentage": 88}, "email": "private@example.com"
            }, output)
            self.assertEqual(result.returncode, 0, result.stderr)
            data = json.loads(output.read_text())
            self.assertEqual(set(data), {"schema", "provider", "observedAt", "rate_limits"})
            self.assertEqual(data["rate_limits"], {"seven_day": {"used_percentage": 41.2,
                                                                  "resets_at": 2000000000}})
            self.assertEqual(output.stat().st_mode & 0o777, 0o600)
            self.assertNotIn("private", output.read_text() + result.stdout + result.stderr)

    def test_antigravity_exports_quota_without_personal_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "usage.json"
            result = self.run_exporter("antigravity", {
                "product": "antigravity", "email": "private@example.com",
                "quota": {"gemini-weekly": {"remaining_fraction": 0.9378,
                                              "reset_time": "2030-01-01T00:00:00Z"}},
                "transcript_path": "/private/chat"
            }, output)
            self.assertEqual(result.returncode, 0, result.stderr)
            data = json.loads(output.read_text())
            self.assertEqual(data["quota"]["gemini-weekly"]["remaining_fraction"], 0.9378)
            self.assertNotIn("private", output.read_text())
            self.assertEqual(len(data["accountKey"]), 64)

    def test_symlink_and_public_parent_are_rejected_without_modifying_target(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "target"
            target.write_text("preserve")
            link = Path(directory) / "link"
            link.symlink_to(target)
            for output in [link, Path(directory) / "public" / "usage.json"]:
                if output.name == "usage.json":
                    output.parent.mkdir(mode=0o755)
                result = self.run_exporter("claude", {"rate_limits": {}}, output)
                self.assertNotEqual(result.returncode, 0)
            self.assertEqual(target.read_text(), "preserve")

    def test_invalid_input_keeps_previous_file_and_logs_no_payload(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "usage.json"
            for provider, payload in [
                ("claude", {"rate_limits": {"seven_day": {"used_percentage": True}}}),
                ("claude", {"rate_limits": {"seven_day": {"used_percentage": 101, "resets_at": 2000000000}}}),
                ("claude", {"rate_limits": []}),
                ("antigravity", {"product": "wrong", "quota": {"gemini-weekly": {}}})
            ]:
                output.write_text("preserved")
                result = self.run_exporter(provider, payload, output)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(output.read_text(), "preserved")
                self.assertNotIn("used_percentage", result.stderr)


if __name__ == "__main__":
    unittest.main()
