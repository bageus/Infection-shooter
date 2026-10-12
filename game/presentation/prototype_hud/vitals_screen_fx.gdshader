shader_type canvas_item;
render_mode unshaded, blend_mix;

// Screen-edge feedback in one pass, no screen texture read:
// green mutagen smoke rises from the bottom edge to mid-screen,
// a red blood haze spreads down from the top edge to mid-screen.

uniform float smoke : hint_range(0.0, 1.0) = 0.0;
uniform float blood : hint_range(0.0, 1.0) = 0.0;
uniform float pulse : hint_range(0.0, 1.0) = 1.0;
uniform float aspect = 1.7778;
uniform vec3 smoke_color : source_color = vec3(0.16, 0.62, 0.2);
uniform vec3 blood_color : source_color = vec3(0.62, 0.03, 0.04);

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
			mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += a * value_noise(p);
		p = p * 2.03 + vec2(7.1, 3.7);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV;
	float edge_x = min(uv.x, 1.0 - uv.x);
	vec4 result = vec4(0.0);

	if (smoke > 0.001) {
		float from_bottom = 1.0 - uv.y;
		float reach = 0.5 * smoke;
		float rise = 1.0 - smoothstep(0.0, max(reach, 0.001), from_bottom);
		float side = 1.0 - smoothstep(0.0, 0.12 + 0.2 * smoke, edge_x);
		float floor_band = 1.0 - smoothstep(0.0, 0.1 + 0.12 * smoke, from_bottom);
		vec2 p = vec2(uv.x * aspect, uv.y) * 2.4;
		float n = fbm(p + vec2(TIME * 0.05, -TIME * 0.09));
		float n2 = fbm(p * 1.7 - vec2(TIME * 0.04, -TIME * 0.06) + 3.0);
		float cloud = smoothstep(0.25, 0.8, n * 0.6 + n2 * 0.55);
		float density = max(rise * side * 1.15, floor_band * 0.75) * (0.4 + 0.9 * cloud);
		density = clamp(density, 0.0, 1.0) * smoke * pulse;
		vec3 tint = mix(smoke_color * 0.55, smoke_color * 1.25, cloud);
		result = vec4(tint, clamp(density * 0.85, 0.0, 0.8));
	}

	if (blood > 0.001) {
		float from_top = uv.y;
		float reach = 0.5 * blood;
		float fall = 1.0 - smoothstep(0.0, max(reach, 0.001), from_top);
		float side = 1.0 - smoothstep(0.0, 0.2 + 0.25 * blood, edge_x);
		float ceiling_band = 1.0 - smoothstep(0.0, 0.14 + 0.14 * blood, from_top);
		vec2 p = vec2(uv.x * aspect, uv.y) * 2.4;
		float n = fbm(p + vec2(TIME * 0.03, TIME * 0.05) + 11.0);
		float n2 = fbm(p * 1.7 - vec2(TIME * 0.02, TIME * 0.04) + 5.0);
		float cloud = smoothstep(0.25, 0.8, n * 0.6 + n2 * 0.55);
		float density = max(fall * side * 1.5, ceiling_band * 1.0) * (0.55 + 0.9 * cloud);
		density = clamp(density, 0.0, 1.0) * clamp(blood * 1.4, 0.0, 1.0);
		vec3 tint = mix(blood_color * 0.45, blood_color * 1.0, cloud);
		vec4 blood_layer = vec4(tint, clamp(density * 1.1, 0.0, 0.92));
		result.rgb = mix(result.rgb, blood_layer.rgb, blood_layer.a);
		result.a = max(result.a, blood_layer.a);
	}

	COLOR = result;
}
