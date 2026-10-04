"""Exercise validation and process cleanup without generating CPU load."""
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "generate-cpu.sh"


class GenerateCpuTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.pid_log = self.directory / "workers"
        fake_yes = self.directory / "yes"
        fake_yes.write_text('#!/bin/sh\necho "$$" >> "$PID_LOG"\nexec sleep 600\n')
        fake_yes.chmod(0o755)
        self.env = dict(os.environ, PID_LOG=str(self.pid_log),
                        PATH=f"{self.directory}:{os.environ['PATH']}")

    def workers(self):
        if not self.pid_log.exists():
            return []
        return [int(pid) for pid in self.pid_log.read_text().splitlines()]

    def assert_workers_stopped(self):
        for pid in self.workers():
            with self.assertRaises(ProcessLookupError):
                os.kill(pid, 0)

    def test_invalid_arguments_do_not_start_load(self):
        for arguments in [("",), ("0",), ("-1",), ("01",), ("1801",), ("text",),
                          ("1", ""), ("1", "0"), ("1", "65"), ("1", "x"),
                          ("1", "1", "extra")]:
            with self.subTest(arguments=arguments):
                result = subprocess.run(["bash", str(SCRIPT), *arguments],
                                        env=self.env, capture_output=True, text=True, timeout=5)
                self.assertEqual(result.returncode, 2)
                self.assertIn("Usage:", result.stderr)
        self.assertEqual(self.workers(), [])

    def test_timeout_cleans_up_only_its_own_workers(self):
        unrelated = subprocess.Popen([str(self.directory / "yes")],
                                     env=dict(self.env, PID_LOG=str(self.directory / "unrelated")))
        try:
            result = subprocess.run(["bash", str(SCRIPT), "1", "2"], env=self.env,
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(len(self.workers()), 2)
            self.assert_workers_stopped()
            self.assertIsNone(unrelated.poll())
        finally:
            unrelated.terminate()
            unrelated.wait(timeout=5)

    def test_sigterm_cleans_up_workers(self):
        process = subprocess.Popen(["bash", str(SCRIPT), "30", "2"], env=self.env,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            deadline = time.monotonic() + 5
            while len(self.workers()) < 2 and time.monotonic() < deadline:
                time.sleep(0.02)
            self.assertEqual(len(self.workers()), 2)
            process.send_signal(signal.SIGTERM)
            process.communicate(timeout=5)
            self.assertEqual(process.returncode, 143)
            self.assert_workers_stopped()
        finally:
            if process.poll() is None:
                process.terminate()
                process.communicate(timeout=5)


if __name__ == "__main__":
    unittest.main()
