shader_type spatial;
// Floor path arrow: a double chevron of worn emergency-exit paint on the floor,
// pointing along -Z. Scuffed and scratched like the markings in the offices,
// with a light running through it; `glow` carries the running light.
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

#include "res://game/features/player/skill_fx/fx_noise.gdshaderinc"

uniform vec3 paint : source_color = vec3(0.16, 0.85, 0.62);
uniform vec3 dark : source_color = vec3(0.02, 0.12, 0.09);

instance uniform float glow = 1.0;
instance uniform float seed = 0.0;

// Distance to a segment.
float segment(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0));
}

float chevron(vec2 p, float lift) {
	vec2 q = vec2(abs(p.x), p.y + lift);
	return segment(q, vec2(0.0, -0.55), vec2(0.78, 0.2));
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float d = min(chevron(p, 0.0), chevron(p, 0.5));
	float body = 1.0 - smoothstep(0.1, 0.13, d);
	float halo = (1.0 - smoothstep(0.13, 0.4, d)) * 0.35;
	// Worn paint: scuffs break the edge, scratches cut across it.
	vec2 spot = p * 3.5 + seed * 11.0;
	float wear = fx_fbm(spot);
	float scratch = smoothstep(0.74, 0.8, fx_noise(vec2(p.x * 14.0 + p.y * 5.0, p.y * 2.0 + seed)));
	float paint_cover = body * smoothstep(0.28, 0.52, wear + 0.22) * (1.0 - scratch * 0.5);
	vec3 tone = mix(dark, paint, 0.55 + 0.45 * glow);
	tone += paint * halo * glow * 0.6;
	float alpha = clamp(paint_cover * (0.45 + 0.5 * glow) + halo * glow * 0.5, 0.0, 1.0);
	ALBEDO = tone;
	ALPHA = alpha * (1.0 - smoothstep(0.92, 1.0, max(abs(p.x), abs(p.y))));
}
