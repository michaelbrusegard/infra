"""Exercise the workflow's boot wait without starting a real emulator."""

import os
from pathlib import Path
import subprocess
import tempfile
import textwrap
import unittest


WORKFLOW = Path(__file__).resolve().parents[5] / ".github/workflows/hermes-android-image.yaml"


class AndroidCiStartupTests(unittest.TestCase):
    def run_boot_wait(self, scenario):
        workflow = WORKFLOW.read_text()
        start = workflow.index("          wait_for_boot() {")
        end = workflow.index("\n          adb_cmd()", start)
        wait_for_boot = textwrap.dedent(workflow[start:end])
        fixture = r"""
set -euo pipefail
round=0
sleep() { round=$((round + 1)); }
docker() {
  case "$1" in
    exec)
      if [ "$3" = bash ]; then
        # The launcher's ADB listener becomes ready before Android boots.
        [ "$round" -ge 1 ] && [ "$SCENARIO" != timeout ]
      else
        if [ "$round" -lt 1 ]; then
          echo 'ADB probe raced launcher startup' > "$COLLISION"
          return 1
        fi
        if [ "$4" = -s ] && [ "$round" -ge 2 ]; then
          printf '1\r\n'
        fi
      fi
      ;;
    inspect)
      if [ -f "$COLLISION" ] || [ "$SCENARIO" = exited ]; then
        echo false
      else
        echo true
      fi
      ;;
    logs) : ;;
    *) return 99 ;;
  esac
}
"""
        with tempfile.TemporaryDirectory() as directory:
            collision = Path(directory) / "collision"
            result = subprocess.run(
                ["bash"],
                input=fixture + wait_for_boot + '\nwait_for_boot\nprintf "%s\\n" "$round"\n',
                text=True,
                capture_output=True,
                timeout=10,
                env={**os.environ, "SCENARIO": scenario, "COLLISION": str(collision)},
            )
            self.assertFalse(collision.exists(), "probe must not auto-start a competing ADB server")
            return result

    def test_waits_for_adb_listener_and_then_android_boot(self):
        result = self.run_boot_wait("boot")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "2")

    def test_container_exit_still_fails(self):
        self.assertNotEqual(self.run_boot_wait("exited").returncode, 0)

    def test_listener_timeout_still_fails(self):
        self.assertNotEqual(self.run_boot_wait("timeout").returncode, 0)


if __name__ == "__main__":
    unittest.main()
