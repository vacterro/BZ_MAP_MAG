extends PanelContainer
## Right-hand docked Attributes / Inspector host.
## Routes contexts without creating popup Windows or recreating heavy panels.

const WorkspaceState := preload("res://ui/workspace_state.gd")

signal close_requested
signal context_picked(context_id: int)

var state: WorkspaceState
var header_label := Label.new()
var pin_button := Button.new()
var close_button := Button.new()
var scroll := ScrollContainer.new()
var host_stack := VBoxContainer.new()
var empty_label := Label.new()
var panels: Dictionary = {} # int(InspectorContext) -> Control
var active_context: int = WorkspaceState.InspectorContext.NONE


func _ready() -> void:
	custom_minimum_size.x = 224
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var outer := VBoxContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_theme_constant_override("separation", 4)
	add_child(outer)

	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 4)
	outer.add_child(hdr)

	header_label.text = "Attributes"
	header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hdr.add_child(header_label)

	pin_button.text = "Pin"
	pin_button.toggle_mode = true
	pin_button.tooltip_text = "Pin current Attributes context so viewport selection does not replace it"
	pin_button.toggled.connect(func(on: bool):
		if state != null:
			state.set_pinned(on))
	hdr.add_child(pin_button)

	close_button.text = "×"
	close_button.tooltip_text = "Hide Attributes Inspector"
	close_button.pressed.connect(func(): close_requested.emit())
	hdr.add_child(close_button)

	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	outer.add_child(scroll)

	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["top", "bottom", "left", "right"]:
		pad.add_theme_constant_override("margin_" + side, 4)
	scroll.add_child(pad)

	host_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_stack.add_theme_constant_override("separation", 4)
	pad.add_child(host_stack)

	empty_label.text = "Select a tool, object, path or layer to inspect attributes."
	empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	host_stack.add_child(empty_label)


func bind_state(ws: WorkspaceState) -> void:
	state = ws
	state.inspector_context_changed.connect(show_context)
	state.pin_changed.connect(func(on: bool): pin_button.set_pressed_no_signal(on))
	pin_button.set_pressed_no_signal(state.pinned_inspector)
	show_context(state.active_inspector_context)


func register_panel(context_id: int, panel: Control) -> void:
	panels[context_id] = panel
	if panel.get_parent() != host_stack:
		if panel.get_parent() != null:
			panel.get_parent().remove_child(panel)
		host_stack.add_child(panel)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.visible = (context_id == active_context)
	_sync_empty_state()


func show_context(context_id: int) -> void:
	active_context = context_id
	var label_str: String = String(WorkspaceState.CONTEXT_LABELS.get(context_id, "Attributes"))
	header_label.text = "Attributes · " + label_str if context_id != WorkspaceState.InspectorContext.NONE else "Attributes"
	header_label.tooltip_text = header_label.text
	for key_v in panels:
		var key := int(key_v)
		var ctrl: Control = panels[key]
		if is_instance_valid(ctrl):
			ctrl.visible = (key == context_id)
	_sync_empty_state()
	scroll.scroll_vertical = 0


func current_panel() -> Control:
	return panels.get(active_context, null)


func _sync_empty_state() -> void:
	var has_active: bool = panels.has(active_context) and is_instance_valid(panels[active_context])
	empty_label.visible = not has_active
