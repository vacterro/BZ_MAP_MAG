shader_type spatial;
render_mode cull_disabled, diffuse_burley;

uniform sampler2DArray tiles : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D tile_slots : filter_nearest, repeat_disable;
uniform sampler2D weights : filter_linear, repeat_disable;
uniform sampler2D tints : source_color, filter_linear, repeat_disable;
uniform vec2 world_minimum;
uniform vec2 world_size;
varying vec2 position_xz;

void vertex() {
	position_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 relative = position_xz - world_minimum;
	vec2 terrain_uv = clamp(relative / world_size, vec2(0.0), vec2(0.99999));
	vec4 id = round(texture(tile_slots, terrain_uv) * 255.0);
	vec3 strength = texture(weights, terrain_uv).rgb;
	vec2 tile_uv = relative / 32.0;
	vec4 base = texture(tiles, vec3(tile_uv, min(id.x, 15.0)));
	vec3 surface = mix(vec3(1.0), base.rgb, base.a);
	for (int layer = 0; layer < 3; layer++) {
		float slot = id[layer + 1];
		if (slot < 16.0) {
			vec4 top = texture(tiles, vec3(tile_uv, slot));
			surface = mix(surface, top.rgb, strength[layer] * top.a);
		}
	}
	ALBEDO = clamp(surface * texture(tints, terrain_uv).rgb, vec3(0.0), vec3(1.0));
	ROUGHNESS = 1.0;
}
