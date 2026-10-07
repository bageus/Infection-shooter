shader_type spatial;
// Soft contact shadow under a piece of furniture: a dark rounded rectangle
// lying on the floor that fades out toward its edges. The quad is scaled to
// the footprint plus a margin; half_size and margin are in metres.
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform float strength : hint_range(0.0, 1.0) = 0.55;
instance uniform vec2 half_size = vec2(0.5);
instance uniform float margin = 0.2;
// 1 on the floor, fading to 0 as the prop is lifted or thrown.
instance uniform float presence = 1.0;

void fragment() {
	vec2 p = (UV - 0.5) * 2.0 * half_size;
	vec2 inner = max(half_size - vec2(margin), vec2(0.01));
	vec2 d = abs(p) - inner;
	float outside = length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0);
	// Darkest under the footprint, soft past its edge.
	float shade = 1.0 - smoothstep(-margin * 0.8, margin, outside);
	ALBEDO = vec3(0.0);
	ALPHA = shade * shade * strength * presence;
}
