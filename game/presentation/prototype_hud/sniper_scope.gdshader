shader_type canvas_item;
void fragment() {
	vec4 image = texture(TEXTURE, UV);
	float radius = length(UV - vec2(0.5));
	image.a *= 1.0 - smoothstep(0.486, 0.495, radius);
	COLOR = image;
}
