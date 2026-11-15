#import "GameViewController.h"

#import <GameController/GameController.h>
#import <QuartzCore/CAMetalLayer.h>

#import "Menus.h"
#import "PSOHost.h"
#import "PSOUI.h"
#import "Settings.h"
#import "TouchControls.h"
#import "TouchEditor.h"

@interface PSOMetalView : UIView
@end

@implementation PSOMetalView
+ (Class)layerClass
{
  return [CAMetalLayer class];
}
@end

static __weak PSOGameViewController* s_current;

@implementation PSOGameViewController
{
  PSOMetalView* _metalView;
  PSOTouchControls* _touchControls;
  UIButton* _menuButton;
  UILabel* _message;
  BOOL _started;
  BOOL _menuOpen;
  BOOL _stopped;
  BOOL _quitting;
  PSOPadButton _padMap[8];  // controller button for each of PSOSettings.mappableInputs
}

+ (PSOGameViewController*)current
{
  return s_current;
}

- (instancetype)init
{
  if ((self = [super init]))
  {
    self.modalPresentationStyle = UIModalPresentationFullScreen;
    self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    s_current = self;
  }
  return self;
}

- (void)loadView
{
  UIView* root = [[UIView alloc] initWithFrame:UIScreen.mainScreen.bounds];
  root.backgroundColor = UIColor.blackColor;

  _metalView = [[PSOMetalView alloc] initWithFrame:root.bounds];
  _metalView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  _metalView.contentScaleFactor = UIScreen.mainScreen.nativeScale;
  ((CAMetalLayer*)_metalView.layer).contentsScale = UIScreen.mainScreen.nativeScale;
  [root addSubview:_metalView];

  _touchControls = [[PSOTouchControls alloc] initWithFrame:root.bounds];
  _touchControls.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  [root addSubview:_touchControls];

  _menuButton = [UIButton buttonWithType:UIButtonTypeCustom];
  UIImageSymbolConfiguration* config = [UIImageSymbolConfiguration configurationWithPointSize:16
                                                                                       weight:UIImageSymbolWeightBold];
  [_menuButton setImage:[UIImage systemImageNamed:@"line.3.horizontal" withConfiguration:config]
               forState:UIControlStateNormal];
  _menuButton.tintColor = UIColor.whiteColor;
  _menuButton.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
  _menuButton.layer.cornerRadius = 18;
  _menuButton.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.6].CGColor;
  _menuButton.layer.borderWidth = 1.5;
  [_menuButton addTarget:self action:@selector(openMenu) forControlEvents:UIControlEventTouchUpInside];
  [root addSubview:_menuButton];

  _message = [UILabel new];
  _message.textColor = UIColor.whiteColor;
  _message.font = PSOFont(20);
  _message.numberOfLines = 0;
  _message.textAlignment = NSTextAlignmentCenter;
  _message.hidden = YES;
  [root addSubview:_message];

  self.view = root;
}

- (void)viewDidLoad
{
  [super viewDidLoad];
  NSNotificationCenter* center = NSNotificationCenter.defaultCenter;
  [center addObserver:self selector:@selector(updateOverlay) name:GCControllerDidConnectNotification object:nil];
  [center addObserver:self selector:@selector(updateOverlay) name:GCControllerDidDisconnectNotification object:nil];
  [center addObserver:self selector:@selector(updateOverlay) name:PSOSettingsDidChangeNotification object:nil];
  [center addObserver:self selector:@selector(loadPadMap) name:PSOSettingsDidChangeNotification object:nil];
  [self loadPadMap];

  __weak PSOGameViewController* weakSelf = self;
  PSOPad.gameHandler = ^(GCExtendedGamepad* pad) {
    [weakSelf padChanged:pad];
  };
  PSOPad.menuHandler = ^{
    [weakSelf openMenu];
  };
}

