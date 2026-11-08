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
#import <objc/runtime.h>
#include "SDL.h"
#include "SDL_syswm.h"

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
	if (frame == 600 && w > 0 && h > 0)
	{
		// What the game drew, as frame600.ppm in the app's folder, to compare
		// with what the screen shows
		std::vector<unsigned char> buf((size_t)w * h * 4);
		glReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, buf.data());
		NSString* docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
		FILE* f = fopen([[docs stringByAppendingPathComponent:@"frame600.ppm"] fileSystemRepresentation], "wb");
		if (f)
		{
			fprintf(f, "P6\n%d %d\n255\n", w, h);
			for (int y = h - 1; y >= 0; y--)
				for (int x = 0; x < w; x++) fwrite(&buf[((size_t)y * w + x) * 4], 1, 3, f);
			fclose(f);
			printf("Saved frame600.ppm (%dx%d), alpha at centre %d\n", w, h, buf[((size_t)(h / 2) * w + w / 2) * 4 + 3]);
		}
	}
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
			// Hand a frame to the screen ourselves once: does it work?
			glBindRenderbuffer(GL_RENDERBUFFER, info.info.uikit.colorbuffer);
			BOOL ok = [[EAGLContext currentContext] presentRenderbuffer:GL_RENDERBUFFER];
			printf("Test present: %s, GL error 0x%x, context API %d\n", ok ? "ok" : "FAILED", glGetError(),
				(int)[EAGLContext currentContext].API);
			UIView* v = info.info.uikit.window.rootViewController.view;
			printf("SDL view: %s, frame %.0f,%.0f %.0fx%.0f, hidden %d, alpha %.2f, layer %s opaque %d, superview %s\n",
				class_getName(v.class), v.frame.origin.x, v.frame.origin.y, v.frame.size.width, v.frame.size.height,
				v.hidden, v.alpha, class_getName(v.layer.class), v.layer.opaque, v.superview ? class_getName(v.superview.class) : "none");
			// (A bright label on the game's window for 6 seconds showed the window is shown; off now)
			if (0)
			{
			UILabel* l = [[UILabel alloc] initWithFrame:CGRectMake(40, 40, 360, 44)];
			l.text = @"RAZE SCREEN TEST";
			l.font = [UIFont boldSystemFontOfSize:28];
			l.textColor = UIColor.blackColor;
			l.backgroundColor = UIColor.yellowColor;
			[v addSubview:l];
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 6 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [l removeFromSuperview]; });
			}
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

// SDL 2 makes its UIWindow with initWithFrame:, outside any scene. Recent iOS
// versions don't show such a window (the game drew into it, nothing appeared).
// Put it into the app's window scene and show it.
void IOS_AttachWindowToScene(SDL_Window* window)
{
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

// Screen test: the first 3 seconds (180 frames) are cleared solid red right
// before they are shown, straight into the bound (screen) frame buffer: does
// anything GL draws reach the screen?
extern "C" void IOS_ScreenTest(int frame)
{
	return; // done its job: GL reaches the screen with ES 3 at point resolution
	if (frame >= 180) return;
	glDisable(GL_SCISSOR_TEST);
	glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
	glClearColor(1.f, 0.f, 0.f, 1.f);
	glClear(GL_COLOR_BUFFER_BIT);
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
	const bool report = frame < 6;
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
