// The game picker and "Switch game": see IOSPicker.h. (Objective-C++ with
// ARC; no engine headers: the game's flags are repeated below.)
//
// At start: a card for each main game found, side by side (scrolling if they
// don't fit), each in its family's colours with an emblem, its name and
// edition, "LAST PLAYED" on the last one, and how many add-ons it has. A tap
// starts the game; held 0.5 s (a ring runs round the card, then a thump) its
// add-ons open: the main game and each add-on, to tap. "LAN multiplayer"
// below (the host and join steps are i_ios.mm's).
//
// "Switch game" (MENU's tray, IOSGame.cpp): the same picker over the game,
// held still behind it, with Cancel. A pick is written down with the time,
// the game's settings are written, a "Tap to start <game>" notification is
// asked for in a second, and the app closes (iOS can't start an app again,
// and Raze can't change games in one run). The next start of the app within
// 10 minutes goes straight to that game (IOSPicker_TakeNext).

#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "IOSPicker.h"

extern "C" void IOSGame_WriteConfig(void); // IOSGame.cpp: the settings, written now

// (gamecontrol.h's GAMEFLAG_*)
enum
{
	PF_DUKE = 0x1, PF_NAM = 0x2, PF_NAPALM = 0x4, PF_WW2GI = 0x8,
	PF_RR = 0x100, PF_RRRA = 0x200, PF_BLOOD = 0x800, PF_SW = 0x1000,
	PF_POWERSLAVE = 0x2000, PF_EXHUMED = 0x4000, PF_WORLDTOUR = 0x8000,
};

static IOSPickEntry* _aEntries = nullptr;
static int _ctEntries = 0;
static int _iLast = -1;

void IOSPicker_SetEntries(const IOSPickEntry* aEntries, int ctEntries, int iLast)
{
	for (int i = 0; i < _ctEntries; i++)
	{
		free((void*)_aEntries[i].name);
		free((void*)_aEntries[i].file);
	}
	free(_aEntries);
	_aEntries = (IOSPickEntry*)calloc(ctEntries > 0 ? ctEntries : 1, sizeof(IOSPickEntry));
	_ctEntries = ctEntries;
	for (int i = 0; i < ctEntries; i++)
	{
		_aEntries[i] = aEntries[i];
		_aEntries[i].name = strdup(aEntries[i].name ? aEntries[i].name : "?");
		_aEntries[i].file = strdup(aEntries[i].file ? aEntries[i].file : "");
	}
	_iLast = iLast;
}

// ---------------------------------------------------------------- the look

typedef struct
{
	const char* symbol;	// an SF Symbol, the card's emblem
	CGFloat top[3], bottom[3];	// the card's gradient
} Family;

static Family FamilyOf(int flags)
{
	if (flags & PF_BLOOD) return { "drop.fill", { 0.62, 0.02, 0.06 }, { 0.14, 0.00, 0.02 } };
	if (flags & PF_SW) return { "flame.fill", { 0.05, 0.47, 0.36 }, { 0.02, 0.12, 0.10 } };
	if (flags & (PF_RR | PF_RRRA)) return { "hare.fill", { 0.70, 0.42, 0.12 }, { 0.20, 0.10, 0.03 } };
	if (flags & (PF_POWERSLAVE | PF_EXHUMED)) return { "sun.max.fill", { 0.82, 0.62, 0.20 }, { 0.30, 0.17, 0.04 } };
	if (flags & (PF_NAM | PF_NAPALM | PF_WW2GI)) return { "shield.fill", { 0.38, 0.45, 0.20 }, { 0.10, 0.13, 0.05 } };
	return { "bolt.fill", { 0.88, 0.27, 0.05 }, { 0.30, 0.05, 0.02 } }; // Duke Nukem 3D
}

static UIColor* RGB(const CGFloat c[3], CGFloat a = 1.0)
{
	return [UIColor colorWithRed:c[0] green:c[1] blue:c[2] alpha:a];
}

