shader_type canvas_item;

// Murky green haze for the second loss of control: a translucent wash with a slow drifting grain.
uniform vec4 haze_color : source_color = vec4(0.36, 0.58, 0.26, 1.0);
uniform float strength = 0.0;
uniform float clock = 0.0;

void fragment() {
	float grain = fract(sin(dot(floor(UV * vec2(240.0, 135.0)) + vec2(floor(clock * 4.0), 0.0), vec2(12.9898, 78.233))) * 43758.5453);
	float drift = 0.5 + 0.5 * sin(clock * 0.9 + UV.y * 6.0);
	COLOR = vec4(haze_color.rgb, strength * (0.22 + 0.06 * drift + 0.04 * grain));
}
