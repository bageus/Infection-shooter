shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform float darkness = 0.88;
uniform vec2 hole_center = vec2(-10.0);
uniform vec2 viewport_size = vec2(1280.0, 720.0);
uniform float hole_radius = 0.0;
uniform float player_depth = 0.0;
varying float main_view;
void vertex() {
    main_view = distance(INV_VIEW_MATRIX[3].xyz, MAIN_CAM_INV_VIEW_MATRIX[3].xyz) < 0.01 ? 1.0 : 0.0;
}
void fragment() {
    float cover = darkness;
    // Lens x-ray: same dithered hole the walls get, so the hero stays visible under the cover.
    if (main_view > 0.5 && hole_radius > 0.0 && -VERTEX.z < player_depth - 0.05) {
        float distance_px = length((SCREEN_UV - hole_center) * viewport_size);
        float fade = smoothstep(hole_radius * 0.88, hole_radius, distance_px);
        float dither = fract(dot(floor(FRAGCOORD.xy), vec2(0.754877666, 0.569840296)));
        if (fade < dither + 0.0001) discard;
    }
    ALBEDO = vec3(0.0);
    ALPHA = cover;
}
