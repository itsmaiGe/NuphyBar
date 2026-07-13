# Upstream firmware notice

The NuphyBar Air60 V2 image is an aggregate of:

1. NuPhy's official Air60 V2 ANSI v2.1.5 QMK firmware payload, distributed by NuPhy under the QMK/GPL firmware line; and
2. the NuphyBar hook and patch builder in this directory, licensed under GPL-2.0-or-later.

Upstream source and release information:

- NuPhy QMK source: <https://github.com/nuphy-src/qmk_firmware>
- NuPhy QMK firmware releases: <https://nuphy.com/pages/qmk-firmwares>
- NuPhy update instructions: <https://nuphy.com/pages/update-instructions>

The public NuPhy QMK tree available during development did not produce a byte-identical v2.1.5 image. For that reason, this repository does not claim that its hook sources are the complete source of NuPhy's official base. The builder requires the user-supplied official image with SHA-256 `cd0425f548a01416d1c3c25208ff74867fffd20165520c7c2eaa56000ff347bf`, documents every NuphyBar-added byte, and refuses any other baseline.

If NuPhy publishes a byte-reproducible source tag for v2.1.5, the project should pin that source and prefer a complete source-level build.
