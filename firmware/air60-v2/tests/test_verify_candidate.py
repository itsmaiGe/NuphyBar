"""SPDX-License-Identifier: GPL-2.0-or-later"""

import pathlib
import subprocess
import sys
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class CandidateVerificationTests(unittest.TestCase):
    def test_rejects_invalid_candidate_when_assertions_are_disabled(self) -> None:
        suffix = b"\x00" * 8 + b"UFD" + bytes([16]) + b"\x00" * 4

        with tempfile.TemporaryDirectory() as directory:
            directory = pathlib.Path(directory)
            official = directory / "official.bin"
            candidate = directory / "candidate.bin"
            hook = directory / "hook.bin"
            official.write_bytes(b"official" + suffix)
            candidate.write_bytes(b"invalid" + suffix)
            hook.write_bytes(b"hook")

            result = subprocess.run(
                [
                    sys.executable,
                    "-O",
                    str(ROOT / "verify_candidate.py"),
                    "--official",
                    str(official),
                    "--candidate",
                    str(candidate),
                    "--hook",
                    str(hook),
                ],
                capture_output=True,
                text=True,
                check=False,
            )

        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
