// Cheats for PSO (GPOE8P v1.02), as a ModernGekko mod: infinite meseta,
// infinite HP/TP, a mag that can always be fed, EXP / rare drop boosts, and a
// camera turned with the C-stick.
//
// Hooks can't change registers (the loader restores them afterwards), so each
// cheat edits guest memory around a game function instead. The hooked
// functions are all reached from other recompiled chunks or through vtables;
// a call within the same 16 KB chunk is a direct jump that skips hooks.
//
// Addresses and offsets come from pso-decomp (config/GPOE8P/psov3/symbols.txt
// and the TObjChara / TItemMag headers).
#include "moderngekko/mod_abi.h"
#include "pso_cheats.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define ADDR_player_slot_table 0x8050EA10u          // TObjPlayer*[]; slot 0 is the local player offline
#define ADDR_TObjPlayer_run_task 0x801BB330u        // once per frame per player (vtable)
#define ADDR_receive_physical_attack 0x80014108u    // TObjChara: hits that take HP
#define ADDR_receive_direct_attack 0x8001311Cu
#define ADDR_receive_weapon_special_attack 0x80011824u
#define ADDR_TObjPlayer_add_actor_exp 0x801B0F34u   // (this, amount); clamps to the level limit
#define ADDR_create_font_small_task 0x800FD204u     // floating text, e.g. the EXP number on a kill
#define LR_award_exp_add 0x800F6D98u                // award_enemy_experience's call to add_actor_exp
#define LR_award_exp_popup 0x800F6DC4u              // ... and to create_font_small_task
#define ADDR_is_mag_full 0x8027C0F4u                // (mag): greys out "feed" in the item menu
#define ADDR_select_enemy_drop 0x8010663Cu          // enemy drop roll (rare first)
#define ADDR_select_box_item 0x80106818u            // box drop roll (rare first)
#define ADDR_rare_item_table_file 0x805D5464u       // -> {enemy entries*, box count, box types*, box entries*}
#define ADDR_camera_controller_registry 0x80488A58u // TCameraCtrl*[], indexed by the view state
#define ADDR_camera_view_state 0x804FF628u          // u8; 0 = the normal single view
#define ADDR_controller_input_state 0x8050E208u     // pads from +0x20

#define OFS_stats 0x2B0u          // TObjChara: -> character stats block
#define OFS_stats_exp 0x1Cu
#define OFS_stats_meseta 0x20u
#define OFS_hpmax 0x2B8u          // s16
#define OFS_tpmax 0x2BAu
#define OFS_hp 0x32Cu
#define OFS_tp 0x32Eu
#define OFS_mag_fullness_frames 0x190u // TItemMag: f32, frames until hungry
#define OFS_mag_feeds_while_full 0x194u // f32; the mag is "full" from a threshold up

#define OFS_cam_mode 0x24u        // TCameraCtrl: 1 = following the player
#define OFS_cam_heading 0x30u     // s32 holding a u16 angle (0x10000 = 360 degrees)
#define OFS_pad0_cx 0x20u + 0x18u // s16 C-stick x

#define OFS_font_width 0x30u      // TFontSmallTask: f32 text width
#define OFS_font_text 0x34u       // char[0x10]
#define FONT_TEXT_LEN 0x10u

#define MAX_MESETA 999999u
#define HP_DURING_HIT 30000u       // above any hit, so a hit can't kill
#define RARE_ENEMY_ENTRIES 0x58u
#define RARE_BOX_ENTRIES_MAX 1024u

static uint32_t read_u32(CPUState* s, uint32_t a) { return (uint32_t)moderngekko_mod_read(s, a, 4); }
static uint32_t read_u16(CPUState* s, uint32_t a) { return (uint32_t)moderngekko_mod_read(s, a, 2); }
static uint32_t read_u8(CPUState* s, uint32_t a) { return (uint32_t)moderngekko_mod_read(s, a, 1); }
static void write_u32(CPUState* s, uint32_t a, uint32_t v) { moderngekko_mod_write(s, a, v, 4); }
static void write_u16(CPUState* s, uint32_t a, uint32_t v) { moderngekko_mod_write(s, a, v, 2); }
static void write_u8(CPUState* s, uint32_t a, uint32_t v) { moderngekko_mod_write(s, a, v, 1); }

