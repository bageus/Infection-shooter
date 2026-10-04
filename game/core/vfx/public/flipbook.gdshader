shader_type spatial;
// Premultiplied output lets one shader draw both additive (fire, sparks) and
// normally blended (smoke, paper) frames: additive = 1 adds, 0 blends.
render_mode blend_premul_alpha, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 grid = vec2(4.0, 3.0);
uniform bool billboard = true;
uniform float additive : hint_range(0.0, 1.0) = 0.0;
uniform float brightness = 1.0;
// Soft fade of the quad edge hides frame borders bleeding through mipmaps.
uniform float edge_softness : hint_range(0.0, 0.2) = 0.02;

// Fractional frame: the fraction crossfades into the next frame so slow
// (smoke) frames blend smoothly instead of popping.
instance uniform float frame_position = 0.0;
instance uniform float frame_count = 12.0;
instance uniform float opacity = 1.0;
instance uniform vec4 tint : source_color = vec4(1.0);
instance uniform float spin = 0.0;

vec4 frame_sample(float frame, vec2 uv) {
	float index = clamp(floor(frame), 0.0, frame_count - 1.0);
	vec2 cell = vec2(mod(index, grid.x), floor(index / grid.x));
	return texture(atlas, (cell + uv) / grid);
}

void vertex() {
	float c = cos(spin);
	float s = sin(spin);
	VERTEX.xy = mat2(vec2(c, s), vec2(-s, c)) * VERTEX.xy;
	if (billboard) {
		float scale = length(MODEL_MATRIX[0].xyz);
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * scale, INV_VIEW_MATRIX[1] * scale, INV_VIEW_MATRIX[2] * scale, MODEL_MATRIX[3]);
		MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	}
}

void fragment() {
	vec2 uv = clamp(UV, vec2(0.002), vec2(0.998));
	float blend = fract(frame_position);
	vec4 current = frame_sample(frame_position, uv);
	vec4 next = frame_sample(min(frame_position + 1.0, frame_count - 1.0), uv);
	vec4 color = mix(current, next, blend) * tint;
	vec2 edge = min(UV, 1.0 - UV);
	float soft = edge_softness > 0.0 ? smoothstep(0.0, edge_softness, min(edge.x, edge.y)) : 1.0;
	float alpha = clamp(color.a * opacity * soft, 0.0, 1.0);
	ALBEDO = color.rgb * brightness * alpha;
	ALPHA = alpha * (1.0 - additive);
}
