shader_type spatial;
// Mutagen cloud: a MultiMesh of camera-facing gas puffs (plus a ground haze
// quad). Each puff plays one of the two 6-frame sheets as an animation
// (cross-faded flipbook), turns slowly, pulses its glowing veins and
// dissolves through noise when it dies.
//
// INSTANCE_CUSTOM: r = variant / 12 (sheet = variant / 6, start frame =
// variant % 6), g = random seed, b = signed spin
// speed (rad/s), a = stagger (0..1: appear delay, or the cycle offset of a
// permanent cloud). COLOR = per-puff tint.
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D atlas_a : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D atlas_b : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D wall_mask : filter_nearest, repeat_disable;
uniform bool wall_mask_enabled = false;
uniform float wall_radius = 2.25;
uniform float opacity : hint_range(0.0, 1.0) = 0.55;
uniform float flow_strength : hint_range(0.0, 0.2) = 0.035;
uniform float flow_speed : hint_range(0.0, 2.0) = 0.35;
// Sheet frames per second (each puff varies it by -20..+25%).
uniform float frame_rate : hint_range(0.5, 12.0) = 5.0;
uniform vec4 vein_color : source_color = vec4(0.72, 1.0, 0.22, 1.0);
uniform float vein_glow : hint_range(0.0, 4.0) = 0.35;
// Ground haze: the quad lies flat on the floor instead of facing the camera.
uniform bool ground = false;

instance uniform float progress = 0.0;
instance uniform float phase = 0.0;
// 1 = permanent cloud: every puff loops on its own offset, never all at once.
instance uniform float looping = 0.0;
instance uniform float cycle_seconds = 14.0;
instance uniform vec3 cloud_center = vec3(0.0);

varying float v_life;
varying float v_seed;
varying float v_variant;
varying float v_sheet;
varying vec4 v_tint;
varying float v_spin;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) {
		value += amplitude * noise(p);
		p = p * 2.02 + vec2(17.3, 9.1);
		amplitude *= 0.5;
	}
	return value;
}

vec2 rotate(vec2 p, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	return mat2(vec2(c, s), vec2(-s, c)) * p;
}

