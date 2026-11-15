#import "GameViewController.h"

#import <AVFoundation/AVFoundation.h>
#import <GameController/GameController.h>
#import <QuartzCore/CAMetalLayer.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

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

@interface PSOGameViewController () <UIDocumentPickerDelegate>
@end

@implementation PSOGameViewController
{
  PSOMetalView* _metalView;
  PSOTouchControls* _touchControls;
  UILabel* _message;
  UIButton* _importButton;
  BOOL _started;
  BOOL _importing;
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

  _importButton = [UIButton buttonWithType:UIButtonTypeSystem];
  [_importButton setTitle:@"Import game files…" forState:UIControlStateNormal];
  _importButton.titleLabel.font = [UIFont boldSystemFontOfSize:20];
  _importButton.frame = CGRectMake(0, 0, 260, 50);
  _importButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin |
                                   UIViewAutoresizingFlexibleTopMargin;
  _importButton.center = CGPointMake(CGRectGetMidX(root.bounds), CGRectGetMaxY(root.bounds) - 60);
  _importButton.hidden = YES;
  [_importButton addTarget:self action:@selector(chooseGameFolder) forControlEvents:UIControlEventTouchUpInside];
  [root addSubview:_importButton];

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
  _importButton.hidden = YES;
}

// ---- Game files ------------------------------------------------------------------

+ (BOOL)isGameFolder:(NSURL*)url
{
  NSFileManager* fm = NSFileManager.defaultManager;
  return [fm fileExistsAtPath:[url URLByAppendingPathComponent:@"sys/main.dol"].path] &&
         [fm fileExistsAtPath:[url URLByAppendingPathComponent:@"files/PsoV3.dol"].path];
}

- (void)chooseGameFolder
{
  // Some sideloading tools inject a "file picker fix" that forces asCopy:YES,
  // which UIKit rejects for folders with an exception. Fall back to the older
  // initializer, and failing that, point to the Files app instead of crashing.
  UIDocumentPickerViewController* picker = nil;
  @try
  {
    picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[ UTTypeFolder ] asCopy:NO];
  }
  @catch (NSException* e)
  {
    NSLog(@"PSO: folder picker failed (%@): %@", e.name, e.reason);
    picker = nil;
  }
  if (!picker)
  {
    @try
    {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
      picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[ @"public.folder" ]
                                                                       inMode:UIDocumentPickerModeOpen];
#pragma clang diagnostic pop
    }
    @catch (NSException* e)
    {
      NSLog(@"PSO: legacy folder picker failed (%@): %@", e.name, e.reason);
      picker = nil;
    }
  }
  if (!picker)
  {
    [self showMissingFiles:@"This copy of the app can't open the folder picker (the sideloading tool's "
                           @"file picker fix only allows single files). Turn that option off when signing, "
                           @"or copy the game files in with the Files app as described below."];
    return;
  }
  picker.delegate = self;
  picker.allowsMultipleSelection = NO;
  [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController*)controller didPickDocumentsAtURLs:(NSArray<NSURL*>*)urls
{
  NSURL* picked = urls.firstObject;
  if (!picked || _importing)
    return;
  _importing = YES;
  [self showMessage:@"Copying game files…\n\nThis takes a few minutes (about 1.4 GB). Keep the app open."];

  NSString* dest = [[self documentsDirectory] stringByAppendingPathComponent:@"pso"];
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    const BOOL scoped = [picked startAccessingSecurityScopedResource];
    __block NSError* error = nil;
    __block NSString* problem = nil;

    // A coordinated read makes iCloud Drive download the folder first.
    NSFileCoordinator* coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    NSError* coordError = nil;
    [coordinator coordinateReadingItemAtURL:picked
                                    options:0
                                      error:&coordError
                                 byAccessor:^(NSURL* url) {
                                   // Accept either the pso folder itself or a folder that contains it.
                                   NSURL* source = url;
                                   if (![PSOGameViewController isGameFolder:source])
                                     source = [url URLByAppendingPathComponent:@"pso"];
                                   if (![PSOGameViewController isGameFolder:source])
                                   {
                                     problem = @"That folder doesn't look like the PSO game files. Pick the "
                                               @"\"pso\" folder that has \"sys\" and \"files\" inside it.";
                                     return;
                                   }
                                   NSFileManager* fm = NSFileManager.defaultManager;
                                   [fm removeItemAtPath:dest error:nil];
                                   NSError* copyError = nil;
                                   if (![fm copyItemAtURL:source toURL:[NSURL fileURLWithPath:dest] error:&copyError])
                                     error = copyError;
                                 }];
    if (scoped)
      [picked stopAccessingSecurityScopedResource];
    if (!problem && (coordError || error))
      problem = [NSString stringWithFormat:@"Couldn't copy the game files: %@",
                                           (error ?: coordError).localizedDescription];

    dispatch_async(dispatch_get_main_queue(), ^{
      self->_importing = NO;
      if (problem)
      {
        [self showMissingFiles:problem];
        return;
      }
      self->_message.hidden = YES;
      [self controllersChanged];
      [self startIfReady];
    });
  });
}

- (void)showMissingFiles:(NSString*)detail
{
  NSString* text = @"Game files not found.\n\nTap Import and pick the \"pso\" folder (from iCloud Drive or "
                   @"anywhere in Files), or copy it into On My iPhone → PSO with the Files app or Finder.";
  if (detail)
    text = [detail stringByAppendingFormat:@"\n\n%@", text];
  [self showMessage:text];
  _importButton.hidden = NO;
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
    [self showMissingFiles:nil];
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
