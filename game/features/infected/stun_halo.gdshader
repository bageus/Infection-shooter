shader_type spatial;
// Stun: a crackling ring of pale energy around the head with a few bright
// arcs racing along it and a faint counter-swirl inside. Replaces the cartoon
// stars; the node still spins, so the arcs circle the head.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

#include "res://game/features/player/skill_fx/fx_noise.gdshaderinc"

uniform vec3 tint : source_color = vec3(0.55, 0.78, 1.0);

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	vec2 around = vec2(cos(a), sin(a)) * 2.2;
	// The ring wobbles and tears like live current.
	float wobble = fx_fbm(around + vec2(TIME * 2.5, 0.0)) - 0.5;
	float d = r - (0.7 + wobble * 0.14);
	float ring = exp(-d * d / 0.0016);
	float core = exp(-d * d / 0.0002);
	// Arcs: bright stretches that move along the ring.
	float arc = smoothstep(0.55, 0.85, fx_noise(vec2(a * 1.4 + TIME * 4.0, TIME * 0.7)));
	arc = max(arc, smoothstep(0.6, 0.9, fx_noise(vec2(-a * 2.1 - TIME * 3.0, 4.0 + TIME * 0.5))));
	// A faint spiral swirl inside the ring reads as dizziness.
	float swirl = 0.5 + 0.5 * sin(a * 3.0 - r * 9.0 - TIME * 5.0);
	swirl *= smoothstep(0.1, 0.5, r) * (1.0 - smoothstep(0.55, 0.7, r)) * 0.14;
	float cover = (ring * (0.35 + 0.9 * arc) + core * arc * 1.2 + swirl) * (1.0 - smoothstep(0.92, 1.0, r));
	ALBEDO = mix(tint, vec3(1.0), clamp(core * arc, 0.0, 1.0)) * cover * 1.6;
	ALPHA = 1.0;
}
