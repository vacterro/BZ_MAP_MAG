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
var message := Label.new()
var preview_button: Button


func _ready() -> void:
	title = "Shape Terrain"
	ok_button_text = "Apply"
	dialog_hide_on_ok = false
	min_size = Vector2i(410, 225)
	var layout := VBoxContainer.new()
	add_child(layout)
	for name in ["Slope plane", "Mirror heights"]:
		operation.add_item(name)
	layout.add_child(operation)
	operation.item_selected.connect(choose_operation)
	layout.add_child(slope_fields)
	add_number(slope_fields, "Anchor height (m)", height, 100000.0, 0.1)
	add_number(slope_fields, "Grade along X (%)", grade_x, 1000.0, 0.1)
	add_number(slope_fields, "Grade along Z (%)", grade_z, 1000.0, 0.1)
	layout.add_child(mirror_fields)
	for name in ["Min X → Max X", "Max X → Min X", "Min Z → Max Z", "Max Z → Min Z"]:
		direction.add_item(name)
	mirror_fields.add_child(direction)
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
	preview_button.disabled = index != 0
	if index == 0:
		message.text = "Plane at the terrain cursor with a %.0f m brush radius." % radius_m
	else:
		message.text = "Copy one half of the map into the opposite half."


func preview_plane() -> bool:
	if not document.preview_slope_plane(center, radius_m, height.value, Vector2(grade_x.value, grade_z.value) / 100.0):
		message.text = document.error
		return false
	message.text = "Previewing %d height samples. Apply to keep the plane." % document.preview_after.size()
	return true


func apply_terrain() -> void:
	var count: int
	if operation.selected == 0:
		if not preview_plane():
			return
		count = document.preview_after.size()
		document.bake_preview()
	else:
		count = document.mirror_heights(direction.selected)
		if count < 0:
			message.text = document.error
			return
	updated.emit("Shaped %d height samples." % count if count else "The terrain already matches the selected shape.")
	hide()


func clear_preview() -> void:
	if document != null:
		document.clear_preview()
