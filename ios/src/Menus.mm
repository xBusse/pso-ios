#import "Menus.h"

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#import "GameViewController.h"
#import "PSOHost.h"
#import "Settings.h"
#import "TouchEditor.h"

static NSString* Documents()
{
  return NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
}

NSString* PSOGameDirectory(void)
{
  return [Documents() stringByAppendingPathComponent:@"pso"];
}

NSString* PSOUserDirectory(void)
{
  NSString* user = [Documents() stringByAppendingPathComponent:@"User"];
  [NSFileManager.defaultManager createDirectoryAtPath:user withIntermediateDirectories:YES attributes:nil error:nil];
  return user;
}

static BOOL IsGameFolder(NSString* path)
{
  NSFileManager* fm = NSFileManager.defaultManager;
  return [fm fileExistsAtPath:[path stringByAppendingPathComponent:@"sys/main.dol"]] &&
         [fm fileExistsAtPath:[path stringByAppendingPathComponent:@"files/PsoV3.dol"]];
}

BOOL PSOGameFilesReady(void)
{
  return IsGameFolder(PSOGameDirectory());
}

static NSArray<NSString*>* DiscExtensions()
{
  return @[ @"iso", @"gcm", @"ciso", @"gcz", @"rvz", @"wia" ];
}

// A disc image the user dropped into the app's folder with the Files app.
static NSString* DiscImageInDocuments()
{
  for (NSString* name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:Documents() error:nil])
  {
    if ([DiscExtensions() containsObject:name.pathExtension.lowercaseString])
      return [Documents() stringByAppendingPathComponent:name];
  }
  return nil;
}

// ---- Settings ------------------------------------------------------------------------

static NSString* OnOff(BOOL on, NSString* yes, NSString* no)
{
  return on ? yes : no;
}

// Steps through `values` (wrapping) from `current`.
static NSInteger Cycle(NSArray<NSNumber*>* values, NSInteger current, NSInteger d)
{
  NSInteger i = (NSInteger)[values indexOfObject:@(current)];
  if (i == NSNotFound)
    i = 0;
  const NSInteger n = (NSInteger)values.count;
  return values[(NSUInteger)(((i + d) % n + n) % n)].integerValue;
}

static NSString* Multiplier(NSInteger m)
{
  return m <= 1 ? @"Off" : [NSString stringWithFormat:@"%ldx", (long)m];
}

static PSOPageViewController* MakeModsPage(BOOL overGame)
{
  PSOPageViewController* page = [PSOPageViewController new];
  page.pageTitle = @"Mods";
  page.overGame = overGame;
  page.smallItems = YES;
  page.valueColumn = 8.2;
  __weak PSOPageViewController* weakPage = page;

  page.items = @[
    [PSOMenuItem choice:@"INFINITE MESETA"
                   help:@"Keeps your meseta at 999,999."
                  value:^{
                    return OnOff(PSOSettings.infiniteMeseta, @"On", @"Off");
                  }
                 adjust:^(NSInteger) {
                   PSOSettings.infiniteMeseta = !PSOSettings.infiniteMeseta;
                 }],
    [PSOMenuItem choice:@"INFINITE HP / TP"
                   help:@"Keeps HP and TP full. Hits still knock you down but can't kill you."
                  value:^{
                    return OnOff(PSOSettings.infiniteHpTp, @"On", @"Off");
                  }
                 adjust:^(NSInteger) {
                   PSOSettings.infiniteHpTp = !PSOSettings.infiniteHpTp;
                 }],
    [PSOMenuItem choice:@"MAG ALWAYS HUNGRY"
                   help:@"Feed your mag any time, without waiting between feedings."
                  value:^{
                    return OnOff(PSOSettings.magAlwaysHungry, @"On", @"Off");
                  }
                 adjust:^(NSInteger) {
                   PSOSettings.magAlwaysHungry = !PSOSettings.magAlwaysHungry;
                 }],
    [PSOMenuItem choice:@"EXP BOOST"
                   help:@"Multiplies the EXP you earn."
                  value:^{
                    return Multiplier(PSOSettings.expMultiplier);
                  }
                 adjust:^(NSInteger d) {
                   PSOSettings.expMultiplier = Cycle(PSOSettings.expMultipliers, PSOSettings.expMultiplier, d);
                 }],
    [PSOMenuItem choice:@"RARE DROP BOOST"
                   help:@"Multiplies the chance of rare items from enemies and boxes."
                  value:^{
                    return Multiplier(PSOSettings.rareMultiplier);
                  }
                 adjust:^(NSInteger d) {
                   PSOSettings.rareMultiplier = Cycle(PSOSettings.rareMultipliers, PSOSettings.rareMultiplier, d);
                 }],
    [PSOMenuItem action:@"BACK" help:nil run:^{
      [weakPage goBack];
    }],
  ];
  return page;
}

