shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
// Down-pointing arrow drawn in UV space: head triangle + shaft, tip at uv.y = 1.

uniform vec4 arrow_color : source_color = vec4(1.0, 0.82, 0.25, 1.0);
uniform float intensity = 1.6;
uniform float blink : hint_range(0.0, 1.0) = 1.0;

void vertex() {
	// Y-axis billboard: always faces the camera, stays upright.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], vec4(0.0, 1.0, 0.0, 0.0), INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	float ax = abs(UV.x - 0.5);
	bool in_head = UV.y > 0.55;
	float bound = in_head ? (1.0 - UV.y) * 1.1 : 0.11; // half-width of the silhouette at this row
	float d = bound - ax; // distance to the edge, > 0 inside
	float mask = smoothstep(0.0, 0.025, d);
	mask *= in_head ? 1.0 : smoothstep(0.0, 0.08, UV.y); // tail fades out at the top
	float rim = 1.0 - smoothstep(0.0, 0.07, d); // inner rim highlight
	float core = mix(0.3, 1.2, UV.y * UV.y) * (1.0 - 0.5 * ax / max(bound, 0.01)); // bright toward the tip and the centre line
	float band = smoothstep(0.55, 1.0, sin((UV.y * 3.0 - TIME * 1.2) * 6.2832) * 0.5 + 0.5) * (in_head ? 0.0 : 1.2);
	float light = core + rim * 0.7 + band;
	ALBEDO = arrow_color.rgb * light * intensity;
	ALPHA = mask * mix(0.55, 1.0, blink);
}
