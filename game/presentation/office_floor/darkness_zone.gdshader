shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform float darkness = 0.88;
uniform bool lens_zone = false;
uniform mat4 zone_inverse = mat4(1.0);
uniform vec2 zone_half = vec2(0.0);
uniform float wall_margin = 0.3;
uniform vec3 hero_pos = vec3(0.0);
uniform float outside_reach = 2.5;
uniform float outside_height = 0.6;
uniform vec2 hole_center = vec2(-10.0);
uniform vec2 viewport_size = vec2(1280.0, 720.0);
uniform float hole_radius = 0.0;
uniform float player_depth = 0.0;
uniform int portal_count = 0;
uniform vec3 portal_centre[8];
uniform vec3 portal_normal[8];
uniform vec3 portal_u[8];
uniform vec3 portal_v[8];
varying float main_view;
void vertex() {
    main_view = distance(INV_VIEW_MATRIX[3].xyz, MAIN_CAM_INV_VIEW_MATRIX[3].xyz) < 0.01 ? 1.0 : 0.0;
}
void fragment() {
    float cover = darkness;
    // Lens: a soft circle that opens only in the room the hero stands in: what lies inside that room
    // and below the cover plane shows, walls on its edge, ceiling fixtures and other rooms stay covered.
    // The hero has its own reveal pass. The cover is drawn over everything inside the lens.
    DEPTH = FRAGCOORD.z;
    if (main_view > 0.5 && hole_radius > 0.0) {
        float distance_px = length((SCREEN_UV - hole_center) * viewport_size);
        if (distance_px < hole_radius) {
            float depth = textureLod(scene_depth, SCREEN_UV, 0.0).r;
            vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
            ndc.z = depth * 2.0 - 1.0;
#endif
            vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
            vec3 world = (INV_VIEW_MATRIX * vec4(view.xyz / view.w, 1.0)).xyz;
            vec3 local = (zone_inverse * vec4(world, 1.0)).xyz;
            DEPTH = 1.0;
            bool below = local.y < -0.1;
            bool in_room = lens_zone && below && abs(local.x) < zone_half.x - wall_margin && abs(local.z) < zone_half.y - wall_margin;
            // The hero stands outside this zone (its cover only hangs over him in perspective):
            // open the low floor-level surfaces next to him that belong to his own side of the wall.
            bool outside = !lens_zone && below && world.y < outside_height && distance(world.xz, hero_pos.xz) < outside_reach
                && (abs(local.x) > zone_half.x + wall_margin || abs(local.z) > zone_half.y + wall_margin);
            in_room = in_room || outside;
            if (in_room) cover *= smoothstep(hole_radius * 0.6, hole_radius, distance_px);
        }
    }
    // Fog rooms: a view ray that enters through an open door or glass pane sees the room, so the cover opens there.
    vec3 camera = INV_VIEW_MATRIX[3].xyz;
    vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
    vec3 dir = normalize(world - camera);
    for (int i = 0; i < portal_count; i++) {
        float facing = dot(dir, portal_normal[i]);
        if (facing >= -0.0001) continue;
        float along = dot(portal_centre[i] - world, portal_normal[i]) / facing;
        if (along <= 0.0) continue;
        vec3 hit = world + dir * along - portal_centre[i];
        if (abs(dot(hit, portal_u[i])) <= dot(portal_u[i], portal_u[i]) && abs(dot(hit, portal_v[i])) <= dot(portal_v[i], portal_v[i])) discard;
    }
    ALBEDO = vec3(0.0);
    ALPHA = cover;
}
