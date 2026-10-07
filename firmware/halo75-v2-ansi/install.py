#!/usr/bin/env python3
"""Install the NuphyBar overlay into an exact NuPhy QMK source tree."""

from __future__ import annotations

import argparse
import shutil
import subprocess
from pathlib import Path


BASELINE_COMMIT = "4223dece7852b9fd9abd7c61559272241ef4a223"
KEYBOARD_PATH = Path("keyboards/nuphy/halo75_v2/ansi")


def replace_once(path: Path, old: str, new: str) -> None:
    content = path.read_text()
    if content.count(old) != 1:
        raise RuntimeError(f"expected one audited insertion point in {path}")
    path.write_text(content.replace(old, new))


def install(qmk_root: Path) -> None:
    revision = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=qmk_root, text=True
    ).strip()
    if revision != BASELINE_COMMIT:
        raise RuntimeError(
            f"NuPhy QMK must be checked out at {BASELINE_COMMIT}; found {revision}"
        )

    keyboard = qmk_root / KEYBOARD_PATH
    if not keyboard.is_dir():
        raise RuntimeError(f"Halo75 V2 ANSI source is missing at {keyboard}")

    source_dir = Path(__file__).resolve().parent / "src"
    for name in ("agent_light.c", "agent_light.h", "effect_model.c", "effect_model.h"):
        shutil.copy2(source_dir / name, keyboard / name)

    replace_once(
        keyboard / "keyboard.json",
        '"keyboard_name": "NuPhy Halo75 V2",',
        '"keyboard_name": "NuPhy Halo75 V2 NuphyBar",',
    )

    replace_once(
        keyboard / "side.c",
        '#include "side.h"\n',
        '#include "side.h"\n#ifdef VIA_ENABLE\n#include "agent_light.h"\n#endif\n',
    )
    replace_once(
        keyboard / "side.c",
        "    bat_led_show();\n",
        "#ifdef VIA_ENABLE\n    agent_light_render_overlay();\n#endif\n    bat_led_show();\n",
    )

    via_rules = keyboard / "keymaps/via/rules.mk"
    replace_once(
        via_rules,
        "VIA_ENABLE = yes\n",
        "VIA_ENABLE = yes\nSRC += agent_light.c effect_model.c\n",
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("qmk_root", type=Path)
    arguments = parser.parse_args()
    install(arguments.qmk_root.resolve())


if __name__ == "__main__":
    main()
