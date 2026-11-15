#pragma once

#import <UIKit/UIKit.h>

// On-screen GameCube pad: analog stick, D-pad, A/B/X/Y, L/R/Z and Start.
// Sends input through PSOSetInput/PSOClearInput. Positions, sizes and
// opacity come from PSOSettings and can be changed in editing mode.
@interface PSOTouchControls : UIView

// Layout editing: drag controls to move them; touches don't reach the game.
@property(nonatomic) BOOL editing;
@property(nonatomic, copy) void (^selectionChanged)(void);

@property(nonatomic, readonly) NSString* selectedName;  // nil: nothing selected
@property(nonatomic) CGFloat selectedScale;             // 0.5..2
@property(nonatomic) CGFloat selectedOpacity;           // 0..1, relative to the global opacity
@property(nonatomic) BOOL selectedHidden;               // removed from the pad (shown faintly while editing)
- (void)resetSelected;
- (void)resetAll;

// Releases anything held (when a menu opens over the game).
- (void)releaseAll;
@end
