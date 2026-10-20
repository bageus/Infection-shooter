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

// Surface edges (biomass_clip.gd), per piece. clip_a = rectangle centre xy and
// unit direction zw of its first axis, clip_b = half sizes along the two axes
// (x <= 0 means no clip), clip_limit = per side (+u, -u, +v, -v): > 0 wraps
// round a convex edge up to that depth, < 0 folds onto a concave floor/wall
// up to that span, 0 only clips. depth_scale flattens settled (baked) mass.
instance uniform vec4 clip_a = vec4(0.0);
instance uniform vec4 clip_b = vec4(0.0);
instance uniform vec4 clip_limit = vec4(0.0);
instance uniform float depth_scale = 1.0;
varying float excess;
varying float corner;
varying vec3 fold;

void vertex() {
	vec2 atlas_uv = uv_rect.xy + UV * uv_rect.zw;
	float h = textureLod(relief_texture, atlas_uv, 0.0).b * textureLod(albedo_texture, atlas_uv, 0.0).a * depth * depth_scale;
	vec3 p = vec3(VERTEX.xy, VERTEX.z + h);
	excess = -1.0;
	corner = -1.0;
	fold = vec3(0.0);
	if (clip_b.x > 0.0) {
		vec2 u = clip_a.zw;
		vec2 v = vec2(-u.y, u.x);
		vec2 rel = VERTEX.xy - clip_a.xy;
		float along_u = dot(rel, u);
		float along_v = dot(rel, v);
		vec4 d = vec4(along_u - clip_b.x, -along_u - clip_b.x, along_v - clip_b.y, -along_v - clip_b.y);
		vec2 dirs[4] = vec2[](u, -u, v, -v);
		int best = 0;
		float over = d.x;
		float second = -1e9;
		excess = d.x - abs(clip_limit.x);
		for (int i = 1; i < 4; i++) {
			excess = max(excess, d[i] - abs(clip_limit[i]));
			if (d[i] > over) {
				second = max(second, over);
				over = d[i];
				best = i;
			} else {
				second = max(second, d[i]);
			}
		}
		corner = second;
		float limit = clip_limit[best];
		if (over > 0.0 && second <= 0.0 && limit != 0.0) {
			float c = limit > 0.0 ? 1.0 : -1.0;
			vec2 t = dirs[best];
			p.xy = VERTEX.xy - t * over + t * (c * h);
			p.z = VERTEX.z - c * over;
			fold = vec3(t, c);
		}
	}
	VERTEX = p;
}

void fragment() {
	if (excess > 0.0 || corner > 0.0) {
		discard;
	}
	vec2 atlas_uv = uv_rect.xy + UV * uv_rect.zw;
	vec4 color = texture(albedo_texture, atlas_uv);
	vec3 relief = texture(relief_texture, atlas_uv).rgb;
	vec2 slope = (relief.rg * 2.0 - 1.0);
	float flat_z = sqrt(max(1.0 - dot(slope, slope), 0.05));
	// The authored green channel points the other way to Godot's convention.
	vec3 local_normal = normalize(vec3(slope.x / flat_z * bump, -slope.y / flat_z * bump, 1.0));
	if (abs(fold.z) > 0.5) {
		// The mass wraps an edge: its frame turns a quarter round the edge.
		vec2 t = normalize(fold.xy);
		float c = sign(fold.z);
		vec2 side = vec2(-t.y, t.x);
		local_normal = vec3(t * (c * local_normal.z) + side * dot(local_normal.xy, side), -c * dot(local_normal.xy, t));
	}
	NORMAL = normalize((VIEW_MATRIX * vec4((MODEL_NORMAL_MATRIX * local_normal), 0.0)).xyz);
	ALBEDO = mix(color.rgb, color.rgb * tint, tint_strength);
	ALPHA = color.a;
	ROUGHNESS = glossiness;
	SPECULAR = 0.7;
	METALLIC = 0.0;
}
