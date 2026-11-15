#pragma once

#import <GameController/GameController.h>
#import <UIKit/UIKit.h>

// The app's menus: a start screen in the style of the LAS Recompiled launcher
// (rounded display font, gradient text, a feathered highlight band behind the
// selected item), usable by touch or with a controller.

UIFont* PSOFont(CGFloat size);

// The start screen background: Documents/background.(png|jpg) if the user put
// one there, else a generated one.
UIImage* PSOBackgroundImage(CGSize size);

// Text with a soft drop shadow and a top-to-bottom colour gradient.
UIImage* PSOTextImage(NSString* text, UIFont* font, UIColor* top, UIColor* bottom, CGFloat shadow);

UIColor* PSOColor(int r, int g, int b, int a);

// ---- Menu items -------------------------------------------------------------

@interface PSOMenuItem : NSObject
@property(nonatomic, copy) NSString* title;
@property(nonatomic, copy) NSString* help;
@property(nonatomic, copy) void (^activate)(void);
// Choice rows: the current value, and how to change it (-1 / +1).
@property(nonatomic, copy) NSString* (^value)(void);
@property(nonatomic, copy) void (^adjust)(NSInteger delta);
@property(nonatomic, copy) BOOL (^enabled)(void);

+ (instancetype)action:(NSString*)title help:(NSString*)help run:(void (^)(void))run;
+ (instancetype)choice:(NSString*)title
                  help:(NSString*)help
                 value:(NSString* (^)(void))value
                adjust:(void (^)(NSInteger delta))adjust;
@end

// ---- Controller routing -----------------------------------------------------

// Menu navigation from a controller. The topmost registered target gets it;
// with none, the raw pad goes to `gameHandler`.
@protocol PSOPadTarget <NSObject>
- (void)padMoveX:(NSInteger)dx y:(NSInteger)dy;
- (void)padConfirm;
- (void)padBack;
@end

@interface PSOPad : NSObject
+ (void)pushTarget:(id<PSOPadTarget>)target;
+ (void)removeTarget:(id<PSOPadTarget>)target;
// Pad state for the game, while no menu is up.
@property(class, nonatomic, copy) void (^gameHandler)(GCExtendedGamepad* pad);
// The controller's menu/options button while no menu is up.
@property(class, nonatomic, copy) void (^menuHandler)(void);
+ (BOOL)controllerConnected;
@end

// ---- Menu list --------------------------------------------------------------

@interface PSOMenuView : UIView
@property(nonatomic, copy) NSArray<PSOMenuItem*>* items;
@property(nonatomic) NSInteger selectedIndex;
@property(nonatomic) CGFloat fontSize;
@property(nonatomic) CGFloat leftInset;
@property(nonatomic) CGFloat valueColumn;  // x of the value, from leftInset; 0 = right after the title
@property(nonatomic, copy) void (^selectionChanged)(PSOMenuItem* item);
- (void)reload;
- (void)refreshValues;
- (void)moveSelection:(NSInteger)delta;
- (void)adjustSelection:(NSInteger)delta;
- (void)activateSelection;
- (CGFloat)contentHeight;
@end

// ---- A menu page ------------------------------------------------------------

@interface PSOPageViewController : UIViewController <PSOPadTarget>
@property(nonatomic, copy) NSString* pageTitle;
@property(nonatomic, copy) NSString* subtitle;
@property(nonatomic, copy) NSArray<PSOMenuItem*>* items;
@property(nonatomic) BOOL overGame;      // translucent, over the paused game
@property(nonatomic) BOOL smallItems;    // settings-style rows
@property(nonatomic) CGFloat valueColumn;
@property(nonatomic, copy) void (^onBack)(void);
@property(nonatomic, readonly) UILabel* statusLabel;   // bottom left, above the footer
@property(nonatomic, readonly) UILabel* footerLabel;   // bottom left
@property(nonatomic, readonly) UILabel* cornerLabel;   // bottom right
@property(nonatomic, readonly) PSOMenuView* menu;
- (void)refresh;
// Back to the previous page (or onBack, if set).
- (void)goBack;
// Presents `page` over this one with a crossfade.
- (void)showPage:(UIViewController*)page;
@end
