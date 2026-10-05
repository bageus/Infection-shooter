shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform sampler2D atlas : source_color, filter_linear, repeat_disable;
uniform vec4 region = vec4(0.0, 0.0, 0.25, 0.5);
void fragment() {
	vec4 sampled = texture(atlas, region.xy + UV * region.zw);
	ALBEDO = sampled.rgb;
	ALPHA = sampled.a;
}