static int is_ram(uint32_t a) { return a >= 0x80000000u && a < 0x81800000u; }

static volatile int g_meseta, g_hp_tp, g_mag;
static volatile int g_exp_mult = 1, g_rare_mult = 1;
static volatile int g_camera_speed = 100; // percent; 0 = the C-stick doesn't turn the camera

static int clamp_mult(int m) { return m < 1 ? 1 : m > (1 << 28) ? (1 << 28) : m; } // 1 << 28 makes every rare roll succeed
void pso_cheats_set_infinite_meseta(int on) { g_meseta = on != 0; }
void pso_cheats_set_infinite_hp_tp(int on) { g_hp_tp = on != 0; }
void pso_cheats_set_mag_always_hungry(int on) { g_mag = on != 0; }
void pso_cheats_set_exp_multiplier(int m) { g_exp_mult = clamp_mult(m); }
void pso_cheats_set_rare_multiplier(int m) { g_rare_mult = clamp_mult(m); }
void pso_cheats_set_camera_speed(int percent) { g_camera_speed = percent < 0 ? 0 : percent > 400 ? 400 : percent; }

static uint32_t local_player(CPUState* s) { return read_u32(s, ADDR_player_slot_table); }

static int is_local_player(CPUState* s, uint32_t obj)
{
    return obj != 0u && is_ram(obj) && obj == local_player(s);
}

static uint32_t stats_block(CPUState* s, uint32_t player)
{
    const uint32_t st = read_u32(s, player + OFS_stats);
    return is_ram(st) ? st : 0u;
}

static void refill(CPUState* s, uint32_t p)
{
    write_u16(s, p + OFS_hp, read_u16(s, p + OFS_hpmax));
    write_u16(s, p + OFS_tp, read_u16(s, p + OFS_tpmax));
}

// --- Rare drops -------------------------------------------------------------
//
// A rare entry's first byte encodes its chance: the roll (a u32) must be below
// (2 << max(e - 4, 0)) * (m + 7), e = bits 3-7, m = bits 0-2, worked out in
// u32 like the game does. During a drop roll each entry is swapped for the
// code nearest the multiplied chance, and put back afterwards.

static uint32_t rare_value(uint32_t code)
{
    int e = (int)((code >> 3) & 0x1Fu) - 4;
    if (e < 0)
        e = 0;
    return (2u << e) * ((code & 7u) + 7u);
}

static uint8_t boosted_code(uint8_t code, int mult)
{
    if (code == 0u)
        return 0u; // never drops
    uint64_t target = (uint64_t)rare_value(code) * (uint64_t)mult;
    if (target > 0xFFFFFFFFu)
        target = 0xFFFFFFFFu;
    uint8_t best = code;
    uint32_t best_value = rare_value(code);
    for (uint32_t c = 1u; c < 256u; ++c) {
        const uint32_t v = rare_value(c);
        if (v <= target && v > best_value) {
            best = (uint8_t)c;
            best_value = v;
        }
    }
    return best;
}

static uint32_t g_rare_addr[RARE_ENEMY_ENTRIES + RARE_BOX_ENTRIES_MAX];
static uint8_t g_rare_saved[RARE_ENEMY_ENTRIES + RARE_BOX_ENTRIES_MAX];
static uint32_t g_rare_count; // entries boosted; 0 when the table is as loaded
static int g_drop_depth;      // drop rolls in progress

static void rare_restore(CPUState* s)
{
    for (uint32_t i = 0; i < g_rare_count; ++i)
        write_u8(s, g_rare_addr[i], g_rare_saved[i]);
    g_rare_count = 0;
}

