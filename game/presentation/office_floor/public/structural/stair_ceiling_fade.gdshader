shader_type spatial;

// Above the ceiling the stair breaks up into a ragged, half-hidden edge.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D orm_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 ao_mask = vec4(1.0, 0.0, 0.0, 0.0);
uniform vec4 roughness_mask = vec4(0.0, 1.0, 0.0, 0.0);
uniform vec4 metallic_mask = vec4(0.0, 0.0, 1.0, 0.0);
uniform float ceiling_y = 2.8;
uniform float dissolve_height = 0.4;
// Mip level for the maps: smooths the grain into a concrete-like surface.
uniform float smooth_lod = 2.0;

varying vec3 world_position;

// Per-cell noise: cells of ~2 cm give a dithered, uneven edge.
float cell_noise(vec3 p) {
	return fract(sin(dot(floor(p * 45.0), vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float fade = clamp((world_position.y - ceiling_y) / dissolve_height, 0.0, 1.0);
	if (fade > 0.0 && cell_noise(world_position) < fade) {
		discard;
	}
	vec4 orm = textureLod(orm_tex, UV, smooth_lod);
	ALBEDO = textureLod(albedo_tex, UV, smooth_lod).rgb;
	AO = dot(orm, ao_mask);
	ROUGHNESS = dot(orm, roughness_mask);
	METALLIC = dot(orm, metallic_mask);
	NORMAL_MAP = textureLod(normal_tex, UV, smooth_lod).rgb;
}