// "Duke Nukem 3D: Atomic Edition" -> "Duke Nukem 3D", "Atomic Edition"
static void SplitName(const char* name, NSString** title, NSString** edition)
{
	NSString* s = [NSString stringWithUTF8String:name] ?: @"?";
	NSRange r = [s rangeOfString:@": "];
	if (r.location == NSNotFound) r = [s rangeOfString:@" - "];
	if (r.location != NSNotFound)
	{
		*title = [s substringToIndex:r.location];
		*edition = [s substringFromIndex:r.location + r.length];
	}
	else
	{
		*title = s;
		*edition = @"";
	}
}

static NSArray<NSNumber*>* AddonsOf(int iMain)
{
	NSMutableArray<NSNumber*>* a = [NSMutableArray array];
	for (int i = 0; i < _ctEntries; i++)
		if (_aEntries[i].bAddon && _aEntries[i].iBase == iMain) [a addObject:@(i)];
	return a;
}

// ---------------------------------------------------------------- a card

#define HOLD_TIME 0.5

@interface IOSGameCard : UIControl
@property (nonatomic) int index;
@property (nonatomic, copy) void (^onTap)(int index);
@property (nonatomic, copy) void (^onHold)(int index);
@property (nonatomic) BOOL hasHold;
@end

@implementation IOSGameCard
{
	CAGradientLayer* gradient;
	CAShapeLayer* ring;
	NSTimer* holdTimer;
	BOOL held;
}

