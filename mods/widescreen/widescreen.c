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
#define ADDR_draw_menu_backdrop_gradients 0x8024CE68u   // main menu: teal backdrop
#define SIZE_draw_menu_backdrop_gradients 0x43Cu
#define ADDR_TWindowMenuMainMenu_render 0x802AE730u      // main menu: command list
#define ADDR_TWindowMessage_render 0x80269DC8u           // main menu: help box
#define ADDR_TWindowSubStatusDisp_render 0x802815D0u     // main menu: character panel
#define ADDR_internet_time_callback 0x802C6FB0u          // main menu: internet time (a TWindowCallBack's callback)
#define ADDR_TRaderMapCore_view_mode 0x805D5F3Cu       // 0 corner radar, 1/2 the menu's map views

static float u32_to_f(uint32_t v) { float f; memcpy(&f, &v, 4); return f; }
static uint32_t f_to_u32(float f) { uint32_t v; memcpy(&v, &f, 4); return v; }
static uint32_t read_u32(CPUState* s, uint32_t a) { return (uint32_t)moderngekko_mod_read(s, a, 4); }
static void write_u32(CPUState* s, uint32_t a, uint32_t v) { moderngekko_mod_write(s, a, v, 4); }

static volatile float g_requested = 1.0f;
static volatile float g_requested_hud = 1.0f;
static float g_widen = 1.0f; // W, latched once per frame
static float g_hud = 1.0f;   // HUD size, latched once per frame
static int g_anchor_depth;   // nesting of anchored HUD windows being drawn

void pso_widescreen_set_factor(float widen) { g_requested = widen > 1.0f ? widen : 1.0f; }
void pso_widescreen_set_hud_scale(float scale)
{
    g_requested_hud = scale < 0.25f ? 0.25f : scale > 2.0f ? 2.0f : scale;
}

// Settings are latched where each frame starts (render_TMainTask) and again
// when the main 3D projection is set, in case the former is missed (it can be,
// for a while after a save state is loaded).
static void latch_settings(void)
{
    g_widen = g_requested;
    g_hud = g_requested_hud;
}

// --- 3D -------------------------------------------------------------------

static uint32_t g_saved_m00, g_saved_m11;
static int g_projection_patched;
static int g_in_radar_projection;     // inside the radar's set_perspective_projection_from_fov
static int g_radar_projection_loaded; // the radar's projection is the current one
static float g_radar_scale = 1.0f;    // size of the radar's 3D map, set by radar_begin

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
    if (!g_in_radar_projection && g_anchor_depth == 0)
        latch_settings();
    // The radar's map is sized with the HUD (radar_begin places it and sizes
    // its clip box to match).
    const float k = g_in_radar_projection ? g_radar_scale : 1.0f;
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
// y_view = z * (m11 * Y + m12). While an anchored window draws, its pixels are
// mapped X' = kx*X + ox, Y' = ky*Y + oy: m00 and m11 are scaled by kx and ky,
// and m00*ox and m11*oy are added to m02 and m12.
//
// A window is placed by shifting it by (sx, sy) in the 4:3 layout, scaling it
// by k about its corner (ax, ay), then moving it by (dx, dy) game pixels:
// X' = ax + k*(X + sx - ax) + dx. On screen the centered 4:3 area is 1/W of
// the width, so a window moves to the left edge with dx = -(W-1)*320 and to
// the right edge with dx = +(W-1)*320.

typedef struct { float kx, ky, ox, oy; } Xform;

static Xform g_xf;          // the current anchored window's transform
static Xform g_xf_unsized;  // the same at size 1, for the radar's own projection
static uint32_t g_mtx_addr, g_mtx_saved[4]; // m00, m02, m11, m12
static uint32_t g_mtx_sp, g_mtx_lr;         // the call that moved it

static Xform place(float k, float side, float ax, float ay, float sx, float sy, float dy)
{
    Xform x;
    x.kx = x.ky = k;
    x.ox = side * (g_widen - 1.0f) * 320.0f + k * sx + ax * (1.0f - k);
    x.oy = dy + k * sy + ay * (1.0f - k);
    return x;
}

static void anchor_set(Xform sized, Xform unsized)
{
    if (g_anchor_depth++ != 0)
        return;
    g_xf = sized;
    g_xf_unsized = unsized;
}

static void anchor_place(float k, float side, float ax, float ay, float sx, float sy, float dy)
{
    anchor_set(place(k, side, ax, ay, sx, sy, dy), place(1.0f, side, ax, ay, sx, sy, dy));
}

static void anchor_end(CPUState* s)
{
    (void)s;
    if (g_anchor_depth > 0)
        --g_anchor_depth;
}

