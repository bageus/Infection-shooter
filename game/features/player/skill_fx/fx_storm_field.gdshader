shader_type spatial;
// Storm Pulse field: a faint charged disc with a crackling rim and lightning
// arcs that flick between the player and the rim. Loops on TIME.
render_mode blend_premul_alpha, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

#include "res://game/features/player/skill_fx/fx_noise.gdshaderinc"

uniform vec4 color : source_color = vec4(0.25, 0.6, 1.0, 1.0);
uniform vec4 core_color : source_color = vec4(0.85, 0.95, 1.0, 1.0);
uniform int arcs = 6;

instance uniform float alpha = 1.0;

float wrap_angle(float a) {
	return mod(a + PI, TAU) - PI;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	vec2 around = vec2(cos(a), sin(a));
	float disc = (1.0 - smoothstep(0.82, 0.98, r)) * (0.06 + 0.06 * fx_fbm(p * 3.0 + vec2(TIME * 0.4, -TIME * 0.3)));
	float rim_shift = (fx_fbm(around * 3.0 + vec2(TIME * 5.0, 0.0)) - 0.5) * 0.07;
	float rim_d = r - 0.93 - rim_shift;
	float rim = exp(-rim_d * rim_d / 0.0006) + 0.35 * exp(-rim_d * rim_d / 0.006);
	float bolts = 0.0;
	for (int i = 0; i < arcs; i++) {
		float fi = float(i);
		float tick = floor(TIME * 11.0 + fi * 0.37);
		float live = step(0.4, fx_hash(vec2(tick, fi)));
		float heading = fx_hash(vec2(fi, tick * 0.13)) * TAU + TIME * 0.6;
		float bend = (fx_fbm(vec2(r * 7.0, tick + fi * 3.1)) - 0.5) * 0.9;
		float off = abs(wrap_angle(a - heading - bend * r)) * r;
		float span = smoothstep(0.12, 0.2, r) * (1.0 - smoothstep(0.88, 0.95, r));
		bolts += live * span * (exp(-off * off / 0.00012) + 0.3 * exp(-off * off / 0.002));
	}
	float center = exp(-r * r * 40.0) * 0.5;
	float cover = (disc + rim * 0.9 + bolts + center) * alpha;
	vec3 tone = mix(color.rgb, core_color.rgb, clamp(bolts + rim * 0.5, 0.0, 1.0)) * 1.6;
	vec4 outc = fx_premul(tone, cover, 1.0);
	ALBEDO = outc.rgb;
	ALPHA = outc.a;
}
