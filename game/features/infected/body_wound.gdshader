shader_type spatial;
// Enemy skin with bullet wounds that stick to the body (ADR-0017).
// Wounds are baked on the CPU into blood_mask (UV space, see body_blood_bake.gd):
// red = blood, green = dark wound core. CUSTOM0.xyz holds the bind-pose (rest)
// position of each vertex; it only drives the skin grain, so it follows animation.

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_albedo_texture = false;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool use_normal_texture = false;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.85;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D blood_mask : filter_linear, repeat_disable;
uniform bool use_blood_mask = false;
uniform vec3 blood_color : source_color = vec3(0.32, 0.015, 0.012);
uniform vec3 wound_core_color : source_color = vec3(0.09, 0.0, 0.0);
varying vec3 rest_position;

float hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash31(i), hash31(i + vec3(1, 0, 0)), f.x), mix(hash31(i + vec3(0, 1, 0)), hash31(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash31(i + vec3(0, 0, 1)), hash31(i + vec3(1, 0, 1)), f.x), mix(hash31(i + vec3(0, 1, 1)), hash31(i + vec3(1, 1, 1)), f.x), f.y),
		f.z);
}

void vertex() {
	rest_position = CUSTOM0.xyz;
}

void fragment() {
	vec4 base = albedo_color;
	if (use_albedo_texture) {
		base *= texture(albedo_texture, UV);
	}
	float blood = 0.0;
	float core = 0.0;
	float grain = value_noise(rest_position * 38.0) * 0.6 + value_noise(rest_position * 95.0) * 0.4;
	if (use_blood_mask) {
		vec2 mask = texture(blood_mask, UV).rg;
		// Grain makes the baked edge ragged instead of a clean circle.
		blood = smoothstep(0.3, 0.7, mask.r + (grain - 0.5) * 0.35);
		core = mask.g;
	}
	vec3 wet = mix(blood_color * (0.7 + 0.5 * grain), wound_core_color, core);
	ALBEDO = mix(base.rgb, wet, clamp(blood * 0.95, 0.0, 1.0));
	ROUGHNESS = mix(roughness_value, 0.18, blood);
	METALLIC = metallic_value;
	SPECULAR = mix(0.5, 0.75, blood);
	if (use_normal_texture) {
		NORMAL_MAP = texture(normal_texture, UV).rgb;
		NORMAL_MAP_DEPTH = 1.0 - blood * 0.7;
	}
}
