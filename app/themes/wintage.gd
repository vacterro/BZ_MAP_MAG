extends RefCounted

const DEFAULT_THEME := "goldendefault"

const SPACING_TIGHT := 3
const SPACING_ROW := 4
const SPACING_GROUP := 8
const DIALOG_MARGIN := 12

const THEMES := {
	"goldendefault": {
		"label": "Golden Default",
		"tokens": {
			"background": "#1A1810", "backgroundSoft": "#232018", "surface": "#332E22",
			"surfaceRaised": "#3D372A", "surfaceAlt": "#453D30", "borderDark": "#100E08",
			"borderHighlight": "#F0D060", "bevelLight": "#75663D", "borderMuted": "#5A5040",
			"textPrimary": "#D4C89A", "textSecondary": "#9C9371", "textMuted": "#6E674E",
			"accentTeal": "#008080", "accentTealDeep": "#004C4C", "success": "#4A7A20",
			"warning": "#7A7A20", "danger": "#7A2020", "dangerText": "#D66464",
			"selection": "#3D372A", "compareBack": "#14120C", "link": "#F0D060",
		},
	},
	"vintagedark": {
		"label": "Vintage Dark",
		"tokens": {
			"background": "#181818", "backgroundSoft": "#1B1B1B", "surface": "#2B2B2B",
			"surfaceRaised": "#343434", "surfaceAlt": "#3A3A3A", "borderDark": "#0A0A0A",
			"borderHighlight": "#738EA6", "bevelLight": "#4A5258", "borderMuted": "#4D4D4D",
			"textPrimary": "#C0C0C0", "textSecondary": "#8E8E8E", "textMuted": "#646464",
			"accentTeal": "#008080", "accentTealDeep": "#004C4C", "success": "#4A7A20",
			"warning": "#7A7A20", "danger": "#7A2020", "dangerText": "#D45D5D",
			"selection": "#343434", "compareBack": "#121212", "link": "#738EA6",
		},
	},
	"vintageclassic": {
		"label": "Vintage Classic",
		"tokens": {
			"background": "#C0C0C0", "backgroundSoft": "#FFFFFF", "surface": "#C0C0C0",
			"surfaceRaised": "#D0D0D0", "surfaceAlt": "#DCDCDC", "borderDark": "#808080",
			"borderHighlight": "#F6F6F6", "bevelLight": "#F6F6F6", "borderMuted": "#FFFFFF",
			"textPrimary": "#000000", "textSecondary": "#3A3A3A", "textMuted": "#6A6A6A",
			"accentTeal": "#008080", "accentTealDeep": "#004C4C", "success": "#4A7A20",
			"warning": "#7A7A20", "danger": "#7A2020", "dangerText": "#7A2020",
			"selection": "#D0D0D0", "compareBack": "#D0D0D0", "link": "#3D4F4F",
		},
	},
	"nord": {
		"label": "Nord",
		"tokens": {
			"background": "#272C36", "backgroundSoft": "#2E3440", "surface": "#3B4252",
			"surfaceRaised": "#3F4758", "surfaceAlt": "#434B5D", "borderDark": "#232831",
			"borderHighlight": "#88C0D0", "bevelLight": "#566C7D", "borderMuted": "#4C566A",
			"textPrimary": "#D8DEE9", "textSecondary": "#A3A9B3", "textMuted": "#777C87",
			"accentTeal": "#008080", "accentTealDeep": "#004C4C", "success": "#4A7A20",
			"warning": "#7A7A20", "danger": "#7A2020", "dangerText": "#DE8282",
			"selection": "#3F4758", "compareBack": "#1D2129", "link": "#88C0D0",
		},
	},
}

