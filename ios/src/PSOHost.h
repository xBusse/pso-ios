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

// Restarts audio output after an interruption (phone call, Siri, another app).
void PSORestartAudio(void);

bool PSOIsGameRunning(void);

// Extracts a GameCube disc image (ISO, CISO, GCZ, RVZ, WIA) into `dest` in the
// layout the game expects, checking it's the right game. `progress` (0..1) and
// `done` run on the main queue; `error` is nil on success.
void PSOExtractDisc(NSString* image_path, NSString* dest, void (^progress)(double fraction),
                    void (^done)(NSString* error));

#ifdef __cplusplus
}
#endif
