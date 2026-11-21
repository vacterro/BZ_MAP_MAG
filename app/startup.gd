extends Node

const PlaytestValidation := preload("res://bridge/playtest_validation.gd")


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or args[0] != "--validate-playtest":
		get_tree().change_scene_to_file.call_deferred("res://editor.tscn")
		return
	if args.size() < 3:
		get_tree().quit(2)
		return
	var options := {}
	var i := 3
	while i < args.size():
		var flag := String(args[i])
		if flag == "--noscript":
			options["noscript"] = true
			i += 1
		elif flag in ["--game", "--vrv", "--mod", "--mission", "--asset-profile", "--asset-roots"] and i + 1 < args.size():
			var val := String(args[i + 1])
			match flag:
				"--game":
					options["game"] = val
				"--vrv":
					options["vrv"] = val
				"--mod":
					options["mod"] = val
				"--mission":
					options["mission"] = val
				"--asset-profile":
					options["asset_profile"] = val
				"--asset-roots":
					var roots: Array[String] = []
					for tok in val.split(";"):
						var clean := tok.strip_edges()
						if not clean.is_empty():
							roots.append(clean)
					options["asset_roots"] = roots
			i += 2
		else:
			i += 1
	var output := FileAccess.open(args[2], FileAccess.WRITE)
	if output == null:
		get_tree().quit(2)
		return
	output.store_string(JSON.stringify(PlaytestValidation.validate(args[1], options)))
	output.close()
	get_tree().quit()
