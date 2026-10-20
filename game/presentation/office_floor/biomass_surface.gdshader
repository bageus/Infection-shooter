shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;
// Volumetric biomass (ADR-0061): the relief height lifts the vertices off the
// surface and the relief normal lights the wet, glossy mass.
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D relief_texture : hint_default_black, filter_linear_mipmap, repeat_disable;
// Rectangle of the textures this mesh samples, in 0..1 UV space.
uniform vec4 uv_rect = vec4(0.0, 0.0, 1.0, 1.0);
// Lift of the tallest relief, in the mesh's local units.
uniform float depth = 0.05;
uniform float bump = 1.5;
uniform float glossiness = 0.2;
uniform float tint_strength = 0.0;
uniform vec3 tint : source_color = vec3(1.0);

void vertex() {
	vec2 atlas_uv = uv_rect.xy + UV * uv_rect.zw;
	float lift = textureLod(relief_texture, atlas_uv, 0.0).b * textureLod(albedo_texture, atlas_uv, 0.0).a;
	VERTEX.z += lift * depth;
}

void fragment() {
	vec2 atlas_uv = uv_rect.xy + UV * uv_rect.zw;
	vec4 color = texture(albedo_texture, atlas_uv);
	vec3 relief = texture(relief_texture, atlas_uv).rgb;
	vec2 slope = (relief.rg * 2.0 - 1.0);
	float flat_z = sqrt(max(1.0 - dot(slope, slope), 0.05));
	// The authored green channel points the other way to Godot's convention.
	vec3 local_normal = normalize(vec3(slope.x / flat_z * bump, -slope.y / flat_z * bump, 1.0));
	NORMAL = normalize((VIEW_MATRIX * vec4((MODEL_NORMAL_MATRIX * local_normal), 0.0)).xyz);
	ALBEDO = mix(color.rgb, color.rgb * tint, tint_strength);
	ALPHA = color.a;
	ROUGHNESS = glossiness;
	SPECULAR = 0.7;
	METALLIC = 0.0;
}