static void rare_boost_entry(CPUState* s, uint32_t a, int mult)
{
    const uint8_t code = (uint8_t)read_u8(s, a);
    const uint8_t boosted = boosted_code(code, mult);
    if (boosted == code)
        return;
    g_rare_addr[g_rare_count] = a;
    g_rare_saved[g_rare_count] = code;
    ++g_rare_count;
    write_u8(s, a, boosted);
}

static void drop_roll_entry(CPUState* s)
{
    if (g_drop_depth++ != 0)
        return; // already boosted
    const int mult = g_rare_mult;
    if (mult <= 1)
        return;
    const uint32_t table = read_u32(s, ADDR_rare_item_table_file);
    if (!is_ram(table))
        return;
    const uint32_t enemy = read_u32(s, table);
    if (is_ram(enemy))
        for (uint32_t i = 0; i < RARE_ENEMY_ENTRIES; ++i)
            rare_boost_entry(s, enemy + i * 4u, mult);
    uint32_t count = read_u32(s, table + 4u);
    const uint32_t box = read_u32(s, table + 12u);
    if (count > RARE_BOX_ENTRIES_MAX)
        count = RARE_BOX_ENTRIES_MAX;
    if (is_ram(box))
        for (uint32_t i = 0; i < count; ++i)
            rare_boost_entry(s, box + i * 4u, mult);
}

static void drop_roll_return(CPUState* s)
{
    if (g_drop_depth > 0 && --g_drop_depth == 0)
        rare_restore(s);
}

// --- Camera ------------------------------------------------------------------
//
// PSO GC only turns the camera with L (back behind the player). The follow
// camera keeps its heading until then, so the C-stick turns it by editing
// that heading each frame.

#define CSTICK_DEADZONE 20
#define CSTICK_MAX 110
#define CAMERA_DEG_PER_FRAME 3.0f

static void turn_camera(CPUState* s)
{
    const int speed = g_camera_speed;
    if (speed <= 0 || read_u8(s, ADDR_camera_view_state) != 0u)
        return;
    int cx = (int16_t)read_u16(s, ADDR_controller_input_state + OFS_pad0_cx);
    const int sign = cx < 0 ? -1 : 1;
    cx = cx * sign - CSTICK_DEADZONE;
    if (cx <= 0)
        return;
    if (cx > CSTICK_MAX - CSTICK_DEADZONE)
        cx = CSTICK_MAX - CSTICK_DEADZONE;
    const uint32_t cam = read_u32(s, ADDR_camera_controller_registry);
    if (!is_ram(cam) || read_u32(s, cam + OFS_cam_mode) != 1u)
        return;
    const float deg = CAMERA_DEG_PER_FRAME * (float)speed / 100.0f * (float)cx / (float)(CSTICK_MAX - CSTICK_DEADZONE);
    const int32_t delta = -(int32_t)(deg * 182.04445f) * sign; // stick right pans the view right
    const uint32_t heading = read_u32(s, cam + OFS_cam_heading);
    write_u32(s, cam + OFS_cam_heading, (uint32_t)(uint16_t)(heading + (uint32_t)delta));
}

// --- Per frame ---------------------------------------------------------------

static void player_run_task(CPUState* s)
{
    if (g_drop_depth != 0 || g_rare_count != 0u) {
        rare_restore(s); // a drop roll's return was missed
        g_drop_depth = 0;
    }
    const uint32_t p = s->gpr[3];
    if (!is_local_player(s, p))
        return;
    turn_camera(s);
    if (g_hp_tp)
        refill(s, p);
    if (g_meseta) {
        const uint32_t st = stats_block(s, p);
        if (st != 0u)
            write_u32(s, st + OFS_stats_meseta, MAX_MESETA);
    }
}

// --- Hits ----------------------------------------------------------------------
//
// A hit subtracts HP and marks the player dead at 0 in the same call, so
// refilling once a frame isn't enough: HP is raised above any hit while the
// hit is worked out, then set back to full.

static uint32_t g_hit_player;

static void hit_entry(CPUState* s)
{
    if (!g_hp_tp || !is_local_player(s, s->gpr[3]))
        return;
    g_hit_player = s->gpr[3];
    write_u16(s, g_hit_player + OFS_hp, HP_DURING_HIT);
}

