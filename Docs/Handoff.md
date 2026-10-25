# Meridian — Project Handoff (Godot edition)

Original brief: Oct 23, 2026, Dale Sapalonah. It targeted Unreal Engine 5 on a
dedicated-GPU workstation. The same day we chose to build on the current PC instead.

## Engine decision
| | Original plan | Current plan |
|---|---|---|
| Engine | Unreal Engine 5, C++ | Godot 4.7.2, GDScript |
| PC | RTX 3060+ workstation | Dell OptiPlex 5050: i7-7700 (4C/8T), Intel HD 630, ~28 GB RAM |
| Visual target | Near-photoreal (Lumen, Nanite, Megascans) | Grounded, moody, stylised-realistic: strong lighting, fog, rain, good audio |
| Frame target | 60 fps @ 1440p upscaled | 60 fps @ 900p, 0.75 render scale, on HD 630 |

Why Godot: it runs on integrated graphics, and its scenes and resources are
plain text, so Claude Code can build levels as well as code. Headless tests run
from the command line. Moving to UE5 later means a rewrite, but the design,
data and tuning carry over.

What realism means on this hardware: lighting, fog and atmosphere, sound
design, animation and weapon feel. Not polygon or texture density. Use
mid-poly, optimised assets (glTF), baked lightmaps or VoxelGI where possible,
and keep SDFGI and volumetric fog as optional higher settings.

## Concept (unchanged)
Project Meridian is a grounded near-future single-player military shooter with
an original setting. The slice is a night raid on a coastal industrial port:
rain, sodium lights, containers and a warehouse interior. The player is a
special-forces operator with one AI squadmate, moving from stealth approach to
firefight to extraction.

Pillars: weapons that feel and sound real; tight, cinematic levels; enemies
that use cover and flank; readable chaos.

Avoid Call of Duty names, logos, characters, maps, UI layouts and sound
recordings. Genre conventions are fine.

## Vertical slice scope (unchanged except where noted)
One 10–15 minute mission, three weapons (assault rifle, pump shotgun, sidearm),
frag and flashbang grenades, a knife takedown, and two enemy types (rifle
infantry, shotgun rusher). One squadmate. Movement covers sprint, crouch,
prone, slide, mantle and lean. Ballistics are physical bullets with drop,
penetration and ricochet. Hit zones and ragdolls. Layered gun audio with reverb
zones. Minimal HUD. Intro and extraction sequences.
Changed: the 60 fps target is on this PC (see above).

## Code architecture
| Folder | Responsibility | Godot pieces |
|---|---|---|
| core/ | Settings, save, logging, debug commands (`Debug` autoload) | Autoloads, ConfigFile |
| player/ | CharacterBody3D controller (slide, mantle, lean), FP camera rig | CharacterBody3D, ShapeCast3D |
| weapons/ | WeaponDefinition Resources, weapon node, recoil, spread, reload state machine | Resource, Curve |
| ballistics/ | Pooled bullet sim (drop, travel), penetration by surface | PhysicsDirectSpaceState3D raycasts |
| damage/ | Hit zones, damage types, hit reactions, ragdoll | PhysicalBone3D / PhysicalBoneSimulator3D |
| ai/ | Enemy brain (state machine), perception, cover selection, squad logic | NavigationAgent3D, NavigationRegion3D |
| feedback/ | Camera shake, impact FX tables, layered gunshot audio | GPUParticles3D, AudioStreamPlayer3D, audio buses |
| ui/ | HUD and menus | Control scenes |
| mission/ | Objectives, triggers, scripted sequences, checkpoints | Area3D, AnimationPlayer |

Rules: gameplay is testable headless; every system exposes debug commands; tuning lives in data.

## Milestones
| # | Milestone | Exit check |
|---|---|---|
| 0 | Setup: project, Git + LFS, CLAUDE.md, CLI test run | Tests pass from the command line ✅ |
| 1 | Movement and camera on a greybox map | Traverses greybox without snagging; 60 fps on this PC |
| 2 | Gunplay: three weapons from data, ADS, recoil, reloads, ballistics, impacts | Recoil repeatable; penetration test passes; playtest feels right |
| 3 | Combat AI: two enemy types, cover, suppression, flanking, grenades; hit zones, ragdolls | AI fights without getting stuck; playtest "challenging, fair" |
| 4 | Art pass: port environment, enemy models, FP animations | Screenshot review; still 60 fps |
| 5 | Audio and feedback | Listening check by ear (`sound.demo`) and a playtest; stays procedural, no recordings (chosen 2026-10-25, replacing the blind A/B vs reference recordings) |
| 6 | Mission and polish | Full mission playable, performance budget met |

## Assets (adapted)
Free or cheap and optimised first: Poly Haven (CC0 textures, HDRIs, models),
ambientCG (CC0 materials), Kenney (CC0 prototyping), Quaternius (CC0
characters), Mixamo (animations, placeholder), and Sonniss GDC bundles
(audio). Paid FPS arm and animation packs remain the biggest feel upgrade.
Record every pack in Docs/AssetLicences.md.

## Open questions
- [ ] Hours per week for playtesting and feedback?
- [ ] Asset budget, if any?
- [ ] GPU upgrade later (an RTX 5060 Ti 16 GB plus an ATX power supply works if the case is the Mini Tower)?
