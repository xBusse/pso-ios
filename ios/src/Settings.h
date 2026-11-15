#pragma once

#import <UIKit/UIKit.h>

#import "PSOHost.h"

// User settings, saved in NSUserDefaults. Changing one posts
// PSOSettingsDidChangeNotification and pushes it to the game.
extern NSNotificationName const PSOSettingsDidChangeNotification;

typedef NS_ENUM(NSInteger, PSOTouchVisibility) {
  PSOTouchVisibilityAuto = 0,  // hidden while a controller is connected
  PSOTouchVisibilityAlways,
  PSOTouchVisibilityNever,
};

typedef NS_ENUM(NSInteger, PSOStickMode) {
  PSOStickAlways = 0,    // drawn all the time
  PSOStickWhileTouched,  // in its place, drawn only while held
  PSOStickFloating,      // appears where the thumb lands on the left half
};

// Controller buttons the GameCube buttons can be mapped to. Options/Home stay
// reserved for the pause menu.
typedef NS_ENUM(NSInteger, PSOPadButton) {
  PSOPadNone = 0,
  PSOPadA,  // bottom face button
  PSOPadB,  // right
  PSOPadX,  // left
  PSOPadY,  // top
  PSOPadLB,
  PSOPadRB,
  PSOPadLT,
  PSOPadRT,
  PSOPadL3,
  PSOPadR3,
  PSOPadMenu,
  PSOPadButtonCount,
};

@interface PSOSettings : NSObject
@property(class, nonatomic) PSODisplayMode displayMode;
@property(class, nonatomic) NSInteger resolutionScale;  // 1..4 (x native)
@property(class, nonatomic) NSInteger volume;           // 0..100
@property(class, nonatomic) NSInteger hudScale;         // 50..150 (% of the game's HUD size)
@property(class, nonatomic) BOOL rToggle;
@property(class, nonatomic) BOOL playWhenSilent;        // ignore the ring/silent switch
@property(class, nonatomic) PSOTouchVisibility touchVisibility;
@property(class, nonatomic) CGFloat touchOpacity;       // 0.1..1, all controls
@property(class, nonatomic) PSOStickMode stickMode;
@property(class, nonatomic) BOOL tapPalette;    // tapping the game's action palette presses its button
@property(class, nonatomic) BOOL cameraSwipe;
@property(class, nonatomic) NSInteger cameraSpeed;  // percent, one of cameraSpeeds
+ (NSArray<NSNumber*>*)cameraSpeeds;   // dragging on empty space (right half) turns the camera

// Mods (cheats).
@property(class, nonatomic) BOOL infiniteMeseta;
@property(class, nonatomic) BOOL infiniteHpTp;
@property(class, nonatomic) BOOL magAlwaysHungry;
@property(class, nonatomic) NSInteger expMultiplier;   // 1 = off
@property(class, nonatomic) NSInteger rareMultiplier;  // 1 = off
+ (NSArray<NSNumber*>*)expMultipliers;
+ (NSArray<NSNumber*>*)rareMultipliers;

// Per-control overrides from the layout editor: id -> {x, y (fraction of the
// safe area), scale, opacity}. Missing keys use the defaults.
+ (NSDictionary<NSString*, NSDictionary<NSString*, NSNumber*>*>*)touchLayout;
+ (void)setTouchLayout:(NSDictionary<NSString*, NSDictionary<NSString*, NSNumber*>*>*)layout;

+ (NSString*)displayModeName:(PSODisplayMode)mode;

// Controller mapping: which controller button drives each GameCube button
// (A, B, X, Y, Z, L, R, Start; see mappableInputs). Sticks and D-pad are fixed.
+ (NSArray<NSNumber*>*)mappableInputs;
+ (NSString*)inputName:(PSOInput)input;
+ (NSString*)padButtonName:(PSOPadButton)button;
+ (PSOPadButton)controllerButtonFor:(PSOInput)input;
+ (void)setControllerButton:(PSOPadButton)button forInput:(PSOInput)input;
+ (void)resetControllerMap;

// Pushes everything to the game side (safe before and during play).
+ (void)applyToGameWithScreenSize:(CGSize)size;
// Sets the audio session category for the current silent-switch setting.
+ (void)applyAudioSession;
@end
