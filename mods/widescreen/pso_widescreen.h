#pragma once

#ifdef __cplusplus
extern "C" {
#endif

struct ModernGekkoModDesc;

// The mod's descriptor, for registering it in-process (RuntimeConfig::attached_mods).
const struct ModernGekkoModDesc* pso_widescreen_descriptor(void);

// How much wider than 4:3 the picture is: screen aspect / (4/3). 1 turns the
// mod off. Takes effect at the next frame; safe to call from any thread.
void pso_widescreen_set_factor(float widen);

// Size of the HUD (status panel, action palette, radar, START menu windows),
// 1 = the game's own; each piece is scaled about its screen corner. Also works
// in 4:3.
void pso_widescreen_set_hud_scale(float scale);

// Whether the action palette is on screen (in the field, outside menus and dialogs).
int pso_widescreen_action_palette_visible(void);

#ifdef __cplusplus
}
#endif
