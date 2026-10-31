shader_type spatial;
// Overlay on the player: writes the stencil over the hero (also the see-through silhouette), so the outline rim leaves those pixels alone.
render_mode unshaded, depth_test_disabled, depth_draw_never, shadows_disabled;
stencil_mode write, 1;
void fragment() {
    ALBEDO = vec3(0.0);
    ALPHA = 0.0;
}
