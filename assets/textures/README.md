# PBR texture slots

Optional authored detail for Grivet's procedural surfaces. Put files here and
they load automatically (core/pbr_library.gd); without them the surfaces stay
procedural.

    assets/textures/<slot>/normal.png      tiling normal map (OpenGL / +Y up)
    assets/textures/<slot>/roughness.png   greyscale roughness (white = rough)

Slots: `container` (corrugated metal), `concrete`, `asphalt`, `dirt`,
`weapon_metal` (the guns). Use seamless 1K or 2K power-of-two images. Strength
and tiling per slot are in PbrLibrary.SLOTS. In Godot's import dock set normal
maps to "Normal Map" so they compress correctly.

Every texture pack needs a row in Docs/AssetLicences.md before it goes in.
