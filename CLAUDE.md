# Meridian — realistic military FPS (Godot 4.7, GDScript)

Engine changed from the original UE5 plan: the dev PC is a Dell OptiPlex 5050
(i7-7700, Intel HD 630, ~28 GB RAM). Godot 4 runs on it and its scenes are
text, so code *and* levels are editable here. See Docs/Handoff.md.

## Rules
- Gameplay code is GDScript, statically typed. Scenes (.tscn) and resources (.tres) stay text.
- All tuning lives in Resources (.tres under data/): weapons, enemies, AI, recoil. No magic numbers.
- Gameplay must run headless: every system gets tests runnable with --headless.
- Every system registers debug commands on the `Debug` autoload (god, give, spawn, ai.show).
- Original IP only: no Call of Duty names, assets, sounds or UI copies.
- Keep a licence record in Docs/AssetLicences.md for every imported asset pack.
- Performance target is this PC: 60 fps at 900p with 0.75 render scale. Profile before adding effects.

## Layout
core/ player/ weapons/ ballistics/ damage/ ai/ feedback/ ui/ mission/ — gameplay modules
data/ — tuning Resources   levels/ — scenes   assets/ — imported art/audio (LFS)   tests/ — test_*.gd

## Commands (run from the project root)
- Godot: `D:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe` (call it $GODOT)
- Import/check scripts: `$GODOT --headless --path . --import`
- Tests: `$GODOT --headless --path . -s res://tests/framework/run.gd` (exit code 0 = pass)
- Smoke-run main scene: `$GODOT --headless --path . --quit-after 120`
- Editor: `D:\Tools\Godot\Godot_v4.7.2-stable_win64.exe --path . -e`

## Milestones
Work milestone by milestone (Docs/Handoff.md). Do not start the next one until the current exit check passes.
