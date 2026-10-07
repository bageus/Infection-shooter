shader_type spatial;
// Camera-facing soft cloud puff that billows out and thins with `progress`.
render_mode blend_premul_alpha, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

#include "res://game/features/player/skill_fx/fx_noise.gdshaderinc"

uniform vec4 color : source_color = vec4(0.6, 0.95, 0.25, 1.0);
uniform float glow : hint_range(0.0, 1.0) = 0.4;

instance uniform float progress = 0.0;
instance uniform float alpha = 1.0;
instance uniform float seed = 0.0;

void vertex() {
	float s = length(MODEL_MATRIX[0].xyz);
	vec3 world = MODEL_MATRIX[3].xyz + (INV_VIEW_MATRIX[0].xyz * VERTEX.x + INV_VIEW_MATRIX[1].xyz * VERTEX.y) * s;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float n = fx_fbm(UV * 3.0 + vec2(seed * 17.0, seed * 5.0 - progress * 1.2));
	float r = length(p);
	float mask = 1.0 - smoothstep(0.3 + 0.4 * n, 1.0, r + 0.25 * (n - 0.5));
	mask *= 1.0 - smoothstep(0.8, 1.0, r);
	float thin = smoothstep(progress * 0.8, progress * 0.8 + 0.35, n + 0.2);
	float life = smoothstep(0.0, 0.1, progress) * (1.0 - smoothstep(0.5, 1.0, progress));
	float cover = mask * thin * life * alpha * 0.6;
	vec3 tone = color.rgb * (0.8 + 0.5 * n) * (1.0 - 0.3 * p.y);
	vec4 outc = fx_premul(tone, cover, glow);
	ALBEDO = outc.rgb;
	ALPHA = outc.a;
}
