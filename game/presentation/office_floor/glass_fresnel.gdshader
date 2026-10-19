shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;

// Clear centre, brighter rim; tint.a is the authored glass alpha.
uniform vec4 tint : source_color = vec4(0.35, 0.65, 0.79, 0.55);
uniform float roughness : hint_range(0.0, 1.0) = 0.08;
uniform float center_alpha_scale = 0.5;
uniform float rim_alpha_boost = 0.35;
uniform float rim_power = 3.0;

void fragment() {
	float fres = pow(1.0 - clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), rim_power);
	ALBEDO = mix(tint.rgb, vec3(1.0), fres * 0.35);
	ROUGHNESS = roughness;
	METALLIC = 0.0;
	SPECULAR = 0.8;
	ALPHA = clamp(mix(tint.a * center_alpha_scale, tint.a + rim_alpha_boost, fres), 0.0, 1.0);
}
