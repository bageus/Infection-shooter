shader_type spatial;
// A shock ring sweeping out over the floor (unit plane, radius 1 at the
// edge), with an optional wash behind it. `jagged` tears the front into an
// electric crackle; glow 1 adds light, 0 stains the floor like paint.
render_mode blend_premul_alpha, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

#include "res://game/features/player/skill_fx/fx_noise.gdshaderinc"

uniform vec4 color : source_color = vec4(1.0, 0.2, 0.1, 1.0);
uniform vec4 core_color : source_color = vec4(1.0, 0.8, 0.7, 1.0);
uniform float glow : hint_range(0.0, 1.0) = 1.0;
uniform float jagged : hint_range(0.0, 1.0) = 0.0;
uniform float width = 0.07;
uniform float fill : hint_range(0.0, 1.0) = 0.3;
uniform float brightness = 1.5;

instance uniform float progress = 0.0;
instance uniform float alpha = 1.0;
instance uniform float seed = 0.0;

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float front = 1.0 - pow(1.0 - clamp(progress * 1.6, 0.0, 1.0), 3.0);
	vec2 around = vec2(cos(a), sin(a)) * 2.5 + seed * 7.0;
	float tear = fx_fbm(around + vec2(TIME * 9.0, 0.0) * jagged) - 0.5;
	float edge = front * (1.0 + tear * (0.08 + 0.3 * jagged));
	float d = r - edge;
	float w = width * (1.0 + jagged * 0.6 * fx_noise(around * 3.0 + TIME * 20.0));
	float ring = exp(-d * d / (w * w));
	float core = exp(-d * d / (w * w * 0.08)) * (1.0 - jagged * 0.5 * step(0.55, fx_noise(around * 6.0 + TIME * 30.0)));
	float wash = (1.0 - smoothstep(edge - 0.05, edge, r)) * smoothstep(0.0, edge, r);
	wash *= fill * (0.55 + 0.45 * fx_fbm(p * 3.5 + seed * 3.0));
	float life = 1.0 - smoothstep(0.45, 1.0, progress);
	float mask = 1.0 - smoothstep(0.97, 1.0, r);
	float cover = (ring + wash + core) * life * alpha * mask;
	vec3 tone = mix(color.rgb, core_color.rgb, clamp(core, 0.0, 1.0)) * brightness;
	vec4 outc = fx_premul(tone, cover, glow);
	ALBEDO = outc.rgb;
	ALPHA = outc.a;
}