void vertex() {
	vec4 custom = INSTANCE_CUSTOM;
	v_seed = custom.g;
	v_variant = floor(custom.r * 12.0 + 0.5);
	v_sheet = step(5.5, v_variant);
	v_tint = COLOR;
	float life;
	if (looping > 0.5) {
		life = fract(TIME / max(cycle_seconds, 0.1) + custom.a + phase * 0.01);
	} else {
		// Puffs bloom one after another and die at their own moments.
		float start = custom.a * 0.12;
		float finish = mix(0.62, 1.0, fract(v_seed * 7.13));
		life = (progress - start) / max(finish - start, 0.01);
	}
	v_life = life;
	float shown = step(0.0, life) * step(life, 1.0);
	float l = clamp(life, 0.0, 1.0);
	float bloom = 1.0 - pow(1.0 - clamp(l / 0.14, 0.0, 1.0), 3.0);
	float size = mix(0.12, 1.0, bloom) * (1.0 + l * 0.35) * shown;
	v_spin = custom.b * (TIME + phase) + v_seed * 6.2831;
	vec2 local = rotate(VERTEX.xy, v_spin) * size;
	vec3 center = MODEL_MATRIX[3].xyz;
	float scale = length(MODEL_MATRIX[0].xyz);
	// Puffs drift outwards and rise as they age.
	vec3 spread = center - cloud_center;
	spread.y = 0.0;
	center += spread * l * 0.28 + vec3(0.0, l * mix(0.25, 0.6, v_seed), 0.0);
	vec3 world;
	if (ground) {
		world = center + (vec3(1.0, 0.0, 0.0) * local.x + vec3(0.0, 0.0, -1.0) * local.y) * scale;
	} else {
		world = center + (INV_VIEW_MATRIX[0].xyz * local.x + INV_VIEW_MATRIX[1].xyz * local.y) * scale;
	}
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

// One frame of a sheet: 3 x 2 cells, frames run left to right, top to bottom.
vec4 sample_frame(float sheet, float frame, vec2 uv) {
	float index = mod(frame, 6.0);
	vec2 cell = vec2(mod(index, 3.0), floor(index / 3.0));
	vec2 atlas_uv = (cell + clamp(uv, vec2(0.004), vec2(0.996))) / vec2(3.0, 2.0);
	return sheet < 0.5 ? texture(atlas_a, atlas_uv) : texture(atlas_b, atlas_uv);
}

void fragment() {
	float l = clamp(v_life, 0.0, 1.0);
	float t = (TIME + phase) * flow_speed + v_seed * 31.0;
	// The sheet plays as a looping flipbook: each puff starts on its own
	// frame and runs at its own rate; neighbouring frames cross-fade.
	float clock = (TIME + phase) * frame_rate * mix(0.8, 1.25, v_seed) + v_variant;
	float frame = floor(clock);
	float blend = smoothstep(0.0, 1.0, fract(clock));
	// A light flow drags the gas along while one frame dissolves into the next.
	vec2 drift = (vec2(noise(UV * 3.0 + vec2(t, -t * 0.7)), noise(UV * 3.0 + vec2(-t * 0.8, t * 0.6) + 5.2)) - 0.5) * flow_strength;
	vec4 current = sample_frame(v_sheet, frame, UV + drift * (1.0 + blend));
	vec4 next = sample_frame(v_sheet, frame + 1.0, UV + drift * blend);
	vec4 gas = mix(current, next, blend);
	// Cross-fading thins the gas between frames; keep the density steady.
	gas.a = clamp(gas.a * (1.0 + 0.35 * blend * (1.0 - blend) * 4.0), 0.0, 1.0);

	float activity = 1.0 - smoothstep(0.35, 1.0, l);
	vec3 color = gas.rgb * v_tint.rgb;
	// Glowing veins: the brightest strands pulse with a slow toxic heartbeat.
	float luminance = dot(gas.rgb, vec3(0.3, 0.59, 0.11));
	float veins = smoothstep(0.5, 0.85, luminance);
	float pulse = 0.55 + 0.45 * sin(TIME * 2.6 + v_seed * 12.0);
	color += vein_color.rgb * veins * vein_glow * pulse * mix(0.35, 1.0, activity);
	// Fresh gas flashes, old gas darkens.
	color *= mix(0.72, 1.0, activity);

	// Birth: quick fade in. Death: noise eats the gas from its thin edges.
	float dissolve = smoothstep(0.5, 1.0, l);
	float grain = fbm(UV * 4.0 + vec2(v_seed * 13.0, -t * 0.5));
	float eaten = smoothstep(dissolve - 0.18, dissolve + 0.02, grain * (0.55 + 0.45 * gas.a));
	float alpha = gas.a * v_tint.a * opacity * smoothstep(0.0, 0.05, l) * mix(1.0, eaten, step(0.001, dissolve));
	alpha *= 1.0 - smoothstep(0.92, 1.0, l);
	// Soft cell edge so no straight border of the sheet ever shows.
	vec2 edge = min(UV, 1.0 - UV);
	alpha *= smoothstep(0.0, 0.06, min(edge.x, edge.y));
	if (wall_mask_enabled) {
		vec3 world_position = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vec2 horizontal = world_position.xz - cloud_center.xz;
		float azimuth = atan(horizontal.y, horizontal.x);
		float sample_index = floor((azimuth + PI) / TAU * 24.0);
		float limit = texture(wall_mask, vec2((sample_index + 0.5) / 24.0, 0.5)).r * wall_radius;
		alpha *= 1.0 - smoothstep(limit - 0.1, limit, length(horizontal));
	}
	ALBEDO = color;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
