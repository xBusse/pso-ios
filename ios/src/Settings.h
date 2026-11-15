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

@interface PSOSettings : NSObject
@property(class, nonatomic) PSODisplayMode displayMode;
@property(class, nonatomic) NSInteger resolutionScale;  // 1..4 (x native)
@property(class, nonatomic) NSInteger volume;           // 0..100
@property(class, nonatomic) NSInteger hudScale;         // 50..150 (% of the game's HUD size)
@property(class, nonatomic) BOOL rToggle;
@property(class, nonatomic) BOOL playWhenSilent;        // ignore the ring/silent switch
@property(class, nonatomic) PSOTouchVisibility touchVisibility;
@property(class, nonatomic) CGFloat touchOpacity;       // 0.1..1, all controls

// Per-control overrides from the layout editor: id -> {x, y (fraction of the
// safe area), scale, opacity}. Missing keys use the defaults.
+ (NSDictionary<NSString*, NSDictionary<NSString*, NSNumber*>*>*)touchLayout;
+ (void)setTouchLayout:(NSDictionary<NSString*, NSDictionary<NSString*, NSNumber*>*>*)layout;

+ (NSString*)displayModeName:(PSODisplayMode)mode;

// Pushes everything to the game side (safe before and during play).
+ (void)applyToGameWithScreenSize:(CGSize)size;
// Sets the audio session category for the current silent-switch setting.
+ (void)applyAudioSession;
@end
