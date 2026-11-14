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

#ifdef __cplusplus
}
#endif
