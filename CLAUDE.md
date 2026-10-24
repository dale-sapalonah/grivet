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
- Movement traversal probe (drives the player through the greybox): `$GODOT --headless --path . res://tests/probes/movement_course.tscn` (prints PASS/FAIL per route; set PROBE_TRACE=1 for a per-frame trace)
- Gunplay probe (shoots the firing range: distances, drop, penetration, ricochet, recoil repeatability, reloads, pump): `$GODOT --headless --path . res://tests/probes/firing_range.tscn`
- GPU frame time + screenshot: `$GODOT --path . res://tests/probes/frame_capture.tscn -- [shot=<abs path>.png] [scene=res://...] [fire] [aim] [weapon=<id>] [hide_gun]` (named options only; ignores real mouse/keyboard; defaults to the main scene)
- Never pass empty-string arguments to Godot from PowerShell: it drops them and later arguments shift.
- Sounds are generated in code (feedback/procedural_audio.gd) from WeaponDefinition / SurfaceMaterial fields until Milestone 5's recordings. Mechanism sounds fire at ViewModelTuning timing points so they match the animation.
- Impacts are physics-driven: each hit reports outcome (penetrated / stopped / ricochet / exit), measured thickness (or solid) and remaining energy; SurfaceMaterial.acoustic_type + mass_factor (density x thickness) pick the sound and debris. Light rounds ricochet at steeper angles.
- Impact sounds are built on a worker thread (ImpactEffects); never build audio on the main thread during play. Effect shaders are pre-compiled when a camera first exists.
- Combat probe (arena: spotting, cover, flank, grenade, stuck check, ragdoll, blast, respawn, AI budget): `$GODOT --headless --path . res://tests/probes/combat_arena.tscn`
- AI: `AI` autoload (ai/ai_director.gd) owns the target, cover map, flank slot, grenade cooldown, noise and near-miss suppression. Soldier = body + senses + carrying out SoldierBrain (pure, tested) decisions. Enemy types are data/ai/*.tres (EnemyProfile); world tuning data/ai/ai_settings.tres.
- Levels with AI need a NavigationRegion3D named Navigation over CSG (`use_collision`); bake at runtime after CSG has built (2 frames), wait for the map iteration to change, then `AI.build_cover`. See levels/greybox/arena.gd. Navmesh cells are 0.125 m (project setting); doorways ≥ 1.6 m.
- The baked navmesh floats ~0.5 m above the floor: compare path points on the ground plane (CoverScoring.flat_distance), never in 3D.
- tools/gen_arena.py regenerates levels/greybox/arena.tscn.
- Ragdolls use Generic6DOFJoint3D with anatomical per-axis limits, built in the neutral pose then moved to the death pose (ai/ragdoll.gd). The joint's angle sign is opposite to Mannequin's pivot rotations (measured). HingeJoint3D/ConeTwist were tried and didn't behave predictably.
- Pushes on loose bodies (death, blasts) are velocity changes scaled by mass, never fixed impulses (light limbs would fly off).
- Collision layers: core/physics_layers.gd. Bullets hit Hitbox zone shapes (layer 4), never movement capsules.
- Frame-rate numbers drift with whatever else the PC is doing (Chrome on the shared iGPU). Compare against `scene=res://levels/boot/boot.tscn` measured in the same session before calling something a regression.
- Lights you toggle (muzzle flash): set `visible`, never just `light_energy = 0` — a dark light still costs every nearby pixel.
- The test runner fails any test that raises an engine or script error, not just failed asserts.
- Weapons are data: data/weapons/<id>.tres (WeaponDefinition). Surfaces: data/ballistics/surfaces/*.tres, mapped by id in ballistics_settings.tres; tag colliders with metadata `surface = "<id>"`.
- `Ballistics` autoload simulates all bullets; anything with `apply_damage(hit: Dictionary)` takes damage.
- Probes run as scenes, not `-s`: scripts that reference autoloads (Debug) don't compile under `-s`.
- Scene files store Transform3D row by row: `Transform3D(xx, yx, zx, xy, yy, zy, xz, yz, zz, ox, oy, oz)` in basis-column terms.
- Editor: `D:\Tools\Godot\Godot_v4.7.2-stable_win64.exe --path . -e`

## Milestones
Work milestone by milestone (Docs/Handoff.md). Do not start the next one until the current exit check passes.
