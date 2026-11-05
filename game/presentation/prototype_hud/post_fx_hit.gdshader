shader_type canvas_item;
render_mode unshaded, blend_mix;

// Damage hit: RGB split that grows toward the screen edges plus a short red
// edge flash. Reads the screen texture, so the rect is visible only while
// hit > 0 and costs nothing the rest of the time.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float hit : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 d = UV - 0.5;
	float edge = dot(d, d) * 4.0;
	vec2 off = d * hit * (0.004 + 0.016 * edge);
	vec3 col;
	col.r = texture(screen_tex, SCREEN_UV - off).r;
	col.g = texture(screen_tex, SCREEN_UV).g;
	col.b = texture(screen_tex, SCREEN_UV + off).b;
	col = mix(col, vec3(0.7, 0.02, 0.03), hit * smoothstep(0.15, 1.0, edge) * 0.5);
	COLOR = vec4(col, 1.0);
}
