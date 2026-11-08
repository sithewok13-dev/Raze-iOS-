/*
** i_ios.mm: the iOS pieces the SDL backend expects from the Mac files
**
** - I_PickIWad_Cocoa: the game picker, a native list over the game
** - Mac_I_FatalError: an alert with the error before the app ends
** - LAN games: after the game is picked, Single player / Host / Join (the
**   host's mode, players, friendly fire, cheats; the hosts found on the
**   Wi-Fi or a typed address), then -host / -join for the engine; and
**   I_NetWaitTick, the box while waiting for the players
**
** Both run before or outside the game loop, so they show a UIKit alert and
** spin the main run loop until it is answered.
*/

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <AVFoundation/AVFoundation.h>
#include "SDL.h"
#include "SDL_syswm.h"

#include "cmdlib.h"
#include "i_interface.h"
#include "m_argv.h"
#include "c_cvars.h"
#include "IOSNet.h"



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

// What to put an alert on: the top of what's on screen, or, with nothing
// on screen yet (the game window comes later), a plain black window of our
// own (HideOwnWindow takes it away again)
static UIWindow* ownWindow = nil;

static UIViewController* PresentingController()
{
	UIViewController* vc = TopViewController();
	if (vc == nil)
	{
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
	return vc;
}

static void HideOwnWindow()
{
	if (ownWindow)
	{
		// Out of the way again before the game makes its own window
		ownWindow.hidden = YES;
		ownWindow = nil;
	}
}

static void SpinRunLoop(double seconds)
{
	@autoreleasepool
	{
		[[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
	}
}

// Shows an alert (an iPad's action sheet gets an anchor); false when it
// couldn't be shown
static bool Present(UIAlertController* alert)
{
	UIViewController* vc = PresentingController();
	if (vc == nil) return false;
	if (alert.popoverPresentationController)
	{
		alert.popoverPresentationController.sourceView = vc.view;
		alert.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(vc.view.bounds), CGRectGetMidY(vc.view.bounds), 0, 0);
		alert.popoverPresentationController.permittedArrowDirections = 0;
	}
	[vc presentViewController:alert animated:YES completion:nil];
	return alert.presentingViewController != nil;
}

// Waits (up to a second) until a closed alert is really off the screen, so
// the next one can be shown
static void WaitGone(UIAlertController* alert)
{
	for (int i = 0; i < 20 && alert.presentingViewController != nil; i++) SpinRunLoop(0.05);
}

// Shows the alert and waits for an answer; returns the chosen action's index
// (-1: it couldn't be shown)
static int RunAlert(UIAlertController* alert, NSArray<NSString*>* titles, int cancelIndex)
{
	__block int chosen = -1;
	for (NSUInteger i = 0; i < titles.count; i++)
	{
		const int index = (int)i;
		UIAlertActionStyle style = (index == cancelIndex) ? UIAlertActionStyleCancel : UIAlertActionStyleDefault;
		[alert addAction:[UIAlertAction actionWithTitle:titles[i] style:style handler:^(UIAlertAction*) { chosen = index; }]];
	}
	if (!Present(alert))
	{
		HideOwnWindow();
		return -1;
	}
	while (chosen < 0) SpinRunLoop(0.05);
	WaitGone(alert);
	HideOwnWindow();
	return chosen;
}

//---------------------------------------------------------------------------
//
// LAN games: the choice after the game is picked
//
//---------------------------------------------------------------------------

struct NetMode { const char* name; int mode; bool coop; };

// The game's modes (each game's own numbers: see its SetupNetGame), from the
// picker's name; none: no network game for it (Exhumed / PowerSlave)
static void NetModes(const char* gameName, int* pCount, const NetMode** ppModes)
{
	static const NetMode duke[] = { { "DukeMatch", 0, false }, { "Co-op", 1, true }, { "DukeMatch (no spawn)", 2, false } };
	static const NetMode rr[] = { { "Deathmatch", 0, false }, { "Co-op", 1, true }, { "Deathmatch (no spawn)", 2, false } };
	static const NetMode blood[] = { { "Co-op", 1, true }, { "BloodBath", 2, false }, { "Teams", 3, false } };
	static const NetMode sw[] = { { "WangBang", 1, false }, { "WangBang (no respawn)", 2, false }, { "Co-op", 3, true } };
	NSString* name = [[NSString stringWithUTF8String:gameName ? gameName : ""] lowercaseString];
	*pCount = 3;
	if ([name containsString:@"exhumed"] || [name containsString:@"powerslave"]) { *pCount = 0; *ppModes = nullptr; }
	else if ([name containsString:@"blood"]) *ppModes = blood;
	else if ([name containsString:@"shadow warrior"] || [name containsString:@"wanton"] || [name containsString:@"twin dragon"]) *ppModes = sw;
	else if ([name containsString:@"redneck"] || [name containsString:@"route 66"] || [name containsString:@"rides again"] || [name containsString:@"deer"]) *ppModes = rr;
	else *ppModes = duke;
}

static UIAlertController* Sheet(NSString* title, NSString* message)
{
	return [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleActionSheet];
}

// Hosting: mode, players, friendly fire (co-op), cheats. false: back
static bool ChooseHost(const NetMode* modes, int ctModes)
{
	NSMutableArray<NSString*>* titles = [NSMutableArray array];
	for (int i = 0; i < ctModes; i++) [titles addObject:[NSString stringWithUTF8String:modes[i].name]];
	[titles addObject:@"Back"];
	const int m = RunAlert(Sheet(@"Host a LAN game", @"Which game?"), titles, ctModes);
	if (m < 0 || m >= ctModes) return false;

	titles = [NSMutableArray array];
	for (int n = 2; n <= 8; n++) [titles addObject:[NSString stringWithFormat:@"%d players", n]];
	[titles addObject:@"Back"];
	const int p = RunAlert(Sheet(@"Host a LAN game", @"How many players, you too? The game starts when they are all here."), titles, 7);
	if (p < 0 || p >= 7) return false;

	bool ffire = false;
	if (modes[m].coop)
	{
		const int f = RunAlert(Sheet(@"Co-op", @"Can players hurt each other?"), @[ @"No friendly fire", @"Friendly fire", @"Back" ], 2);
		if (f < 0 || f >= 2) return false;
		ffire = f == 1;
	}

	const int c = RunAlert(Sheet(@"Cheats", @"Allow the game's console cheats (god, give) for everyone? The CHEAT button stays single player."), @[ @"No cheats", @"Allow cheats", @"Back" ], 2);
	if (c < 0 || c >= 2) return false;

	IOSNet_TouchNetwork();	// (iOS asks for the Local Network permission now)
	// (the engine reads these after the game's settings: netgame.cpp)
	Args->AppendArg("-host");
	Args->AppendArg(FStringf("%d", p + 2).GetChars());
	Args->AppendArg("+set"); Args->AppendArg("net_mode"); Args->AppendArg(FStringf("%d", modes[m].mode).GetChars());
	Args->AppendArg("+set"); Args->AppendArg("net_ffire"); Args->AppendArg(ffire ? "1" : "0");
	Args->AppendArg("+set"); Args->AppendArg("net_cheats"); Args->AppendArg(c == 1 ? "1" : "0");
	printf("LAN game: hosting %s, %d players, friendly fire %d, cheats %d\n", modes[m].name, p + 2, ffire, c == 1);
	return true;
}

// Joining: the hosts found on the Wi-Fi, or a typed address. false: back
static bool ChooseJoin()
{
	IOSNet_TouchNetwork();
	for (;;)
	{
		// the search (1.5 s, off the main thread; a box meanwhile)
		static IOSNetHost hosts[IOSNET_MAXHOSTS];	// (static: the search block fills it)
		__block int ctHosts = -1;
		UIAlertController* busy = [UIAlertController alertControllerWithTitle:@"Join a LAN game" message:@"Looking for games on this Wi-Fi…" preferredStyle:UIAlertControllerStyleAlert];
		const bool shown = Present(busy);
		dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
			int n = IOSNet_Scan(hosts, IOSNET_MAXHOSTS, 1.5);
			dispatch_async(dispatch_get_main_queue(), ^{ ctHosts = n; });
		});
		while (ctHosts < 0) SpinRunLoop(0.05);
		if (shown)
		{
			[busy dismissViewControllerAnimated:NO completion:nil];
			WaitGone(busy);
		}
		HideOwnWindow();

		NSMutableArray<NSString*>* titles = [NSMutableArray array];
		for (int i = 0; i < ctHosts; i++)
		{
			[titles addObject:[NSString stringWithFormat:@"%s · %s · %d of %d · %s", hosts[i].strGame, hosts[i].strMode,
				hosts[i].ctPresent, hosts[i].ctWanted, hosts[i].strAddress]];
		}
		const int iType = (int)titles.count;
		[titles addObject:@"Type an address"];
		[titles addObject:@"Search again"];
		[titles addObject:@"Back"];
		NSString* msg = ctHosts > 0 ? @"Tap a game to join it (the same game as yours: the same files)."
			: @"No game found. The host must be waiting for players, on this Wi-Fi.";
		const int pick = RunAlert(Sheet(@"Join a LAN game", msg), titles, iType + 2);
		if (pick < 0 || pick == iType + 2) return false;
		if (pick == iType + 1) continue;

		NSString* address = nil;
		if (pick < ctHosts) address = [NSString stringWithUTF8String:hosts[pick].strAddress];
		else
		{
			UIAlertController* ask = [UIAlertController alertControllerWithTitle:@"Join a LAN game"
				message:@"The host's address (it shows on the host's screen while it waits)" preferredStyle:UIAlertControllerStyleAlert];
			NSString* last = [NSUserDefaults.standardUserDefaults stringForKey:@"RazeLanLastAddress"];
			[ask addTextFieldWithConfigurationHandler:^(UITextField* field) {
				field.placeholder = @"192.168.1.20";
				field.text = last;
				field.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
				field.autocorrectionType = UITextAutocorrectionTypeNo;
			}];
			const int ok = RunAlert(ask, @[ @"Join", @"Back" ], 1);
			NSString* typed = [ask.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
			if (ok != 0 || typed.length == 0) continue;
			address = typed;
		}
		[NSUserDefaults.standardUserDefaults setObject:address forKey:@"RazeLanLastAddress"];
		Args->AppendArg("-join");
		Args->AppendArg(address.UTF8String);
		printf("LAN game: joining %s\n", address.UTF8String);
		return true;
	}
}

// Host or join, for the game picked. false: back
static bool ChooseNetwork(const char* gameName, const NetMode* modes, int ctModes)
{
	for (;;)
	{
		const int c = RunAlert(Sheet([NSString stringWithUTF8String:gameName], @"A game with others on this Wi-Fi"),
			@[ @"Host a LAN game", @"Join a LAN game", @"Back" ], 2);
		if (c == 0 && ChooseHost(modes, ctModes)) return true;
		if (c == 1 && ChooseJoin()) return true;
		if (c < 0 || c == 2) return false;
	}
}

int I_PickIWad_Cocoa(WadStuff* wads, int numwads, bool showwin, int defaultiwad)
{
	if (!showwin) return defaultiwad;
	// the games that have network games
	TArray<int> netGames;
	for (int i = 0; i < numwads; i++)
	{
		const NetMode* modes = nullptr;
		int ctModes = 0;
		NetModes(wads[i].Name.GetChars(), &ctModes, &modes);
		if (ctModes > 0) netGames.Push(i);
	}

	for (;;)
	{
		// The picker as it always was (a game: single player straight away),
		// with one more entry at the end: LAN multiplayer (Added)
		NSMutableArray<NSString*>* titles = [NSMutableArray array];
		for (int i = 0; i < numwads; i++)
		{
			NSString* name = [NSString stringWithUTF8String:wads[i].Name.GetChars()];
			if (name == nil) name = @"?";
			if (i == defaultiwad) name = [name stringByAppendingString:@"  ✓"];
			[titles addObject:name];
		}
		const int iLan = netGames.Size() > 0 ? numwads : -1;
		if (iLan >= 0) [titles addObject:@"LAN multiplayer…"];
		const int iQuit = (int)titles.count;
		[titles addObject:@"Quit"];

		const int chosen = numwads > 1 || iLan >= 0
			? RunAlert(Sheet(@"Raze", @"Choose a game"), titles, iQuit)
			: defaultiwad;
		printf("Game picker: chose %d of %d\n", chosen, numwads);
		if (chosen < 0 || chosen == iQuit) return -1;
		if (chosen != iLan) return chosen;

		// LAN multiplayer: which game, then host or join (Back: the picker again)
		NSMutableArray<NSString*>* games = [NSMutableArray array];
		for (unsigned i = 0; i < netGames.Size(); i++)
		{
			NSString* name = [NSString stringWithUTF8String:wads[netGames[i]].Name.GetChars()];
			[games addObject:name ? name : @"?"];
		}
		[games addObject:@"Back"];
		const int g = RunAlert(Sheet(@"LAN multiplayer", @"Which game? (Everyone needs the same game files.)"), games, (int)netGames.Size());
		if (g < 0 || g >= (int)netGames.Size()) continue;
		const int pick = netGames[g];
		const NetMode* modes = nullptr;
		int ctModes = 0;
		NetModes(wads[pick].Name.GetChars(), &ctModes, &modes);
		if (ChooseNetwork(wads[pick].Name.GetChars(), modes, ctModes)) return pick;
	}
}

//---------------------------------------------------------------------------
//
// LAN games: the box while waiting for the players (i_net.cpp calls this
// about 8 times a second; false: Cancel; message null: done)
//
//---------------------------------------------------------------------------

bool I_NetWaitTick(const char* message, int pos, int max)
{
	static UIAlertController* box = nil;
	static bool cancelled = false;
	if (message == nullptr)
	{
		// (the network game is set up, or cancelled: the box goes)
		if (box && box.presentingViewController) [box dismissViewControllerAnimated:NO completion:nil];
		if (box) WaitGone(box);
		[box release];
		box = nil;
		HideOwnWindow();
		return true;
	}

	NSString* text;
	NSString* what = [NSString stringWithUTF8String:message];
	if ([what hasPrefix:@"Hosting"])
	{
		char mine[64] = "";
		IOSNet_WifiAddress(mine, sizeof(mine));
		text = [NSString stringWithFormat:@"%d of %d players here.\n\nThis phone's address: %s\n(the others: LAN multiplayer, Join, then tap this game or type the address)",
			pos > 0 ? pos : 1, max, mine[0] ? mine : "no Wi-Fi?"];
	}
	else if ([what hasPrefix:@"Contacting"]) text = @"Looking for the host…\n(it must be waiting for players, on this Wi-Fi)";
	else if ([what hasPrefix:@"Waiting for other"]) text = [NSString stringWithFormat:@"%d of %d players here: waiting for the rest", pos, max];
	else text = @"Starting…";

	if (box == nil)
	{
		cancelled = false;
		box = [[UIAlertController alertControllerWithTitle:@"LAN game" message:text preferredStyle:UIAlertControllerStyleAlert] retain];
		[box addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction*) { cancelled = true; }]];
	}
	else if (![box.message isEqualToString:text]) box.message = text;
	// (shown once; again if it couldn't be shown yet, while something else
	// was still going away)
	if (!cancelled && box.presentingViewController == nil) Present(box);

	SpinRunLoop(0.12);
	if (cancelled)
	{
		// (its button closed it; the next call, or the null one, makes a
		// new box if the wait goes on)
		WaitGone(box);
		[box release];
		box = nil;
		return false;
	}
	return true;
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
__attribute__((constructor(101))) static void IOS_LogToFile()
{
	NSString* docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
	if (docs == nil) return;
	const char* path = [[docs stringByAppendingPathComponent:@"raze-log.txt"] fileSystemRepresentation];
	if (freopen(path, "w", stdout)) setvbuf(stdout, NULL, _IOLBF, 0);
	dup2(fileno(stdout), fileno(stderr));
	setvbuf(stderr, NULL, _IONBF, 0);
}

