shader_type spatial;
// Power Strike fist: one quad that turns around its forward axis towards the
// camera. A white-hot head, a noisy fire tail that dissolves and narrows
// away from it. UV.y 0 is the front.
render_mode blend_premul_alpha, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

#include "res://game/features/player/skill_fx/fx_noise.gdshaderinc"

uniform float brightness = 1.7;

// x = half width, y = length, in metres.
instance uniform vec2 size = vec2(0.5, 2.0);
instance uniform float alpha = 1.0;

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 forward = normalize(-MODEL_MATRIX[2].xyz);
	vec3 side = normalize(cross(forward, INV_VIEW_MATRIX[3].xyz - center));
	vec3 world = center + side * VERTEX.x * 2.0 * size.x + forward * (VERTEX.y + 0.5) * size.y;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	float x = (UV.x - 0.5) * 2.0;
	float t = UV.y;
	float width = mix(1.0, 0.12, pow(t, 0.7));
	float body = 1.0 - smoothstep(width * 0.55, width, abs(x));
	float n = fx_fbm(vec2(x * 1.6, t * 5.0 + TIME * 7.0));
	float lead = 1.0 - t;
	float mask = smoothstep(0.35, 0.55, n * 0.7 + lead * 0.65);
	float ball = exp(-(x * x * 2.2 + (t - 0.1) * (t - 0.1) * 45.0));
	float cover = clamp(body * mask + ball, 0.0, 1.0) * smoothstep(0.0, 0.05, t) * alpha;
	float heat = lead * 1.3 * (1.0 - abs(x) / width * 0.6) + ball;
	vec4 outc = fx_premul(fx_fire_ramp(heat) * brightness, cover, 1.0);
	ALBEDO = outc.rgb;
	ALPHA = outc.a;
}