const TOKENS := {
	"background": "#1A1810", "backgroundSoft": "#232018", "surface": "#332E22",
	"surfaceRaised": "#3D372A", "surfaceAlt": "#453D30", "borderDark": "#100E08",
	"borderHighlight": "#F0D060", "bevelLight": "#75663D", "borderMuted": "#5A5040",
	"textPrimary": "#D4C89A", "textSecondary": "#9C9371", "textMuted": "#6E674E",
	"accentTeal": "#008080", "accentTealDeep": "#004C4C", "success": "#4A7A20",
	"warning": "#7A7A20", "danger": "#7A2020", "dangerText": "#D66464",
	"selection": "#3D372A", "compareBack": "#14120C", "link": "#F0D060",
}


static func theme_slugs() -> Array[String]:
	return ["goldendefault", "vintagedark", "vintageclassic", "nord"]


static func theme_label(slug: String) -> String:
	var entry: Dictionary = THEMES.get(slug, THEMES[DEFAULT_THEME])
	return String(entry["label"])


static func palette(slug: String = DEFAULT_THEME) -> Dictionary:
	var entry: Dictionary = THEMES.get(slug, THEMES[DEFAULT_THEME])
	var tokens: Dictionary = entry["tokens"]
	var result := {}
	for key: String in tokens:
		result[key] = Color(tokens[key])
	return result


static func box(fill: Color, top: Color, bottom: Color, compact: bool = false) -> StyleBoxTexture:
	var bitmap := Image.create_empty(7, 7, false, Image.FORMAT_RGBA8)
	bitmap.fill(bottom)
	bitmap.fill_rect(Rect2i(0, 0, 7, 2), top)
	bitmap.fill_rect(Rect2i(0, 0, 2, 7), top)
	bitmap.fill_rect(Rect2i(2, 2, 3, 3), fill)
	var style := StyleBoxTexture.new()
	style.texture = ImageTexture.create_from_image(bitmap)
	for side in [SIDE_TOP, SIDE_BOTTOM, SIDE_LEFT, SIDE_RIGHT]:
		style.set_texture_margin(side, 2)
	style.content_margin_left = 4 if compact else 6
	style.content_margin_right = 4 if compact else 6
	style.content_margin_top = 2 if compact else 3
	style.content_margin_bottom = 2 if compact else 3
	return style


