shader_type spatial;
render_mode unshaded, cull_back;
uniform sampler2D screen_texture : source_color, filter_linear, repeat_disable;
uniform vec4 atlas_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 content_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform bool powered = false;
void fragment() {
	vec2 screen_uv = content_rect.xy + UV * content_rect.zw;
	vec3 color = texture(screen_texture, atlas_rect.xy + screen_uv * atlas_rect.zw).rgb;
	ALBEDO = powered ? color : vec3(0.003, 0.004, 0.006);
	EMISSION = powered ? color * 0.18 : vec3(0.0);
}
