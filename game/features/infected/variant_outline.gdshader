shader_type spatial;
// Overlay on an infected variant: a thin translucent "suit" halo in one colour,
// brighter at the rim and faint in the centre, with a very slow shimmer, over the
// body's own shading.
render_mode blend_mix, unshaded, depth_draw_never, cull_back, shadows_disabled;

uniform vec4 outline_color : source_color = vec4(1.0, 0.5, 0.1, 1.0);
uniform float strength : hint_range(0.0, 1.0) = 0.35;
instance uniform float fade = 1.0;

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	float shimmer = 0.95 + 0.05 * sin(TIME * 1.5);
	ALBEDO = outline_color.rgb;
	ALPHA = clamp((strength * 0.5 + rim * strength) * shimmer * fade, 0.0, 1.0);
}
