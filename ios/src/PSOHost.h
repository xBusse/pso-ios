// Bridge between the UIKit side of the app and the ModernGekko runtime.
#pragma once

#import <Foundation/Foundation.h>
#import <QuartzCore/CAMetalLayer.h>

#ifdef __cplusplus
extern "C" {
#endif

// The layer Dolphin's Metal backend renders into. Set before PSOStartGame.
void PSOSetRenderLayer(CAMetalLayer* layer, float scale);

// Boots the game on a background thread. `on_exit` runs on the main queue
// when the runtime stops; `error` is nil on a normal exit.
void PSOStartGame(NSString* game_dir, NSString* user_dir, NSString* module_path,
                  void (^on_exit)(NSString* error));

void PSOSetPaused(bool paused);
// Whether this launch loaded the widescreen and cheats mods (Settings > Mods > LOAD MODS).
bool PSOModsLoaded(void);
void PSORequestStop(void);

// GameCube pad input for port 1, from the touch overlay or a controller.
// Buttons take 0/1; sticks and triggers take -1..1 / 0..1.
typedef enum
{
  PSOInputA,
  PSOInputB,
  PSOInputX,
  PSOInputY,
  PSOInputZ,
  PSOInputStart,
  PSOInputDpadUp,
  PSOInputDpadDown,
  PSOInputDpadLeft,
  PSOInputDpadRight,
  PSOInputL,
  PSOInputR,
  PSOInputStickX,
  PSOInputStickY,
  PSOInputCStickX,
  PSOInputCStickY,
} PSOInput;

void PSOSetInput(PSOInput input, double value);
void PSOClearInput(PSOInput input);
// Releases every input, including a latched R.
void PSOClearAllInputs(void);

// R as a toggle: each press flips it on/off instead of holding it.
void PSOSetRToggle(bool enabled);
bool PSOIsRLatched(void);
// Called on the main queue whenever the latched state changes.
void PSOSetRLatchHandler(void (^handler)(bool latched));

// Display: how the picture fits the screen.
typedef enum
{
  PSODisplayOriginal = 0,  // 4:3, black bars at the sides
  PSODisplayWidescreen,    // 16:9, wider view of the 3D scene
  PSODisplayFill,          // the whole screen, wider view of the 3D scene
  PSODisplayStretch,       // 4:3 picture stretched to the screen
} PSODisplayMode;

// Video and audio settings. Safe to call before the game starts (they're
// applied when it boots) or while it runs (applied live).
void PSOSetVideoSettings(PSODisplayMode mode, int screen_width, int screen_height, int resolution_scale);
void PSOSetVolume(int percent);
// HUD size in percent of the game's own (status panel, action palette, radar).
void PSOSetHUDScale(int percent);
// Cheats (mods/cheats), applied live. Multipliers of 1 are off.
void PSOSetCheats(bool infinite_meseta, bool infinite_hp_tp, bool mag_always_hungry, int exp_multiplier,
                  int rare_multiplier);
// How fast the C-stick turns the camera, in percent (mods/cheats).
void PSOSetCameraSpeed(int percent);

// Online play: which network adapter the GameCube gets.
typedef enum
{
  PSONetworkOff = 0,
  // Dolphin's built-in adapter: the game uses this phone's internet connection, and its DNS
  // lookups go to `address`, a PSO server's DNS that points the game at that server.
  PSONetworkPublic,
  // A tapserver link to a newserv server's IP stack simulator at `address` (host[:port], port
  // 5059 if left out). newserv gives the game its IP address itself.
  PSONetworkPrivate,
} PSONetworkMode;

// Safe before the game starts (applied at boot) or while it runs (the adapter is swapped,
// like unplugging and replugging it).
void PSOSetNetwork(PSONetworkMode mode, NSString* address);

// Restarts audio output after an interruption (phone call, Siri, another app).
void PSORestartAudio(void);

bool PSOIsGameRunning(void);
// Whether the action palette is on screen: in the field, not in a menu or dialog.
bool PSOIsActionPaletteVisible(void);

// Extracts a GameCube disc image (ISO, CISO, GCZ, RVZ, WIA) into `dest` in the
// layout the game expects, checking it's the right game. `progress` (0..1) and
// `done` run on the main queue; `error` is nil on success.
void PSOExtractDisc(NSString* image_path, NSString* dest, void (^progress)(double fraction),
                    void (^done)(NSString* error));

#ifdef __cplusplus
}
#endif
