shader_type canvas_item;
render_mode unshaded, blend_mix;

// Always-on horror grade in one pass with no screen texture read (cheap on
// Compatibility/Web): a cold green-grey tint, edge vignette and film grain,
// all composed as one alpha overlay over the 3D view.

uniform float strength : hint_range(0.0, 1.0) = 1.0;
uniform float vignette_amount : hint_range(0.0, 1.0) = 0.55;
uniform float grain_amount : hint_range(0.0, 0.2) = 0.05;
uniform float tint_amount : hint_range(0.0, 0.3) = 0.07;
uniform vec3 tint_color : source_color = vec3(0.05, 0.13, 0.12);
uniform float aspect = 1.7778;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 c = (UV - 0.5) * vec2(aspect, 1.0);
	float vig = smoothstep(0.45, 1.05, length(c)) * vignette_amount;
	float g = hash21(floor(UV * vec2(aspect, 1.0) * 540.0) + floor(fract(TIME * 24.0) * 24.0) * 7.31);
	// Layer 1: tint. Layer 2: grain (white or black speckle). Layer 3: vignette.
	vec4 col = vec4(tint_color, tint_amount);
	vec4 gr = vec4(vec3(step(0.5, g)), grain_amount * 0.5);
	float a = gr.a + col.a * (1.0 - gr.a);
	vec3 rgb = (gr.rgb * gr.a + col.rgb * col.a * (1.0 - gr.a)) / max(a, 0.0001);
	float out_a = vig + a * (1.0 - vig);
	vec3 out_rgb = (vec3(0.0) * vig + rgb * a * (1.0 - vig)) / max(out_a, 0.0001);
	COLOR = vec4(out_rgb, out_a * strength);
}