static void anchor_top_left(CPUState* s) { (void)s; anchor_place(g_hud, -1.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f); }
static void anchor_bottom_right(CPUState* s) { (void)s; anchor_place(g_hud, 1.0f, 640.0f, 480.0f, 0.0f, 0.0f, 0.0f); }

// --- Main menu (START) -----------------------------------------------------
//
// In 4:3 the menu is a teal backdrop with a hole at the top right for the 3D
// view, the command list hanging under the HP/TP panel (27..143 x 115..285),
// the help box at the bottom left (17..223 x 313..450) and the character panel
// with the internet time at the bottom right (300..617 x 258..444). The
// backdrop is stretched across the screen; the windows go to their corners.
// They grow with HUD size only as far as the list (under the HP/TP panel,
// which keeps the full HUD size) and the help box still fit one above the
// other: 115*k + 170*km <= 480 - 167*km.

// TWindowMessage and the others are used elsewhere too (NPC dialogue, for
// one); they are moved only while the command list is up (drawn this frame or
// the last).
static uint32_t g_frame, g_menu_frame = 0xFFFFFFF0u;
static int menu_open(void) { return g_frame - g_menu_frame <= 1u; }

static float menu_scale(void)
{
    const float fit = (480.0f - 115.0f * g_hud) / (170.0f + 167.0f);
    return g_hud < fit ? g_hud : fit;
}

// The backdrop is stretched across the screen. Its function is called from
// inside the same chunk of recompiled code, which jumps straight to it rather
// than through the hook dispatcher, so it can't be hooked; it is recognized
// from the call stack when its matrices are loaded instead.
static int called_from(CPUState* s, uint32_t start, uint32_t size, int frames)
{
    uint32_t sp = s->gpr[1];
    for (int i = 0; i < frames; ++i) {
        const uint32_t next = read_u32(s, sp);
        if (next < 0x80000000u || next >= 0x81800000u || next <= sp)
            return 0;
        if (read_u32(s, next + 4) - start < size)
            return 1;
        sp = next;
    }
    return 0;
}

static int menu_backdrop_xform(CPUState* s, Xform* x)
{
    if (g_widen <= 1.0001f ||
        !called_from(s, ADDR_draw_menu_backdrop_gradients, SIZE_draw_menu_backdrop_gradients, 6))
        return 0;
    x->kx = g_widen;
    x->ky = 1.0f;
    x->ox = 320.0f * (1.0f - g_widen);
    x->oy = 0.0f;
    return 1;
}

static void menu_list_begin(CPUState* s)
{
    (void)s;
    g_menu_frame = g_frame;
    // Scaled about the top of the list, then moved down with the HP/TP panel.
    anchor_place(menu_scale(), -1.0f, 0.0f, 115.0f, 0.0f, 0.0f, 115.0f * (g_hud - 1.0f));
}

static void menu_window_begin(float side, float ax)
{
    if (menu_open())
        anchor_place(menu_scale(), side, ax, 480.0f, 0.0f, 0.0f, 0.0f);
    else
        anchor_place(1.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f); // left as the game has it
}

static void menu_help_begin(CPUState* s) { (void)s; menu_window_begin(-1.0f, 0.0f); }
static void menu_status_begin(CPUState* s) { (void)s; menu_window_begin(1.0f, 640.0f); }

// --- Radar -----------------------------------------------------------------
//
// The corner radar (view mode 0) is a 128x128 box at 480..608 x 64..192 in the
// 4:3 layout: a faint backdrop, the 3D map clipped to it, and the compass. The
// game leaves it well below and left of the corner, close to the action
// palette; it is moved to RADAR_MARGIN from the top-right corner first, then
// sized about the corner like the other HUD pieces.
#define RADAR_MARGIN 16.0f
#define RADAR_SHIFT_X (640.0f - RADAR_MARGIN - 608.0f)
#define RADAR_SHIFT_Y (RADAR_MARGIN - 64.0f)

