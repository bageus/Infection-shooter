shader_type canvas_item;
// Dims the whole screen except up to four rectangles (x, y, width, height in canvas pixels).
uniform vec4 holes[4];
uniform int hole_count = 0;
uniform vec2 screen_size = vec2(1280.0, 720.0);
uniform vec4 dim_color : source_color = vec4(0.03, 0.04, 0.05, 0.82);

void fragment() {
	vec2 pixel = UV * screen_size;
	float cover = 1.0;
	for (int i = 0; i < 4; i++) {
		if (i >= hole_count) {
			break;
		}
		vec2 origin = holes[i].xy;
		vec2 extent = holes[i].zw;
		if (pixel.x >= origin.x && pixel.y >= origin.y && pixel.x <= origin.x + extent.x && pixel.y <= origin.y + extent.y) {
			cover = 0.0;
		}
	}
	COLOR = vec4(dim_color.rgb, dim_color.a * cover);
}
