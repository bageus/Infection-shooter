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
uniform float edge_softness : hint_range(0.0, 0.3) = 0.02;

// Fractional frame: the fraction crossfades into the next frame so slow
// (smoke) frames blend smoothly instead of popping.
instance uniform float frame_position = 0.0;
instance uniform float frame_count = 12.0;
instance uniform float opacity = 1.0;
instance uniform vec4 tint : source_color = vec4(1.0);
instance uniform float spin = 0.0;
// Point of the frame (UV, y down) that sits at the node origin: a ground
// explosion pivots at its base, a spray at its nozzle.
instance uniform vec2 pivot = vec2(0.5, 0.5);
// Axial mode: the sheet's own direction (atlas_angle, radians, counter-
// clockwise from +U) is laid along the world axis and the quad turns about
// that axis to face the camera (spray jets, beams).
instance uniform float axial = 0.0;
instance uniform vec3 axis = vec3(1.0, 0.0, 0.0);
instance uniform float atlas_angle = 0.0;
// Ground mode: the quad lies flat on the floor, turned so the sheet's top
// points away from the camera, and stretched in depth by ground_stretch so
// a ring drawn as a camera-angle ellipse lies on the floor as a circle.
instance uniform float ground = 0.0;
instance uniform float ground_stretch = 1.0;
// Cycle mode: the last frame crossfades into the first (seamless loops).
instance uniform float cycle = 0.0;

vec4 frame_sample(float frame, vec2 uv) {
	float index = clamp(floor(frame), 0.0, frame_count - 1.0);
	vec2 cell = vec2(mod(index, grid.x), floor(index / grid.x));
	return texture(atlas, (cell + uv) / grid);
}

void vertex() {
	// POSITION is written on every path: once a shader writes it, Godot uses it
	// for all vertices.
	vec2 local = VERTEX.xy - vec2(pivot.x - 0.5, 0.5 - pivot.y);
	float scale = length(MODEL_MATRIX[0].xyz);
	vec3 origin = MODEL_MATRIX[3].xyz;
	if (ground > 0.5) {
		vec3 away = origin - INV_VIEW_MATRIX[3].xyz;
		away.y = 0.0;
		away = length(away) > 0.001 ? normalize(away) : vec3(0.0, 0.0, -1.0);
		vec3 right = vec3(-away.z, 0.0, away.x);
		vec3 world = origin + (right * local.x + away * local.y * ground_stretch) * scale;
		POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
	} else if (axial > 0.5) {
		float a = -atlas_angle;
		local = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * local;
		vec3 along = normalize(axis);
		vec3 to_camera = normalize(INV_VIEW_MATRIX[3].xyz - origin);
		vec3 side = cross(to_camera, along);
		side = length(side) > 0.001 ? normalize(side) : normalize(cross(vec3(0.0, 1.0, 0.0), along));
		vec3 world = origin + (along * local.x + side * local.y) * scale;
		POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
	} else {
		float c = cos(spin);
		float s = sin(spin);
		local = mat2(vec2(c, s), vec2(-s, c)) * local;
		mat4 model_view = MODELVIEW_MATRIX;
		if (billboard) {
			model_view = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * scale, INV_VIEW_MATRIX[1] * scale, INV_VIEW_MATRIX[2] * scale, MODEL_MATRIX[3]);
		}
		POSITION = PROJECTION_MATRIX * model_view * vec4(local, VERTEX.z, 1.0);
	}
}

void fragment() {
	vec2 uv = clamp(UV, vec2(0.002), vec2(0.998));
	float blend = fract(frame_position);
	vec4 current = frame_sample(frame_position, uv);
	float following = frame_position + 1.0;
	following = cycle > 0.5 ? mod(following, frame_count) : min(following, frame_count - 1.0);
	vec4 next = frame_sample(following, uv);
	vec4 color = mix(current, next, blend) * tint;
	vec2 edge = min(UV, 1.0 - UV);
	float soft = edge_softness > 0.0 ? smoothstep(0.0, edge_softness, min(edge.x, edge.y)) : 1.0;
	float alpha = clamp(color.a * opacity * soft, 0.0, 1.0);
	ALBEDO = color.rgb * brightness * alpha;
	ALPHA = alpha * (1.0 - additive);
}
