shader_type spatial;
// Blood Burst bone spike: a wet dark-red body whose tip turns toxic green, so the poison reads at a glance.
// The cone is 1 m tall around its origin; the tip is at local y = +0.5.

uniform vec3 body : source_color = vec3(0.42, 0.05, 0.06);
uniform vec3 poison : source_color = vec3(0.35, 0.95, 0.15);

varying float along;

void vertex() {
	along = VERTEX.y + 0.5;
}

void fragment() {
	float tip = smoothstep(0.55, 0.95, along);
	ALBEDO = mix(body, poison * 0.7, tip);
	EMISSION = mix(vec3(0.55, 0.02, 0.03) * 0.5, poison * 0.9, tip);
	ROUGHNESS = 0.28;
	METALLIC = 0.15;
	RIM = 0.6;
}
