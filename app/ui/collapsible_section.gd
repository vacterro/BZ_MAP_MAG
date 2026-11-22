extends VBoxContainer
## Reusable Wintage collapsible section for the docked Attributes Inspector.
## Connects to WorkspaceState via section_id for persistent collapse state and Reset Layout.

const WorkspaceState := preload("res://ui/workspace_state.gd")

signal toggled(collapsed: bool)

var section_id := ""
var title_text := ""
var default_collapsed := false
var collapsed := false
var header_button := Button.new()
var body := VBoxContainer.new()
var _bound_state: WorkspaceState


func _init(caption: String = "", id: String = "", start_collapsed: bool = false) -> void:
	title_text = caption
	section_id = id
	default_collapsed = start_collapsed
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


func bind_workspace_state(ws: WorkspaceState) -> void:
	if _bound_state == ws:
		if ws != null and not section_id.is_empty():
			set_collapsed(ws.is_section_collapsed(section_id, default_collapsed), false)
		return
	if _bound_state != null:
		if _bound_state.sections_reset.is_connected(_on_workspace_sections_reset):
			_bound_state.sections_reset.disconnect(_on_workspace_sections_reset)
		if _bound_state.section_toggled.is_connected(_on_workspace_section_toggled):
			_bound_state.section_toggled.disconnect(_on_workspace_section_toggled)
	_bound_state = ws
	if _bound_state == null or section_id.is_empty():
		return
	_bound_state.sections_reset.connect(_on_workspace_sections_reset)
	_bound_state.section_toggled.connect(_on_workspace_section_toggled)
	set_collapsed(_bound_state.is_section_collapsed(section_id, default_collapsed), false)


func add_content(ctrl: Control) -> void:
	body.add_child(ctrl)


func set_collapsed(value: bool, emit_sig: bool = false) -> void:
	if collapsed == value:
		_apply_state()
		return
	collapsed = value
	_apply_state()
	if emit_sig:
		if _bound_state != null and not section_id.is_empty():
			_bound_state.set_section_collapsed(section_id, collapsed)
		toggled.emit(collapsed)


func _on_toggle() -> void:
	collapsed = not collapsed
	_apply_state()
	if _bound_state != null and not section_id.is_empty():
		_bound_state.set_section_collapsed(section_id, collapsed)
	toggled.emit(collapsed)


func _on_workspace_sections_reset() -> void:
	if _bound_state == null or section_id.is_empty():
		return
	set_collapsed(_bound_state.is_section_collapsed(section_id, default_collapsed), false)


func _on_workspace_section_toggled(id: String, is_col: bool) -> void:
	if id == section_id:
		set_collapsed(is_col, false)


func _apply_state() -> void:
	var glyph := "▸ " if collapsed else "▾ "
	header_button.text = glyph + title_text
	body.visible = not collapsed
