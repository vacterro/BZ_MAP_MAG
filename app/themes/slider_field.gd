extends HBoxContainer
## Houdini-style numeric control: Wintage HSlider + direct-entry LineEdit + MMB Value Ladder.
## Exposes a SpinBox-compatible Range API (.value, .min_value, .max_value, .step,
## .editable, .allow_lesser, .allow_greater, set_value_no_signal, value_changed)
## plus gesture lifecycle signals (gesture_started, preview_changed,
## value_committed, gesture_cancelled).

const Wintage := preload("res://themes/wintage.gd")

signal value_changed(value: float)
signal gesture_started(initial_value: float)
signal preview_changed(value: float)
signal value_committed(initial_value: float, final_value: float)
signal gesture_cancelled(restored_value: float)
signal gesture_ended(committed: bool)

enum Role { PURE_PARAMETER, PREVIEW_PARAMETER, DIRECT_DOCUMENT_EDIT }

const LADDER_STEP_PIXELS_Y := 18.0
const LADDER_TICK_PIXELS_X := 8.0

var slider := HSlider.new()
var readout := LineEdit.new()
var field_role: Role = Role.PURE_PARAMETER

var _value := 0.0
var _default_value := 0.0
var _has_default := false
var _min_value := 0.0
var _max_value := 100.0
var _step := 1.0
var _allow_lesser := false
var _allow_greater := false
var _editable := true
var _has_slider_range := false
var _slider_min := 0.0
var _slider_max := 100.0
var _syncing := false
var _unit_suffix := ""

var _gesture_mode := "" # "", "slider", "ladder"
var _gesture_initial_value := 0.0
var _readout_initial_value := 0.0
var _readout_cancelling := false

var _ladder_active := false
var _ladder_steps: Array[float] = []
var _ladder_custom_steps: Array[float] = []
var _ladder_index := 0
var _ladder_start_index := 0
var _ladder_anchor_pos := Vector2.ZERO
var _ladder_accum_x := 0.0
var _ladder_layer: CanvasLayer
var _ladder_panel: PanelContainer
var _ladder_header: Label
var _ladder_row_panels: Array[PanelContainer] = []
var _ladder_row_labels: Array[Label] = []
var _context_menu: PopupMenu
var _bound_window: Window

var min_value: float:
	get:
		return _min_value
	set(v):
		_min_value = v
		if _max_value < _min_value:
			_max_value = _min_value
		_sync_slider_bounds()
		_set_value_internal(_value, false)

var max_value: float:
	get:
		return _max_value
	set(v):
		_max_value = v
		if _min_value > _max_value:
			_min_value = _max_value
		_sync_slider_bounds()
		_set_value_internal(_value, false)

var step: float:
	get:
		return _step
	set(v):
		_step = maxf(0.0, v)
		slider.step = _step
		_set_value_internal(_value, false)

var allow_lesser: bool:
	get:
		return _allow_lesser
	set(v):
		_allow_lesser = v
		_sync_slider_bounds()

var allow_greater: bool:
	get:
		return _allow_greater
	set(v):
		_allow_greater = v
		_sync_slider_bounds()

var editable: bool:
	get:
		return _editable
	set(v):
		_editable = v
		slider.editable = _editable
		readout.editable = _editable
		if not _editable and is_gesture_active():
			cancel_gesture()

var value: float:
	get:
		return _value
	set(v):
		if not _has_default and is_finite(v):
			_default_value = v
			_has_default = true
		_set_value_internal(v, true)

var default_value: float:
	get:
		return _default_value
	set(v):
		if is_finite(v):
			_default_value = v
			_has_default = true


func _init() -> void:
	add_theme_constant_override("separation", 4)
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_control_gui_input)

	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size.x = 56
	slider.min_value = _min_value
	slider.max_value = _max_value
	slider.step = _step
	slider.value_changed.connect(_on_slider_changed)
	slider.gui_input.connect(_on_child_gui_input)
	add_child(slider)

	readout.custom_minimum_size.x = 48
	readout.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	readout.select_all_on_focus = true
	readout.context_menu_enabled = false
	readout.focus_entered.connect(_on_readout_focus_entered)
	readout.text_submitted.connect(_on_readout_submitted)
	readout.focus_exited.connect(_on_readout_focus_exited)
	readout.gui_input.connect(_on_readout_gui_input)
	add_child(readout)
	_refresh_readout()


