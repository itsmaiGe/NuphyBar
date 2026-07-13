"""SPDX-License-Identifier: GPL-2.0-or-later"""

import unittest

from build_candidate import encode_thumb_bl


class ThumbBranchEncodingTests(unittest.TestCase):
    def test_reproduces_verified_official_sys_led_call(self) -> None:
        self.assertEqual(
            encode_thumb_bl(0x080028EA, 0x080023A4),
            bytes.fromhex("ff f7 5b fd"),
        )

    def test_encodes_candidate_hook_call(self) -> None:
        self.assertEqual(
            encode_thumb_bl(0x080028EA, 0x08010E00),
            bytes.fromhex("0e f0 89 fa"),
        )


if __name__ == "__main__":
    unittest.main()