PSOPageViewController* PSOMakeSettingsPage(BOOL overGame)
{
  PSOPageViewController* page = [PSOPageViewController new];
  page.pageTitle = @"Settings";
  page.overGame = overGame;
  page.smallItems = YES;
  page.valueColumn = 8.2;
  __weak PSOPageViewController* weakPage = page;

  page.items = @[
    [PSOMenuItem choice:@"DISPLAY"
                   help:@"Fill screen widens the 3D view to the whole screen and moves the HUD and the START "
                        @"menu to its corners. Original keeps the GameCube picture with bars at the sides."
                  value:^{
                    return [PSOSettings displayModeName:PSOSettings.displayMode];
                  }
                 adjust:^(NSInteger d) {
                   PSOSettings.displayMode = (PSODisplayMode)((PSOSettings.displayMode + d + 4) % 4);
                 }],
    [PSOMenuItem choice:@"RESOLUTION"
                   help:@"How sharp the 3D is drawn. Higher looks better but uses more battery and gets warmer."
                  value:^{
                    const NSInteger s = PSOSettings.resolutionScale;
                    return s == 1 ? @"1x (GameCube)" : [NSString stringWithFormat:@"%ldx", (long)s];
                  }
                 adjust:^(NSInteger d) {
                   PSOSettings.resolutionScale = (PSOSettings.resolutionScale - 1 + d + 4) % 4 + 1;
                 }],
    [PSOMenuItem choice:@"HUD SIZE"
                   help:@"Size of the HP/TP panel, action palette, radar and START menu. Each stays in its corner."
                  value:^{
                    return [NSString stringWithFormat:@"%ld%%", (long)PSOSettings.hudScale];
                  }
                 adjust:^(NSInteger d) {
                   NSInteger v = PSOSettings.hudScale + d * 10;
                   PSOSettings.hudScale = v > 150 ? 50 : v < 50 ? 150 : v;
                 }],
    [PSOMenuItem choice:@"VOLUME"
                   help:nil
                  value:^{
                    return [NSString stringWithFormat:@"%ld%%", (long)PSOSettings.volume];
                  }
                 adjust:^(NSInteger d) {
                   NSInteger v = PSOSettings.volume + d * 10;
                   PSOSettings.volume = v > 100 ? 0 : v < 0 ? 100 : v;
                 }],
    [PSOMenuItem choice:@"SILENT MODE"
                   help:@"Whether the ring/silent switch mutes the game."
                  value:^{
                    return OnOff(PSOSettings.playWhenSilent, @"Sound stays on", @"Mutes the game");
                  }
                 adjust:^(NSInteger) {
                   PSOSettings.playWhenSilent = !PSOSettings.playWhenSilent;
                 }],
    [PSOMenuItem choice:@"R BUTTON"
                   help:@"Toggle: press R once to switch to the second row of actions and again to switch back, "
                        @"instead of holding it. Works on the touch pad and controllers."
                  value:^{
                    return OnOff(PSOSettings.rToggle, @"Toggle", @"Hold");
                  }
                 adjust:^(NSInteger) {
                   PSOSettings.rToggle = !PSOSettings.rToggle;
                 }],
    [PSOMenuItem choice:@"TOUCH CONTROLS"
                   help:@"Auto hides the on-screen pad while a controller is connected."
                  value:^{
                    switch (PSOSettings.touchVisibility)
                    {
                    case PSOTouchVisibilityAuto: return @"Auto";
                    case PSOTouchVisibilityAlways: return @"Always";
                    case PSOTouchVisibilityNever: return @"Hidden";
                    }
                    return @"";
                  }
                 adjust:^(NSInteger d) {
                   PSOSettings.touchVisibility = (PSOTouchVisibility)((PSOSettings.touchVisibility + d + 3) % 3);
                 }],
    [PSOMenuItem choice:@"TOUCH OPACITY"
                   help:@"How visible the on-screen pad is. Single buttons can be changed in the layout editor."
                  value:^{
                    return [NSString stringWithFormat:@"%d%%", (int)lround(PSOSettings.touchOpacity * 100)];
                  }
                 adjust:^(NSInteger d) {
                   PSOSettings.touchOpacity = PSOSettings.touchOpacity + d * 0.05;
                 }],
    [PSOMenuItem action:@"EDIT TOUCH LAYOUT"
                   help:@"Move, resize and fade the on-screen buttons."
                    run:^{
                      PSOTouchEditorViewController* editor = [PSOTouchEditorViewController new];
                      editor.overGame = overGame;
                      editor.onDone = ^{
                        weakPage.view.alpha = 1;
                        [weakPage refresh];
                      };
                      [weakPage presentViewController:editor animated:YES completion:^{
                        weakPage.view.alpha = 0;
                      }];
                    }],
    [PSOMenuItem action:@"MODS"
                   help:@"Cheats: infinite meseta, infinite HP/TP, a mag you can always feed, EXP and rare drop "
                        @"boosts."
                    run:^{
                      [weakPage showPage:MakeModsPage(overGame)];
                    }],
    [PSOMenuItem action:@"BACK" help:nil run:^{
      [weakPage goBack];
    }],
  ];
  return page;
}

