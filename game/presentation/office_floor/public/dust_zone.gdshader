shader_type spatial;
// Dust motes in the air of one zone layer. Motes are lit only by the scene lights (light() below),
// so they show up inside the flashlight cone and under lamps and stay invisible in the dark.
render_mode blend_add, cull_disabled, depth_draw_never, shadows_disabled, ambient_light_disabled;

uniform float density : hint_range(0.0, 1.0) = 0.6;
uniform float fade : hint_range(0.0, 1.0) = 1.0; // settings switch, eased by the zone script
uniform float layer_weight = 1.0; // layers near the floor and the ceiling are weaker
uniform float layer_seed = 0.0;
uniform float edge_fade_m = 1.5; // metres over which the zone melts into the air
uniform float boost = 3.0;
uniform float overhead_share = 0.25; // directional (overhead) light shows the dust, but faintly

varying vec3 world_pos;
varying vec2 local_xz;
varying vec2 scale_xz;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// One grid of motes: cell size in metres, drift in metres per second.
float motes(vec2 xz, float cell, vec2 drift, float seed) {
	vec2 g = (xz + drift * TIME) / cell;
	vec2 id = floor(g) + seed;
	vec2 f = fract(g);
	float r = hash(id);
	float present = step(1.0 - 0.45 * density, r);
	vec2 centre = 0.2 + 0.6 * vec2(hash(id + 7.1), hash(id + 3.7));
	centre += 0.12 * vec2(sin(TIME * 0.7 + r * 40.0), cos(TIME * 0.5 + r * 25.0));
	float radius = mix(0.07, 0.15, hash(id + 1.3));
	float twinkle = 0.6 + 0.4 * sin(TIME * 1.3 + r * 60.0);
	return present * twinkle * smoothstep(radius, radius * 0.3, length(f - centre));
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	local_xz = VERTEX.xz;
	scale_xz = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[2].xyz));
}

void fragment() {
	// Distance to the zone edge in metres (the 4 m base quad is stretched by the node scale).
	vec2 edge_m = (vec2(2.0) - abs(local_xz)) * scale_xz;
	float edge = smoothstep(0.0, edge_fade_m, min(edge_m.x, edge_m.y));
	float m = max(motes(world_pos.xz, 0.3, vec2(0.04, 0.025), layer_seed),
			motes(world_pos.xz, 0.55, vec2(-0.03, 0.035), layer_seed + 31.0));
	ALBEDO = vec3(1.0);
	ALPHA = m * edge * fade * layer_weight;
}

void light() {
	float share = LIGHT_IS_DIRECTIONAL ? overhead_share : 1.0;
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * share * boost / PI;
}
