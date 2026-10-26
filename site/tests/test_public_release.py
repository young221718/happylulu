"""A future app candidate must not retarget the public site's downloads."""
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest


class PublicReleaseTests(unittest.TestCase):
    def test_future_app_candidate_keeps_public_downloads_valid(self):
        source = Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            shutil.copytree(source, root / "site")
            (root / "Resources").mkdir()
            (root / "Resources/Info.plist").write_bytes(plistlib.dumps({
                "CFBundleShortVersionString": "999.0.0",
                "CFBundleVersion": "99999",
            }))
            result = subprocess.run(
                [sys.executable, str(root / "site/check-site.py")],
                capture_output=True, text=True, check=False,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
