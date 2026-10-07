shader_type spatial;
// Bone Blades orbit: comet tails sweeping behind each blade on a flat ring
// at blade height. `angle` is the lead blade's heading, set by the script.
render_mode blend_premul_alpha, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 color : source_color = vec4(0.45, 0.95, 1.0, 1.0);
uniform int blades = 4;
uniform float ring = 0.78;

instance uniform float angle = 0.0;
instance uniform float alpha = 1.0;

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float a = atan(-p.y, p.x);
	float band = exp(-pow((r - ring) / 0.07, 2.0));
	float tails = 0.0;
	for (int i = 0; i < blades; i++) {
		float lead = angle + float(i) * TAU / float(blades);
		float behind = mod(lead - a, TAU);
		tails += exp(-behind * 2.2);
	}
	float faint = exp(-pow((r - ring) / 0.02, 2.0)) * 0.25;
	float cover = (band * tails + faint) * alpha;
	vec3 tone = mix(color.rgb, vec3(1.0), clamp(band * tails - 0.4, 0.0, 1.0)) * 1.5;
	ALBEDO = tone * clamp(cover, 0.0, 1.0);
	ALPHA = 0.0;
}
