shader_type spatial;
// Procedural rolling smoke for particle quads: layered value noise with a
// soft round mask, lit from above, that dissolves as the particle ages.
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 smoke_color : source_color = vec4(0.34, 0.33, 0.32, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.45, 0.12, 1.0);
// Ember glow in young smoke (from a fireball); 0 for cold smoke.
uniform float glow : hint_range(0.0, 4.0) = 0.0;
uniform float opacity : hint_range(0.0, 1.0) = 0.6;
uniform float growth : hint_range(1.0, 5.0) = 2.4;
uniform float swirl : hint_range(0.0, 3.0) = 1.0;

varying float age;
varying float seed;

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
		p = p * 2.03 + vec2(11.7, 5.3);
		amplitude *= 0.5;
	}
	return value;
}

void vertex() {
	age = clamp(INSTANCE_CUSTOM.y, 0.0, 1.0);
	seed = fract(float(INSTANCE_ID) * 0.6180339 + INSTANCE_CUSTOM.x * 0.0001);
	float angle = seed * 6.28318 + age * (seed - 0.5) * swirl;
	VERTEX.xy = mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle))) * VERTEX.xy;
	VERTEX.xy *= mix(0.7, 1.3, seed) * mix(0.45, growth, sqrt(age));
}

void fragment() {
	vec2 p = UV - 0.5;
	float n = fbm(UV * 3.2 + vec2(seed * 19.0, seed * 7.0 - age * 1.4 * swirl));
	float radius = length(p) * 2.0;
	// Billowing edge: the noise pushes the round mask in and out.
	float mask = 1.0 - smoothstep(0.35 + 0.35 * n, 1.0, radius + 0.25 * (n - 0.5));
	// Dissolve: thin wisps vanish first as the puff thins out.
	float density = smoothstep(age * 0.85, age * 0.85 + 0.35, n + 0.25);
	float fade = smoothstep(0.0, 0.08, age) * (1.0 - smoothstep(0.55, 1.0, age));
	float light = 0.75 + 0.45 * (0.5 - p.y) * (0.6 + n);
	vec3 color = smoke_color.rgb * light;
	float ember = glow * (1.0 - smoothstep(0.0, 0.35, age)) * smoothstep(0.45, 0.75, n);
	color += glow_color.rgb * ember;
	ALBEDO = color;
	ALPHA = clamp(mask * density * fade * opacity, 0.0, 1.0);
}
