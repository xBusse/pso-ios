#pragma once

#ifdef __cplusplus
extern "C" {
#endif

struct ModernGekkoModDesc;

// The mod's descriptor, for registering it in-process (RuntimeConfig::attached_mods).
const struct ModernGekkoModDesc* pso_cheats_descriptor(void);

// All take effect at once and are safe to call from any thread. They apply
// to the local player (player slot 0, i.e. offline play).

// Meseta held at 999,999.
void pso_cheats_set_infinite_meseta(int on);

// HP and TP kept full, and hits never take you below full HP.
void pso_cheats_set_infinite_hp_tp(int on);

// The mag can always be fed (the item menu never shows it as full).
void pso_cheats_set_mag_always_hungry(int on);

// Multiplies the EXP you earn (1 = off). Still capped at the level limit.
void pso_cheats_set_exp_multiplier(int multiplier);

// Multiplies the chance of rare drops from enemies and boxes (1 = off).
void pso_cheats_set_rare_multiplier(int multiplier);

#ifdef __cplusplus
}
#endif
