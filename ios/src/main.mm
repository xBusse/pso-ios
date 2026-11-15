#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>

#import "GameViewController.h"
#import "Menus.h"
#import "PSOHost.h"
#import "PSOUI.h"
#import "Settings.h"

// iOS 27 requires the scene-based lifecycle: the app delegate only does
// process-wide setup, and the scene delegate owns the window.

@interface PSOAppDelegate : UIResponder <UIApplicationDelegate>
@end

@implementation PSOAppDelegate

- (BOOL)application:(UIApplication*)application
    didFinishLaunchingWithOptions:(NSDictionary*)launchOptions
{
  // Put something in Documents straight away so the app's folder appears in the
  // Files app (On My iPhone → PSO) and in Finder's Files tab.
  NSString* docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
  NSString* readme = [docs stringByAppendingPathComponent:@"Put the pso folder here.txt"];
  if (![NSFileManager.defaultManager fileExistsAtPath:readme])
  {
    [@"Put your PSO disc image (.iso, .ciso, .rvz, .gcz) here, then use Game Files in the app.\n"
     @"Or copy the extracted \"pso\" folder (with \"sys\" and \"files\" inside) here.\n"
     writeToFile:readme atomically:YES encoding:NSUTF8StringEncoding error:nil];
  }

  [PSOPad controllerConnected];  // starts listening for controllers
  [PSOSettings applyAudioSession];

  // Audio stops when a call, Siri or another app interrupts it, and doesn't
  // come back by itself: reactivate the session and restart the output.
  NSNotificationCenter* center = NSNotificationCenter.defaultCenter;
  [center addObserverForName:AVAudioSessionInterruptionNotification
                      object:nil
                       queue:NSOperationQueue.mainQueue
                  usingBlock:^(NSNotification* note) {
                    const NSUInteger type = [note.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];
                    if (type == AVAudioSessionInterruptionTypeEnded &&
                        UIApplication.sharedApplication.applicationState == UIApplicationStateActive)
                    {
                      [PSOSettings applyAudioSession];
                      PSORestartAudio();
                    }
                  }];
  [center addObserverForName:AVAudioSessionMediaServicesWereResetNotification
                      object:nil
                       queue:NSOperationQueue.mainQueue
                  usingBlock:^(NSNotification*) {
                    [PSOSettings applyAudioSession];
                    PSORestartAudio();
                  }];
  return YES;
}

- (UISceneConfiguration*)application:(UIApplication*)application
    configurationForConnectingSceneSession:(UISceneSession*)session
                                   options:(UISceneConnectionOptions*)options
{
  UISceneConfiguration* config = [[UISceneConfiguration alloc] initWithName:@"Default Configuration"
                                                                sessionRole:session.role];
  config.delegateClass = NSClassFromString(@"PSOSceneDelegate");
  return config;
}

@end

@interface PSOSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property(nonatomic, strong) UIWindow* window;
@end

@implementation PSOSceneDelegate

- (void)scene:(UIScene*)scene
    willConnectToSession:(UISceneSession*)session
                 options:(UISceneConnectionOptions*)connectionOptions
{
  if (![scene isKindOfClass:[UIWindowScene class]])
    return;
  self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene*)scene];
  self.window.rootViewController = [PSOLauncherViewController new];
  [self.window makeKeyAndVisible];
}

- (void)sceneWillResignActive:(UIScene*)scene
{
  [PSOGameViewController.current appWillResignActive];
}

- (void)sceneDidBecomeActive:(UIScene*)scene
{
  [PSOGameViewController.current appDidBecomeActive];
}

@end

int main(int argc, char* argv[])
{
  @autoreleasepool
  {
    return UIApplicationMain(argc, argv, nil, NSStringFromClass([PSOAppDelegate class]));
  }
}
