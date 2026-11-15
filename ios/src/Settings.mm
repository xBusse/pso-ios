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

+ (PSOStickMode)stickMode
{
  return (PSOStickMode)MAX(0, MIN(2, IntegerOr(@"stickMode", PSOStickAlways)));
}
+ (void)setStickMode:(PSOStickMode)v
{
  Set(@"stickMode", @(v));
}

// ---- Controller mapping ----

+ (NSArray<NSNumber*>*)mappableInputs
{
  return @[ @(PSOInputA), @(PSOInputB), @(PSOInputX), @(PSOInputY), @(PSOInputZ), @(PSOInputL), @(PSOInputR),
            @(PSOInputStart) ];
}

+ (NSString*)inputName:(PSOInput)input
{
  switch (input)
  {
  case PSOInputA: return @"A";
  case PSOInputB: return @"B";
  case PSOInputX: return @"X";
  case PSOInputY: return @"Y";
  case PSOInputZ: return @"Z";
  case PSOInputL: return @"L";
  case PSOInputR: return @"R";
  case PSOInputStart: return @"START";
  default: return @"";
  }
}

+ (NSString*)padButtonName:(PSOPadButton)button
{
  switch (button)
  {
  case PSOPadNone: return @"None";
  case PSOPadA: return @"A / Cross (bottom)";
  case PSOPadB: return @"B / Circle (right)";
  case PSOPadX: return @"X / Square (left)";
  case PSOPadY: return @"Y / Triangle (top)";
  case PSOPadLB: return @"LB / L1";
  case PSOPadRB: return @"RB / R1";
  case PSOPadLT: return @"LT / L2";
  case PSOPadRT: return @"RT / R2";
  case PSOPadL3: return @"Left stick click";
  case PSOPadR3: return @"Right stick click";
  case PSOPadMenu: return @"Menu / Start";
  default: return @"";
  }
}

static PSOPadButton DefaultPadButton(PSOInput input)
{
  // Same physical layout as a GameCube pad: A bottom, B left, X right, Y top.
  switch (input)
  {
  case PSOInputA: return PSOPadA;
  case PSOInputB: return PSOPadX;
  case PSOInputX: return PSOPadB;
  case PSOInputY: return PSOPadY;
  case PSOInputZ: return PSOPadRB;
  case PSOInputL: return PSOPadLT;
  case PSOInputR: return PSOPadRT;
  case PSOInputStart: return PSOPadMenu;
  default: return PSOPadNone;
  }
}

+ (PSOPadButton)controllerButtonFor:(PSOInput)input
{
  NSDictionary* map = [Defaults() dictionaryForKey:@"controllerMap"];
  id v = map[[self inputName:input]];
  if (![v isKindOfClass:NSNumber.class])
    return DefaultPadButton(input);
  return (PSOPadButton)MAX(0, MIN(PSOPadButtonCount - 1, [v integerValue]));
}

+ (void)setControllerButton:(PSOPadButton)button forInput:(PSOInput)input
{
  NSMutableDictionary* map = [[Defaults() dictionaryForKey:@"controllerMap"] mutableCopy] ?: [NSMutableDictionary dictionary];
  map[[self inputName:input]] = @(button);
  Set(@"controllerMap", map);
}

+ (void)resetControllerMap
{
  Set(@"controllerMap", @{});
}

+ (NSArray<NSNumber*>*)cameraSpeeds
{
  return @[ @50, @75, @100, @150, @200, @250, @300, @400 ];
}
+ (NSInteger)cameraSpeed
{
  const NSInteger v = IntegerOr(@"cameraSpeed", 150);
  return [self.cameraSpeeds containsObject:@(v)] ? v : 150;
}
+ (void)setCameraSpeed:(NSInteger)v
{
  Set(@"cameraSpeed", @(v));
  PSOSetCameraSpeed((int)v);
}

+ (BOOL)tapPalette
{
  return IntegerOr(@"tapPalette", YES) != 0;
}
+ (void)setTapPalette:(BOOL)v
{
  Set(@"tapPalette", @(v));
}