func set_slider_range(lo: float, hi: float) -> void:
	_has_slider_range = true
	_slider_min = minf(lo, hi)
	_slider_max = maxf(lo, hi)
	_sync_slider_bounds()
	_sync_slider_value()


func set_readout_width(width: float) -> void:
	readout.custom_minimum_size.x = width


func set_unit_suffix(unit: String) -> void:
	_unit_suffix = unit.strip_edges()
	_refresh_tooltip()


func set_default_value(v: float) -> void:
	if is_finite(v):
		_default_value = _snap_and_clamp(v)
		_has_default = true


func set_ladder_steps(steps: Array[float]) -> void:
	_ladder_custom_steps = steps.duplicate()


func set_field_role(role: Role) -> void:
	field_role = role


func bind_preview_parameter(on_preview: Callable, on_cancel: Callable = Callable()) -> void:
	field_role = Role.PREVIEW_PARAMETER
	if on_preview.is_valid():
		preview_changed.connect(func(v: float): on_preview.call(v))
		value_committed.connect(func(_i: float, f: float): on_preview.call(f))
	if on_cancel.is_valid():
		gesture_cancelled.connect(func(r: float): on_cancel.call(r))


func bind_direct_edit(on_begin: Callable, on_preview: Callable, on_commit: Callable, on_cancel: Callable) -> void:
	field_role = Role.DIRECT_DOCUMENT_EDIT
	if on_begin.is_valid():
		gesture_started.connect(func(init_v: float): on_begin.call(init_v))
	if on_preview.is_valid():
		preview_changed.connect(func(v: float): on_preview.call(v))
	if on_commit.is_valid():
		value_committed.connect(func(init_v: float, final_v: float): on_commit.call(init_v, final_v))
	if on_cancel.is_valid():
		gesture_cancelled.connect(func(restored_v: float): on_cancel.call(restored_v))


func set_value_no_signal(v: float) -> void:
	if not _has_default and is_finite(v):
		_default_value = v
		_has_default = true
	_set_value_internal(v, false)


func is_integer_field() -> bool:
	return _step >= 1.0 and is_equal_approx(_step, roundf(_step))


func is_gesture_active() -> bool:
	return not _gesture_mode.is_empty()


func is_ladder_active() -> bool:
	return _ladder_active


func active_ladder_step() -> float:
	if _ladder_steps.is_empty():
		_ladder_steps = get_ladder_steps()
	if _ladder_steps.is_empty():
		return _step if _step > 0.0 else 1.0
	return _ladder_steps[clampi(_ladder_index, 0, _ladder_steps.size() - 1)]


func get_ladder_steps() -> Array[float]:
	if not _ladder_custom_steps.is_empty():
		return _ladder_custom_steps.duplicate()
	var span := absf(_max_value - _min_value)
	if _has_slider_range:
		span = maxf(span, absf(_slider_max - _slider_min))
	var candidates: Array[float] = [1000.0, 100.0, 10.0, 5.0, 1.0, 0.5, 0.1, 0.01, 0.001]
	var min_step := _step if _step > 0.0 else 0.001
	var int_only := is_integer_field()
	var max_rung := 1000.0
	if span > 0.0 and not _allow_greater and not _allow_lesser:
		max_rung = maxf(min_step, span * 0.5)
	var result: Array[float] = []
	for c in candidates:
		if int_only and c < 1.0:
			continue
		if c + 0.000001 < min_step:
			continue
		if c > max_rung + 0.0001 and c > min_step:
			continue
		# Avoid adding both 5.0 and 10.0 on wide ranges; keep 5.0 only for small integer spans (e.g. 0..15)
		if is_equal_approx(c, 5.0) and max_rung >= 50.0:
			continue
		if is_equal_approx(c, 0.5) and not is_equal_approx(min_step, 0.5):
			continue
		if int_only and _step > 1.0 and not is_zero_approx(fmod(c, _step)):
			continue
		result.append(c)
	if not result.any(func(x: float): return is_equal_approx(x, min_step)):
		result.append(min_step)
	result.sort_custom(func(a: float, b: float) -> bool: return a > b)
	return result


