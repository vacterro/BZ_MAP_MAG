extends Node

const PlaytestValidation := preload("res://bridge/playtest_validation.gd")


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or args[0] != "--validate-playtest":
		get_tree().change_scene_to_file.call_deferred("res://editor.tscn")
		return
	if args.size() != 3:
		get_tree().quit(2)
		return
	var output := FileAccess.open(args[2], FileAccess.WRITE)
	if output == null:
		get_tree().quit(2)
		return
	output.store_string(JSON.stringify(PlaytestValidation.validate(args[1])))
	output.close()
	get_tree().quit()
