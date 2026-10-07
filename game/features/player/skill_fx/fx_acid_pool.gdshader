shader_type spatial;
// Acid pool lying flat on the floor: a ragged emerald puddle with a bright
// rim, slow swirls and bubbles that swell and pop. Fixed in the world.
render_mode blend_premul_alpha, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

#include "res://game/features/player/skill_fx/fx_noise.gdshaderinc"

uniform vec4 deep_color : source_color = vec4(0.03, 0.25, 0.08, 1.0);
uniform vec4 bright_color : source_color = vec4(0.45, 1.0, 0.25, 1.0);

instance uniform float progress = 0.0;
instance uniform float alpha = 1.0;
instance uniform float seed = 0.0;

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	vec2 dir = r > 0.0001 ? p / r : vec2(1.0, 0.0);
	float spread = smoothstep(0.0, 1.0, clamp(progress * 6.0, 0.0, 1.0));
	float border = (0.72 + 0.3 * (fx_fbm(dir * 1.6 + seed * 9.0) - 0.5) * 2.0) * mix(0.35, 1.0, spread);
	float inside = 1.0 - smoothstep(border - 0.03, border, r);
	// A few splashes thrown past the edge.
	vec2 c = fx_cells(p * 3.2 + seed * 13.0);
	float drops = (1.0 - smoothstep(0.1, 0.16, c.x)) * step(0.72, c.y) * step(r, 1.0) * spread;
	inside = max(inside, drops);
	float depth = clamp(1.0 - r / max(border, 0.01), 0.0, 1.0);
	float swirl = fx_fbm(p * 2.6 + vec2(TIME * 0.12, -TIME * 0.09) + seed);
	vec3 tone = mix(bright_color.rgb * 0.7, deep_color.rgb, smoothstep(0.0, 0.6, depth));
	tone += bright_color.rgb * 0.25 * smoothstep(0.55, 0.75, swirl);
	float rim = exp(-pow((r - border) / 0.05, 2.0));
	tone += bright_color.rgb * rim * 0.9;
	// Bubbles: each cell swells on its own clock and pops with a ring.
	vec2 b = fx_cells(p * 6.0 + seed * 5.0);
	float phase = fract(TIME * (0.35 + b.y * 0.5) + b.y * 7.0);
	float size = 0.08 + 0.22 * phase;
	float bubble = (1.0 - smoothstep(size - 0.05, size, b.x)) * step(0.45, b.y) * step(phase, 0.85);
	float rim_bubble = exp(-pow((b.x - size) / 0.035, 2.0)) * step(0.45, b.y);
	tone = mix(tone, bright_color.rgb * 0.85, bubble * 0.35 * depth);
	tone += vec3(0.8, 1.0, 0.7) * rim_bubble * 0.5 * smoothstep(0.1, 0.5, depth);
	// A wet highlight across the surface.
	tone += vec3(0.7, 1.0, 0.8) * 0.35 * smoothstep(0.62, 0.8, fx_fbm(p * 1.4 + vec2(-0.6, 0.4) + TIME * 0.04));
	float cover = inside * 0.92 * alpha;
	vec4 outc = fx_premul(tone, cover, 0.15);
	ALBEDO = outc.rgb;
	ALPHA = outc.a;
}
