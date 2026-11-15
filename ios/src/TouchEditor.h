#pragma once

#import <UIKit/UIKit.h>

// Edits the on-screen pad: drag controls to move them, tap one to select it
// and change its size and opacity. Saved as you go.
@interface PSOTouchEditorViewController : UIViewController
@property(nonatomic) BOOL overGame;  // translucent, over the paused game
@property(nonatomic, copy) void (^onDone)(void);
@end
