// Game-side widescreen for PSO (GPOE8P v1.02), as a ModernGekko mod.
//
// 3D: the main scene projection (scene_projection_state, built by
// set_perspective_projection_from_fov) is widened only in the copy that
// GXSetProjection sends to the GPU, by W = screen aspect / (4/3). The game's
// own aspect fields stay 4:3, so its 2D (drawn through the same projection
// with load_screen_space_matrix) stays centered and aspect-correct, speech
// bubbles and markers stay on their targets, and other projections (shadow
// and texture passes) are untouched. Dolphin stretches the 4:3 frame to the
// screen; the widescreen hack stays off.
//
// HUD: while an anchored HUD window renders, its screen-space matrix is moved
// so the window sits against the screen edge instead of the centered 4:3
// area, and scaled about its corner by the HUD size setting.
//
// Hooks can't change registers (the loader restores them afterwards), so
// everything here works by editing guest memory around the GX calls.
//
// Addresses come from pso-decomp's config/GPOE8P/psov3/symbols.txt.
#include "moderngekko/mod_abi.h"
#include "pso_widescreen.h"

#include <stdlib.h>
#include <string.h>

#define ADDR_render_TMainTask 0x802298D8u
#define ADDR_GXSetProjection 0x8038E8F0u
#define ADDR_GXLoadPosMtxImm 0x8038EAC8u
#define ADDR_scene_projection_state 0x8058CA60u
#define ADDR_set_perspective_projection_from_fov 0x803D676Cu
#define ADDR_TWindowStatus_render 0x80271280u        // HP/TP panel, top left
#define ADDR_TWindowActionPalette_render 0x80243DC0u // action palette, bottom right
#define ADDR_TRaderMapCore_render 0x801FAC78u        // radar, top right
#define ADDR_setup_overhead_projection 0x801F9314u   // the radar's projection
#define SIZE_setup_overhead_projection 0x104u
#define ADDR_radar_map_view_rect_table 0x804C8748u    // {center_x, center_y, ...}[3]
#define ADDR_radar_map_view_scissor_table 0x804C8784u // {x0, y0, x1, y1}[3], 32-pixel units

static float u32_to_f(uint32_t v) { float f; memcpy(&f, &v, 4); return f; }
static uint32_t f_to_u32(float f) { uint32_t v; memcpy(&v, &f, 4); return v; }
static uint32_t read_u32(CPUState* s, uint32_t a) { return (uint32_t)moderngekko_mod_read(s, a, 4); }
static void write_u32(CPUState* s, uint32_t a, uint32_t v) { moderngekko_mod_write(s, a, v, 4); }

static volatile float g_requested = 1.0f;
static volatile float g_requested_hud = 1.0f;
static float g_widen = 1.0f; // W, latched once per frame
static float g_hud = 1.0f;   // HUD size, latched once per frame

void pso_widescreen_set_factor(float widen) { g_requested = widen > 1.0f ? widen : 1.0f; }
void pso_widescreen_set_hud_scale(float scale)
{
    g_requested_hud = scale < 0.25f ? 0.25f : scale > 2.0f ? 2.0f : scale;
}

// --- 3D -------------------------------------------------------------------

static uint32_t g_saved_m00, g_saved_m11;
static int g_projection_patched;
static int g_in_radar_projection;     // inside the radar's set_perspective_projection_from_fov
static int g_radar_projection_loaded; // the radar's projection is the current one

static void perspective_entry(CPUState* s)
{
    g_in_radar_projection = s->lr - ADDR_setup_overhead_projection < SIZE_setup_overhead_projection;
}

static void perspective_return(CPUState* s)
{
    (void)s;
    g_in_radar_projection = 0;
}

