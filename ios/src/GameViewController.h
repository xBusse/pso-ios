#pragma once

#import <UIKit/UIKit.h>

// Hosts the Metal view the game renders into, the touch controls, and
// hardware controller input. Boots the game once its files are in place.
@interface PSOGameViewController : UIViewController
- (void)setPaused:(BOOL)paused;
@end
