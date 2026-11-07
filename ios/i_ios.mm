/*
** i_ios.mm: the iOS pieces the SDL backend expects from the Mac files
**
** - I_PickIWad_Cocoa: the game picker, a native list over the game
** - Mac_I_FatalError: an alert with the error before the app ends
**
** Both run before or outside the game loop, so they show a UIKit alert and
** spin the main run loop until it is answered.
*/

#import <UIKit/UIKit.h>

#include "cmdlib.h"
#include "i_interface.h"

static UIViewController* TopViewController()
{
	UIWindow* key = nil;
	for (UIScene* scene in UIApplication.sharedApplication.connectedScenes)
	{
		if (![scene isKindOfClass:UIWindowScene.class]) continue;
		for (UIWindow* w in ((UIWindowScene*)scene).windows)
		{
			if (w.isKeyWindow) { key = w; break; }
		}
		if (key) break;
	}
	if (!key) key = UIApplication.sharedApplication.windows.firstObject;
	UIViewController* vc = key.rootViewController;
	while (vc.presentedViewController) vc = vc.presentedViewController;
	return vc;
}

// Shows the alert and waits for an answer; returns the chosen action's index
static int RunAlert(UIAlertController* alert, NSArray<NSString*>* titles, int cancelIndex)
{
	__block int chosen = -1;
	for (NSUInteger i = 0; i < titles.count; i++)
	{
		const int index = (int)i;
		UIAlertActionStyle style = (index == cancelIndex) ? UIAlertActionStyleCancel : UIAlertActionStyleDefault;
		[alert addAction:[UIAlertAction actionWithTitle:titles[i] style:style handler:^(UIAlertAction*) { chosen = index; }]];
	}

	UIViewController* vc = TopViewController();
	static UIWindow* ownWindow = nil;
	if (vc == nil)
	{
		// Nothing on screen yet (the game window comes later): put up a
		// plain black window of our own to show the alert on
		UIWindowScene* windowScene = nil;
		for (UIScene* scene in UIApplication.sharedApplication.connectedScenes)
			if ([scene isKindOfClass:UIWindowScene.class]) { windowScene = (UIWindowScene*)scene; break; }
		ownWindow = windowScene ? [[UIWindow alloc] initWithWindowScene:windowScene]
		                        : [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
		ownWindow.rootViewController = [UIViewController new];
		ownWindow.rootViewController.view.backgroundColor = UIColor.blackColor;
		[ownWindow makeKeyAndVisible];
		vc = ownWindow.rootViewController;
	}
	if (alert.popoverPresentationController)
	{
		// iPad: an action sheet needs an anchor
		alert.popoverPresentationController.sourceView = vc.view;
		alert.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(vc.view.bounds), CGRectGetMidY(vc.view.bounds), 0, 0);
		alert.popoverPresentationController.permittedArrowDirections = 0;
	}
	[vc presentViewController:alert animated:YES completion:nil];

	while (chosen < 0)
	{
		@autoreleasepool
		{
			[[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
		}
	}
	if (ownWindow)
	{
		// Out of the way again before the game makes its own window
		ownWindow.hidden = YES;
		ownWindow = nil;
	}
	return chosen;
}

int I_PickIWad_Cocoa(WadStuff* wads, int numwads, bool showwin, int defaultiwad)
{
	if (numwads <= 1 || !showwin) return defaultiwad;

	UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Raze"
		message:@"Choose a game"
		preferredStyle:UIAlertControllerStyleActionSheet];

	NSMutableArray<NSString*>* titles = [NSMutableArray array];
	for (int i = 0; i < numwads; i++)
	{
		NSString* name = [NSString stringWithUTF8String:wads[i].Name.GetChars()];
		if (name == nil) name = @"?";
		if (i == defaultiwad) name = [name stringByAppendingString:@"  ✓"];
		[titles addObject:name];
	}
	[titles addObject:@"Quit"];

	const int chosen = RunAlert(alert, titles, numwads);
	printf("Game picker: chose %d of %d\n", chosen, numwads);
	return chosen < numwads ? chosen : -1;
}

void Mac_I_FatalError(const char* errortext)
{
	NSString* text = [NSString stringWithUTF8String:errortext ? errortext : ""];
	if (text == nil) text = [NSString stringWithCString:errortext encoding:NSISOLatin1StringEncoding];

	UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Raze: fatal error"
		message:text
		preferredStyle:UIAlertControllerStyleAlert];
	RunAlert(alert, @[ @"Exit" ], 0);
}

// Everything the engine prints goes to Files > On My iPhone > Raze >
// raze-log.txt (replaced at each launch), so a problem on the phone can be
// read and sent. Runs before main().
#include <stdio.h>
#include <unistd.h>
__attribute__((constructor)) static void IOS_LogToFile()
{
	NSString* docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
	if (docs == nil) return;
	const char* path = [[docs stringByAppendingPathComponent:@"raze-log.txt"] fileSystemRepresentation];
	if (freopen(path, "w", stdout)) setvbuf(stdout, NULL, _IOLBF, 0);
	dup2(fileno(stdout), fileno(stderr));
	setvbuf(stderr, NULL, _IONBF, 0);
}