// ---- Game files ----------------------------------------------------------------------

@interface PSOGameFilesPage : PSOPageViewController <UIDocumentPickerDelegate>
@end

@implementation PSOGameFilesPage
{
  BOOL _busy;
  BOOL _pickingFolder;
  NSString* _message;
  BOOL _failed;
}

- (instancetype)init
{
  if ((self = [super init]))
  {
    self.pageTitle = @"Game Files";
    self.smallItems = YES;
    __weak PSOGameFilesPage* weakSelf = self;
    BOOL (^idle)(void) = ^{
      PSOGameFilesPage* s = weakSelf;
      return (BOOL)(s && !s->_busy);
    };

    PSOMenuItem* disc = [PSOMenuItem action:@"IMPORT DISC IMAGE"
                                       help:@"Pick your PSO Episode I & II Plus disc image (ISO, CISO, GCZ, RVZ) "
                                            @"from Files or iCloud Drive. The app extracts it (about 1.4 GB)."
                                        run:^{
                                          [weakSelf pickDisc];
                                        }];
    disc.enabled = idle;
    PSOMenuItem* local = [PSOMenuItem action:@"USE DISC IMAGE IN APP FOLDER"
                                        help:@"Extract a disc image you copied into On My iPhone → PSO with the "
                                             @"Files app or Finder."
                                         run:^{
                                           [weakSelf extractLocal];
                                         }];
    local.enabled = ^{
      return (BOOL)(idle() && DiscImageInDocuments() != nil);
    };
    PSOMenuItem* folder = [PSOMenuItem action:@"IMPORT EXTRACTED FOLDER"
                                         help:@"Pick a \"pso\" folder made with `make extract` on a Mac. Some "
                                              @"sideloading tools can't open folders; use a disc image then."
                                          run:^{
                                            [weakSelf pickFolder];
                                          }];
    folder.enabled = idle;
    PSOMenuItem* remove = [PSOMenuItem action:@"DELETE GAME FILES"
                                         help:@"Frees about 1.4 GB. Saves and settings are kept."
                                          run:^{
                                            [weakSelf confirmDelete];
                                          }];
    remove.enabled = ^{
      return (BOOL)(idle() && PSOGameFilesReady());
    };
    PSOMenuItem* back = [PSOMenuItem action:@"BACK" help:nil run:^{
      [weakSelf goBack];
    }];
    back.enabled = idle;
    self.items = @[ disc, local, folder, remove, back ];
  }
  return self;
}

- (void)refresh
{
  [super refresh];
  UILabel* status = self.statusLabel;
  if (_message)
  {
    status.text = _message;
    status.textColor = _failed ? PSOColor(255, 128, 102, 255) : _busy ? PSOColor(237, 194, 84, 255)
                                                                      : PSOColor(115, 242, 140, 255);
  }
  else if (PSOGameFilesReady())
  {
    status.text = @"✓ Game files ready.";
    status.textColor = PSOColor(115, 242, 140, 255);
  }
  else
  {
    status.text = @"No game files yet. Import your disc image.";
    status.textColor = PSOColor(237, 194, 84, 255);
  }
  self.footerLabel.text = @"Phantasy Star Online Episode I & II Plus · USA v1.02 (GPOE8P)";
  [self.view setNeedsLayout];
}