// Start-up diagnostics (called from SwapBuffers for the first frames): what
// the GL frame buffer holds and which windows UIKit shows, into the log.
#define GLES_SILENCE_DEPRECATION 1
#include <OpenGLES/ES3/gl.h>
#import <OpenGLES/EAGL.h>
#include <vector>
extern "C" void IOS_FrameReport(int frame, int w, int h)
{
	GLint fb = 0, vp[4] = {0, 0, 0, 0};
	glGetIntegerv(GL_FRAMEBUFFER_BINDING, &fb);
	glGetIntegerv(GL_VIEWPORT, vp);
	GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
	unsigned char px[4] = {0, 0, 0, 0};
	if (w > 0 && h > 0) glReadPixels(w / 2, h / 2, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, px);
	GLenum err = glGetError();
	if (frame == 0)
	{
		// SDL's own idea of the screen's frame buffer, to compare with ours
		SDL_SysWMinfo info;
		SDL_VERSION(&info.version);
		SDL_Window* sw = SDL_GL_GetCurrentWindow();
		if (sw && SDL_GetWindowWMInfo(sw, &info) && info.subsystem == SDL_SYSWM_UIKIT)
		{
			printf("SDL screen: framebuffer %u, colorbuffer %u, resolve %u\n",
				info.info.uikit.framebuffer, info.info.uikit.colorbuffer, info.info.uikit.resolveFramebuffer);
			UIView* v = info.info.uikit.window.rootViewController.view;
			printf("SDL view: %s, frame %.0f,%.0f %.0fx%.0f, hidden %d, alpha %.2f, layer %s opaque %d, superview %s\n",
				class_getName(v.class), v.frame.origin.x, v.frame.origin.y, v.frame.size.width, v.frame.size.height,
				v.hidden, v.alpha, class_getName(v.layer.class), v.layer.opaque, v.superview ? class_getName(v.superview.class) : "none");

		}
	}
	printf("Frame %d: drawable %dx%d, fb %d (status 0x%x), viewport %d,%d %dx%d, centre pixel %d,%d,%d, GL error 0x%x\n",
		frame, w, h, (int)fb, status, vp[0], vp[1], vp[2], vp[3], px[0], px[1], px[2], err);
	for (UIWindow* win in UIApplication.sharedApplication.windows)
	{
		printf("  window %s: %s%s%s level %.0f, %.0fx%.0f, root %s\n", class_getName(win.class),
			win.isKeyWindow ? "key, " : "", win.hidden ? "hidden" : "shown", win.windowScene ? ", in a scene" : ", NO scene", win.windowLevel,
			win.bounds.size.width, win.bounds.size.height,
			win.rootViewController ? class_getName(win.rootViewController.class) : "none");
	}
	fflush(stdout);
}

