#import "Settings.h"

#import <AVFoundation/AVFoundation.h>

NSNotificationName const PSOSettingsDidChangeNotification = @"PSOSettingsDidChange";

static NSUserDefaults* Defaults()
{
  return NSUserDefaults.standardUserDefaults;
}

static NSInteger IntegerOr(NSString* key, NSInteger fallback)
{
  id v = [Defaults() objectForKey:key];
  return [v isKindOfClass:NSNumber.class] ? [v integerValue] : fallback;
}

static void Set(NSString* key, id value)
{
  [Defaults() setObject:value forKey:key];
  [NSNotificationCenter.defaultCenter postNotificationName:PSOSettingsDidChangeNotification object:nil];
}

static CGSize s_screen = CGSizeMake(16, 9);

@implementation PSOSettings

+ (PSODisplayMode)displayMode
{
  return (PSODisplayMode)MAX(0, MIN(3, IntegerOr(@"displayMode", PSODisplayFill)));
}
+ (void)setDisplayMode:(PSODisplayMode)v
{
  Set(@"displayMode", @(v));
  [self applyToGameWithScreenSize:s_screen];
}

+ (NSInteger)resolutionScale
{
  return MAX(1, MIN(4, IntegerOr(@"resolutionScale", 2)));
}
+ (void)setResolutionScale:(NSInteger)v
{
  Set(@"resolutionScale", @(MAX(1, MIN(4, v))));
  [self applyToGameWithScreenSize:s_screen];
}

+ (NSInteger)volume
{
  return MAX(0, MIN(100, IntegerOr(@"volume", 100)));
}
+ (void)setVolume:(NSInteger)v
{
  Set(@"volume", @(MAX(0, MIN(100, v))));
  PSOSetVolume((int)self.volume);
}

+ (NSInteger)hudScale
{
  return MAX(50, MIN(150, IntegerOr(@"hudScale", 100)));
}
+ (void)setHudScale:(NSInteger)v
{
  Set(@"hudScale", @(MAX(50, MIN(150, v))));
  PSOSetHUDScale((int)self.hudScale);
}

+ (BOOL)rToggle
{
  return [Defaults() boolForKey:@"rToggle"];
}
+ (void)setRToggle:(BOOL)v
{
  Set(@"rToggle", @(v));
  PSOSetRToggle(v);
}

+ (BOOL)playWhenSilent
{
  return [Defaults() boolForKey:@"playWhenSilent"];
}
+ (void)setPlayWhenSilent:(BOOL)v
{
  Set(@"playWhenSilent", @(v));
  [self applyAudioSession];
}

+ (PSOTouchVisibility)touchVisibility
{
  return (PSOTouchVisibility)MAX(0, MIN(2, IntegerOr(@"touchVisibility", PSOTouchVisibilityAuto)));
}
+ (void)setTouchVisibility:(PSOTouchVisibility)v
{
  Set(@"touchVisibility", @(v));
}

+ (CGFloat)touchOpacity
{
  id v = [Defaults() objectForKey:@"touchOpacity"];
  const CGFloat o = [v isKindOfClass:NSNumber.class] ? [v doubleValue] : 0.45;
  return MAX(0.1, MIN(1.0, o));
}
+ (void)setTouchOpacity:(CGFloat)v
{
  Set(@"touchOpacity", @(MAX(0.1, MIN(1.0, v))));
}

+ (NSDictionary*)touchLayout
{
  id v = [Defaults() objectForKey:@"touchLayout"];
  return [v isKindOfClass:NSDictionary.class] ? v : @{};
}
+ (void)setTouchLayout:(NSDictionary*)layout
{
  Set(@"touchLayout", layout ?: @{});
}

+ (NSString*)displayModeName:(PSODisplayMode)mode
{
  switch (mode)
  {
  case PSODisplayOriginal: return @"Original 4:3";
  case PSODisplayWidescreen: return @"Widescreen 16:9";
  case PSODisplayFill: return @"Fill screen";
  case PSODisplayStretch: return @"Stretch 4:3";
  }
  return @"";
}

+ (void)applyToGameWithScreenSize:(CGSize)size
{
  if (size.width > 0 && size.height > 0)
    s_screen = size;
  // Landscape: the long side is the width.
  const int w = (int)lround(MAX(s_screen.width, s_screen.height));
  const int h = (int)lround(MIN(s_screen.width, s_screen.height));
  PSOSetVideoSettings(self.displayMode, w, h, (int)self.resolutionScale);
  PSOSetVolume((int)self.volume);
  PSOSetHUDScale((int)self.hudScale);
  PSOSetRToggle(self.rToggle);
}

+ (void)applyAudioSession
{
  AVAudioSession* session = AVAudioSession.sharedInstance;
  if (self.playWhenSilent)
    [session setCategory:AVAudioSessionCategoryPlayback
                    mode:AVAudioSessionModeDefault
                 options:AVAudioSessionCategoryOptionMixWithOthers
                   error:nil];
  else
    [session setCategory:AVAudioSessionCategoryAmbient error:nil];
  [session setActive:YES error:nil];
}

@end