- (instancetype)initWithEntry:(int)index
{
	if (!(self = [super initWithFrame:CGRectZero])) return nil;
	_index = index;
	const IOSPickEntry* e = &_aEntries[index];
	const Family f = FamilyOf(e->flags);
	NSString *title, *edition;
	SplitName(e->name, &title, &edition);
	NSArray* addons = AddonsOf(index);
	_hasHold = addons.count > 0;

	self.layer.cornerRadius = 18;
	self.layer.borderWidth = 1.5;
	self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.18].CGColor;
	self.clipsToBounds = YES;

	gradient = [CAGradientLayer layer];
	gradient.colors = @[ (id)RGB(f.top).CGColor, (id)RGB(f.bottom).CGColor ];
	gradient.startPoint = CGPointMake(0.2, 0.0);
	gradient.endPoint = CGPointMake(0.8, 1.0);
	[self.layer addSublayer:gradient];

	// the emblem, big and faint behind the name
	UIImageSymbolConfiguration* big = [UIImageSymbolConfiguration configurationWithPointSize:120 weight:UIImageSymbolWeightBold];
	UIImageView* emblem = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@(f.symbol) withConfiguration:big]];
	emblem.tintColor = [UIColor colorWithWhite:1.0 alpha:0.10];
	emblem.contentMode = UIViewContentModeScaleAspectFit;
	emblem.translatesAutoresizingMaskIntoConstraints = NO;
	[self addSubview:emblem];

	// and small and bright above it
	UIImageSymbolConfiguration* small = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightSemibold];
	UIImageView* badge = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@(f.symbol) withConfiguration:small]];
	badge.tintColor = [UIColor colorWithWhite:1.0 alpha:0.9];
	badge.translatesAutoresizingMaskIntoConstraints = NO;
	[self addSubview:badge];

	UILabel* name = [[UILabel alloc] init];
	name.text = [title uppercaseString];
	name.textColor = UIColor.whiteColor;
	name.font = [UIFont systemFontOfSize:22 weight:UIFontWeightHeavy];
	name.numberOfLines = 3;
	name.adjustsFontSizeToFitWidth = YES;
	name.minimumScaleFactor = 0.55;
	name.layer.shadowColor = UIColor.blackColor.CGColor;
	name.layer.shadowOpacity = 0.6;
	name.layer.shadowRadius = 3;
	name.layer.shadowOffset = CGSizeMake(0, 1);

	UILabel* sub = [[UILabel alloc] init];
	sub.text = edition;
	sub.textColor = [UIColor colorWithWhite:1.0 alpha:0.78];
	sub.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
	sub.numberOfLines = 2;
	sub.adjustsFontSizeToFitWidth = YES;
	sub.minimumScaleFactor = 0.7;

	UILabel* foot = [[UILabel alloc] init];
	foot.text = addons.count == 0 ? @"" :
		[NSString stringWithFormat:@"+%d ADD-ON%@ · HOLD", (int)addons.count, addons.count == 1 ? @"" : @"S"];
	foot.textColor = [UIColor colorWithRed:1.0 green:0.82 blue:0.45 alpha:1.0];
	foot.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
	foot.adjustsFontSizeToFitWidth = YES;
	foot.minimumScaleFactor = 0.7;

	UIStackView* text = [[UIStackView alloc] initWithArrangedSubviews:@[ name, sub, [UIView new], foot ]];
	text.axis = UILayoutConstraintAxisVertical;
	text.spacing = 4;
	text.userInteractionEnabled = NO;
	text.translatesAutoresizingMaskIntoConstraints = NO;
	[self addSubview:text];

	NSMutableArray* cons = [NSMutableArray arrayWithArray:@[
		[badge.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
		[badge.topAnchor constraintEqualToAnchor:self.topAnchor constant:16],
		[emblem.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:28],
		[emblem.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:22],
		[emblem.widthAnchor constraintEqualToAnchor:self.widthAnchor multiplier:0.85],
		[emblem.heightAnchor constraintEqualToAnchor:emblem.widthAnchor],
		[text.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
		[text.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14],
		[text.topAnchor constraintEqualToAnchor:badge.bottomAnchor constant:12],
		[text.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-14],
	]];

	// the one played last
	if (index == _iLast)
	{
		UILabel* last = [[UILabel alloc] init];
		last.text = @" LAST PLAYED ";
		last.font = [UIFont systemFontOfSize:10 weight:UIFontWeightHeavy];
		last.textColor = UIColor.blackColor;
		last.backgroundColor = [UIColor colorWithRed:1.0 green:0.82 blue:0.35 alpha:1.0];
		last.layer.cornerRadius = 7;
		last.clipsToBounds = YES;
		last.translatesAutoresizingMaskIntoConstraints = NO;
		[self addSubview:last];
		[cons addObjectsFromArray:@[
			[last.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
			[last.centerYAnchor constraintEqualToAnchor:badge.centerYAnchor],
			[last.heightAnchor constraintEqualToConstant:18],
		]];
	}
	[NSLayoutConstraint activateConstraints:cons];

	// the hold's ring round the card's edge
	ring = [CAShapeLayer layer];
	ring.fillColor = UIColor.clearColor.CGColor;
	ring.strokeColor = [UIColor colorWithRed:1.0 green:0.78 blue:0.25 alpha:1.0].CGColor;
	ring.lineWidth = 5;
	ring.lineCap = kCALineCapRound;
	ring.strokeEnd = 0;
	[self.layer addSublayer:ring];
	return self;
}

- (void)layoutSubviews
{
	[super layoutSubviews];
	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	gradient.frame = self.bounds;
	ring.frame = self.bounds;
	ring.path = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(self.bounds, 2.5, 2.5) cornerRadius:16].CGPath;
	[CATransaction commit];
}

- (void)setHighlighted:(BOOL)highlighted
{
	[super setHighlighted:highlighted];
	[UIView animateWithDuration:0.12 animations:^{
		self.transform = highlighted ? CGAffineTransformMakeScale(0.96, 0.96) : CGAffineTransformIdentity;
	}];
}

- (void)stopRing
{
	[holdTimer invalidate];
	holdTimer = nil;
	[ring removeAllAnimations];
	ring.strokeEnd = 0;
}

- (BOOL)beginTrackingWithTouch:(UITouch*)touch withEvent:(UIEvent*)event
{
	held = NO;
	if (_hasHold)
	{
		CABasicAnimation* a = [CABasicAnimation animationWithKeyPath:@"strokeEnd"];
		a.fromValue = @0;
		a.toValue = @1;
		a.duration = HOLD_TIME;
		a.fillMode = kCAFillModeForwards;
		a.removedOnCompletion = NO;
		[ring addAnimation:a forKey:@"hold"];
		__weak IOSGameCard* weakSelf = self;
		holdTimer = [NSTimer scheduledTimerWithTimeInterval:HOLD_TIME repeats:NO block:^(NSTimer* t) {
			IOSGameCard* card = weakSelf;
			if (!card) return;
			card->held = YES;
			[card stopRing];
			[[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
			if (card.onHold) card.onHold(card.index);
		}];
	}
	return YES;
}

- (BOOL)continueTrackingWithTouch:(UITouch*)touch withEvent:(UIEvent*)event
{
	// slid off the card: nothing (the ring stops)
	if (!CGRectContainsPoint(CGRectInset(self.bounds, -20, -20), [touch locationInView:self])) [self stopRing];
	return YES;
}

- (void)endTrackingWithTouch:(UITouch*)touch withEvent:(UIEvent*)event
{
	const BOOL inside = touch && CGRectContainsPoint(CGRectInset(self.bounds, -20, -20), [touch locationInView:self]);
	const BOOL wasHolding = holdTimer != nil || !_hasHold;
	[self stopRing];
	if (!held && inside && wasHolding && self.onTap) self.onTap(self.index);
}

- (void)cancelTrackingWithEvent:(UIEvent*)event
{
	[self stopRing];
}
@end

// ---------------------------------------------------------------- the picker

@interface IOSPickerController : UIViewController
@property (nonatomic, copy) void (^done)(int picked); // an index, IOSPICKER_LAN, or -1 (Cancel)
@property (nonatomic) BOOL switching;	// "Switch game", with Cancel
@property (nonatomic) BOOL lan;		// "LAN multiplayer" shows
@end

@implementation IOSPickerController
{
	UIView* addonsBack;
	BOOL finished;
}

- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskLandscape; }

- (void)finish:(int)picked
{
	if (finished) return;
	finished = YES;
	if (self.done) self.done(picked);
}

- (void)viewDidLoad
{
	[super viewDidLoad];
	CAGradientLayer* back = [CAGradientLayer layer];
	back.colors = @[ (id)[UIColor colorWithRed:0.10 green:0.08 blue:0.08 alpha:1].CGColor,
	                 (id)[UIColor colorWithRed:0.03 green:0.03 blue:0.04 alpha:1].CGColor ];
	back.frame = CGRectMake(0, 0, 4000, 4000); // (any size the screen turns to)
	[self.view.layer addSublayer:back];
	self.view.backgroundColor = UIColor.blackColor;

	// RAZE  Choose a game                         [Cancel]
	UILabel* logo = [[UILabel alloc] init];
	logo.attributedText = [[NSAttributedString alloc] initWithString:@"RAZE" attributes:@{
		NSFontAttributeName: [UIFont systemFontOfSize:30 weight:UIFontWeightBlack],
		NSForegroundColorAttributeName: [UIColor colorWithRed:1.0 green:0.45 blue:0.12 alpha:1.0],
		NSKernAttributeName: @4 }];
	UILabel* heading = [[UILabel alloc] init];
	heading.text = self.switching ? @"Switch game" : @"Choose a game";
	heading.textColor = [UIColor colorWithWhite:1.0 alpha:0.9];
	heading.font = [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold];
	UIView* gap = [UIView new];
	UIStackView* top = [[UIStackView alloc] initWithArrangedSubviews:@[ logo, heading, gap ]];
	top.alignment = UIStackViewAlignmentLastBaseline;
	top.spacing = 16;
	if (self.switching)
	{
		UIButton* cancel = [UIButton buttonWithType:UIButtonTypeSystem];
		[cancel setTitle:@"Cancel" forState:UIControlStateNormal];
		cancel.titleLabel.font = [UIFont systemFontOfSize:19 weight:UIFontWeightSemibold];
		cancel.tintColor = [UIColor colorWithRed:1.0 green:0.7 blue:0.3 alpha:1.0];
		[cancel addTarget:self action:@selector(cancelTapped) forControlEvents:UIControlEventTouchUpInside];
		[top addArrangedSubview:cancel];
	}

	// the cards: one for each main game, side by side
	UIStackView* row = [[UIStackView alloc] init];
	row.axis = UILayoutConstraintAxisHorizontal;
	row.spacing = 14;
	row.translatesAutoresizingMaskIntoConstraints = NO;
	int ctCards = 0;
	__weak IOSPickerController* weakSelf = self;
	for (int i = 0; i < _ctEntries; i++)
	{
		// (an add-on without its main game here: a card of its own)
		if (_aEntries[i].bAddon && _aEntries[i].iBase >= 0) continue;
		IOSGameCard* card = [[IOSGameCard alloc] initWithEntry:i];
		card.onTap = ^(int index) { [weakSelf finish:index]; };
		card.onHold = ^(int index) { [weakSelf showAddons:index]; };
		[row addArrangedSubview:card];
		[card.widthAnchor constraintEqualToConstant:190].active = YES;
		ctCards++;
	}
	UIScrollView* scroll = [[UIScrollView alloc] init];
	scroll.showsHorizontalScrollIndicator = NO;
	scroll.alwaysBounceHorizontal = YES;
	scroll.clipsToBounds = NO;
	scroll.delaysContentTouches = NO;
	[scroll addSubview:row];

	UILabel* hint = [[UILabel alloc] init];
	hint.text = @"Tap a game to play  ·  Hold one for its add-ons";
	hint.textColor = [UIColor colorWithWhite:1.0 alpha:0.5];
	hint.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
	UIStackView* bottom = [[UIStackView alloc] initWithArrangedSubviews:@[ hint, [UIView new] ]];
	bottom.alignment = UIStackViewAlignmentCenter;
	bottom.spacing = 12;
	if (self.lan)
	{
		UIButton* lanButton = [UIButton buttonWithType:UIButtonTypeSystem];
		[lanButton setTitle:@"  LAN multiplayer  " forState:UIControlStateNormal];
		lanButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
		lanButton.tintColor = UIColor.whiteColor;
		lanButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.12];
		lanButton.layer.cornerRadius = 16;
		lanButton.layer.borderWidth = 1;
		lanButton.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.25].CGColor;
		[lanButton.heightAnchor constraintEqualToConstant:34].active = YES;
		[lanButton addTarget:self action:@selector(lanTapped) forControlEvents:UIControlEventTouchUpInside];
		[bottom addArrangedSubview:lanButton];
	}

	UIStackView* page = [[UIStackView alloc] initWithArrangedSubviews:@[ top, scroll, bottom ]];
	page.axis = UILayoutConstraintAxisVertical;
	page.spacing = 14;
	page.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:page];

	UILayoutGuide* safe = self.view.safeAreaLayoutGuide;
	[NSLayoutConstraint activateConstraints:@[
		[page.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:20],
		[page.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-20],
		[page.topAnchor constraintEqualToAnchor:safe.topAnchor constant:14],
		[page.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-10],
		// the row fills the scroll view's height and centres when it fits
		[row.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
		[row.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
		[row.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
		[row.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
		[row.heightAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.heightAnchor],
		[row.widthAnchor constraintGreaterThanOrEqualToAnchor:scroll.frameLayoutGuide.widthAnchor],
	]];
	row.distribution = UIStackViewDistributionEqualSpacing;
	if (ctCards <= 1) row.alignment = UIStackViewAlignmentFill;
}

- (void)cancelTapped { [self finish:-1]; }
- (void)lanTapped { [self finish:IOSPICKER_LAN]; }

// A main game's add-ons over the picker: the game itself, then each add-on
- (void)showAddons:(int)iMain
{
	[addonsBack removeFromSuperview];
	addonsBack = [[UIView alloc] initWithFrame:self.view.bounds];
	addonsBack.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	addonsBack.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.7];
	addonsBack.alpha = 0;
	[addonsBack addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(closeAddons)]];
	[self.view addSubview:addonsBack];

	const Family f = FamilyOf(_aEntries[iMain].flags);
	NSString *title, *edition;
	SplitName(_aEntries[iMain].name, &title, &edition);

	UIView* panel = [[UIView alloc] init];
	panel.backgroundColor = [UIColor colorWithRed:0.09 green:0.08 blue:0.08 alpha:0.98];
	panel.layer.cornerRadius = 20;
	panel.layer.borderWidth = 1.5;
	panel.layer.borderColor = RGB(f.top, 0.9).CGColor;
	panel.translatesAutoresizingMaskIntoConstraints = NO;
	[addonsBack addSubview:panel];

	UILabel* head = [[UILabel alloc] init];
	head.text = [title uppercaseString];
	head.font = [UIFont systemFontOfSize:20 weight:UIFontWeightHeavy];
	head.textColor = UIColor.whiteColor;
	UIButton* close = [UIButton buttonWithType:UIButtonTypeClose];
	[close addTarget:self action:@selector(closeAddons) forControlEvents:UIControlEventTouchUpInside];
	UIStackView* headRow = [[UIStackView alloc] initWithArrangedSubviews:@[ head, [UIView new], close ]];
	headRow.alignment = UIStackViewAlignmentCenter;

	UIStackView* list = [[UIStackView alloc] init];
	list.axis = UILayoutConstraintAxisVertical;
	list.spacing = 8;
	NSMutableArray<NSNumber*>* rows = [NSMutableArray arrayWithObject:@(iMain)];
	[rows addObjectsFromArray:AddonsOf(iMain)];
	for (NSNumber* n in rows)
	{
		const int i = n.intValue;
		NSString *t, *ed;
		SplitName(_aEntries[i].name, &t, &ed);
		UIButton* b = [UIButton buttonWithType:UIButtonTypeSystem];
		NSString* label = (i == iMain) ? [NSString stringWithFormat:@"%@  ·  the main game", ed.length ? ed : t]
		                               : (ed.length ? ed : t);
		[b setTitle:label forState:UIControlStateNormal];
		b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
		b.titleLabel.font = [UIFont systemFontOfSize:17 weight:(i == iMain ? UIFontWeightSemibold : UIFontWeightBold)];
		b.titleLabel.adjustsFontSizeToFitWidth = YES;
		b.titleLabel.minimumScaleFactor = 0.7;
		b.tintColor = UIColor.whiteColor;
		b.backgroundColor = (i == iMain) ? [UIColor colorWithWhite:1.0 alpha:0.08] : RGB(f.top, 0.35);
		b.layer.cornerRadius = 12;
		b.contentEdgeInsets = UIEdgeInsetsMake(0, 16, 0, 16);
		b.tag = i;
		[b.heightAnchor constraintEqualToConstant:44].active = YES;
		[b addTarget:self action:@selector(addonTapped:) forControlEvents:UIControlEventTouchUpInside];
		[list addArrangedSubview:b];
	}
	UIScrollView* scroll = [[UIScrollView alloc] init];
	scroll.translatesAutoresizingMaskIntoConstraints = NO;
	list.translatesAutoresizingMaskIntoConstraints = NO;
	[scroll addSubview:list];

	UIStackView* stack = [[UIStackView alloc] initWithArrangedSubviews:@[ headRow, scroll ]];
	stack.axis = UILayoutConstraintAxisVertical;
	stack.spacing = 12;
	stack.translatesAutoresizingMaskIntoConstraints = NO;
	[panel addSubview:stack];

	const CGFloat listHeight = rows.count * 52.0;
	NSLayoutConstraint* tall = [scroll.heightAnchor constraintEqualToConstant:listHeight];
	tall.priority = UILayoutPriorityDefaultHigh;
	[NSLayoutConstraint activateConstraints:@[
		[panel.centerXAnchor constraintEqualToAnchor:addonsBack.centerXAnchor],
		[panel.centerYAnchor constraintEqualToAnchor:addonsBack.centerYAnchor],
		[panel.widthAnchor constraintEqualToConstant:440],
		[panel.heightAnchor constraintLessThanOrEqualToAnchor:addonsBack.safeAreaLayoutGuide.heightAnchor constant:-24],
		[stack.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:18],
		[stack.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-18],
		[stack.topAnchor constraintEqualToAnchor:panel.topAnchor constant:14],
		[stack.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor constant:-18],
		tall,
		[list.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
		[list.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
		[list.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
		[list.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
		[list.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor],
	]];
	// (a tap on the panel itself doesn't close it)
	[panel addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:nil action:nil]];
	[UIView animateWithDuration:0.18 animations:^{ self->addonsBack.alpha = 1; }];
}

- (void)closeAddons
{
	UIView* v = addonsBack;
	addonsBack = nil;
	[UIView animateWithDuration:0.15 animations:^{ v.alpha = 0; } completion:^(BOOL f) { [v removeFromSuperview]; }];
}

- (void)addonTapped:(UIButton*)b
{
	[self finish:(int)b.tag];
}
@end

// ---------------------------------------------------------------- at start

static UIWindowScene* Scene()
{
	for (UIScene* scene in UIApplication.sharedApplication.connectedScenes)
		if ([scene isKindOfClass:UIWindowScene.class]) return (UIWindowScene*)scene;
	return nil;
}

int IOSPicker_Run(int bLan)
{
	if (_ctEntries <= 0) return -1;
	__block int picked = -100;
	UIWindowScene* scene = Scene();
	UIWindow* window = scene ? [[UIWindow alloc] initWithWindowScene:scene] : [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
	IOSPickerController* menu = [IOSPickerController new];
	menu.lan = bLan != 0;
	menu.done = ^(int p) { picked = p; };
	window.rootViewController = menu;
	window.windowLevel = UIWindowLevelNormal + 1;
	[window makeKeyAndVisible];
	while (picked == -100)
	{
		@autoreleasepool
		{
			[[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
		}
	}
	window.hidden = YES;
	window.rootViewController = nil;
	printf("Game picker: chose %d of %d\n", picked, _ctEntries);
	return picked;
}

// ---------------------------------------------------------------- switching

#define KEY_NEXT_FILE @"razeNextGameFile"
#define KEY_NEXT_NAME @"razeNextGameName"
#define KEY_NEXT_TIME @"razeNextGameTime"
#define NEXT_GAME_TIME 600.0 // seconds

int IOSPicker_TakeNext(void)
{
	// its "tap to start" notification, if still there, has done its job
	[[UNUserNotificationCenter currentNotificationCenter] removeAllDeliveredNotifications];

	NSUserDefaults* d = NSUserDefaults.standardUserDefaults;
	NSString* file = [d stringForKey:KEY_NEXT_FILE];
	NSString* name = [d stringForKey:KEY_NEXT_NAME];
	const double age = NSDate.timeIntervalSinceReferenceDate - [d doubleForKey:KEY_NEXT_TIME];
	[d removeObjectForKey:KEY_NEXT_FILE];
	[d removeObjectForKey:KEY_NEXT_NAME];
	[d removeObjectForKey:KEY_NEXT_TIME];
	if (!file || !name || age < 0 || age > NEXT_GAME_TIME) return -1;
	for (int i = 0; i < _ctEntries; i++)
	{
		// (the app's folder moves with each install: the same file from Documents on)
		NSString* f = @(_aEntries[i].file);
		NSRange r = [f rangeOfString:@"/Documents/"], rs = [file rangeOfString:@"/Documents/"];
		NSString* a = r.location != NSNotFound ? [f substringFromIndex:r.location] : f;
		NSString* b = rs.location != NSNotFound ? [file substringFromIndex:rs.location] : file;
		if ([a isEqualToString:b] && [name isEqualToString:@(_aEntries[i].name)])
		{
			printf("Game picker: the game switched to, %s\n", _aEntries[i].name);
			return i;
		}
	}
	return -1;
}

static void CloseForNext(int picked)
{
	const IOSPickEntry* e = &_aEntries[picked];
	NSUserDefaults* d = NSUserDefaults.standardUserDefaults;
	[d setObject:@(e->file) forKey:KEY_NEXT_FILE];
	[d setObject:@(e->name) forKey:KEY_NEXT_NAME];
	[d setDouble:NSDate.timeIntervalSinceReferenceDate forKey:KEY_NEXT_TIME];
	[d synchronize];
	IOSGame_WriteConfig();
	printf("Switch game: %s, the app closes\n", e->name);
	fflush(stdout);

	NSString* title = [NSString stringWithUTF8String:e->name] ?: @"the game";
	UNUserNotificationCenter* center = UNUserNotificationCenter.currentNotificationCenter;
	[center requestAuthorizationWithOptions:UNAuthorizationOptionAlert | UNAuthorizationOptionSound
		completionHandler:^(BOOL granted, NSError* err) {
		if (!granted)
		{
			// no notifications: say how it goes instead, then close
			dispatch_async(dispatch_get_main_queue(), ^{
				UIAlertController* alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Open Raze again to start %@", title]
					message:@"The app closes now. Your pick starts when you open it again (within 10 minutes)." preferredStyle:UIAlertControllerStyleAlert];
				[alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction* a) { exit(0); }]];
				UIViewController* top = Scene().keyWindow.rootViewController;
				while (top.presentedViewController) top = top.presentedViewController;
				if (top) [top presentViewController:alert animated:YES completion:nil];
				else exit(0);
			});
			return;
		}
		UNMutableNotificationContent* content = [UNMutableNotificationContent new];
		content.title = [NSString stringWithFormat:@"Tap to start %@", title];
		content.body = @"Or open Raze within 10 minutes.";
		UNNotificationRequest* request = [UNNotificationRequest requestWithIdentifier:@"raze.nextgame" content:content
			trigger:[UNTimeIntervalNotificationTrigger triggerWithTimeInterval:1 repeats:NO]];
		[center addNotificationRequest:request withCompletionHandler:^(NSError* e2) {
			dispatch_async(dispatch_get_main_queue(), ^{ exit(0); });
		}];
	}];
}

void IOSPicker_PresentSwitch(void (*pfnDone)(int bPicked))
{
	UIWindowScene* scene = Scene();
	UIViewController* host = nil;
	for (UIWindow* w in scene.windows)
		if (w.isKeyWindow) { host = w.rootViewController; break; }
	if (!host) host = scene.windows.firstObject.rootViewController;
	while (host.presentedViewController) host = host.presentedViewController;
	if (!host || _ctEntries <= 0)
	{
		if (pfnDone) pfnDone(0);
		return;
	}
	IOSPickerController* menu = [IOSPickerController new];
	menu.switching = YES;
	menu.modalPresentationStyle = UIModalPresentationFullScreen;
	__weak IOSPickerController* weakMenu = menu;
	menu.done = ^(int picked) {
		if (picked >= 0 && picked < _ctEntries)
		{
			CloseForNext(picked);
			return; // (the menu stays up until the app closes)
		}
		[weakMenu dismissViewControllerAnimated:YES completion:nil];
		if (pfnDone) pfnDone(0);
	};
	[host presentViewController:menu animated:YES completion:nil];
}