static void set_projection_entry(CPUState* s)
{
    g_projection_patched = 0;
    g_radar_projection_loaded = g_in_radar_projection;
    if (s->gpr[3] != ADDR_scene_projection_state || s->gpr[4] != 0u)
        return;
    // The radar's map is sized with the HUD (radar_begin places it and sizes
    // its clip box to match).
    const float k = g_in_radar_projection ? g_hud : 1.0f;
    if (g_widen <= 1.0001f && k == 1.0f)
        return;
    g_saved_m00 = read_u32(s, ADDR_scene_projection_state);
    g_saved_m11 = read_u32(s, ADDR_scene_projection_state + 20);
    write_u32(s, ADDR_scene_projection_state, f_to_u32(u32_to_f(g_saved_m00) * k / g_widen));
    write_u32(s, ADDR_scene_projection_state + 20, f_to_u32(u32_to_f(g_saved_m11) * k));
    g_projection_patched = 1;
}

static void set_projection_return(CPUState* s)
{
    if (!g_projection_patched)
        return;
    write_u32(s, ADDR_scene_projection_state, g_saved_m00);
    write_u32(s, ADDR_scene_projection_state + 20, g_saved_m11);
    g_projection_patched = 0;
}

// --- HUD ------------------------------------------------------------------
//
// load_screen_space_matrix maps game pixels to x_view = z * (m00 * X + m02),
// y_view = z * (m11 * Y + m12). Scaling m00/m11 by k and adding
// m00 * (dx + ax*(1-k)) to m02 and m11 * ay*(1-k) to m12 scales the drawing
// by k about the corner (ax, ay) and moves it by dx game pixels. On screen the
// centered 4:3 area is 1/W of the width; a window moves to the left edge with
// dx = -(W-1)*320 and to the right edge with dx = +(W-1)*320.

static float g_anchor_dx, g_anchor_x, g_anchor_y;
static int g_anchor_depth;
static uint32_t g_mtx_addr, g_mtx_saved[4]; // m00, m02, m11, m12

static void anchor_begin(float side, float ax, float ay)
{
    if (g_anchor_depth++ != 0)
        return;
    g_anchor_dx = side * (g_widen - 1.0f) * 320.0f;
    g_anchor_x = ax;
    g_anchor_y = ay;
}

static void anchor_end(CPUState* s)
{
    (void)s;
    if (g_anchor_depth > 0 && --g_anchor_depth == 0)
        g_anchor_dx = 0.0f;
}

static void anchor_top_left(CPUState* s) { (void)s; anchor_begin(-1.0f, 0.0f, 0.0f); }
static void anchor_bottom_right(CPUState* s) { (void)s; anchor_begin(1.0f, 640.0f, 480.0f); }

static void radar_begin(CPUState* s)
{
    // The radar's 3D map is placed with a scissor-box offset from its view
    // table (center 544,128 in the 640x480 frame, in frame pixels, which the
    // projection doesn't touch) and clipped by a box of 4x4 32-pixel units
    // around 17,4. Move and size both as its 2D frame is moved and sized
    // about the top-right corner. Written every frame, so settings apply live.
    const float k = g_hud;
    write_u32(s, ADDR_radar_map_view_rect_table, f_to_u32(640.0f - (640.0f - 544.0f) * k / g_widen));
    write_u32(s, ADDR_radar_map_view_rect_table + 4, f_to_u32(128.0f * k));
    write_u32(s, ADDR_radar_map_view_scissor_table + 0, f_to_u32(17.0f - 2.0f * k));
    write_u32(s, ADDR_radar_map_view_scissor_table + 4, f_to_u32(4.0f - 2.0f * k));
    write_u32(s, ADDR_radar_map_view_scissor_table + 8, f_to_u32(17.0f + 2.0f * k));
    write_u32(s, ADDR_radar_map_view_scissor_table + 12, f_to_u32(4.0f + 2.0f * k));
    anchor_begin(1.0f, 640.0f, 0.0f);
}