static void hit_return(CPUState* s)
{
    if (g_hit_player == 0u)
        return;
    refill(s, g_hit_player);
    g_hit_player = 0u;
}

// --- EXP -----------------------------------------------------------------------
//
// The extra EXP is added before the game adds its own amount, so the game's
// level-limit clamp still applies. If the game added nothing (EXP is off in
// some areas), the extra is taken back. The runtime can dispatch one call
// twice (same stack pointer and return address); the repeat is ignored.

static uint32_t g_exp_stats, g_exp_before, g_exp_boosted;
static uint32_t g_exp_sp, g_exp_lr;
static int g_popup_mult;      // an enemy kill's EXP was boosted; its popup is next
static int g_popup_call;      // create_font_small_task is making that popup

static void exp_entry(CPUState* s)
{
    if (g_exp_stats != 0u && g_exp_sp == s->gpr[1] && g_exp_lr == s->lr)
        return; // the same call again
    g_exp_stats = 0u;
    g_popup_mult = 0;
    const int mult = g_exp_mult;
    const int32_t amount = (int32_t)s->gpr[4];
    if (mult <= 1 || amount <= 0 || !is_local_player(s, s->gpr[3]))
        return;
    const uint32_t st = stats_block(s, s->gpr[3]);
    if (st == 0u)
        return;
    const uint32_t before = read_u32(s, st + OFS_stats_exp);
    uint64_t boosted = (uint64_t)before + (uint64_t)amount * (uint64_t)(mult - 1);
    if (boosted > 99999999u)
        boosted = 99999999u;
    g_exp_stats = st;
    g_exp_sp = s->gpr[1];
    g_exp_lr = s->lr;
    g_exp_before = before;
    g_exp_boosted = (uint32_t)boosted;
    write_u32(s, st + OFS_stats_exp, g_exp_boosted);
    if (s->lr == LR_award_exp_add)
        g_popup_mult = mult;
}

static void exp_return(CPUState* s)
{
    if (g_exp_stats == 0u)
        return;
    if (read_u32(s, g_exp_stats + OFS_stats_exp) == g_exp_boosted) {
        write_u32(s, g_exp_stats + OFS_stats_exp, g_exp_before);
        g_popup_mult = 0; // no EXP was given, so nothing to show
    }
    g_exp_stats = 0u;
}

// The "+EXP" popup gets the game's own amount, so its text is rewritten with
// the boosted one once the popup exists.

static void popup_entry(CPUState* s)
{
    g_popup_call = g_popup_mult > 1 && s->lr == LR_award_exp_popup;
}

static void popup_return(CPUState* s)
{
    if (!g_popup_call)
        return;
    g_popup_call = 0;
    const int mult = g_popup_mult;
    g_popup_mult = 0;
    const uint32_t task = s->gpr[3];
    if (!is_ram(task))
        return;
    char text[FONT_TEXT_LEN + 1];
    uint32_t len = 0;
    while (len < FONT_TEXT_LEN && (text[len] = (char)read_u8(s, task + OFS_font_text + len)) != 0)
        ++len;
    text[len] = 0;
    uint32_t digits = len;
    while (digits > 0 && text[digits - 1] >= '0' && text[digits - 1] <= '9')
        --digits;
    if (digits == len)
        return;
    uint64_t amount = (uint64_t)strtoul(text + digits, NULL, 10) * (uint64_t)mult;
    if (amount > 99999999u)
        amount = 99999999u;
    char number[12];
    const int n = snprintf(number, sizeof number, "%u", (unsigned)amount);
    if (n <= 0 || digits + (uint32_t)n >= FONT_TEXT_LEN)
        return;
    for (int i = 0; i <= n; ++i)
        write_u8(s, task + OFS_font_text + digits + (uint32_t)i, (uint8_t)number[i]);
    // Digits are about equally wide; widen the text by the extra ones.
    union { uint32_t u; float f; } w;
    w.u = read_u32(s, task + OFS_font_width);
    if (w.f > 0.0f && len > 0u) {
        w.f = w.f * (float)(digits + (uint32_t)n) / (float)len;
        write_u32(s, task + OFS_font_width, w.u);
    }
#ifdef PSO_CHEATS_DYLIB
    fprintf(stderr, "[cheats] popup '%s' -> '%.*s%s'\n", text, (int)digits, text, number);
#endif
}