func _default_ladder_index(steps: Array[float]) -> int:
	if steps.is_empty():
		return 0
	var preferred := 1.0
	if _step >= 1.0:
		preferred = _step
	elif _max_value - _min_value <= 2.0 and not _has_slider_range:
		preferred = 0.05 if _step <= 0.05 and _step > 0.0 else 0.1
	elif _step > 0.0:
		preferred = maxf(_step, 1.0 if (_has_slider_range or _max_value - _min_value >= 20.0) else _step)
	var best_idx := 0
	var best_dist := INF
	for i in steps.size():
		var d := absf(log(maxf(steps[i], 0.0001)) - log(maxf(preferred, 0.0001)))
		if d < best_dist:
			best_dist = d
			best_idx = i
	return best_idx


func reset_to_default() -> void:
	if not _editable:
		return
	var target := _default_value if _has_default else 0.0
	var prev := _value
	_set_value_internal(target, true)
	if not is_equal_approx(prev, _value):
		value_committed.emit(prev, _value)


func begin_ladder(screen_pos: Vector2) -> void:
	if not _editable:
		return
	if _gesture_mode == "slider":
		commit_gesture()
	_ladder_steps = get_ladder_steps()
	_ladder_start_index = _default_ladder_index(_ladder_steps)
	_ladder_index = _ladder_start_index
	_ladder_anchor_pos = screen_pos
	_ladder_accum_x = 0.0
	_ladder_active = true
	_begin_gesture("ladder")
	_show_ladder_overlay(screen_pos)
	set_process_input(true)


func update_ladder(screen_pos: Vector2, delta_x: float, shift_held: bool = false, ctrl_held: bool = false) -> void:
	if not _ladder_active or not _editable:
		return
	var dy := screen_pos.y - _ladder_anchor_pos.y
	var rung_shift := int(round(dy / LADDER_STEP_PIXELS_Y))
	var next_index := clampi(_ladder_start_index + rung_shift, 0, maxi(0, _ladder_steps.size() - 1))
	if next_index != _ladder_index:
		_ladder_index = next_index
		_ladder_accum_x = 0.0
		_refresh_ladder_overlay()
		return
	var step_mag := active_ladder_step()
	var mod_scale := 1.0
	if shift_held and not ctrl_held:
		mod_scale = 0.25 if not is_integer_field() else 0.5
	elif ctrl_held and not shift_held:
		mod_scale = 4.0
	_ladder_accum_x += delta_x * mod_scale
	var ticks := int(_ladder_accum_x / LADDER_TICK_PIXELS_X)
	if ticks != 0:
		_ladder_accum_x -= float(ticks) * LADDER_TICK_PIXELS_X
		var next_val := _value + float(ticks) * step_mag
		_set_value_internal(next_val, true, true)
	_refresh_ladder_overlay()


func step_ladder_by(ticks: int, rung_index: int = -1) -> void:
	if not _editable:
		return
	if not _ladder_active:
		begin_ladder(get_global_rect().get_center())
	if rung_index >= 0 and rung_index < _ladder_steps.size():
		_ladder_index = rung_index
	var step_mag := active_ladder_step()
	_set_value_internal(_value + float(ticks) * step_mag, true, true)
	_refresh_ladder_overlay()


func end_ladder(commit: bool = true) -> void:
	if not _ladder_active:
		return
	_ladder_active = false
	_hide_ladder_overlay()
	if commit:
		commit_gesture()
	else:
		cancel_gesture()


func _begin_gesture(mode: String) -> void:
	_gesture_mode = mode
	_gesture_initial_value = _value
	gesture_started.emit(_gesture_initial_value)


func commit_gesture() -> void:
	if _gesture_mode.is_empty():
		return
	var initial := _gesture_initial_value
	var final_val := _value
	_gesture_mode = ""
	if _ladder_active:
		_ladder_active = false
		_hide_ladder_overlay()
	if not is_equal_approx(initial, final_val):
		value_committed.emit(initial, final_val)
	gesture_ended.emit(true)


func cancel_gesture() -> void:
	if _gesture_mode.is_empty() and not _ladder_active:
		return
	var restored := _gesture_initial_value
	_gesture_mode = ""
	if _ladder_active:
		_ladder_active = false
		_hide_ladder_overlay()
	_set_value_internal(restored, true, false)
	gesture_cancelled.emit(_value)
	gesture_ended.emit(false)


