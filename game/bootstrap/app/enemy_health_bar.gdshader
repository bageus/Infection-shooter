shader_type canvas_item;
// Each bar is one quad: UV spans the bar, and COLOR.r carries its health fraction.
uniform vec4 back_color : source_color = vec4(0.04, 0.04, 0.06, 0.75);
uniform vec4 fill_color : source_color = vec4(0.78, 0.12, 0.14, 1.0);
uniform vec4 fill_highlight : source_color = vec4(1.0, 0.5, 0.42, 1.0);
uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 0.9);

void fragment() {
	// Thin dark rim around the bar.
	float rim = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	vec4 col = back_color;
	if (UV.x <= COLOR.r) {
		// Glossy fill: brighter along the top edge.
		col = mix(fill_color, fill_highlight, (1.0 - UV.y) * 0.45);
	}
	if (rim < 0.14) {
		col = outline_color;
	}
	COLOR = col;
}
