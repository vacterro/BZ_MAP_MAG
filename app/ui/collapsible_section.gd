extends VBoxContainer
## Reusable Wintage collapsible section for the docked Attributes Inspector.

signal toggled(collapsed: bool)

var section_id := ""
var title_text := ""
var collapsed := false
var header_button := Button.new()
var body := VBoxContainer.new()


func _init(caption: String = "", id: String = "", start_collapsed: bool = false) -> void:
	title_text = caption
	section_id = id
	collapsed = start_collapsed
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 3)

	header_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_button.focus_mode = Control.FOCUS_NONE
	header_button.pressed.connect(_on_toggle)
	add_child(header_button)

	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 3)
	add_child(body)
	_apply_state()


func add_content(ctrl: Control) -> void:
	body.add_child(ctrl)


func set_collapsed(value: bool, emit_sig: bool = false) -> void:
	if collapsed == value:
		return
	collapsed = value
	_apply_state()
	if emit_sig:
		toggled.emit(collapsed)


func _on_toggle() -> void:
	collapsed = not collapsed
	_apply_state()
	toggled.emit(collapsed)


func _apply_state() -> void:
	var glyph := "▸ " if collapsed else "▾ "
	header_button.text = glyph + title_text
	body.visible = not collapsed