func _input(event: InputEvent) -> void:
	if _ladder_active:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			end_ladder(false)
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				end_ladder(false)
				get_viewport().set_input_as_handled()
				return
			if event.button_index == MOUSE_BUTTON_MIDDLE and not event.pressed:
				end_ladder(true)
				get_viewport().set_input_as_handled()
				return
		if event is InputEventMouseMotion:
			update_ladder(event.global_position, event.relative.x, event.shift_pressed, event.ctrl_pressed)
			get_viewport().set_input_as_handled()
			return
	elif _gesture_mode == "slider":
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			cancel_gesture()
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			commit_gesture()


func _on_control_gui_input(event: InputEvent) -> void:
	_handle_pointer_event(event)


func _on_child_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and _editable and _gesture_mode.is_empty():
			_begin_gesture("slider")
		elif not event.pressed and _gesture_mode == "slider":
			commit_gesture()
		return
	_handle_pointer_event(event)


func _on_readout_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			_readout_cancelling = true
			_set_value_internal(_readout_initial_value, true, false)
			_refresh_readout()
			gesture_cancelled.emit(_value)
			readout.release_focus()
			_readout_cancelling = false
			accept_event()
			return
		if event.keycode in [KEY_UP, KEY_DOWN] and _editable:
			var dir := 1.0 if event.keycode == KEY_UP else -1.0
			var delta := (_step if _step > 0.0 else 1.0) * dir
			if event.shift_pressed and not is_integer_field():
				delta *= 0.1
			elif event.ctrl_pressed:
				delta *= 10.0
			var prev := _value
			_set_value_internal(_value + delta, true, false)
			if not is_equal_approx(prev, _value):
				value_committed.emit(prev, _value)
			accept_event()
			return
	_handle_pointer_event(event)


func _handle_pointer_event(event: InputEvent) -> void:
	if not _editable:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				if event.ctrl_pressed:
					reset_to_default()
				else:
					begin_ladder(event.global_position)
			elif _ladder_active:
				end_ladder(true)
			accept_event()
			if is_inside_tree() and get_viewport() != null:
				get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if _ladder_active:
				end_ladder(false)
			else:
				_open_context_menu(event.global_position)
			accept_event()
			if is_inside_tree() and get_viewport() != null:
				get_viewport().set_input_as_handled()


func _open_context_menu(global_pos: Vector2) -> void:
	if _context_menu == null:
		_context_menu = PopupMenu.new()
		_context_menu.add_item("Copy Value", 0)
		_context_menu.add_item("Paste Value", 1)
		_context_menu.add_separator()
		_context_menu.add_item("Reset to Default", 2)
		_context_menu.id_pressed.connect(_on_context_menu_id)
		add_child(_context_menu)
	_context_menu.set_item_disabled(1, not _editable)
	_context_menu.set_item_disabled(2, not _editable)
	var win := get_window()
	var win_pos := win.position if win != null else Vector2i.ZERO
	_context_menu.position = win_pos + Vector2i(global_pos.round())
	_context_menu.reset_size()
	_context_menu.popup()


static var _fallback_clipboard := ""


func _on_context_menu_id(id: int) -> void:
	match id:
		0:
			_fallback_clipboard = readout.text
			if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
				DisplayServer.clipboard_set(readout.text)
		1:
			if _editable:
				var clip := DisplayServer.clipboard_get() if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD) else _fallback_clipboard
				_commit_text(clip)
		2:
			reset_to_default()


func _bind_window_lifecycle() -> void:
	var win := get_window()
	if win == _bound_window:
		return
	if _bound_window != null:
		if _bound_window.visibility_changed.is_connected(_on_host_window_hidden):
			_bound_window.visibility_changed.disconnect(_on_host_window_hidden)
		if _bound_window.close_requested.is_connected(_on_host_window_closed):
			_bound_window.close_requested.disconnect(_on_host_window_closed)
	_bound_window = win
	if _bound_window != null:
		if not _bound_window.visibility_changed.is_connected(_on_host_window_hidden):
			_bound_window.visibility_changed.connect(_on_host_window_hidden)
		if not _bound_window.close_requested.is_connected(_on_host_window_closed):
			_bound_window.close_requested.connect(_on_host_window_closed)


func _on_host_window_hidden() -> void:
	if _bound_window != null and not _bound_window.visible:
		if is_gesture_active() or _ladder_active:
			cancel_gesture()
		else:
			_hide_ladder_overlay()


func _on_host_window_closed() -> void:
	if is_gesture_active() or _ladder_active:
		cancel_gesture()
	else:
		_hide_ladder_overlay()