- (void)setMessage:(NSString*)message failed:(BOOL)failed
{
  _message = [message copy];
  _failed = failed;
  [self refresh];
}

- (void)pickDisc
{
  UIDocumentPickerViewController* picker = nil;
  @try
  {
    picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[ UTTypeData ] asCopy:YES];
  }
  @catch (NSException* e)
  {
    [self setMessage:[NSString stringWithFormat:@"The file picker failed: %@", e.reason] failed:YES];
    return;
  }
  _pickingFolder = NO;
  picker.delegate = self;
  picker.allowsMultipleSelection = NO;
  [self presentViewController:picker animated:YES completion:nil];
}

- (void)pickFolder
{
  // Some sideloading tools inject a "file picker fix" that forces asCopy:YES,
  // which UIKit rejects for folders with an exception.
  UIDocumentPickerViewController* picker = nil;
  @try
  {
    picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[ UTTypeFolder ] asCopy:NO];
  }
  @catch (NSException* e)
  {
    picker = nil;
  }
  if (!picker)
  {
    [self setMessage:@"This copy of the app can't open folders (the sideloading tool's file picker fix). "
                     @"Import a disc image instead."
              failed:YES];
    return;
  }
  _pickingFolder = YES;
  picker.delegate = self;
  picker.allowsMultipleSelection = NO;
  [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController*)controller didPickDocumentsAtURLs:(NSArray<NSURL*>*)urls
{
  NSURL* picked = urls.firstObject;
  if (!picked || _busy)
    return;
  if (_pickingFolder)
    [self importFolder:picked];
  else
    [self extract:picked deleteAfter:YES];
}

- (void)beginBusy:(NSString*)message
{
  _busy = YES;
  UIApplication.sharedApplication.idleTimerDisabled = YES;
  [self setMessage:message failed:NO];
}

- (void)endBusy:(NSString*)error success:(NSString*)success
{
  _busy = NO;
  UIApplication.sharedApplication.idleTimerDisabled = NO;
  [self setMessage:error ?: success failed:error != nil];
}

- (void)extractLocal
{
  NSString* image = DiscImageInDocuments();
  if (image)
    [self extract:[NSURL fileURLWithPath:image] deleteAfter:NO];
}

- (void)extract:(NSURL*)url deleteAfter:(BOOL)deleteAfter
{
  [self beginBusy:@"Extracting game files… keep the app open."];
  const BOOL scoped = [url startAccessingSecurityScopedResource];
  __weak PSOGameFilesPage* weakSelf = self;
  PSOExtractDisc(
      url.path, PSOGameDirectory(),
      ^(double fraction) {
        [weakSelf setMessage:[NSString stringWithFormat:@"Extracting game files… %d%%  (keep the app open)",
                                                        (int)(fraction * 100)]
                      failed:NO];
      },
      ^(NSString* error) {
        if (scoped)
          [url stopAccessingSecurityScopedResource];
        // The picker's copy is ours to remove; an image in Documents is the user's.
        if (deleteAfter)
          [NSFileManager.defaultManager removeItemAtURL:url error:nil];
        [weakSelf endBusy:error
                  success:deleteAfter ? @"✓ Game files ready."
                                      : @"✓ Game files ready. You can delete the disc image from the app folder."];
      });
}

