"""Exercise mail synchronization with fake mail tools and a real flock."""

import fcntl
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "mail-sync.sh"


class MailSyncTest(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.TemporaryDirectory()
        self.addCleanup(self.root.cleanup)
        root = Path(self.root.name)
        self.log = root / "calls"
        self.log.touch()
        self.env = dict(
            os.environ,
            PATH=f"{root}:{os.environ['PATH']}",
            XDG_RUNTIME_DIR=str(root),
            ARCMAC_TEST_LOG=str(self.log),
        )
        for tool in ("mbsync", "notmuch"):
            executable = root / tool
            executable.write_text(
                f'#!{shutil.which("bash")}\n'
                f'printf "%s\\n" "{tool} $*" >> "$ARCMAC_TEST_LOG"\n'
                f'if [ "${{ARCMAC_TEST_FAIL:-}}" = "{tool}" ]; then exit 23; fi\n'
            )
            executable.chmod(0o755)

    def run_sync(self, *args):
        return subprocess.run(
            ["bash", str(SCRIPT), *args], env=self.env,
            capture_output=True, text=True, timeout=10,
        )

    def test_full_pipeline(self):
        result = self.run_sync()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log.read_text(), "mbsync -a\nnotmuch new\nmbsync -a\n")
        self.assertIn("Mail sync done", result.stdout)

    def test_failure_stops_pipeline_and_releases_lock(self):
        for tool, expected in (
            ("mbsync", "mbsync -a\n"),
            ("notmuch", "mbsync -a\nnotmuch new\n"),
        ):
            with self.subTest(tool=tool):
                self.log.write_text("")
                self.env["ARCMAC_TEST_FAIL"] = tool
                result = self.run_sync()
                self.assertEqual(result.returncode, 23)
                self.assertEqual(self.log.read_text(), expected)
                self.assertIn("Mail sync failed", result.stderr)
                del self.env["ARCMAC_TEST_FAIL"]
                self.assertEqual(self.run_sync().returncode, 0)

    def test_busy_manual_call_and_queued_sent_sync(self):
        lock = Path(self.root.name) / "arcmac-mail-sync.lock"
        with lock.open("w") as handle:
            fcntl.flock(handle, fcntl.LOCK_EX)
            result = self.run_sync()
            self.assertEqual(result.returncode, 75)
            self.assertIn("already running", result.stdout)
            self.assertEqual(self.log.read_text(), "")
            with subprocess.Popen(
                ["bash", str(SCRIPT), "--wait"], env=self.env,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            ) as queued:
                try:
                    self.assertEqual(queued.stdout.readline(), "Waiting for mail sync lock…\n")
                    self.assertIsNone(queued.poll())
                    self.assertEqual(self.log.read_text(), "")
                    fcntl.flock(handle, fcntl.LOCK_UN)
                    output, errors = queued.communicate(timeout=10)
                    self.assertEqual(queued.returncode, 0, errors)
                    self.assertIn("Mail sync done", output)
                finally:
                    if queued.poll() is None:
                        queued.kill()
            self.assertEqual(self.log.read_text(), "mbsync -a\nnotmuch new\nmbsync -a\n")

    def test_invalid_arguments_do_not_sync(self):
        for args in (("--invalid",), ("--wait", "extra")):
            self.assertEqual(self.run_sync(*args).returncode, 64)
        self.assertEqual(self.log.read_text(), "")


if __name__ == "__main__":
    unittest.main()
