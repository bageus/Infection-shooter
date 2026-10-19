shader_type spatial;
// Predator Dash speed streak (vertex colour alpha = strength x fade, UV.x
// metres along the path, UV.y 0 on the centre line to 1 at the edge, UV2.x
// which streak). Noise runs along the streak and eats its edges and tail, so
// each one reads as torn hot air with a white core instead of a flat bar.
render_mode blend_premul_alpha, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

#include "res://game/features/player/skill_fx/fx_noise.gdshaderinc"

uniform vec3 tint = vec3(1.0, 0.55, 0.5);
uniform float brightness = 2.2;

void fragment() {
	float strength = COLOR.a;
	float core = 1.0 - UV.y;
	core *= core;
	float n = fx_fbm(vec2(UV.x * 1.8 - TIME * 6.0, UV2.x * 7.3 + UV.y * 1.5));
	float mask = smoothstep(0.62 - strength * 0.5, 0.8 - strength * 0.5, n + core * 0.35);
	float cover = clamp(strength * 1.5, 0.0, 1.0) * mask * (0.25 + core);
	vec3 tone = fx_fire_ramp(strength * core * 1.9) * tint * brightness;
	vec4 outc = fx_premul(tone, cover, 1.0);
	ALBEDO = outc.rgb;
	ALPHA = outc.a;
}
