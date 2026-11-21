extends RefCounted

const TOKENS := {
	"background": "#1A1810", "backgroundSoft": "#232018", "surface": "#332E22",
	"surfaceRaised": "#3D372A", "surfaceAlt": "#453D30", "borderDark": "#100E08",
	"borderHighlight": "#F0D060", "bevelLight": "#75663D", "borderMuted": "#5A5040",
	"textPrimary": "#D4C89A", "textSecondary": "#9C9371", "textMuted": "#6E674E",
	"accentTeal": "#008080", "accentTealDeep": "#004C4C", "success": "#4A7A20",
	"warning": "#7A7A20", "danger": "#7A2020", "dangerText": "#D66464",
	"selection": "#3D372A", "compareBack": "#14120C", "link": "#F0D060"
}


static func palette() -> Dictionary:
	var result := {}
	for key: String in TOKENS:
		result[key] = Color(TOKENS[key])
	return result


static func box(fill: Color, top: Color, bottom: Color) -> StyleBoxTexture:
	var bitmap := Image.create_empty(7, 7, false, Image.FORMAT_RGBA8)
	bitmap.fill(bottom)
	bitmap.fill_rect(Rect2i(0, 0, 7, 2), top)
	bitmap.fill_rect(Rect2i(0, 0, 2, 7), top)
	bitmap.fill_rect(Rect2i(2, 2, 3, 3), fill)
	var style := StyleBoxTexture.new()
	style.texture = ImageTexture.create_from_image(bitmap)
	for side in [SIDE_TOP, SIDE_BOTTOM, SIDE_LEFT, SIDE_RIGHT]:
		style.set_texture_margin(side, 2)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style


static func make(colors: Dictionary) -> Theme:
	var theme := Theme.new()
	var font := verdana("verdana.ttf")
	var bold := verdana("verdanab.ttf")
	theme.default_font = font
	theme.default_font_size = 12
	ThemeDB.fallback_font = font
	ThemeDB.fallback_font_size = 12
	theme.set_font("title_font", "Window", bold)
	theme.set_font("title_font", "GraphNode", bold)
	for type in ["Label", "Button", "LineEdit", "CheckButton", "PopupMenu"]:
		theme.set_color("font_color", type, colors["textPrimary"])
		theme.set_color("font_hover_color", type, colors["borderHighlight"])
		theme.set_color("font_pressed_color", type, colors["borderHighlight"])
		theme.set_color("font_disabled_color", type, colors["textMuted"])
	theme.set_stylebox("normal", "Button", box(colors["surfaceRaised"], colors["bevelLight"], colors["borderDark"]))
	theme.set_stylebox("hover", "Button", box(colors["surfaceAlt"], colors["borderHighlight"], colors["borderDark"]))
	theme.set_stylebox("pressed", "Button", box(colors["selection"], colors["borderDark"], colors["bevelLight"]))
	theme.set_stylebox("disabled", "Button", box(colors["backgroundSoft"], colors["borderMuted"], colors["borderDark"]))
	var focus := box(colors["background"], colors["borderHighlight"], colors["borderHighlight"])
	focus.draw_center = false
	theme.set_stylebox("focus", "Button", focus)
	theme.set_stylebox("focus", "LineEdit", focus)
	theme.set_stylebox("normal", "LineEdit", box(colors["backgroundSoft"], colors["borderDark"], colors["bevelLight"]))
	theme.set_stylebox("panel", "PopupPanel", box(colors["surface"], colors["bevelLight"], colors["borderDark"]))
	theme.set_stylebox("panel", "AcceptDialog", box(colors["surface"], colors["bevelLight"], colors["borderDark"]))
	theme.set_stylebox("panel", "PopupMenu", box(colors["surface"], colors["bevelLight"], colors["borderDark"]))
	theme.set_stylebox("panel", "ItemList", box(colors["backgroundSoft"], colors["borderDark"], colors["bevelLight"]))
	theme.set_stylebox("panel", "PanelContainer", box(colors["backgroundSoft"], colors["bevelLight"], colors["borderDark"]))
	theme.set_stylebox("scroll", "VScrollBar", box(colors["backgroundSoft"], colors["borderDark"], colors["bevelLight"]))
	theme.set_stylebox("grabber", "VScrollBar", box(colors["surfaceRaised"], colors["bevelLight"], colors["borderDark"]))
	theme.set_stylebox("grabber_highlight", "VScrollBar", box(colors["surfaceAlt"], colors["borderHighlight"], colors["borderDark"]))
	theme.set_stylebox("grabber_pressed", "VScrollBar", box(colors["selection"], colors["borderDark"], colors["bevelLight"]))
	theme.set_stylebox("panel", "GraphEdit", box(colors["backgroundSoft"], colors["borderDark"], colors["bevelLight"]))
	theme.set_stylebox("panel", "GraphNode", box(colors["surface"], colors["bevelLight"], colors["borderDark"]))
	theme.set_stylebox("panel_selected", "GraphNode", box(colors["surfaceRaised"], colors["borderHighlight"], colors["borderDark"]))
	return theme


static func verdana(filename: String) -> Font:
	var font := FontFile.new()
	var path := OS.get_environment("WINDIR").path_join("Fonts").path_join(filename)
	if OS.get_name() == "Windows" and FileAccess.file_exists(path) and font.load_dynamic_font(path) == OK:
		font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		font.oversampling = 1.0
		return font
	var system := SystemFont.new()
	system.font_names = PackedStringArray(["Verdana"])
	system.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	system.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	system.oversampling = 1.0
	return system