static void load_pos_mtx_entry(CPUState* s)
{
    g_mtx_addr = 0;
    if (g_anchor_depth == 0 || s->gpr[4] != 0u)
        return;
    // Under the radar's own projection the map is already sized.
    const float k = g_radar_projection_loaded ? 1.0f : g_hud;
    if (g_anchor_dx == 0.0f && k == 1.0f)
        return;
    const uint32_t m = s->gpr[3];
    const float m00 = u32_to_f(read_u32(s, m));
    const float m11 = u32_to_f(read_u32(s, m + 20));
    if (!(m00 < 0.0f && m00 > -0.02f && m11 > 0.0f && m11 < 0.02f))
        return; // not a screen-space matrix
    g_mtx_saved[0] = read_u32(s, m);
    g_mtx_saved[1] = read_u32(s, m + 8);
    g_mtx_saved[2] = read_u32(s, m + 20);
    g_mtx_saved[3] = read_u32(s, m + 24);
    write_u32(s, m, f_to_u32(m00 * k));
    write_u32(s, m + 8, f_to_u32(u32_to_f(g_mtx_saved[1]) + m00 * (g_anchor_dx + g_anchor_x * (1.0f - k))));
    write_u32(s, m + 20, f_to_u32(m11 * k));
    write_u32(s, m + 24, f_to_u32(u32_to_f(g_mtx_saved[3]) + m11 * g_anchor_y * (1.0f - k)));
    g_mtx_addr = m;
}

static void load_pos_mtx_return(CPUState* s)
{
    if (!g_mtx_addr)
        return;
    write_u32(s, g_mtx_addr, g_mtx_saved[0]);
    write_u32(s, g_mtx_addr + 8, g_mtx_saved[1]);
    write_u32(s, g_mtx_addr + 20, g_mtx_saved[2]);
    write_u32(s, g_mtx_addr + 24, g_mtx_saved[3]);
    g_mtx_addr = 0;
}

static void frame_begin(CPUState* s)
{
    (void)s;
    g_widen = g_requested;
    g_hud = g_requested_hud;
    g_anchor_depth = 0;
    g_anchor_dx = 0.0f;
}

static const ModernGekkoModHook hooks[] = {
    RECOMP_HOOK(ADDR_render_TMainTask, frame_begin),
    RECOMP_HOOK(ADDR_set_perspective_projection_from_fov, perspective_entry),
    RECOMP_HOOK_RETURN(ADDR_set_perspective_projection_from_fov, perspective_return),
    RECOMP_HOOK(ADDR_GXSetProjection, set_projection_entry),
    RECOMP_HOOK_RETURN(ADDR_GXSetProjection, set_projection_return),
    RECOMP_HOOK(ADDR_GXLoadPosMtxImm, load_pos_mtx_entry),
    RECOMP_HOOK_RETURN(ADDR_GXLoadPosMtxImm, load_pos_mtx_return),
    RECOMP_HOOK(ADDR_TWindowStatus_render, anchor_top_left),
    RECOMP_HOOK_RETURN(ADDR_TWindowStatus_render, anchor_end),
    RECOMP_HOOK(ADDR_TWindowActionPalette_render, anchor_bottom_right),
    RECOMP_HOOK_RETURN(ADDR_TWindowActionPalette_render, anchor_end),
    RECOMP_HOOK(ADDR_TRaderMapCore_render, radar_begin),
    RECOMP_HOOK_RETURN(ADDR_TRaderMapCore_render, anchor_end),
};

static void on_load(const ModernGekkoModHostApi* api)
{
    (void)api;
    const char* env = getenv("PSO_WIDE");
    if (env)
        pso_widescreen_set_factor((float)atof(env));
    env = getenv("PSO_HUD");
    if (env)
        pso_widescreen_set_hud_scale((float)atof(env));
}

static const ModernGekkoModDesc descriptor = {
    MODERNGEKKO_MOD_ABI_VERSION, MODERNGEKKO_CPU_ABI_VERSION, sizeof(CPUState),
    "GPOE8P", "pso_widescreen", "1.1.0", "Widescreen",
    0, 0u,
    0, 0u,
    hooks, (uint32_t)(sizeof hooks / sizeof hooks[0]),
    0, 0u,
    0, 0u,
    0, 0u,
    0, 0u,
    on_load, 0,
};

const ModernGekkoModDesc* pso_widescreen_descriptor(void) { return &descriptor; }

#ifdef PSO_WIDESCREEN_DYLIB
MODERNGEKKO_MOD_EXPORT const ModernGekkoModDesc* moderngekko_get_mod(void) { return &descriptor; }
#endif
