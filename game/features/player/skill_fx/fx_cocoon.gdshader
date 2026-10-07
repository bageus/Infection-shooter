shader_type spatial;
// Spore cocoon: a lumpy flesh pod with glowing spore sacs and veins that
// pulse faster and brighter as the burst nears (`charge` 0..1).
render_mode cull_back;

#include "res://game/features/player/skill_fx/fx_noise.gdshaderinc"

uniform vec4 flesh : source_color = vec4(0.32, 0.07, 0.1, 1.0);
uniform vec4 spore : source_color = vec4(0.55, 1.0, 0.2, 1.0);

instance uniform float charge = 0.0;
instance uniform float seed = 0.0;

varying vec3 local;

void vertex() {
	local = VERTEX * 3.0 + seed * 5.0;
	float beat = pow(0.5 + 0.5 * sin(TIME * mix(5.0, 18.0, charge)), 3.0);
	float lumps = fx_noise3(local) - 0.5;
	VERTEX += NORMAL * (lumps * 0.35 + beat * 0.06 * (0.4 + charge)) * length(VERTEX.xz + vec2(0.001));
	VERTEX.y = max(VERTEX.y, 0.0);
}

void fragment() {
	float n = fx_noise3(local * 1.6);
	float veins = 1.0 - smoothstep(0.0, 0.06, abs(fx_noise3(local * 2.4) - 0.5));
	float sacs = smoothstep(0.62, 0.72, n);
	float beat = pow(0.5 + 0.5 * sin(TIME * mix(5.0, 18.0, charge)), 3.0);
	ALBEDO = mix(flesh.rgb * (0.7 + 0.5 * fx_noise3(local * 4.0)), spore.rgb * 0.5, sacs);
	ROUGHNESS = mix(0.45, 0.15, sacs);
	SPECULAR = 0.6;
	RIM = 0.3;
	EMISSION = spore.rgb * (veins * 0.5 + sacs * 0.7) * (0.25 + charge * 1.8 + beat * 0.6);
}