// --- Mag -------------------------------------------------------------------

static void is_mag_full_entry(CPUState* s)
{
    const uint32_t mag = s->gpr[3];
    if (!g_mag || !is_ram(mag))
        return;
    write_u32(s, mag + OFS_mag_fullness_frames, 0u);
    write_u32(s, mag + OFS_mag_feeds_while_full, 0u);
}

static const ModernGekkoModHook hooks[] = {
    RECOMP_HOOK(ADDR_TObjPlayer_run_task, player_run_task),
    RECOMP_HOOK(ADDR_receive_physical_attack, hit_entry),
    RECOMP_HOOK_RETURN(ADDR_receive_physical_attack, hit_return),
    RECOMP_HOOK(ADDR_receive_direct_attack, hit_entry),
    RECOMP_HOOK_RETURN(ADDR_receive_direct_attack, hit_return),
    RECOMP_HOOK(ADDR_receive_weapon_special_attack, hit_entry),
    RECOMP_HOOK_RETURN(ADDR_receive_weapon_special_attack, hit_return),
    RECOMP_HOOK(ADDR_TObjPlayer_add_actor_exp, exp_entry),
    RECOMP_HOOK_RETURN(ADDR_TObjPlayer_add_actor_exp, exp_return),
    RECOMP_HOOK(ADDR_create_font_small_task, popup_entry),
    RECOMP_HOOK_RETURN(ADDR_create_font_small_task, popup_return),
    RECOMP_HOOK(ADDR_is_mag_full, is_mag_full_entry),
    RECOMP_HOOK(ADDR_select_enemy_drop, drop_roll_entry),
    RECOMP_HOOK_RETURN(ADDR_select_enemy_drop, drop_roll_return),
    RECOMP_HOOK(ADDR_select_box_item, drop_roll_entry),
    RECOMP_HOOK_RETURN(ADDR_select_box_item, drop_roll_return),
};

// On the Mac: PSO_CHEATS=meseta,hp,mag,exp=4,rare=8 (any subset).
static void on_load(const ModernGekkoModHostApi* api)
{
    (void)api;
    const char* env = getenv("PSO_CHEATS");
    if (!env)
        return;
    pso_cheats_set_infinite_meseta(strstr(env, "meseta") != NULL);
    pso_cheats_set_infinite_hp_tp(strstr(env, "hp") != NULL);
    pso_cheats_set_mag_always_hungry(strstr(env, "mag") != NULL);
    const char* e = strstr(env, "exp=");
    if (e)
        pso_cheats_set_exp_multiplier(atoi(e + 4));
    const char* c = strstr(env, "cam=");
    if (c)
        pso_cheats_set_camera_speed(atoi(c + 4));
    const char* r = strstr(env, "rare=");
    if (r)
        pso_cheats_set_rare_multiplier(atoi(r + 5));
}

static const ModernGekkoModDesc descriptor = {
    MODERNGEKKO_MOD_ABI_VERSION, MODERNGEKKO_CPU_ABI_VERSION, sizeof(CPUState),
    "GPOE8P", "pso_cheats", "1.0.0", "Cheats",
    0, 0u,
    0, 0u,
    hooks, (uint32_t)(sizeof hooks / sizeof hooks[0]),
    0, 0u,
    0, 0u,
    0, 0u,
    0, 0u,
    on_load, 0,
};

const ModernGekkoModDesc* pso_cheats_descriptor(void) { return &descriptor; }

#ifdef PSO_CHEATS_DYLIB
MODERNGEKKO_MOD_EXPORT const ModernGekkoModDesc* moderngekko_get_mod(void) { return &descriptor; }
#endif
