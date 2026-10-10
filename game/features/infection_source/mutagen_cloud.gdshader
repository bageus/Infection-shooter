shader_type spatial;
// Procedural translucent green smoke. No sprite textures or flipbooks.
// INSTANCE_CUSTOM carries variant, seed, spin and life offset; COLOR is tint.
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D wall_mask : filter_nearest, repeat_disable;
uniform bool wall_mask_enabled = false;
uniform float wall_radius = 2.25;
uniform float opacity : hint_range(0.0, 1.0) = 0.55;
uniform float flow_speed : hint_range(0.0, 2.0) = 0.35;
// Ground haze: the quad lies flat on the floor instead of facing the camera.
uniform bool ground = false;

instance uniform float progress = 0.0;
instance uniform float phase = 0.0;
// 1 = permanent cloud: every puff loops on its own offset, never all at once.
instance uniform float looping = 0.0;
instance uniform float cycle_seconds = 14.0;
instance uniform vec3 cloud_center = vec3(0.0);

varying vec3 v_world_position;
varying float v_life;
varying float v_seed;
varying float v_variant;
varying vec4 v_tint;
varying float v_spin;

float hash(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
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
	v_world_position = world;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	if (v_world_position.y < cloud_center.y + 0.5 || v_world_position.y > cloud_center.y + 2.0) {
		discard;
	}
	vec2 centered = UV * 2.0 - 1.0;
	float radial = dot(centered, centered);
	if (radial >= 1.0 || v_life <= 0.0 || v_life >= 1.0) {
		discard;
	}
	float l = clamp(v_life, 0.0, 1.0);
	float t = (TIME + phase) * flow_speed;
	vec2 flow = UV * 3.5 + vec2(v_seed * 19.0 + v_variant, -t);
	// Two low-frequency noise layers; animation runs entirely on the GPU.
	float density = noise(flow) * 0.7 + noise(flow * 2.03 + vec2(t * 0.3, 7.1)) * 0.3;
	float edge = 1.0 - smoothstep(0.18, 1.0, radial);
	float envelope = smoothstep(0.0, 0.08, l) * (1.0 - smoothstep(0.55, 1.0, l));
	float alpha = edge * smoothstep(0.15, 0.85, density) * opacity * v_tint.a * envelope;
	float height = v_world_position.y - cloud_center.y;
	alpha *= smoothstep(0.5, 0.65, height) * (1.0 - smoothstep(1.85, 2.0, height));
	vec3 color = mix(vec3(0.12, 0.30, 0.08), vec3(0.38, 0.66, 0.22), density) * v_tint.rgb;
	if (wall_mask_enabled) {
		vec3 world_position = v_world_position;
		vec2 horizontal = world_position.xz - cloud_center.xz;
		float azimuth = atan(horizontal.y, horizontal.x);
		float sample_index = floor((azimuth + PI) / TAU * 24.0);
		float limit = texture(wall_mask, vec2((sample_index + 0.5) / 24.0, 0.5)).r * wall_radius;
		alpha *= 1.0 - smoothstep(limit - 0.1, limit, length(horizontal));
	}
	ALBEDO = color;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
