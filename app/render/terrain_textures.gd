extends RefCounted

const Assets := preload("res://formats/native_assets.gd")
const Terrain := preload("res://formats/terrain_v5.gd")
const TILE_PIXELS := 128
const SHADER := preload("res://render/terrain_surface.gdshader")


func load_native(game: String, map_folder: String, adapter: String, terrain: Terrain, settings: Dictionary) -> Dictionary:
	var assets := Assets.new()
	assets.index_game(game, map_folder)
	return layers(terrain, settings, assets.index, adapter)


func layers(terrain: Terrain, settings: Dictionary, index: Dictionary, adapter: String) -> Dictionary:
	var textures: Array[Image] = []
	var loaded := 0
	for slot in 16:
		var name: String = settings.get("tiletexture%d" % slot, "").strip_edges().trim_prefix('"').trim_suffix('"').get_file().to_lower()
		var path: String = index.get(name.get_basename() + ".dds", index.get(name, ""))
		var image := Assets.read_image(adapter, path) if path != "" else null
		if image:
			image.convert(Image.FORMAT_RGBA8)
			image.resize(TILE_PIXELS, TILE_PIXELS, Image.INTERPOLATE_LANCZOS)
			loaded += 1
		else:
			image = Image.create_empty(TILE_PIXELS, TILE_PIXELS, false, Image.FORMAT_RGBA8)
			image.fill(Color(1, 1, 1, 0))
		image.generate_mipmaps()
		textures.append(image)
	if loaded == 0:
		return {}
	var maps := terrain.material_maps(false)
	maps["textures"] = textures
	maps["loaded"] = loaded
	return maps


func material(data: Dictionary, terrain: Terrain) -> ShaderMaterial:
	var array := Texture2DArray.new()
	if array.create_from_images(data["textures"]) != OK:
		return null
	var colors: Image = data["colors"]
	for index: int in terrain.displayed_material_changes(Terrain.Layer.COLOR):
		var sample := terrain.sample_at(index)
		colors.set_pixelv(sample, terrain.color_at(sample.x, sample.y))
	var slots: Image = data["slots"]
	for block: int in terrain.displayed_material_changes(Terrain.Layer.TILES):
		slots.set_pixelv(terrain.block_origin(block) / Terrain.BLOCK, terrain.slot_color(block))
	var result := ShaderMaterial.new()
	result.shader = SHADER
	result.set_shader_parameter("tiles", array)
	result.set_shader_parameter("tile_slots", ImageTexture.create_from_image(data["slots"]))
	result.set_shader_parameter("weights", ImageTexture.create_from_image(data["weights"]))
	result.set_shader_parameter("tints", ImageTexture.create_from_image(data["colors"]))
	result.set_shader_parameter("world_minimum", Vector2(terrain.origin) * terrain.SPACING)
	result.set_shader_parameter("world_size", Vector2(terrain.dimensions) * terrain.SPACING)
	return result
