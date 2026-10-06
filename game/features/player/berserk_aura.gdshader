shader_type spatial;
// Berserk aura: a shell slightly outside the body glows red at the silhouette
// and licks upward like flame. Additive and translucent.
render_mode blend_add, unshaded, depth_draw_never, cull_back, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.12, 0.05, 1.0);
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float grow = 0.025;
uniform float flame_height = 0.2;

varying vec3 world_position;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	vec3 world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Faces turned up stretch into flame tongues that waver over time.
	float lick = noise(world_position * 6.0 + vec3(0.0, -TIME * 3.0, 0.0));
	float upward = max(world_normal.y, 0.0);
	vec3 offset = world_normal * grow + vec3(0.0, 1.0, 0.0) * upward * lick * flame_height;
	VERTEX += (inverse(MODEL_MATRIX) * vec4(offset, 0.0)).xyz;
}

void fragment() {
	float rim = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.4);
	float flicker = noise(world_position * vec3(9.0, 4.0, 9.0) + vec3(0.0, -TIME * 4.5, 0.0));
	float body = 0.05 + rim * 0.8;
	float a = intensity * body * (0.35 + 0.65 * flicker);
	ALBEDO = color.rgb;
	ALPHA = clamp(a, 0.0, 1.0);
}