- (void)viewDidLayoutSubviews
{
  [super viewDidLayoutSubviews];
  const CGRect b = self.view.bounds;
  const UIEdgeInsets safe = self.view.safeAreaInsets;
  _menuButton.frame = CGRectMake(CGRectGetMidX(b) - 18, MAX(safe.top, 6) + 4, 36, 36);
  _message.frame = CGRectInset(b, 60, 40);
  [self updateOverlay];
}

- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }
- (UIRectEdge)preferredScreenEdgesDeferringSystemGestures { return UIRectEdgeAll; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskLandscape; }

- (void)updateOverlay
{
  BOOL showTouch = YES;
  switch (PSOSettings.touchVisibility)
  {
  case PSOTouchVisibilityAuto: showTouch = !PSOPad.controllerConnected; break;
  case PSOTouchVisibilityAlways: showTouch = YES; break;
  case PSOTouchVisibilityNever: showTouch = NO; break;
  }
  const BOOL playing = _started && !_stopped && !_menuOpen;
  if (_touchControls.hidden != !(showTouch && playing))
  {
    [_touchControls releaseAll];
    _touchControls.hidden = !(showTouch && playing);
  }
  _menuButton.hidden = !playing;
  _menuButton.alpha = MAX(0.3, MIN(1.0, PSOSettings.touchOpacity * 1.4));
}

// ---- Running the game ------------------------------------------------------------

- (void)start
{
  if (_started)
    return;
  _started = YES;
  [self loadViewIfNeeded];
  [self.view layoutIfNeeded];

  [PSOSettings applyAudioSession];
  [PSOSettings applyToGameWithScreenSize:self.view.bounds.size];
  UIApplication.sharedApplication.idleTimerDisabled = YES;

  PSOSetRenderLayer((CAMetalLayer*)_metalView.layer, (float)UIScreen.mainScreen.nativeScale);
  __weak PSOGameViewController* weakSelf = self;
  PSOStartGame(PSOGameDirectory(), PSOUserDirectory(),
               [NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:@PSO_MODULE_FILE],
               ^(NSString* error) {
                 [weakSelf gameStopped:error];
               });
  [self updateOverlay];
}

- (void)gameStopped:(NSString*)error
{
  _stopped = YES;
  UIApplication.sharedApplication.idleTimerDisabled = NO;
  if (_quitting && !error)
    exit(0);  // only one game can run per launch, so Quit closes the app
  if (self.presentedViewController)
    [self dismissViewControllerAnimated:NO completion:nil];
  _menuOpen = NO;
  _message.text = error ? error : @"The game has stopped. Reopen the app to play again.";
  _message.hidden = NO;
  [self updateOverlay];
}

- (void)appWillResignActive
{
  if (_started && !_stopped)
    PSOSetPaused(true);
}

- (void)appDidBecomeActive
{
  [PSOSettings applyAudioSession];
  if (_started && !_stopped && !_menuOpen)
    PSOSetPaused(false);
  PSORestartAudio();
}

// ---- In-game menu ------------------------------------------------------------------

- (void)openMenu
{
  if (!_started || _stopped || _menuOpen)
    return;
  _menuOpen = YES;
  PSOClearAllInputs();
  [_touchControls releaseAll];
  PSOSetPaused(true);
  [self updateOverlay];

  PSOPageViewController* menu = [PSOPageViewController new];
  menu.overGame = YES;
  menu.pageTitle = @"Paused";
  __weak PSOGameViewController* weakSelf = self;
  __weak PSOPageViewController* weakMenu = menu;
  menu.onBack = ^{
    [weakSelf closeMenu];
  };
  menu.items = @[
    [PSOMenuItem action:@"RESUME" help:nil run:^{
      [weakSelf closeMenu];
    }],
    [PSOMenuItem action:@"SETTINGS" help:@"Display, sound, R button, touch controls."
                    run:^{
                      [weakMenu showPage:PSOMakeSettingsPage(YES)];
                    }],
    [PSOMenuItem action:@"EDIT TOUCH CONTROLS" help:@"Move, resize and fade the on-screen buttons."
                    run:^{
                      PSOTouchEditorViewController* editor = [PSOTouchEditorViewController new];
                      editor.overGame = YES;
                      editor.onDone = ^{
                        weakMenu.view.alpha = 1;
                      };
                      [weakMenu presentViewController:editor animated:YES completion:^{
                        weakMenu.view.alpha = 0;
                      }];
                    }],
    [PSOMenuItem action:@"QUIT GAME" help:@"Stops the game and closes the app. Save in the game first."
                    run:^{
                      [weakSelf confirmQuitFrom:weakMenu];
                    }],
  ];
  [self presentViewController:menu animated:YES completion:nil];
}