func _show_ladder_overlay(screen_pos: Vector2) -> void:
	if not is_inside_tree():
		return
	_bind_window_lifecycle()
	if _ladder_layer == null:
		_ladder_layer = CanvasLayer.new()
		_ladder_layer.layer = 128
		add_child(_ladder_layer)
		_ladder_panel = PanelContainer.new()
		_ladder_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ladder_layer.add_child(_ladder_panel)
	_ladder_layer.visible = true
	for child in _ladder_panel.get_children():
		child.queue_free()
	_ladder_row_panels.clear()
	_ladder_row_labels.clear()

	var colors := Wintage.palette()
	var win := get_window()
	if win != null and win.theme != null:
		_ladder_panel.theme = win.theme
	elif theme != null:
		_ladder_panel.theme = theme
	_ladder_panel.add_theme_stylebox_override("panel", Wintage.box(colors["surface"], colors["borderHighlight"], colors["borderDark"], true))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ladder_panel.add_child(box)

	_ladder_header = Label.new()
	_ladder_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ladder_header.add_theme_color_override("font_color", colors["borderHighlight"])
	_ladder_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_ladder_header)

	for step_val in _ladder_steps:
		var rpanel := PanelContainer.new()
		rpanel.custom_minimum_size = Vector2(88, 18)
		rpanel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rlbl := Label.new()
		rlbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rlbl.text = "± " + _format_step(step_val)
		rlbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rpanel.add_child(rlbl)
		box.add_child(rpanel)
		_ladder_row_panels.append(rpanel)
		_ladder_row_labels.append(rlbl)

	_ladder_panel.show()
	_refresh_ladder_overlay()
	_ladder_panel.reset_size()
	var vp_rect := get_viewport_rect().size
	var panel_sz := _ladder_panel.get_combined_minimum_size()
	var target_pos := screen_pos - Vector2(panel_sz.x * 0.5, float(_ladder_index + 1) * 20.0)
	target_pos.x = clampf(target_pos.x, 4.0, maxf(4.0, vp_rect.x - panel_sz.x - 4.0))
	target_pos.y = clampf(target_pos.y, 4.0, maxf(4.0, vp_rect.y - panel_sz.y - 4.0))
	_ladder_panel.position = target_pos


func _refresh_ladder_overlay() -> void:
	if _ladder_panel == null or not _ladder_panel.visible:
		return
	var colors := Wintage.palette()
	var suffix_str := (" " + _unit_suffix) if not _unit_suffix.is_empty() else ""
	_ladder_header.text = _format_value(_value) + suffix_str
	for i in _ladder_row_panels.size():
		var active := (i == _ladder_index)
		var rpanel := _ladder_row_panels[i]
		var rlbl := _ladder_row_labels[i]
		if active:
			rpanel.add_theme_stylebox_override("panel", Wintage.box(colors["accentTealDeep"], colors["borderDark"], colors["borderHighlight"], true))
			rlbl.add_theme_color_override("font_color", colors["borderHighlight"])
		else:
			rpanel.add_theme_stylebox_override("panel", Wintage.box(colors["surfaceRaised"], colors["bevelLight"], colors["borderDark"], true))
			rlbl.add_theme_color_override("font_color", colors["textPrimary"])


func _hide_ladder_overlay() -> void:
	if _ladder_panel != null:
		_ladder_panel.hide()
	if _ladder_layer != null:
		_ladder_layer.visible = false


func _format_step(s: float) -> String:
	if s >= 1.0 and is_equal_approx(s, roundf(s)):
		return str(int(round(s)))
	elif s >= 0.1:
		return "%.1f" % s
	elif s >= 0.01:
		return "%.2f" % s
	return "%.3f" % s


func _snap_and_clamp(v: float) -> float:
	if not is_finite(v):
		return _value
	var out := v
	if not _allow_lesser:
		out = maxf(out, _min_value)
	if not _allow_greater:
		out = minf(out, _max_value)
	if _step > 0.0:
		var steps := roundf((out - _min_value) / _step)
		out = _min_value + steps * _step
		if not _allow_lesser:
			out = maxf(out, _min_value)
		if not _allow_greater:
			out = minf(out, _max_value)
	if is_zero_approx(out):
		out = 0.0
	return out