// SDL 2 makes its UIWindow with initWithFrame:, outside any scene: make sure
// it is in the app's window scene, key and shown. (On the owner's phone it
// already was; kept as a safeguard for newer iOS versions.)
void IOS_AttachWindowToScene(SDL_Window* window)
{
	// Sound follows the silent switch, and music from other apps can play on
	// (the ambient category; set before the game opens its sound)
	[[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryAmbient error:nil];
	[[AVAudioSession sharedInstance] setActive:YES error:nil];
	SDL_SysWMinfo info;
	SDL_VERSION(&info.version);
	if (!SDL_GetWindowWMInfo(window, &info) || info.subsystem != SDL_SYSWM_UIKIT || !info.info.uikit.window) return;
	UIWindow* w = info.info.uikit.window;
	UIWindowScene* windowScene = nil;
	for (UIScene* scene in UIApplication.sharedApplication.connectedScenes)
	{
		if ([scene isKindOfClass:UIWindowScene.class]) { windowScene = (UIWindowScene*)scene; break; }
	}
	printf("Game window: scene %s, attaching to %s\n", w.windowScene ? "set" : "none", windowScene ? "the app's scene" : "nothing (no scene found)");
	if (windowScene && w.windowScene != windowScene)
	{
		w.windowScene = windowScene;
		w.frame = windowScene.coordinateSpace.bounds;
	}
	[w makeKeyAndVisible];
}


// The frame's hand-over to the screen, done here instead of SDL's swap so
// that failures show in the log: SDL's colour renderbuffer, its size and
// attachment, and what presentRenderbuffer says (logged for the first frames
// and on every change of outcome).
extern "C" void IOS_Present(SDL_Window* window, int frame)
{
	SDL_SysWMinfo info;
	SDL_VERSION(&info.version);
	if (!SDL_GetWindowWMInfo(window, &info) || info.subsystem != SDL_SYSWM_UIKIT) { SDL_GL_SwapWindow(window); return; }
	const GLuint fb = info.info.uikit.framebuffer, rb = info.info.uikit.colorbuffer;
	static int lastOk = -1;
	const bool report = frame < 1;
	if (report)
	{
		GLint boundFb = 0, boundRb = 0, att = 0, attType = 0, w = 0, h = 0;
		glGetIntegerv(GL_FRAMEBUFFER_BINDING, &boundFb);
		glGetIntegerv(GL_RENDERBUFFER_BINDING, &boundRb);
		glBindFramebuffer(GL_FRAMEBUFFER, fb);
		glGetFramebufferAttachmentParameteriv(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_FRAMEBUFFER_ATTACHMENT_OBJECT_TYPE, &attType);
		glGetFramebufferAttachmentParameteriv(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_FRAMEBUFFER_ATTACHMENT_OBJECT_NAME, &att);
		glBindRenderbuffer(GL_RENDERBUFFER, rb);
		glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &w);
		glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &h);
		printf("Present %d: bound fb %d rb %d; SDL fb %u rb %u (is rb %d, %dx%d); fb colour attachment type 0x%x name %d; GL error before 0x%x\n",
			frame, boundFb, boundRb, fb, rb, glIsRenderbuffer(rb), w, h, attType, att, glGetError());
		glBindFramebuffer(GL_FRAMEBUFFER, boundFb);
	}
	while (glGetError() != GL_NO_ERROR) {}
	glBindRenderbuffer(GL_RENDERBUFFER, rb);
	const BOOL ok = [[EAGLContext currentContext] presentRenderbuffer:GL_RENDERBUFFER];
	const GLenum err = glGetError();
	if (report || (int)ok != lastOk)
	{
		printf("Present %d: %s, GL error 0x%x\n", frame, ok ? "ok" : "FAILED", err);
		fflush(stdout);
	}
	lastOk = ok;
}

// At start-up: the app's Documents folder (Files > On My iPhone > Raze) and
// what is in it, into the log
__attribute__((constructor(102))) static void IOS_LogDocuments()
{
	NSString* docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
	NSArray* items = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:docs error:nil];
	printf("Documents: %s, %d items\n", docs.UTF8String, (int)items.count);
	for (NSString* name in items) printf("  %s\n", name.UTF8String);
	fflush(stdout);
}
