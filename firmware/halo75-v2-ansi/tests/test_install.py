import importlib.util
import subprocess
import tempfile
import unittest
from pathlib import Path


INSTALL_PATH = Path(__file__).resolve().parents[1] / "install.py"
SPEC = importlib.util.spec_from_file_location("halo75_install", INSTALL_PATH)
INSTALL = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(INSTALL)


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.qmk_root = Path(self.temporary_directory.name)
        keyboard = self.qmk_root / "keyboards/nuphy/halo75_v2/ansi"
        (keyboard / "keymaps/via").mkdir(parents=True)
        (keyboard / "keyboard.json").write_text(
            '{"keyboard_name": "NuPhy Halo75 V2", "features": {}}\n'
        )
        (keyboard / "side.c").write_text(
            '#include "side.h"\n\nvoid m_side_led_show(void) {\n'
            "    bat_led_show();\n}\n"
        )
        (keyboard / "keymaps/via/rules.mk").write_text("VIA_ENABLE = yes\n")

        subprocess.run(["git", "init", "--quiet"], cwd=self.qmk_root, check=True)
        subprocess.run(["git", "add", "."], cwd=self.qmk_root, check=True)
        subprocess.run(
            [
                "git",
                "-c",
                "user.name=NuphyBar Tests",
                "-c",
                "user.email=tests@example.invalid",
                "commit",
                "--quiet",
                "-m",
                "baseline",
            ],
            cwd=self.qmk_root,
            check=True,
        )
        self.baseline = subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=self.qmk_root, text=True
        ).strip()

    def tearDown(self):
        self.temporary_directory.cleanup()

    def test_install_adds_only_the_audited_hooks(self):
        INSTALL.BASELINE_COMMIT = self.baseline
        INSTALL.install(self.qmk_root)

        keyboard = self.qmk_root / INSTALL.KEYBOARD_PATH
        self.assertIn(
            '"keyboard_name": "NuPhy Halo75 V2 NuphyBar"',
            (keyboard / "keyboard.json").read_text(),
        )
        side_source = (keyboard / "side.c").read_text()
        self.assertLess(
            side_source.index("agent_light_render_overlay();"),
            side_source.index("bat_led_show();"),
        )
        self.assertEqual(
            (keyboard / "keymaps/via/rules.mk").read_text(),
            "VIA_ENABLE = yes\nSRC += agent_light.c effect_model.c\n",
        )
        for name in ("agent_light.c", "agent_light.h", "effect_model.c", "effect_model.h"):
            self.assertTrue((keyboard / name).is_file())

    def test_install_rejects_an_unknown_source_revision(self):
        INSTALL.BASELINE_COMMIT = "0" * 40
        with self.assertRaisesRegex(RuntimeError, "must be checked out"):
            INSTALL.install(self.qmk_root)


if __name__ == "__main__":
    unittest.main()