static void radar_begin(CPUState* s)
{
    if (read_u32(s, ADDR_TRaderMapCore_view_mode) != 0u) {
        // The menu's map views are laid out for the 4:3 area; leave them be.
        g_radar_scale = 1.0f;
        anchor_place(1.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f);
        return;
    }
    // The 3D map is placed with a scissor-box offset from its view table
    // (center 544,128, in frame pixels, which the projection doesn't touch)
    // and clipped by a box sized from the scissor table (4x4 32-pixel units,
    // centered by the game). Place and size both as the 2D parts are, in frame
    // pixels: the 4:3 area is 1/W of the frame's width. Written every frame,
    // so settings apply live.
    const float k = g_hud;
    const float half = 2.0f * k;
    g_radar_scale = k;
    write_u32(s, ADDR_radar_map_view_rect_table,
              f_to_u32(640.0f - (640.0f - (544.0f + RADAR_SHIFT_X)) * k / g_widen));
    write_u32(s, ADDR_radar_map_view_rect_table + 4, f_to_u32((128.0f + RADAR_SHIFT_Y) * k));
    write_u32(s, ADDR_radar_map_view_scissor_table + 0, f_to_u32(17.0f - half / g_widen));
    write_u32(s, ADDR_radar_map_view_scissor_table + 4, f_to_u32(4.0f - half));
    write_u32(s, ADDR_radar_map_view_scissor_table + 8, f_to_u32(17.0f + half / g_widen));
    write_u32(s, ADDR_radar_map_view_scissor_table + 12, f_to_u32(4.0f + half));
    anchor_place(k, 1.0f, 640.0f, 0.0f, RADAR_SHIFT_X, RADAR_SHIFT_Y, 0.0f);
}

static void restore_pos_mtx(CPUState* s)
{
    write_u32(s, g_mtx_addr, g_mtx_saved[0]);
    write_u32(s, g_mtx_addr + 8, g_mtx_saved[1]);
    write_u32(s, g_mtx_addr + 20, g_mtx_saved[2]);
    write_u32(s, g_mtx_addr + 24, g_mtx_saved[3]);
    g_mtx_addr = 0;
}

static void load_pos_mtx_entry(CPUState* s)
{
    if (g_mtx_addr != 0u) {
        // The runtime can dispatch one call twice (same stack pointer and
        // return address): the matrix is already moved. Otherwise the last
        // call's return was missed: put that matrix back first.
        if (s->gpr[3] == g_mtx_addr && s->gpr[1] == g_mtx_sp && s->lr == g_mtx_lr)
            return;
        restore_pos_mtx(s);
    }
    if (s->gpr[4] != 0u)
        return;
    const uint32_t m = s->gpr[3];
    const float m00 = u32_to_f(read_u32(s, m));
    const float m11 = u32_to_f(read_u32(s, m + 20));
    if (!(m00 < 0.0f && m00 > -0.02f && m11 > 0.0f && m11 < 0.02f))
        return; // not a screen-space matrix
    Xform x;
    if (g_anchor_depth != 0) {
        // Under the radar's own projection the map is already sized.
        x = g_radar_projection_loaded ? g_xf_unsized : g_xf;
    } else if (!menu_backdrop_xform(s, &x)) {
        return;
    }
    if (x.kx == 1.0f && x.ky == 1.0f && x.ox == 0.0f && x.oy == 0.0f)
        return;
    g_mtx_saved[0] = read_u32(s, m);
    g_mtx_saved[1] = read_u32(s, m + 8);
    g_mtx_saved[2] = read_u32(s, m + 20);
    g_mtx_saved[3] = read_u32(s, m + 24);
    write_u32(s, m, f_to_u32(m00 * x.kx));
    write_u32(s, m + 8, f_to_u32(u32_to_f(g_mtx_saved[1]) + m00 * x.ox));
    write_u32(s, m + 20, f_to_u32(m11 * x.ky));
    write_u32(s, m + 24, f_to_u32(u32_to_f(g_mtx_saved[3]) + m11 * x.oy));
    g_mtx_addr = m;
    g_mtx_sp = s->gpr[1];
    g_mtx_lr = s->lr;
}

static void load_pos_mtx_return(CPUState* s)
{
    if (g_mtx_addr != 0u)
        restore_pos_mtx(s);
}

static void frame_begin(CPUState* s)
{
    (void)s;
    latch_settings();
    g_anchor_depth = 0;
    ++g_frame;
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
    RECOMP_HOOK(ADDR_TWindowMenuMainMenu_render, menu_list_begin),
    RECOMP_HOOK_RETURN(ADDR_TWindowMenuMainMenu_render, anchor_end),
    RECOMP_HOOK(ADDR_TWindowMessage_render, menu_help_begin),
    RECOMP_HOOK_RETURN(ADDR_TWindowMessage_render, anchor_end),
    RECOMP_HOOK(ADDR_TWindowSubStatusDisp_render, menu_status_begin),
    RECOMP_HOOK_RETURN(ADDR_TWindowSubStatusDisp_render, anchor_end),
    RECOMP_HOOK(ADDR_internet_time_callback, menu_status_begin),
    RECOMP_HOOK_RETURN(ADDR_internet_time_callback, anchor_end),
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
