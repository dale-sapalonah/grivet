# Asset licences

One row per imported pack. No asset goes into `assets/` without a row here.

| Pack | Vendor / URL | Licence | Commercial use | Redistribution | Date acquired | Used for |
|---|---|---|---|---|---|---|
| Mixamo characters Ch15 (armoured soldier) and Ch18 (black tactical), with the Mixamo Basic Shooter Pack clips (idle, walk, run, strafes, fire, reload, toss grenade, hit reaction, turns, jump) baked in, assets/models/enemy_ch15.glb, raskol_ch18.glb | Adobe Mixamo, mixamo.com (downloaded by the user as Ch15_nonPBR.fbx, Ch18_nonPBR.fbx and the Basic Shooter Pack folder) | Mixamo terms: royalty-free use of characters and animations in projects, including commercial games | Yes | Only inside the game; not as standalone assets (the source FBX stays out of the repository) | 2026-11-08 | Enemy soldiers (rifleman, rusher) and gang leaders (hostage takers); slimmed by tools/blender/prepare_mixamo.py |
| Enemy shouts (placeholder voice lines, assets/audio/voice/*.wav) | Generated on this PC by tools/gen_voices.ps1 with the Windows built-in voice "Microsoft David" (System.Speech); no download | Windows TTS output, generated locally | Unclear: placeholder for personal builds; replace with recorded Tok Pisin speakers before any release | Generated files only | 2026-10-30 | Enemy shouts (data/ai/shouts.tres) |

Apart from the rows above, art and sound are generated in code or authored in the repo
(Blender bodies and the police Land Cruiser are built by tools/blender/build_soldier.py and build_landcruiser.py; the voice lines above by tools/gen_voices.ps1). Painted
lettering asks the OS for a stencil-style font by name (SystemFont: Stencil,
Impact, Arial Black, Arial); no font file is shipped. Ship a licensed font
before any release build.
