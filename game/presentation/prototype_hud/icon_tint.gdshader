shader_type canvas_item;

// Recolours the cyan icon atlas: brightness keeps the artwork's shading,
// the tint supplies the HUD palette colour.
uniform vec4 tint : source_color = vec4(1.0);

void fragment() {
	vec4 texel = texture(TEXTURE, UV);
	float light = max(texel.r, max(texel.g, texel.b));
	COLOR = vec4(tint.rgb * light, texel.a * tint.a);
}