func _set_value_internal(v: float, emit: bool, is_preview: bool = false) -> void:
	var snapped := _snap_and_clamp(v)
	var changed := not is_equal_approx(snapped, _value)
	_value = snapped
	_sync_slider_bounds()
	_sync_slider_value()
	_refresh_readout()
	if emit and changed:
		if is_preview or is_gesture_active():
			preview_changed.emit(_value)
		value_changed.emit(_value)


func _sync_slider_bounds() -> void:
	_syncing = true
	var lo := _slider_min if _has_slider_range else _min_value
	var hi := _slider_max if _has_slider_range else _max_value
	if not _allow_lesser:
		lo = maxf(lo, _min_value)
	if not _allow_greater:
		hi = minf(hi, _max_value)
	if _value < lo:
		lo = _value
	if _value > hi:
		hi = _value
	if hi <= lo:
		hi = lo + (_step if _step > 0.0 else 1.0)
	slider.min_value = lo
	slider.max_value = hi
	slider.step = _step
	_syncing = false


func _sync_slider_value() -> void:
	_syncing = true
	slider.set_value_no_signal(_value)
	_syncing = false


func _format_value(v: float) -> String:
	var clean_v := 0.0 if is_zero_approx(v) else v
	if is_integer_field():
		return str(int(round(clean_v)))
	elif _step == 0.0:
		if is_equal_approx(clean_v, snappedf(clean_v, 0.01)):
			return "%.2f" % clean_v
		return "%.3f" % clean_v
	elif _step >= 0.1:
		return "%.1f" % clean_v
	elif _step >= 0.01:
		return "%.2f" % clean_v
	return "%.3f" % clean_v


func _refresh_readout() -> void:
	readout.text = _format_value(_value)
	_refresh_tooltip()


func _refresh_tooltip() -> void:
	var unit_part := (" " + _unit_suffix) if not _unit_suffix.is_empty() else ""
	var tip := "Value: %s%s\nMMB drag: Houdini Value Ladder (vertical=step, horizontal=scrub, Esc=cancel)\nCtrl+MMB or Right-click: Reset / Copy / Paste" % [_format_value(_value), unit_part]
	readout.tooltip_text = tip
	if tooltip_text.is_empty():
		slider.tooltip_text = tip
	else:
		slider.tooltip_text = tooltip_text + "\n" + tip


func _on_slider_changed(v: float) -> void:
	if _syncing:
		return
	_set_value_internal(v, true, _gesture_mode == "slider")


func _on_readout_focus_entered() -> void:
	_readout_initial_value = _value
	_readout_cancelling = false


func _on_readout_submitted(text: String) -> void:
	if _readout_cancelling:
		return
	_commit_text(text)


func _on_readout_focus_exited() -> void:
	if _readout_cancelling:
		return
	_commit_text(readout.text)


static func parse_numeric_text(text: String, unit_suffix: String = "") -> float:
	var clean := text.strip_edges()
	if not unit_suffix.is_empty() and clean.to_lower().ends_with(unit_suffix.to_lower()):
		clean = clean.substr(0, clean.length() - unit_suffix.length()).strip_edges()
	for trailing in [" m", "m", " °", "°", " %", "%", " s", "s", " deg"]:
		if clean.to_lower().ends_with(trailing) and clean.length() > trailing.length():
			var prefix := clean.substr(0, clean.length() - trailing.length()).strip_edges()
			if prefix.replace(",", ".").is_valid_float():
				clean = prefix
				break
	clean = clean.replace(",", ".")
	var lower := clean.to_lower()
	if clean.is_empty() or lower in ["nan", "inf", "+inf", "-inf", "infinity", "+infinity", "-infinity"]:
		return NAN
	if not clean.is_valid_float():
		return NAN
	var parsed := clean.to_float()
	return parsed if is_finite(parsed) else NAN


func _commit_text(text: String) -> void:
	var parsed := parse_numeric_text(text, _unit_suffix)
	if is_finite(parsed):
		var prev := _value
		_set_value_internal(parsed, true, false)
		if not is_equal_approx(prev, _value):
			value_committed.emit(prev, _value)
	else:
		_refresh_readout()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		if not is_visible_in_tree() and (is_gesture_active() or _ladder_active):
			cancel_gesture()
	elif what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if is_gesture_active() or _ladder_active:
			cancel_gesture()


func _exit_tree() -> void:
	if is_gesture_active() or _ladder_active:
		cancel_gesture()
	_hide_ladder_overlay()
