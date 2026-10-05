shader_type spatial;
render_mode cull_disabled, depth_draw_never, shadows_disabled;
uniform sampler2D atlas : source_color, filter_linear, repeat_disable;
uniform float opacity = 1.0;
uniform bool scorch = false;
uniform vec4 region = vec4(0.0, 0.0, 0.25, 0.5);
void fragment() {
	vec4 sampled = texture(atlas, region.xy + UV * region.zw);
	ALBEDO = sampled.rgb;
	ALPHA = sampled.a * opacity;
	if (scorch) {
		// Preserve the receiver's color through a soft dark soot mask.
		float soot = 1.0 - dot(sampled.rgb, vec3(0.2126, 0.7152, 0.0722));
		ALBEDO = vec3(0.018, 0.016, 0.014);
		ALPHA *= soot;
	}
	ROUGHNESS = 1.0;
}
