#import <UIKit/UIKit.h>

#import "GameViewController.h"

@interface PSOAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow* window;
@end

@implementation PSOAppDelegate

- (BOOL)application:(UIApplication*)application
    didFinishLaunchingWithOptions:(NSDictionary*)launchOptions
{
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