- (void)importFolder:(NSURL*)picked
{
  [self beginBusy:@"Copying game files… keep the app open."];
  NSString* dest = PSOGameDirectory();
  __weak PSOGameFilesPage* weakSelf = self;
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    const BOOL scoped = [picked startAccessingSecurityScopedResource];
    __block NSString* problem = nil;
    NSFileCoordinator* coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    NSError* coordError = nil;
    // A coordinated read makes iCloud Drive download the folder first.
    [coordinator coordinateReadingItemAtURL:picked
                                    options:0
                                      error:&coordError
                                 byAccessor:^(NSURL* url) {
                                   NSString* source = url.path;
                                   if (!IsGameFolder(source))
                                     source = [source stringByAppendingPathComponent:@"pso"];
                                   if (!IsGameFolder(source))
                                   {
                                     problem = @"That folder isn't the PSO game files. Pick the \"pso\" folder "
                                               @"with \"sys\" and \"files\" inside.";
                                     return;
                                   }
                                   NSFileManager* fm = NSFileManager.defaultManager;
                                   [fm removeItemAtPath:dest error:nil];
                                   NSError* copyError = nil;
                                   if (![fm copyItemAtPath:source toPath:dest error:&copyError])
                                     problem = [NSString stringWithFormat:@"Couldn't copy the game files: %@",
                                                                          copyError.localizedDescription];
                                 }];
    if (scoped)
      [picked stopAccessingSecurityScopedResource];
    if (!problem && coordError)
      problem = [NSString stringWithFormat:@"Couldn't read the folder: %@", coordError.localizedDescription];
    dispatch_async(dispatch_get_main_queue(), ^{
      [weakSelf endBusy:problem success:@"✓ Game files ready."];
    });
  });
}

- (void)confirmDelete
{
  UIAlertController* alert =
      [UIAlertController alertControllerWithTitle:@"Delete the game files?"
                                          message:@"You'll need to import the disc again to play. Saves are kept."
                                   preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
  [alert addAction:[UIAlertAction actionWithTitle:@"Delete"
                                            style:UIAlertActionStyleDestructive
                                          handler:^(UIAlertAction*) {
                                            [NSFileManager.defaultManager removeItemAtPath:PSOGameDirectory()
                                                                                     error:nil];
                                            [self setMessage:nil failed:NO];
                                          }]];
  [self presentViewController:alert animated:YES completion:nil];
}

- (void)goBack
{
  if (!_busy)
    [super goBack];
}
@end

// ---- Start screen ---------------------------------------------------------------------

@implementation PSOLauncherViewController

- (instancetype)init
{
  if ((self = [super init]))
  {
    self.pageTitle = @"Phantasy Star Online";
    self.subtitle = @"Episode I & II Plus";
    __weak PSOLauncherViewController* weakSelf = self;
    self.items = @[
      [PSOMenuItem action:@"PLAY" help:nil run:^{
        [weakSelf play];
      }],
      [PSOMenuItem action:@"SETTINGS" help:nil run:^{
        [weakSelf showPage:PSOMakeSettingsPage(NO)];
      }],
      [PSOMenuItem action:@"CONTROLS" help:nil run:^{
        PSOTouchEditorViewController* editor = [PSOTouchEditorViewController new];
        editor.onDone = ^{
          weakSelf.view.alpha = 1;
        };
        [weakSelf presentViewController:editor animated:YES completion:^{
          weakSelf.view.alpha = 0;
        }];
      }],
      [PSOMenuItem action:@"GAME FILES" help:nil run:^{
        [weakSelf showPage:[PSOGameFilesPage new]];
      }],
    ];
  }
  return self;
}

- (void)refresh
{
  [super refresh];
  NSString* version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"";
  self.footerLabel.text = [NSString stringWithFormat:@"GameCube · USA v1.02  ·  iOS v%@", version];
  self.cornerLabel.text = @"Static recomp";
  if (PSOGameFilesReady())
  {
    self.statusLabel.text = @"✓ Game files ready.";
    self.statusLabel.textColor = PSOColor(115, 242, 140, 255);
  }
  else if (DiscImageInDocuments())
  {
    self.statusLabel.text = @"Disc image found. Open GAME FILES to extract it.";
    self.statusLabel.textColor = PSOColor(237, 194, 84, 255);
  }
  else
  {
    self.statusLabel.text = @"No game files yet. Open GAME FILES to import your disc.";
    self.statusLabel.textColor = PSOColor(237, 194, 84, 255);
  }
}

- (void)viewDidAppear:(BOOL)animated
{
  [super viewDidAppear:animated];
  [self refresh];
}

- (void)play
{
  if (!PSOGameFilesReady())
  {
    [self showPage:[PSOGameFilesPage new]];
    return;
  }
  PSOGameViewController* game = PSOGameViewController.current ?: [PSOGameViewController new];
  [PSOPad removeTarget:self];
  [self presentViewController:game animated:YES completion:^{
    [game start];
  }];
}

// The start screen is the root: nothing to go back to.
- (void)goBack
{
}
@end
