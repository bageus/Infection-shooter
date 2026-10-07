shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Polished grey office tile: dark grout seams, soft clear-coat sheen and
// world-space wear so neighbouring tiles never repeat the same scuffs.
uniform vec3 base_color : source_color = vec3(0.4, 0.42, 0.44);
uniform float tint = 1.0;
uniform vec3 grout_color : source_color = vec3(0.17, 0.175, 0.18);
// Seam half-width and bevel width in metres, measured from the tile edge.
uniform float grout_width = 0.011;
uniform float bevel_width = 0.035;
uniform float roughness_polished : hint_range(0.0, 1.0) = 0.32;
uniform float roughness_worn : hint_range(0.0, 1.0) = 0.62;
uniform float roughness_offset = 0.0;
uniform float specular_amount : hint_range(0.0, 1.0) = 0.5;
uniform float clearcoat_amount : hint_range(0.0, 1.0) = 0.35;
uniform float wear_amount : hint_range(0.0, 1.0) = 1.0;
uniform sampler2D surface_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_noise : hint_default_white, filter_linear_mipmap, repeat_enable;

// Position inside the full 2 m tile (+-1), so stair subtiles keep the seams
// of the tile they were cut from. INSTANCE_CUSTOM = (offset.xy, scale, 0);
// plain meshes report zero and are treated as whole tiles.
varying vec2 tile_pos;
varying vec2 world_xz;

float tile_hash(vec2 cell) {
	vec2 p = fract(cell * vec2(0.1031, 0.1030));
	p += dot(p, p.yx + 33.33);
	return fract((p.x + p.y) * p.x);
}

void vertex() {
	float tile_scale = INSTANCE_CUSTOM.z > 0.0 ? INSTANCE_CUSTOM.z : 1.0;
	tile_pos = VERTEX.xz * tile_scale + INSTANCE_CUSTOM.xy;
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 tile_abs = abs(tile_pos);
	float edge = 1.0 - max(tile_abs.x, tile_abs.y);
	float edge_aa = max(fwidth(edge), 0.002);
	float grout = 1.0 - smoothstep(grout_width - edge_aa, grout_width + edge_aa, edge);
	float bevel = 1.0 - smoothstep(grout_width, grout_width + bevel_width, edge);

	// Per-tile shade: every tile is a slightly different batch of stone.
	vec2 cell = floor((world_xz - tile_pos) * 0.5 + 0.5);
	float tile_shade = 0.965 + tile_hash(cell) * 0.07;

	float mottle = texture(surface_noise, world_xz * 0.045).r;
	float grime = texture(surface_noise, world_xz * 0.13 + vec2(0.37, 0.71)).r;
	float traffic = smoothstep(0.45, 0.8, grime) * wear_amount;
	// Soft scuffs: noise stretched along the two corridor axes, kept sparse
	// so it reads as shoe drag rather than a hatch pattern.
	float scuff_x = texture(detail_noise, vec2(world_xz.x * 0.05, world_xz.y * 0.3)).r;
	float scuff_z = texture(detail_noise, vec2(world_xz.y * 0.05 + 0.5, world_xz.x * 0.3 + 0.25)).r;
	float scuff = max(smoothstep(0.66, 0.86, scuff_x), smoothstep(0.68, 0.88, scuff_z)) * traffic;
	float marks = smoothstep(0.8, 0.93, texture(detail_noise, world_xz * 0.23 + vec2(0.13, 0.57)).r) * traffic;
	float dull = smoothstep(0.35, 0.85, texture(surface_noise, world_xz * 0.3 + vec2(0.61, 0.19)).r) * wear_amount;

	vec3 color = base_color * tint * tile_shade * mix(0.9, 1.05, mottle);
	color *= 1.0 - 0.1 * traffic;
	color *= 1.0 - 0.16 * scuff;
	color *= 1.0 - 0.2 * marks;
	color *= 1.0 - 0.14 * bevel;
	ALBEDO = mix(color, grout_color, grout);

	float wear = clamp(dull * 0.45 + scuff + marks * 0.8 + traffic * 0.25, 0.0, 1.0);
	ROUGHNESS = mix(clamp(roughness_polished + roughness_offset, 0.0, 1.0), roughness_worn, wear);
	ROUGHNESS = mix(ROUGHNESS, 0.9, grout);
	METALLIC = 0.0;
	SPECULAR = specular_amount * (1.0 - grout);
	CLEARCOAT = clearcoat_amount * (1.0 - wear * 0.7) * (1.0 - max(grout, bevel * 0.5));
	CLEARCOAT_ROUGHNESS = mix(0.45, 0.7, wear);
}
