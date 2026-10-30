# Asset licences

One row per imported pack. No asset goes into `assets/` without a row here.

| Pack | Vendor / URL | Licence | Commercial use | Redistribution | Date acquired | Used for |
|---|---|---|---|---|---|---|
| Enemy shouts (placeholder voice lines, assets/audio/voice/*.wav) | Generated on this PC by tools/gen_voices.ps1 with the Windows built-in voice "Microsoft David" (System.Speech); no download | Windows TTS output, generated locally | Unclear: placeholder for personal builds; replace with recorded Tok Pisin speakers before any release | Generated files only | 2026-10-30 | Enemy shouts (data/ai/shouts.tres) |

No packs imported: art and sound are generated in code or authored in the repo
(Blender bodies are built by tools/blender/build_soldier.py; the voice lines above by tools/gen_voices.ps1). Painted
lettering asks the OS for a stencil-style font by name (SystemFont: Stencil,
Impact, Arial Black, Arial); no font file is shipped. Ship a licensed font
before any release build.
