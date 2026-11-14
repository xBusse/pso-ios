#import "GameViewController.h"

#import <AVFoundation/AVFoundation.h>
#import <GameController/GameController.h>
#import <QuartzCore/CAMetalLayer.h>

#import "PSOHost.h"
#import "TouchControls.h"

@interface PSOMetalView : UIView
@end

@implementation PSOMetalView
+ (Class)layerClass
{
  return [CAMetalLayer class];
}
@end

@implementation PSOGameViewController
{
  PSOMetalView* _metalView;
  PSOTouchControls* _touchControls;
  UILabel* _message;
  BOOL _started;
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

  _message = [[UILabel alloc] initWithFrame:CGRectInset(root.bounds, 40, 40)];
  _message.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  _message.textColor = UIColor.whiteColor;
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
  [center addObserver:self selector:@selector(controllersChanged) name:GCControllerDidConnectNotification object:nil];
  [center addObserver:self selector:@selector(controllersChanged) name:GCControllerDidDisconnectNotification object:nil];
  [self controllersChanged];
}

- (void)viewDidAppear:(BOOL)animated
{
  [super viewDidAppear:animated];
  if (!_started)
    [self startIfReady];
}

- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }
- (UIRectEdge)preferredScreenEdgesDeferringSystemGestures { return UIRectEdgeAll; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskLandscape; }

- (NSString*)documentsDirectory
{
  return NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
}

- (void)showMessage:(NSString*)text
{
  _message.text = text;
  _message.hidden = NO;
  _touchControls.hidden = YES;
}

- (void)startIfReady
{
  NSString* docs = [self documentsDirectory];
  NSString* game = [docs stringByAppendingPathComponent:@"pso"];
  NSString* user = [docs stringByAppendingPathComponent:@"User"];
  NSFileManager* fm = NSFileManager.defaultManager;

  if (![fm fileExistsAtPath:[game stringByAppendingPathComponent:@"sys/main.dol"]] ||
      ![fm fileExistsAtPath:[game stringByAppendingPathComponent:@"files/PsoV3.dol"]])
  {
    [self showMessage:@"Game files not found.\n\nCopy the \"pso\" folder from pso-ios/extracted on your Mac "
                      @"into this app's files (Finder → your iPhone → Files → PSO), then reopen the app."];
    return;
  }
  [fm createDirectoryAtPath:user withIntermediateDirectories:YES attributes:nil error:nil];

  NSString* module = [NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:@PSO_MODULE_FILE];

  [AVAudioSession.sharedInstance setCategory:AVAudioSessionCategoryAmbient error:nil];
  [AVAudioSession.sharedInstance setActive:YES error:nil];
  UIApplication.sharedApplication.idleTimerDisabled = YES;

  PSOSetRenderLayer((CAMetalLayer*)_metalView.layer, (float)UIScreen.mainScreen.nativeScale);
  _started = YES;
  __weak PSOGameViewController* weakSelf = self;
  PSOStartGame(game, user, module, ^(NSString* error) {
    UIApplication.sharedApplication.idleTimerDisabled = NO;
    [weakSelf showMessage:error ? error : @"The game has stopped. Reopen the app to play again."];
  });
}

- (void)setPaused:(BOOL)paused
{
  if (_started)
    PSOSetPaused(paused);
}

// ---- Hardware controllers ------------------------------------------------------

- (void)controllersChanged
{
  GCController* controller = nil;
  for (GCController* c in GCController.controllers)
  {
    if (c.extendedGamepad)
    {
      controller = c;
      break;
    }
  }
  _touchControls.hidden = controller != nil || !_message.hidden;
  if (!controller)
    return;

  controller.extendedGamepad.valueChangedHandler = ^(GCExtendedGamepad* pad, GCControllerElement*) {
    PSOSetInput(PSOInputStickX, pad.leftThumbstick.xAxis.value);
    PSOSetInput(PSOInputStickY, pad.leftThumbstick.yAxis.value);
    PSOSetInput(PSOInputCStickX, pad.rightThumbstick.xAxis.value);
    PSOSetInput(PSOInputCStickY, pad.rightThumbstick.yAxis.value);
    PSOSetInput(PSOInputDpadUp, pad.dpad.up.isPressed);
    PSOSetInput(PSOInputDpadDown, pad.dpad.down.isPressed);
    PSOSetInput(PSOInputDpadLeft, pad.dpad.left.isPressed);
    PSOSetInput(PSOInputDpadRight, pad.dpad.right.isPressed);
    // Same physical layout as a GameCube pad: A bottom, B left, X right, Y top.
    PSOSetInput(PSOInputA, pad.buttonA.isPressed);
    PSOSetInput(PSOInputB, pad.buttonX.isPressed);
    PSOSetInput(PSOInputX, pad.buttonB.isPressed);
    PSOSetInput(PSOInputY, pad.buttonY.isPressed);
    PSOSetInput(PSOInputL, pad.leftTrigger.value);
    PSOSetInput(PSOInputR, pad.rightTrigger.value);
    PSOSetInput(PSOInputZ, pad.rightShoulder.isPressed);
    PSOSetInput(PSOInputStart, pad.buttonMenu.isPressed);
  };
}

@end