- (void)closeMenu
{
  if (!_menuOpen)
    return;
  [self dismissViewControllerAnimated:YES completion:^{
    self->_menuOpen = NO;
    if (!self->_stopped)
      PSOSetPaused(false);
    [self updateOverlay];
  }];
}

- (void)confirmQuitFrom:(UIViewController*)presenter
{
  UIAlertController* alert =
      [UIAlertController alertControllerWithTitle:@"Quit the game?"
                                          message:@"Anything since your last save in the game is lost. The app "
                                                  @"closes; open it again to play."
                                   preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
  [alert addAction:[UIAlertAction actionWithTitle:@"Quit"
                                            style:UIAlertActionStyleDestructive
                                          handler:^(UIAlertAction*) {
                                            self->_quitting = YES;
                                            PSOSetPaused(false);
                                            PSORequestStop();
                                          }]];
  [presenter presentViewController:alert animated:YES completion:nil];
}

// ---- Controllers -----------------------------------------------------------------

- (void)loadPadMap
{
  NSArray<NSNumber*>* inputs = PSOSettings.mappableInputs;
  for (NSUInteger i = 0; i < inputs.count && i < 8; ++i)
    _padMap[i] = [PSOSettings controllerButtonFor:(PSOInput)inputs[i].intValue];
}

static GCControllerButtonInput* PadElement(GCExtendedGamepad* pad, PSOPadButton b)
{
  switch (b)
  {
  case PSOPadA: return pad.buttonA;
  case PSOPadB: return pad.buttonB;
  case PSOPadX: return pad.buttonX;
  case PSOPadY: return pad.buttonY;
  case PSOPadLB: return pad.leftShoulder;
  case PSOPadRB: return pad.rightShoulder;
  case PSOPadLT: return pad.leftTrigger;
  case PSOPadRT: return pad.rightTrigger;
  case PSOPadL3: return pad.leftThumbstickButton;
  case PSOPadR3: return pad.rightThumbstickButton;
  case PSOPadMenu: return pad.buttonMenu;
  default: return nil;
  }
}

- (void)padChanged:(GCExtendedGamepad*)pad
{
  if (!_started || _stopped || _menuOpen)
    return;
  PSOSetInput(PSOInputStickX, pad.leftThumbstick.xAxis.value);
  PSOSetInput(PSOInputStickY, pad.leftThumbstick.yAxis.value);
  PSOSetInput(PSOInputCStickX, pad.rightThumbstick.xAxis.value);
  PSOSetInput(PSOInputCStickY, pad.rightThumbstick.yAxis.value);
  PSOSetInput(PSOInputDpadUp, pad.dpad.up.isPressed);
  PSOSetInput(PSOInputDpadDown, pad.dpad.down.isPressed);
  PSOSetInput(PSOInputDpadLeft, pad.dpad.left.isPressed);
  PSOSetInput(PSOInputDpadRight, pad.dpad.right.isPressed);
  // Buttons as mapped in Settings > Controller. L and R keep a trigger's
  // analog travel; the rest are on/off.
  NSArray<NSNumber*>* inputs = PSOSettings.mappableInputs;
  for (NSUInteger i = 0; i < inputs.count && i < 8; ++i)
  {
    const PSOInput input = (PSOInput)inputs[i].intValue;
    GCControllerButtonInput* e = PadElement(pad, _padMap[i]);
    const bool analog = input == PSOInputL || input == PSOInputR;
    PSOSetInput(input, !e ? 0 : analog ? e.value : (e.isPressed ? 1 : 0));
  }
}

@end
