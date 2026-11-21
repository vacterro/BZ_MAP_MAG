extends MarginContainer
## Toggle-button group with an OptionButton-compatible API.
## Automatically switches to a bounded 2-row scrollable + searchable container
## when item_count > compact_overflow_threshold (default 7), preventing large
## lists (such as 20+ Steam Workshop mods) from inflating dialog height.

signal item_selected(index: int)

const DEFAULT_OVERFLOW_THRESHOLD := 12
const DEFAULT_MAX_SCROLL_HEIGHT := 52

var selected := -1
var item_count: int:
	get:
		return _buttons.size()
var disabled := false:
	set(value):
		disabled = value
		if _filter_input != null:
			_filter_input.editable = not disabled
		for btn in _buttons:
			btn.disabled = disabled

var compact_overflow_threshold := DEFAULT_OVERFLOW_THRESHOLD
var max_scroll_height := DEFAULT_MAX_SCROLL_HEIGHT

var _outer := VBoxContainer.new()
var _header_row := HBoxContainer.new()
var _filter_input := LineEdit.new()
var _selected_badge := Label.new()
var _scroll := ScrollContainer.new()
var _container: Container
var _columns := 0
var _expand := false
var _buttons: Array[Button] = []
var _metadata: Array = []


func _init(columns: int = 0, expand_buttons: bool = false) -> void:
	_columns = columns
	_expand = expand_buttons or columns > 0
	_outer.add_theme_constant_override("separation", 3)
	_outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_outer)

	_header_row.add_theme_constant_override("separation", 4)
	_header_row.hide()
	_outer.add_child(_header_row)

	_filter_input.placeholder_text = "Filter options…"
	_filter_input.custom_minimum_size.x = 130
	_filter_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filter_input.text_changed.connect(_on_filter_text_changed)
	_header_row.add_child(_filter_input)

	_selected_badge.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_selected_badge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header_row.add_child(_selected_badge)

	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_outer.add_child(_scroll)

	if columns > 0:
		var grid := GridContainer.new()
		grid.columns = columns
		grid.add_theme_constant_override("h_separation", 4)
		grid.add_theme_constant_override("v_separation", 4)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_container = grid
	else:
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 4)
		flow.add_theme_constant_override("v_separation", 4)
		flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_container = flow
	_scroll.add_child(_container)


func set_overflow_limit(threshold: int, scroll_height: int = DEFAULT_MAX_SCROLL_HEIGHT) -> void:
	compact_overflow_threshold = maxi(2, threshold)
	max_scroll_height = maxi(32, scroll_height)
	_update_overflow_mode()


func add_item(label: String, _id: int = -1) -> void:
	var idx := _buttons.size()
	var btn := Button.new()
	btn.text = label
	btn.tooltip_text = label
	btn.toggle_mode = true
	btn.disabled = disabled
	if _expand:
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(_on_button_pressed.bind(idx))
	_container.add_child(btn)
	_buttons.append(btn)
	_metadata.append(null)
	if selected < 0:
		selected = 0
		btn.set_pressed_no_signal(true)
	_update_overflow_mode()
	_sync_selected_badge()


func clear() -> void:
	for btn in _buttons:
		if btn.get_parent() == _container:
			_container.remove_child(btn)
		btn.queue_free()
	_buttons.clear()
	_metadata.clear()
	selected = -1
	if _filter_input != null and not _filter_input.text.is_empty():
		_filter_input.text = ""
	_update_overflow_mode()
	_sync_selected_badge()


func select(index: int) -> void:
	if index < 0 or index >= _buttons.size():
		selected = -1
	else:
		selected = index
	_sync_pressed()
	_sync_selected_badge()


func get_item_text(index: int) -> String:
	return _buttons[index].text if index >= 0 and index < _buttons.size() else ""


func set_item_metadata(index: int, meta: Variant) -> void:
	if index >= 0 and index < _metadata.size():
		_metadata[index] = meta


func get_item_metadata(index: int) -> Variant:
	return _metadata[index] if index >= 0 and index < _metadata.size() else null


func button_at(index: int) -> Button:
	return _buttons[index] if index >= 0 and index < _buttons.size() else null


func filter_options(query: String) -> void:
	if _filter_input.text != query:
		_filter_input.text = query
	_on_filter_text_changed(query)


func _on_filter_text_changed(query: String) -> void:
	var needle := query.strip_edges().to_lower()
	for i in _buttons.size():
		var btn := _buttons[i]
		var meta_str := String(_metadata[i]).to_lower() if _metadata[i] != null else ""
		var matches := needle.is_empty() or btn.text.to_lower().contains(needle) or meta_str.contains(needle)
		btn.visible = matches or (i == selected)


func _update_overflow_mode() -> void:
	var overflow := _columns == 0 and _buttons.size() > compact_overflow_threshold
	_header_row.visible = overflow
	if overflow:
		_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		_scroll.custom_minimum_size.y = max_scroll_height
	else:
		_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_scroll.custom_minimum_size.y = 0


func _sync_selected_badge() -> void:
	if selected >= 0 and selected < _buttons.size():
		_selected_badge.text = "Active: " + _buttons[selected].text
		_selected_badge.tooltip_text = _buttons[selected].text
	else:
		_selected_badge.text = ""
		_selected_badge.tooltip_text = ""


func _on_button_pressed(index: int) -> void:
	if index < 0 or index >= _buttons.size():
		return
	selected = index
	_sync_pressed()
	_sync_selected_badge()
	item_selected.emit(index)


func _sync_pressed() -> void:
	for i in _buttons.size():
		_buttons[i].set_pressed_no_signal(i == selected)