+ (BOOL)cameraSwipe
{
  return IntegerOr(@"cameraSwipe", YES) != 0;
}
+ (void)setCameraSwipe:(BOOL)v
{
  Set(@"cameraSwipe", @(v));
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

// ---- Mods ----

static void ApplyCheats(void)
{
  if (!PSOSettings.cheatsAllowed)
  {
    PSOSetCheats(false, false, false, 1, 1);
    return;
  }
  PSOSetCheats(PSOSettings.infiniteMeseta, PSOSettings.infiniteHpTp, PSOSettings.magAlwaysHungry,
               (int)PSOSettings.expMultiplier, (int)PSOSettings.rareMultiplier);
}

// ---- Network ----

static NSString* StringOr(NSString* key, NSString* fallback)
{
  id v = [Defaults() objectForKey:key];
  return [v isKindOfClass:NSString.class] ? v : fallback;
}

static void ApplyNetwork(void)
{
  PSOSetNetwork(PSOSettings.networkMode, PSOSettings.networkServerAddress);
  ApplyCheats();
}

+ (PSONetworkMode)networkMode
{
  return (PSONetworkMode)MAX(0, MIN(2, IntegerOr(@"networkMode", PSONetworkOff)));
}
+ (void)setNetworkMode:(PSONetworkMode)v
{
  Set(@"networkMode", @(v));
  ApplyNetwork();
}

// Schthack's DNS, Dolphin's default: it points the game at their server.
+ (NSString*)defaultPublicServer
{
  return @"3.18.217.27";
}
+ (NSString*)publicServer
{
  return StringOr(@"publicServer", self.defaultPublicServer);
}
+ (void)setPublicServer:(NSString*)v
{
  NSString* t = [v stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  Set(@"publicServer", t.length ? t : self.defaultPublicServer);
  ApplyNetwork();
}

+ (NSString*)privateServer
{
  return StringOr(@"privateServer", @"");
}
+ (void)setPrivateServer:(NSString*)v
{
  Set(@"privateServer", [v stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"");
  ApplyNetwork();
}

+ (NSString*)networkServerAddress
{
  switch (self.networkMode)
  {
  case PSONetworkPublic: return self.publicServer;
  case PSONetworkPrivate: return self.privateServer;
  default: return @"";
  }
}

+ (BOOL)cheatsAllowed
{
  return self.networkMode != PSONetworkPublic;
}

static NSInteger OneOf(NSString* key, NSArray<NSNumber*>* allowed)
{
  const NSInteger v = IntegerOr(key, 1);
  return [allowed containsObject:@(v)] ? v : 1;
}

+ (BOOL)infiniteMeseta
{
  return [Defaults() boolForKey:@"infiniteMeseta"];
}
+ (void)setInfiniteMeseta:(BOOL)v
{
  Set(@"infiniteMeseta", @(v));
  ApplyCheats();
}

+ (BOOL)infiniteHpTp
{
  return [Defaults() boolForKey:@"infiniteHpTp"];
}
+ (void)setInfiniteHpTp:(BOOL)v
{
  Set(@"infiniteHpTp", @(v));
  ApplyCheats();
}

+ (BOOL)magAlwaysHungry
{
  return [Defaults() boolForKey:@"magAlwaysHungry"];
}
+ (void)setMagAlwaysHungry:(BOOL)v
{
  Set(@"magAlwaysHungry", @(v));
  ApplyCheats();
}

+ (NSArray<NSNumber*>*)expMultipliers
{
  return @[ @1, @2, @3, @5, @10 ];
}
+ (NSInteger)expMultiplier
{
  return OneOf(@"expMultiplier", self.expMultipliers);
}
+ (void)setExpMultiplier:(NSInteger)v
{
  Set(@"expMultiplier", @(v));
  ApplyCheats();
}

+ (NSArray<NSNumber*>*)rareMultipliers
{
  return @[ @1, @2, @4, @8, @16, @32 ];
}
+ (NSInteger)rareMultiplier
{
  return OneOf(@"rareMultiplier", self.rareMultipliers);
}
+ (void)setRareMultiplier:(NSInteger)v
{
  Set(@"rareMultiplier", @(v));
  ApplyCheats();
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
  PSOSetCameraSpeed((int)self.cameraSpeed);
  ApplyCheats();
  PSOSetNetwork(self.networkMode, self.networkServerAddress);
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
