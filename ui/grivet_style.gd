class_name GrivetStyle
extends RefCounted
## Grivet's look for text: heavy condensed capitals with fat black outlines
## (titles, menus, HUD shouts) and a brush script for flourishes - in the
## spirit of crime-sandbox box art, with system fonts (no font files shipped).

const WHITE := Color(0.98, 0.97, 0.94)
const ORANGE := Color(1.0, 0.56, 0.08)
const GOLD := Color(1.0, 0.82, 0.18)
const RED := Color(0.86, 0.1, 0.06)
const INK := Color(0.02, 0.015, 0.01)


static func heavy() -> SystemFont:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Impact", "Haettenschweiler", "Arial Black", "Arial"])
	return font


static func script() -> SystemFont:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Brush Script MT", "Segoe Script", "Gabriola", "Comic Sans MS"])
	font.font_italic = true
	return font


## A label in the house style: font, size, fill, a fat outline and a hard
## drop shadow.
static func label(text: String, font: Font, size: int, color: Color, outline: int = -1) -> Label:
	var result := Label.new()
	result.text = text
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	style(result, font, size, color, outline)
	return result


static func style(control: Control, font: Font, size: int, color: Color, outline: int = -1) -> void:
	control.add_theme_font_override("font", font)
	control.add_theme_font_size_override("font_size", size)
	control.add_theme_color_override("font_color", color)
	control.add_theme_color_override("font_outline_color", INK)
	control.add_theme_constant_override("outline_size", outline if outline >= 0 else maxi(4, size / 7))
	control.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	control.add_theme_constant_override("shadow_offset_x", maxi(2, size / 22))
	control.add_theme_constant_override("shadow_offset_y", maxi(2, size / 22))
