shader_type spatial;
// Strike area on the floor: a bright edge, a faint fill and chevrons that run
// away from the player. Vertex colour R = edge/fill strength, G = fade along
// the lane; UV.x -1..1 across, UV.y metres along.
render_mode blend_premul_alpha, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

#include "res://game/features/player/skill_fx/fx_noise.gdshaderinc"

uniform vec3 tint = vec3(1.0, 0.35, 0.25);
uniform float chevrons : hint_range(0.0, 1.0) = 1.0;
uniform float flow = 2.2;
uniform float opacity : hint_range(0.0, 1.0) = 0.6;
uniform float spacing = 0.9;
uniform vec3 core = vec3(1.0, 0.85, 0.6);

// 0 is a hairline along the lane centre, 1 the full width: the area unfolds to both sides.
instance uniform float open = 1.0;
instance uniform float alpha = 1.0;

void vertex() {
	VERTEX.x *= open;
}

void fragment() {
	float strength = max(COLOR.r, (1.0 - open) * 0.9);
	float fade = COLOR.g;
	float band = fract(UV.y * spacing - TIME * flow + abs(UV.x) * 0.35);
	band = smoothstep(0.0, 0.1, band) * (1.0 - smoothstep(0.1, 0.5, band));
	float n = fx_fbm(vec2(UV.x * 1.5, UV.y * 1.2 - TIME * 3.0));
	float cover = strength * (0.25 + 0.75 * fade) * (0.7 + 0.5 * n);
	cover += chevrons * band * 0.3 * fade * (1.0 - strength);
	cover = clamp(cover * alpha * opacity, 0.0, 1.0);
	vec3 tone = mix(tint, core, strength * strength * 0.7) * 1.1;
	vec4 outc = fx_premul(tone, cover, 0.4);
	ALBEDO = outc.rgb;
	ALPHA = outc.a;
}
