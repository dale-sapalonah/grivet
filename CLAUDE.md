# Grivet — realistic military FPS set in Port Moresby (Godot 4.7, GDScript)

Engine changed from the original UE5 plan: the dev PC is a Dell OptiPlex 5050
(i7-7700, Intel HD 630, ~28 GB RAM). Godot 4 runs on it and its scenes are
text, so code *and* levels are editable here. See Docs/Handoff.md (written as
"Project Meridian"; the game is now Grivet, the folder keeps its old name).

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
- Smoke-run main scene (the title menu): `$GODOT --headless --path . --quit-after 120`
- Movement traversal probe (drives the player through the greybox): `$GODOT --headless --path . res://tests/probes/movement_course.tscn` (prints PASS/FAIL per route; set PROBE_TRACE=1 for a per-frame trace)
- Gunplay probe (shoots the firing range: distances, drop, penetration, ricochet, recoil repeatability, reloads, pump): `$GODOT --headless --path . res://tests/probes/firing_range.tscn`
- GPU frame time + screenshot: `$GODOT --path . res://tests/probes/frame_capture.tscn -- [shot=<abs path>.png] [scene=res://...] [fire] [aim] [weapon=<id>] [hide_gun] [cmd=<console_command>]` (named options only, underscores in cmd= stand for spaces, e.g. `cmd=tp_-14_0_23 cmd=look_100_-4`; ignores real mouse/keyboard; defaults to the port level)
- Never pass empty-string arguments to Godot from PowerShell: it drops them and later arguments shift.
- Sounds are generated in code (feedback/procedural_audio.gd) from WeaponDefinition / SurfaceMaterial fields until Milestone 5's recordings. Mechanism sounds fire at ViewModelTuning timing points so they match the animation.
- Impacts are physics-driven: each hit reports outcome (penetrated / stopped / ricochet / exit), measured thickness (or solid) and remaining energy; SurfaceMaterial.acoustic_type + mass_factor (density x thickness) pick the sound and debris. Light rounds ricochet at steeper angles.
- Impact sounds are built on a worker thread (ImpactEffects); never build audio on the main thread during play. Effect shaders are pre-compiled when a camera first exists.
- Combat probe (arena: spotting, cover, flank, grenade, stuck check, ragdoll, blast, respawn, AI budget): `$GODOT --headless --path . res://tests/probes/combat_arena.tscn` (add `-- level=res://levels/port/port_yard.tscn` to run it on the port)
- AI: `AI` autoload (ai/ai_director.gd) owns the target, cover map, flank slot, grenade cooldown, noise and near-miss suppression. Soldier = body + senses + carrying out SoldierBrain (pure, tested) decisions. Enemy types are data/ai/*.tres (EnemyProfile); world tuning data/ai/ai_settings.tres.
- Levels with AI need a NavigationRegion3D named Navigation over CSG (`use_collision`); bake at runtime after CSG has built (2 frames), wait for the map iteration to change, then `AI.build_cover`. See levels/greybox/arena.gd. Navmesh cells are 0.125 m (project setting); doorways ≥ 1.6 m.
- The baked navmesh floats ~0.5 m above the floor: compare path points on the ground plane (CoverScoring.flat_distance), never in 3D.
- tools/gen_arena.py regenerates levels/greybox/arena.tscn; tools/gen_port.py regenerates levels/port/port_yard.tscn (the main scene: the arena's layout dressed as a container terminal at dusk). Colliders live in the generated scene; visual-only dressing (lamps, crane, ship, PMV buses, markings) is built by levels/port/port_yard.gd.
- Art is procedural (no downloaded assets): MeshBaker merges primitives into one vertex-coloured mesh per part/prop; surfaces are shaders over levels/port/materials/noise.tres (texture reads, not math noise: cheaper on the HD 630). Shipping lines and goods in markings are made up; PNG flavour comes from Tok Pisin, place names and street life (PMVs, PMV stop, buai market, palms), never real brands.
- First-person arms: weapons/view_arms.gd builds gloved hands around a grip radius and stretches forearms to elbow points (WeaponDefinition.*_elbow_offset); each view style in weapon_view_model.gd sets the hand holds (_right_hold, _left_hold, pump/magazine/loading-port holds). Colours live in view_model_tuning.tres.
- Game flow: ui/main_menu.tscn (title, the main scene) -> levels/port/port_yard.tscn. GameMenu (ui/game_menu.gd) is the title screen and, in every HUD, the Esc pause menu (pauses the tree). Settings autoload (core/settings.gd) saves to user://settings.cfg and applies live (volumes, Music bus, sensitivity, invert Y, FOV, render scale, shadows, fullscreen, FPS); `Settings.requested_stage` carries the menu's stage pick.
- Campaign: data/levels/campaign.tres (Campaign of CampaignStage: title, Tok Pisin subtitle, marker level, player start, difficulty multipliers applied per soldier by AI.spawn). Spawn markers carry metadata `level`; the plain arena spawns level 1 only. Clearing a stage shouts KLIN CHOL! / WARAA! (HUD.announce), then the next stage moves, heals and re-arms the player. `stage <n>` jumps. Probe: `$GODOT --headless --path . res://tests/probes/campaign.tscn`.
- Enemies: rifleman, rusher, machete (EnemyProfile.Role.MELEE, Outfit.CIVILIAN: T-shirt, shorts, sandals, bilum; WeaponDefinition.melee_* drives the strike). Bodies are MeshBaker lathes (smooth tapered limbs, sculpted heads); soldier_body.gdshader: COLOR.a 1 camo cloth, 0.5 plain cloth, 0 gear/skin.
- Town strip east of the yard (gate in the east wall): road, Kamfot taxi rank (levels/port/kamfot_taxi.gd, an original lookalike of the city's blue taxis), stores ("store" group, signs from metadata), rugby league field, buai market; buai bundles (BuaiPickup) heal and are re-laid each stage.
- Look: crime-sandbox box-art inspired, original (no Rockstar logo, font or wording). GrivetStyle (ui/grivet_style.gd) holds the fonts (Impact-style heavy, brush script) and colours; menus and HUD use it. Title art = CharacterPanel (ui/character_panel.gd): live 3D poses in their own worlds, rendered ~12 frames then frozen, through ui/comic_panel.gdshader (posterise, ink edges, halftone).
- Spawning: the port level is in group "spawn_picker"; Player.respawn() asks it for a spot (stage start if no enemy within safe_distance or with sight of it, else the safest of safe_spots), gives spawn protection (Health.protect) and AI.forget_target().
- Audio buses: Master, Music (MusicPlayer), SFX (every other sound player: Settings routes players left on Master to SFX as they are created). Settings has volume and on/off for both.
- Music: feedback/music.gd composes an island reggae groove (menu; alternates with the string band in game, MusicPlayer.play_set("menu"/"game")) and a string-band loop (Karplus-Strong guitars, kundu, garamut, bamboo flute) and a night ambience; MusicPlayer autoload builds them on a worker thread (skipped headless) on the Music bus.
- Directional shadow map is 2048 (project setting). 4096 cost ~6 ms on the HD 630 (fill rate, worst with a low sun facing tall walls). No full-screen glow: lamps use additive halo billboards (halo.gdshader); glow cost ~2.7 ms.
- Ragdolls use Generic6DOFJoint3D with anatomical per-axis limits, built in the neutral pose then moved to the death pose (ai/ragdoll.gd). The joint's angle sign is opposite to Mannequin's pivot rotations (measured). HingeJoint3D/ConeTwist were tried and didn't behave predictably.
- Pushes on loose bodies (death, blasts) are velocity changes scaled by mass, never fixed impulses (light limbs would fly off).
- Collision layers: core/physics_layers.gd. Bullets hit Hitbox zone shapes (layer 4), never movement capsules.
- Frame-rate numbers drift with whatever else the PC is doing (Chrome on the shared iGPU). Compare against `scene=res://levels/boot/boot.tscn` measured in the same session before calling something a regression.
- Lights you toggle (muzzle flash): set `visible`, never just `light_energy = 0` — a dark light still costs every nearby pixel.
- The test runner fails any test that raises an engine or script error, not just failed asserts.
- Judge probes by their exit code, not just their PASS line: an engine crash at exit (exit 139) happens after the report prints.
- Every WorkerThreadPool task must be waited on (wait_for_task_completion, e.g. in _exit_tree) or the engine segfaults at exit; worker functions stay static and hand results to the main thread with call_deferred.
- Level-cycle crash probe (windowed: fights, frees the level mid-fight like `map`, quits): `$GODOT --path . res://tests/probes/level_cycle.tscn` (exit 0 and no SCRIPT ERROR lines = pass).
- A freed object compares equal to null in Godot 4: test references that may outlive their target with `is_instance_valid(x)` alone, never `x != null and not is_instance_valid(x)`.
- AI alerts go through Soldier._alert() (awareness 1 + the alerted flag): setting awareness alone is undone by the next perception decay.
- Weapons are data: data/weapons/<id>.tres (WeaponDefinition). Surfaces: data/ballistics/surfaces/*.tres, mapped by id in ballistics_settings.tres; tag colliders with metadata `surface = "<id>"`.
- `Ballistics` autoload simulates all bullets; anything with `apply_damage(hit: Dictionary)` takes damage.
- Probes run as scenes, not `-s`: scripts that reference autoloads (Debug) don't compile under `-s`.
- Scene files store Transform3D row by row: `Transform3D(xx, yx, zx, xy, yy, zy, xz, yz, zz, ox, oy, oz)` in basis-column terms.
- Editor: `D:\Tools\Godot\Godot_v4.7.2-stable_win64.exe --path . -e`

## Milestones
Work milestone by milestone (Docs/Handoff.md). Do not start the next one until the current exit check passes.
