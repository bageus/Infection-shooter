shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// Short side streaks frame the authored bullet; the middle stays transparent.
void fragment() {
    float y = abs(UV.y - 0.5);
    float stripe = 1.0 - smoothstep(0.025, 0.09, abs(y - 0.24));
    float envelope = smoothstep(0.0, 0.28, UV.x) * (1.0 - smoothstep(0.83, 1.0, UV.x));
    float tail = (1.0 - smoothstep(0.015, 0.08, y)) * (1.0 - smoothstep(0.3, 0.54, UV.x));
    float intensity = max(stripe * envelope, tail * smoothstep(0.0, 0.18, UV.x) * 0.55);
    ALBEDO = vec3(1.0, 0.75, 0.28);
    EMISSION = vec3(1.0, 0.68, 0.18) * 1.3;
    ALPHA = intensity * 0.72;
}
