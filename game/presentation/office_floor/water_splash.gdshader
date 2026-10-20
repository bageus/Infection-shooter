shader_type spatial;
// A drop hitting a surface: a thin ripple ring that widens and fades, with a
// few crown droplets flicking off it. Unit quad lying on the surface.
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

#include "res://game/features/player/skill_fx/fx_noise.gdshaderinc"

uniform vec3 water : source_color = vec3(0.7, 0.9, 1.0);

instance uniform float progress = 0.0;
instance uniform float seed = 0.0;

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float front = 1.0 - pow(1.0 - progress, 2.0);
	float d = r - front;
	float ring = exp(-d * d / 0.004);
	// Crown: short bright flecks just outside the ring.
	float fleck = step(0.6, fx_noise(vec2(a * 4.0 + seed * 9.0, 1.0))) * exp(-pow(r - front * 1.15, 2.0) / 0.0015);
	float life = 1.0 - smoothstep(0.3, 1.0, progress);
	float mask = 1.0 - smoothstep(0.92, 1.0, r);
	ALBEDO = mix(water, vec3(1.0), fleck);
	ALPHA = clamp((ring * 0.6 + fleck * 0.9) * life * mask, 0.0, 1.0);
}
