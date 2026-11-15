#pragma once

#import <UIKit/UIKit.h>

// Hosts the Metal view the game renders into, the touch controls and the
// in-game menu, and feeds controller input to the game.
@interface PSOGameViewController : UIViewController
// The game screen once it exists (there's only ever one: one runtime per process).
@property(class, nonatomic, readonly) PSOGameViewController* current;

// Boots the game. Call once, after the view is on screen.
- (void)start;

// App lifecycle: pause when the app goes inactive; resume (and restore audio) when it's back.
- (void)appWillResignActive;
- (void)appDidBecomeActive;
@end