static func make(colors: Dictionary, font_size: int = 12, compact: bool = false) -> Theme:
	var theme := Theme.new()
	var font := verdana("Verdana_m1.ttf", "verdana.ttf")
	var bold := verdana("Verdana_m1-Bold.ttf", "verdanab.ttf")
	var clamped_size := clampi(font_size, 10, 24)
	theme.default_font = font
	theme.default_font_size = clamped_size
	ThemeDB.fallback_font = font
	ThemeDB.fallback_font_size = clamped_size
	theme.set_font("title_font", "Window", bold)
	theme.set_font("title_font", "GraphNode", bold)
	for rtl_font in ["normal_font", "mono_font", "italics_font"]:
		theme.set_font(rtl_font, "RichTextLabel", font)
	for rtl_bold in ["bold_font", "bold_italics_font"]:
		theme.set_font(rtl_bold, "RichTextLabel", bold)
	for type in ["Label", "Button", "LineEdit", "CheckButton", "CheckBox", "OptionButton", "PopupMenu", "RichTextLabel", "ItemList", "TabContainer"]:
		theme.set_font("font", type, font)
		theme.set_font_size("font_size", type, clamped_size)
		theme.set_color("font_color", type, colors["textPrimary"])
		theme.set_color("font_hover_color", type, colors["borderHighlight"])
		theme.set_color("font_pressed_color", type, colors["borderHighlight"])
		theme.set_color("font_disabled_color", type, colors["textMuted"])
	theme.set_color("default_color", "RichTextLabel", colors["textPrimary"])
	theme.set_stylebox("normal", "Button", box(colors["surfaceRaised"], colors["bevelLight"], colors["borderDark"], compact))
	theme.set_stylebox("hover", "Button", box(colors["surfaceAlt"], colors["borderHighlight"], colors["borderDark"], compact))
	theme.set_stylebox("pressed", "Button", box(colors["selection"], colors["borderDark"], colors["bevelLight"], compact))
	theme.set_stylebox("disabled", "Button", box(colors["backgroundSoft"], colors["borderMuted"], colors["borderDark"], compact))
	var focus := box(colors["background"], colors["borderHighlight"], colors["borderHighlight"], compact)
	focus.draw_center = false
	theme.set_stylebox("focus", "Button", focus)
	theme.set_stylebox("focus", "LineEdit", focus)
	theme.set_stylebox("normal", "LineEdit", box(colors["compareBack"], colors["borderDark"], colors["bevelLight"], compact))
	theme.set_stylebox("read_only", "LineEdit", box(colors["backgroundSoft"], colors["borderDark"], colors["borderMuted"], compact))
	theme.set_stylebox("normal", "RichTextLabel", box(colors["compareBack"], colors["borderDark"], colors["bevelLight"], true))
	theme.set_stylebox("panel", "PopupPanel", box(colors["surface"], colors["bevelLight"], colors["borderDark"], compact))
	theme.set_stylebox("panel", "AcceptDialog", box(colors["surface"], colors["bevelLight"], colors["borderDark"], compact))
	theme.set_stylebox("panel", "PopupMenu", box(colors["surface"], colors["bevelLight"], colors["borderDark"], compact))
	theme.set_stylebox("panel", "ItemList", box(colors["compareBack"], colors["borderDark"], colors["bevelLight"], compact))
	theme.set_stylebox("panel", "PanelContainer", box(colors["backgroundSoft"], colors["bevelLight"], colors["borderDark"], compact))
	theme.set_stylebox("panel", "TabContainer", box(colors["surface"], colors["bevelLight"], colors["borderDark"], compact))
	theme.set_stylebox("tab_selected", "TabContainer", box(colors["surfaceRaised"], colors["borderDark"], colors["bevelLight"], compact))
	theme.set_stylebox("tab_unselected", "TabContainer", box(colors["surface"], colors["bevelLight"], colors["borderDark"], compact))
	theme.set_stylebox("tab_hovered", "TabContainer", box(colors["surfaceAlt"], colors["borderHighlight"], colors["borderDark"], compact))
	theme.set_stylebox("scroll", "VScrollBar", box(colors["backgroundSoft"], colors["borderDark"], colors["bevelLight"], compact))
	theme.set_stylebox("grabber", "VScrollBar", box(colors["surfaceRaised"], colors["bevelLight"], colors["borderDark"], compact))
	theme.set_stylebox("grabber_highlight", "VScrollBar", box(colors["surfaceAlt"], colors["borderHighlight"], colors["borderDark"], compact))
	theme.set_stylebox("grabber_pressed", "VScrollBar", box(colors["selection"], colors["borderDark"], colors["bevelLight"], compact))
	theme.set_stylebox("panel", "GraphEdit", box(colors["backgroundSoft"], colors["borderDark"], colors["bevelLight"], compact))
	theme.set_stylebox("panel", "GraphNode", box(colors["surface"], colors["bevelLight"], colors["borderDark"], compact))
	theme.set_stylebox("panel_selected", "GraphNode", box(colors["surfaceRaised"], colors["borderHighlight"], colors["borderDark"], compact))
	var track := box(colors["compareBack"], colors["borderDark"], colors["bevelLight"], true)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	track.content_margin_left = 2
	track.content_margin_right = 2
	var fill := box(colors["bevelLight"], colors["borderDark"], colors["bevelLight"], true)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	fill.content_margin_left = 2
	fill.content_margin_right = 2
	var fill_hi := box(colors["bevelLight"], colors["borderHighlight"], colors["borderDark"], true)
	fill_hi.content_margin_top = 3
	fill_hi.content_margin_bottom = 3
	fill_hi.content_margin_left = 2
	fill_hi.content_margin_right = 2
	theme.set_stylebox("slider", "HSlider", track)
	theme.set_stylebox("grabber_area", "HSlider", fill)
	theme.set_stylebox("grabber_area_highlight", "HSlider", fill_hi)
	theme.set_icon("grabber", "HSlider", slider_thumb(colors["surfaceRaised"], colors["bevelLight"], colors["borderDark"]))
	theme.set_icon("grabber_highlight", "HSlider", slider_thumb(colors["surfaceAlt"], colors["borderHighlight"], colors["borderDark"]))
	theme.set_icon("grabber_disabled", "HSlider", slider_thumb(colors["backgroundSoft"], colors["borderMuted"], colors["borderDark"]))
	return theme


