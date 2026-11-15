#import <UIKit/UIKit.h>

#import "GameViewController.h"

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
    [@"Copy the \"pso\" game folder (with \"sys\" and \"files\" inside) into this folder,\n"
     @"or use Import in the app.\n" writeToFile:readme atomically:YES encoding:NSUTF8StringEncoding error:nil];
  }
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
  self.window.rootViewController = [[PSOGameViewController alloc] init];
  [self.window makeKeyAndVisible];
}

- (PSOGameViewController*)game
{
  return (PSOGameViewController*)self.window.rootViewController;
}

- (void)sceneWillResignActive:(UIScene*)scene
{
  [[self game] setPaused:YES];
}

- (void)sceneDidBecomeActive:(UIScene*)scene
{
  [[self game] setPaused:NO];
}

@end

int main(int argc, char* argv[])
{
  @autoreleasepool
  {
    return UIApplicationMain(argc, argv, nil, NSStringFromClass([PSOAppDelegate class]));
  }
}
