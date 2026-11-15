#import <UIKit/UIKit.h>

#import "GameViewController.h"

@interface PSOAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow* window;
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

  self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
  self.window.rootViewController = [[PSOGameViewController alloc] init];
  [self.window makeKeyAndVisible];
  return YES;
}

- (PSOGameViewController*)game
{
  return (PSOGameViewController*)self.window.rootViewController;
}

- (void)applicationWillResignActive:(UIApplication*)application
{
  [[self game] setPaused:YES];
}

- (void)applicationDidBecomeActive:(UIApplication*)application
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