static func slider_thumb(fill: Color, top: Color, bottom: Color) -> ImageTexture:
	var bitmap := Image.create_empty(10, 16, false, Image.FORMAT_RGBA8)
	bitmap.fill(bottom)
	bitmap.fill_rect(Rect2i(0, 0, 10, 2), top)
	bitmap.fill_rect(Rect2i(0, 0, 2, 16), top)
	bitmap.fill_rect(Rect2i(2, 2, 6, 12), fill)
	return ImageTexture.create_from_image(bitmap)


static func _usable_bounds(dialog: Window) -> Vector2i:
	if dialog.get_parent() != null:
		var vp := dialog.get_parent().get_viewport()
		if vp != null:
			var vr := vp.get_visible_rect().size
			if vr.x >= 320.0 and vr.y >= 240.0:
				return Vector2i(int(vr.x) - 20, int(vr.y) - 36)
	var screen_sz := DisplayServer.screen_get_usable_rect().size
	if screen_sz.x >= 320 and screen_sz.y >= 240:
		return Vector2i(screen_sz.x - 32, screen_sz.y - 48)
	return Vector2i(1880, 1000)


static func _set_dialog_scroll_mode(node: Node, mode: ScrollContainer.ScrollMode) -> void:
	if node is ScrollContainer:
		var sc := node as ScrollContainer
		# Skip internal ChoiceGroup overflow ScrollContainers (identified by custom_minimum_size.y > 0)
		if sc.custom_minimum_size.y <= 0.0:
			sc.vertical_scroll_mode = mode
	for child in node.get_children():
		_set_dialog_scroll_mode(child, mode)


static func _prelayout_controls(node: Node, avail_w: float) -> void:
	if node is Control:
		var ctrl := node as Control
		if not ctrl.visible:
			return
		var orig_min_x := float(ctrl.get_meta(&"_wintage_orig_min_x", ctrl.custom_minimum_size.x))
		if not ctrl.has_meta(&"_wintage_orig_min_x") and ctrl.custom_minimum_size.x > 0.0:
			ctrl.set_meta(&"_wintage_orig_min_x", ctrl.custom_minimum_size.x)
		if orig_min_x > 0.0:
			ctrl.custom_minimum_size.x = minf(orig_min_x, maxf(80.0, avail_w))
		if ctrl.size.x < avail_w:
			ctrl.size.x = avail_w
		if ctrl is HBoxContainer:
			var fixed_w := 0.0
			var expand_children: Array[Control] = []
			for child in ctrl.get_children():
				if child is Control and (child as Control).visible:
					var c := child as Control
					if (c.size_flags_horizontal & Control.SIZE_EXPAND) != 0:
						expand_children.append(c)
					else:
						fixed_w += maxf(c.custom_minimum_size.x, c.get_combined_minimum_size().x) + 6.0
			var rem := maxf(100.0, avail_w - fixed_w)
			var share := rem / float(maxi(1, expand_children.size()))
			for c in expand_children:
				_prelayout_controls(c, share)
			ctrl.notification(Container.NOTIFICATION_SORT_CHILDREN)
			return
		for child in ctrl.get_children():
			_prelayout_controls(child, maxf(100.0, avail_w - 8.0))
		if ctrl is Container:
			ctrl.notification(Container.NOTIFICATION_SORT_CHILDREN)
	else:
		for child in node.get_children():
			_prelayout_controls(child, avail_w)


