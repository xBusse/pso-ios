#pragma once

#import "PSOUI.h"

// Where the game files and Dolphin's user folder live (in Documents).
NSString* PSOGameDirectory(void);
NSString* PSOUserDirectory(void);
BOOL PSOGameFilesReady(void);

// The settings page. `overGame`: shown from the in-game menu.
PSOPageViewController* PSOMakeSettingsPage(BOOL overGame);

// The start screen: PLAY, SETTINGS, CONTROLS, GAME FILES.
@interface PSOLauncherViewController : PSOPageViewController
@end
