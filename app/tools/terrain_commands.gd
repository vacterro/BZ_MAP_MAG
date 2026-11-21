extends ConfirmationDialog

const Document := preload("res://core/map_document.gd")

signal updated(message: String)

var document: Document
var center: Vector2i
var radius_m := 32.0
var operation := OptionButton.new()
var direction := OptionButton.new()
var height := SpinBox.new()
var grade_x := SpinBox.new()
var grade_z := SpinBox.new()
var slope_fields := VBoxContainer.new()
var mirror_fields := VBoxContainer.new()
var vrv_fields := VBoxContainer.new()
var vrv_scope := OptionButton.new()
var vrv_strength := SpinBox.new()
var vrv_grain := SpinBox.new()
var vrv_softness := SpinBox.new()
var vrv_contrast := SpinBox.new()
var vrv_seed := SpinBox.new()
var vrv_symmetry := OptionButton.new()
var vrv_grain_row: HBoxContainer
var vrv_noise_rows: Array[Control] = []
var message := Label.new()
var preview_button: Button


func _ready() -> void:
	title = "Shape Terrain"
	ok_button_text = "Apply"
	dialog_hide_on_ok = false
	min_size = Vector2i(430, 320)
	var layout := VBoxContainer.new()
	add_child(layout)
	for op_name in ["Slope plane", "Mirror heights", "VRV Smooth", "VRV Rough +", "VRV Rough -", "VRV Relief +", "VRV Relief -"]:
		operation.add_item(op_name)
	layout.add_child(operation)
	operation.item_selected.connect(choose_operation)
	layout.add_child(slope_fields)
	add_number(slope_fields, "Anchor height (m)", height, 100000.0, 0.1)
	add_number(slope_fields, "Grade along X (%)", grade_x, 1000.0, 0.1)
	add_number(slope_fields, "Grade along Z (%)", grade_z, 1000.0, 0.1)
	layout.add_child(mirror_fields)
	for dir_name in ["Min X → Max X", "Max X → Min X", "Min Z → Max Z", "Max Z → Min Z"]:
		direction.add_item(dir_name)
	mirror_fields.add_child(direction)
	layout.add_child(vrv_fields)
	for scope_label in ["Around cursor (brush radius)", "Whole map"]:
		vrv_scope.add_item(scope_label)
	vrv_scope.item_selected.connect(func(_idx): clear_preview())
	vrv_fields.add_child(vrv_scope)
	add_spin_row(vrv_fields, "Strength (%)", vrv_strength, 0.0, 100.0, 1.0, 35.0)
	vrv_grain_row = add_spin_row(vrv_fields, "Grain (m)", vrv_grain, 2.0, 64.0, 2.0, 16.0)
	vrv_noise_rows.append(add_spin_row(vrv_fields, "Softness (%)", vrv_softness, 0.0, 100.0, 1.0, 50.0))
	vrv_noise_rows.append(add_spin_row(vrv_fields, "Contrast (%)", vrv_contrast, 0.0, 100.0, 1.0, 35.0))
	vrv_noise_rows.append(add_spin_row(vrv_fields, "Seed", vrv_seed, 1.0, 999999.0, 1.0, 1.0))
	var sym_row := HBoxContainer.new()
	var sym_lbl := Label.new()
	sym_lbl.text = "Symmetry fold"
	sym_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sym_row.add_child(sym_lbl)
	for sym_name in ["None", "X", "Z", "XZ"]:
		vrv_symmetry.add_item(sym_name)
	vrv_symmetry.item_selected.connect(func(_idx): clear_preview())
	sym_row.add_child(vrv_symmetry)
	vrv_fields.add_child(sym_row)
	vrv_noise_rows.append(sym_row)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size.y = 36
	layout.add_child(message)
	preview_button = add_button("Preview", true, "preview")
	custom_action.connect(func(_action: StringName): preview_plane())
	confirmed.connect(apply_terrain)
	canceled.connect(clear_preview)
	choose_operation(0)


func add_number(parent: Control, caption: String, field: SpinBox, limit: float, step: float) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = caption
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	field.min_value = -limit
	field.max_value = limit
	field.step = step
	field.custom_minimum_size.x = 110
	field.value_changed.connect(func(_value): clear_preview())
	row.add_child(field)


func add_spin_row(parent: Control, caption: String, field: SpinBox, lo: float, hi: float, step: float, initial: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = caption
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	field.min_value = lo
	field.max_value = hi
	field.step = step
	field.value = initial
	field.custom_minimum_size.x = 110
	field.value_changed.connect(func(_value): clear_preview())
	row.add_child(field)
	return row


func begin(value: Document, anchor: Vector2i, radius: float) -> void:
	document = value
	center = anchor
	radius_m = radius
	height.step = document.package.granularity
	height.value = document.package.terrain.heights[center.y * document.package.terrain.dimensions.x + center.x]
	choose_operation(operation.selected)
	popup_centered()


func choose_operation(index: int) -> void:
	clear_preview()
	slope_fields.visible = index == 0
	mirror_fields.visible = index == 1
	vrv_fields.visible = index >= 2
	vrv_grain_row.visible = index in [2, 3, 4]
	var show_noise := index in [3, 4]
	for node in vrv_noise_rows:
		node.visible = show_noise
	preview_button.disabled = index == 1
	if index == 0:
		message.text = "Plane at the terrain cursor with a %.0f m brush radius." % radius_m
	elif index == 1:
		message.text = "Copy one half of the map into the opposite half."
	else:
		message.text = "VRV shape filter on cursor region (%.0f m) or whole map." % radius_m


func vrv_op_name(index: int) -> String:
	match index:
		2:
			return "smooth"
		3:
			return "rough_plus"
		4:
			return "rough_minus"
		5:
			return "relief_plus"
		6:
			return "relief_minus"
	return ""


func vrv_region() -> Rect2i:
	if vrv_scope.selected == 1 or document == null:
		return Rect2i()
	return document.brush_region(Vector2(center), radius_m)


func vrv_params() -> Dictionary:
	var sym_values := ["none", "x", "z", "xz"]
	var sym_idx := clampi(vrv_symmetry.selected, 0, sym_values.size() - 1)
	return {
		"strength": int(vrv_strength.value),
		"grain_m": int(vrv_grain.value),
		"softness": int(vrv_softness.value),
		"contrast": int(vrv_contrast.value),
		"seed": int(vrv_seed.value),
		"symmetry": sym_values[sym_idx],
	}


func preview_plane() -> bool:
	if operation.selected == 0:
		if not document.preview_slope_plane(center, radius_m, height.value, Vector2(grade_x.value, grade_z.value) / 100.0):
			message.text = document.error
			return false
		message.text = "Previewing %d height samples. Apply to keep the plane." % document.preview_after.size()
		return true
	var op := vrv_op_name(operation.selected)
	if op.is_empty():
		return false
	if not document.preview_vrv_shape(op, vrv_params(), vrv_region()):
		message.text = document.error
		return false
	message.text = "Previewing %d height samples (%s). Apply to keep." % [document.preview_after.size(), operation.get_item_text(operation.selected)]
	return true


func apply_terrain() -> void:
	var count: int
	if operation.selected == 1:
		count = document.mirror_heights(direction.selected)
		if count < 0:
			message.text = document.error
			return
	else:
		if not preview_plane():
			return
		count = document.preview_after.size()
		document.bake_preview()
	updated.emit("Shaped %d height samples." % count if count else "The terrain already matches the selected shape.")
	hide()


func clear_preview() -> void:
	if document != null:
		document.clear_preview()