static func _compute_fit_size(dialog: Window, width: int, min_height: int = 0) -> Vector2i:
	var bounds := _usable_bounds(dialog)
	var font_scale := 1.0
	if dialog.theme != null and dialog.theme.default_font_size > 12:
		font_scale = clampf(float(dialog.theme.default_font_size) / 12.0, 1.0, 1.45)
	var eff_width := mini(int(round(width * font_scale)), maxi(300, bounds.x))
	var eff_min_h := mini(min_height, maxi(120, bounds.y))
	_set_dialog_scroll_mode(dialog, ScrollContainer.SCROLL_MODE_DISABLED)
	dialog.min_size = Vector2i(eff_width, 0)
	dialog.size = Vector2i(eff_width, maxi(eff_min_h, 200))
	_prelayout_controls(dialog, float(eff_width - 24))
	var content_min := dialog.get_contents_minimum_size()
	var want_w := maxi(int(ceil(content_min.x)) + 16, eff_width)
	var want_h := maxi(int(ceil(content_min.y)) + 12, eff_min_h)
	var max_w := maxi(300, bounds.x)
	var max_h := maxi(180, bounds.y)
	var clamped_w := mini(want_w, max_w)
	var clamped_h := mini(want_h, max_h)
	if want_h > max_h:
		_set_dialog_scroll_mode(dialog, ScrollContainer.SCROLL_MODE_AUTO)
	dialog.min_size = Vector2i(mini(eff_width, clamped_w), mini(eff_min_h, clamped_h))
	return Vector2i(clamped_w, clamped_h)


static func popup_fit(dialog: Window, width: int, min_height: int = 0) -> void:
	var target := _compute_fit_size(dialog, width, min_height)
	dialog.popup_centered(target)
	target = _compute_fit_size(dialog, width, min_height)
	dialog.size = target
	dialog.move_to_center()


static func shrink_dialog(dialog: Window, width: int, min_height: int = 0) -> void:
	var target := _compute_fit_size(dialog, width, min_height)
	dialog.size = target


static func _configure_crisp_font(font: FontFile) -> FontFile:
	# Preserve Verdana_m1's 1-bit embedded bitmap strikes (4..30 px) and disable all AA/subpixel blur.
	font.disable_embedded_bitmaps = false
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	font.hinting = TextServer.HINTING_NORMAL
	font.keep_rounding_remainders = true
	font.force_autohinter = false
	font.oversampling = 1.0
	return font


static func verdana(embedded_filename: String, fallback_system_filename: String = "verdana.ttf") -> Font:
	var embedded := "res://themes/fonts/" + embedded_filename
	if FileAccess.file_exists(embedded):
		var bytes := FileAccess.get_file_as_bytes(embedded)
		if not bytes.is_empty():
			var font := FontFile.new()
			font.data = bytes
			return _configure_crisp_font(font)
	if ResourceLoader.exists(embedded):
		var loaded := ResourceLoader.load(embedded)
		if loaded is FontFile:
			var dup: FontFile = (loaded as FontFile).duplicate()
			return _configure_crisp_font(dup)
	if OS.get_name() == "Windows":
		var user_fonts := OS.get_environment("LOCALAPPDATA").path_join("Microsoft/Windows/Fonts").path_join(embedded_filename)
		if FileAccess.file_exists(user_fonts):
			var ubytes := FileAccess.get_file_as_bytes(user_fonts)
			if not ubytes.is_empty():
				var ufont := FontFile.new()
				ufont.data = ubytes
				return _configure_crisp_font(ufont)
		var sys_path := OS.get_environment("WINDIR").path_join("Fonts").path_join(fallback_system_filename)
		var sfont := FontFile.new()
		if FileAccess.file_exists(sys_path) and sfont.load_dynamic_font(sys_path) == OK:
			return _configure_crisp_font(sfont)
	var system := SystemFont.new()
	system.font_names = PackedStringArray(["Verdana_m1", "Verdana"])
	system.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	system.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	system.hinting = TextServer.HINTING_NORMAL
	system.oversampling = 1.0
	return system
