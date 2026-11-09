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
// i_ios.mm: LAN multiplayer's questions, and the command line they make
extern "C" int IOS_HasLanGames(const char* const* names, int count);


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

// The five cards: a family each (Duke Nukem 3D with NAM and WWII GI, Blood,
// Redneck Rampage with Rides Again, Shadow Warrior, PowerSlave)
enum { FAM_DUKE, FAM_BLOOD, FAM_RR, FAM_SW, FAM_PS, FAM_COUNT };

typedef struct
{
	const char* title;	// the card's name
	const char* symbol;	// an SF Symbol, the card's emblem
	CGFloat top[3], bottom[3];	// the card's gradient
} Family;

static const Family families[FAM_COUNT] =
{
	{ "Duke Nukem 3D", "bolt.fill", { 0.88, 0.27, 0.05 }, { 0.30, 0.05, 0.02 } },
	{ "Blood", "drop.fill", { 0.62, 0.02, 0.06 }, { 0.14, 0.00, 0.02 } },
	{ "Redneck Rampage", "hare.fill", { 0.70, 0.42, 0.12 }, { 0.20, 0.10, 0.03 } },
	{ "Shadow Warrior", "flame.fill", { 0.05, 0.47, 0.36 }, { 0.02, 0.12, 0.10 } },
	{ "PowerSlave", "sun.max.fill", { 0.82, 0.62, 0.20 }, { 0.30, 0.17, 0.04 } },
};

static int FamilyOf(int flags)
{
	if (flags & PF_BLOOD) return FAM_BLOOD;
	if (flags & PF_SW) return FAM_SW;
	if (flags & (PF_RR | PF_RRRA)) return FAM_RR;
	if (flags & (PF_POWERSLAVE | PF_EXHUMED)) return FAM_PS;
	return FAM_DUKE; // (and NAM, Napalm, WWII GI: Duke's engine)
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

// A family's games: its main games first, then the add-ons (each after the
// main games, in the order found)
static NSArray<NSNumber*>* GamesOf(int fam)
{
	NSMutableArray<NSNumber*>* a = [NSMutableArray array];
	for (int pass = 0; pass < 2; pass++)
		for (int i = 0; i < _ctEntries; i++)
			if (FamilyOf(_aEntries[i].flags) == fam && (_aEntries[i].bAddon != 0) == (pass == 1)) [a addObject:@(i)];
	return a;
}

// What a tap on a family's card starts: the one of its games played last,
// else its first main game
static int TapTarget(int fam)
{
	if (_iLast >= 0 && _iLast < _ctEntries && FamilyOf(_aEntries[_iLast].flags) == fam) return _iLast;
	NSArray<NSNumber*>* g = GamesOf(fam);
	return g.count ? g[0].intValue : -1;
}

// ---------------------------------------------------------------- a card

#define HOLD_TIME 0.5
#define TAP_SLOP 12.0 // points a finger may move and still tap

@interface IOSGameCard : UIControl
@property (nonatomic) int family;
@property (nonatomic, copy) void (^onTap)(int family);
@property (nonatomic, copy) void (^onHold)(int family);
@end

@implementation IOSGameCard
{
	CAGradientLayer* gradient;
	CAShapeLayer* ring;
	NSTimer* holdTimer;
	CGPoint down;
	BOOL fired;	// held long enough: its games opened
	BOOL moved;	// slid: no tap
}

- (instancetype)initWithFamily:(int)fam
{
	if (!(self = [super initWithFrame:CGRectZero])) return nil;
	_family = fam;
	const Family* f = &families[fam];
	const int target = TapTarget(fam);
	NSString *title, *edition;
	SplitName(_aEntries[target].name, &title, &edition);
	const int ctMore = (int)GamesOf(fam).count - 1;

	self.layer.cornerRadius = 18;
	self.layer.borderWidth = 1.5;
	self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.18].CGColor;
	self.clipsToBounds = YES;

	gradient = [CAGradientLayer layer];
	gradient.colors = @[ (id)RGB(f->top).CGColor, (id)RGB(f->bottom).CGColor ];
	gradient.startPoint = CGPointMake(0.2, 0.0);
	gradient.endPoint = CGPointMake(0.8, 1.0);
	[self.layer addSublayer:gradient];

	// the emblem, big and faint behind the name, and small and bright above it
	UIImageSymbolConfiguration* big = [UIImageSymbolConfiguration configurationWithPointSize:120 weight:UIImageSymbolWeightBold];
	UIImageView* emblem = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@(f->symbol) withConfiguration:big]];
	emblem.tintColor = [UIColor colorWithWhite:1.0 alpha:0.10];
	emblem.contentMode = UIViewContentModeScaleAspectFit;
	emblem.translatesAutoresizingMaskIntoConstraints = NO;
	[self addSubview:emblem];
	UIImageSymbolConfiguration* small = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightSemibold];
	UIImageView* badge = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@(f->symbol) withConfiguration:small]];
	badge.tintColor = [UIColor colorWithWhite:1.0 alpha:0.9];
	badge.translatesAutoresizingMaskIntoConstraints = NO;
	[self addSubview:badge];

	UILabel* name = [[UILabel alloc] init];
	name.text = [@(f->title) uppercaseString];
	name.textColor = UIColor.whiteColor;
	name.font = [UIFont systemFontOfSize:21 weight:UIFontWeightHeavy];
	name.numberOfLines = 3;
	name.adjustsFontSizeToFitWidth = YES;
	name.minimumScaleFactor = 0.55;
	name.layer.shadowColor = UIColor.blackColor.CGColor;
	name.layer.shadowOpacity = 0.6;
	name.layer.shadowRadius = 3;
	name.layer.shadowOffset = CGSizeMake(0, 1);

	// what a tap starts
	UILabel* sub = [[UILabel alloc] init];
	sub.text = edition.length ? edition : title;
	sub.textColor = [UIColor colorWithWhite:1.0 alpha:0.8];
	sub.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
	sub.numberOfLines = 2;
	sub.adjustsFontSizeToFitWidth = YES;
	sub.minimumScaleFactor = 0.7;

	UILabel* foot = [[UILabel alloc] init];
	foot.text = ctMore <= 0 ? @"" : [NSString stringWithFormat:@"HOLD · %d MORE", ctMore];
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
		[badge.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14],
		[badge.topAnchor constraintEqualToAnchor:self.topAnchor constant:14],
		[emblem.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:24],
		[emblem.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:20],
		[emblem.widthAnchor constraintEqualToAnchor:self.widthAnchor multiplier:0.85],
		[emblem.heightAnchor constraintEqualToAnchor:emblem.widthAnchor],
		[text.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14],
		[text.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
		[text.topAnchor constraintEqualToAnchor:badge.bottomAnchor constant:10],
		[text.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-12],
	]];
	if (_iLast >= 0 && _iLast < _ctEntries && FamilyOf(_aEntries[_iLast].flags) == fam)
	{
		UILabel* last = [[UILabel alloc] init];
		last.text = @" LAST ";
		last.font = [UIFont systemFontOfSize:10 weight:UIFontWeightHeavy];
		last.textColor = UIColor.blackColor;
		last.backgroundColor = [UIColor colorWithRed:1.0 green:0.82 blue:0.35 alpha:1.0];
		last.layer.cornerRadius = 7;
		last.clipsToBounds = YES;
		last.translatesAutoresizingMaskIntoConstraints = NO;
		[self addSubview:last];
		[cons addObjectsFromArray:@[
			[last.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],
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
		self.transform = (highlighted && !self->moved) ? CGAffineTransformMakeScale(0.97, 0.97) : CGAffineTransformIdentity;
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
	fired = NO;
	moved = NO;
	down = [touch locationInView:self];
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
		card->holdTimer = nil;
		card->fired = YES;
		[card stopRing];
		[[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
		if (card.onHold) card.onHold(card.family);
	}];
	return YES;
}

- (BOOL)continueTrackingWithTouch:(UITouch*)touch withEvent:(UIEvent*)event
{
	// slid: neither a tap nor a hold
	const CGPoint p = [touch locationInView:self];
	if (!moved && hypot(p.x - down.x, p.y - down.y) > TAP_SLOP)
	{
		moved = YES;
		[self stopRing];
		self.highlighted = NO;
	}
	return !moved;
}

- (void)endTrackingWithTouch:(UITouch*)touch withEvent:(UIEvent*)event
{
	const BOOL tap = !fired && !moved && holdTimer != nil;
	[self stopRing];
	if (tap && self.onTap) self.onTap(self.family);
}

- (void)cancelTrackingWithEvent:(UIEvent*)event
{
	moved = YES;
	[self stopRing];
}
@end

// ---------------------------------------------------------------- the picker

@interface IOSPickerController : UIViewController
@property (nonatomic, copy) void (^done)(int picked); // an index, IOSPICKER_LAN, or -1 (Cancel)
@property (nonatomic) BOOL switching;	// "Switch game", with Cancel
@property (nonatomic) BOOL lan;		// "LAN multiplayer" shows
- (void)reopen;
@end

@implementation IOSPickerController
{
	UIView* gamesBack;
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

// (shown again after LAN multiplayer's questions, Back)
- (void)reopen
{
	finished = NO;
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
	UIStackView* top = [[UIStackView alloc] initWithArrangedSubviews:@[ logo, heading, [UIView new] ]];
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

	// the cards: one for each family with a game here, side by side, all on
	// the screen (no scrolling)
	UIStackView* row = [[UIStackView alloc] init];
	row.axis = UILayoutConstraintAxisHorizontal;
	row.spacing = 12;
	row.distribution = UIStackViewDistributionFillEqually;
	__weak IOSPickerController* weakSelf = self;
	for (int fam = 0; fam < FAM_COUNT; fam++)
	{
		if (TapTarget(fam) < 0) continue;
		IOSGameCard* card = [[IOSGameCard alloc] initWithFamily:fam];
		card.onTap = ^(int f) { [weakSelf finish:TapTarget(f)]; };
		card.onHold = ^(int f) { [weakSelf showGames:f]; };
		[row addArrangedSubview:card];
	}

	UILabel* hint = [[UILabel alloc] init];
	hint.text = @"Tap a game to play  ·  Hold it for the other editions and add-ons";
	hint.textColor = [UIColor colorWithWhite:1.0 alpha:0.5];
	hint.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
	hint.adjustsFontSizeToFitWidth = YES;
	hint.minimumScaleFactor = 0.7;
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
		[lanButton setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
		[lanButton addTarget:self action:@selector(lanTapped) forControlEvents:UIControlEventTouchUpInside];
		[bottom addArrangedSubview:lanButton];
	}

	UIStackView* page = [[UIStackView alloc] initWithArrangedSubviews:@[ top, row, bottom ]];
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
	]];
}

- (void)cancelTapped { [self finish:-1]; }
- (void)lanTapped { [self finish:IOSPICKER_LAN]; }

// A family's games over the picker: its main games, then its add-ons
- (void)showGames:(int)fam
{
	[gamesBack removeFromSuperview];
	gamesBack = [[UIView alloc] initWithFrame:self.view.bounds];
	gamesBack.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	gamesBack.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.7];
	gamesBack.alpha = 0;
	UITapGestureRecognizer* away = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(backTapped:)];
	[gamesBack addGestureRecognizer:away];
	[self.view addSubview:gamesBack];

	const Family* f = &families[fam];
	UIView* panel = [[UIView alloc] init];
	panel.backgroundColor = [UIColor colorWithRed:0.09 green:0.08 blue:0.08 alpha:0.98];
	panel.layer.cornerRadius = 20;
	panel.layer.borderWidth = 1.5;
	panel.layer.borderColor = RGB(f->top, 0.9).CGColor;
	panel.tag = 7;
	panel.translatesAutoresizingMaskIntoConstraints = NO;
	[gamesBack addSubview:panel];

	UILabel* head = [[UILabel alloc] init];
	head.text = [@(f->title) uppercaseString];
	head.font = [UIFont systemFontOfSize:20 weight:UIFontWeightHeavy];
	head.textColor = UIColor.whiteColor;
	UIButton* close = [UIButton buttonWithType:UIButtonTypeClose];
	[close addTarget:self action:@selector(closeGames) forControlEvents:UIControlEventTouchUpInside];
	UIStackView* headRow = [[UIStackView alloc] initWithArrangedSubviews:@[ head, [UIView new], close ]];
	headRow.alignment = UIStackViewAlignmentCenter;

	UIStackView* list = [[UIStackView alloc] init];
	list.axis = UILayoutConstraintAxisVertical;
	list.spacing = 8;
	NSArray<NSNumber*>* games = GamesOf(fam);
	BOOL addonsHeader = NO;
	for (NSNumber* n in games)
	{
		const int i = n.intValue;
		const BOOL addon = _aEntries[i].bAddon != 0;
		if (addon && !addonsHeader)
		{
			addonsHeader = YES;
			UILabel* h = [[UILabel alloc] init];
			h.text = @"ADD-ONS";
			h.font = [UIFont systemFontOfSize:12 weight:UIFontWeightHeavy];
			h.textColor = [UIColor colorWithRed:1.0 green:0.82 blue:0.45 alpha:1.0];
			[list addArrangedSubview:h];
		}
		NSString *t, *ed;
		SplitName(_aEntries[i].name, &t, &ed);
		NSString* label = ed.length ? ed : t;
		if (i == _iLast) label = [label stringByAppendingString:@"  ·  last played"];
		UIButton* b = [UIButton buttonWithType:UIButtonTypeSystem];
		[b setTitle:label forState:UIControlStateNormal];
		b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
		b.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
		b.titleLabel.adjustsFontSizeToFitWidth = YES;
		b.titleLabel.minimumScaleFactor = 0.7;
		b.tintColor = UIColor.whiteColor;
		b.backgroundColor = addon ? [UIColor colorWithWhite:1.0 alpha:0.08] : RGB(f->top, 0.4);
		b.layer.cornerRadius = 12;
		b.contentEdgeInsets = UIEdgeInsetsMake(0, 16, 0, 16);
		b.tag = i;
		[b.heightAnchor constraintEqualToConstant:44].active = YES;
		[b addTarget:self action:@selector(gameTapped:) forControlEvents:UIControlEventTouchUpInside];
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

	NSLayoutConstraint* tall = [scroll.heightAnchor constraintEqualToConstant:(games.count + (addonsHeader ? 1 : 0)) * 52.0];
	tall.priority = UILayoutPriorityDefaultHigh;
	[NSLayoutConstraint activateConstraints:@[
		[panel.centerXAnchor constraintEqualToAnchor:gamesBack.centerXAnchor],
		[panel.centerYAnchor constraintEqualToAnchor:gamesBack.centerYAnchor],
		[panel.widthAnchor constraintEqualToConstant:460],
		[panel.heightAnchor constraintLessThanOrEqualToAnchor:gamesBack.safeAreaLayoutGuide.heightAnchor constant:-24],
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
	[UIView animateWithDuration:0.18 animations:^{ self->gamesBack.alpha = 1; }];
}

// a tap off the panel closes it (one on the panel does nothing)
- (void)backTapped:(UITapGestureRecognizer*)g
{
	UIView* panel = [gamesBack viewWithTag:7];
	if (panel && CGRectContainsPoint(panel.bounds, [g locationInView:panel])) return;
	[self closeGames];
}

- (void)closeGames
{
	UIView* v = gamesBack;
	gamesBack = nil;
	[UIView animateWithDuration:0.15 animations:^{ v.alpha = 0; } completion:^(BOOL f) { [v removeFromSuperview]; }];
}

- (void)gameTapped:(UIButton*)b
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

// The picker's window at start: kept up while LAN multiplayer asks its
// questions over it (IOSPicker_Close takes it away)
static UIWindow* _pickerWindow = nil;
static IOSPickerController* _pickerMenu = nil;

void IOSPicker_Show(int bLan)
{
	if (_ctEntries <= 0) return;
	if (!_pickerWindow)
	{
		UIWindowScene* scene = Scene();
		_pickerWindow = scene ? [[UIWindow alloc] initWithWindowScene:scene] : [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
		_pickerMenu = [IOSPickerController new];
		_pickerMenu.lan = bLan != 0;
		_pickerWindow.rootViewController = _pickerMenu;
		_pickerWindow.windowLevel = UIWindowLevelNormal + 1;
	}
	[_pickerWindow makeKeyAndVisible];
	// (drawn before what comes over it)
	[[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
}

int IOSPicker_Run(int bLan)
{
	if (_ctEntries <= 0) return -1;
	__block int picked = -100;
	const bool wasUp = _pickerWindow != nil;
	IOSPicker_Show(bLan);
	if (wasUp) [_pickerMenu reopen];
	_pickerMenu.done = ^(int p) { picked = p; };
	while (picked == -100)
	{
		@autoreleasepool
		{
			[[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
		}
	}
	printf("Game picker: chose %d of %d\n", picked, _ctEntries);
	// (LAN multiplayer: kept up, its questions come over it)
	if (picked != IOSPICKER_LAN) IOSPicker_Close();
	return picked;
}

void IOSPicker_Close(void)
{
	if (!_pickerWindow) return;
	_pickerWindow.hidden = YES;
	_pickerWindow.rootViewController = nil;
	_pickerWindow = nil;
	_pickerMenu = nil;
}

// ---------------------------------------------------------------- switching

#define KEY_NEXT_FILE @"razeNextGameFile"
#define KEY_NEXT_NAME @"razeNextGameName"
#define KEY_NEXT_TIME @"razeNextGameTime"
#define KEY_NEXT_LAN @"razeNextLan" // LAN multiplayer picked in "Switch game": its time
#define NEXT_GAME_TIME 600.0 // seconds

// LAN multiplayer picked in "Switch game" before the app closed: the start
// picker goes straight to its questions (IOSPicker_StartsWithLan)
static bool _bStartWithLan = false;

int IOSPicker_StartsWithLan(void)
{
	const bool b = _bStartWithLan;
	_bStartWithLan = false;
	return b ? 1 : 0;
}

int IOSPicker_TakeNext(void)
{
	// its "tap to start" notification, if still there, has done its job
	[[UNUserNotificationCenter currentNotificationCenter] removeAllDeliveredNotifications];

	NSUserDefaults* d = NSUserDefaults.standardUserDefaults;
	const double ageLan = NSDate.timeIntervalSinceReferenceDate - [d doubleForKey:KEY_NEXT_LAN];
	if ([d objectForKey:KEY_NEXT_LAN])
	{
		[d removeObjectForKey:KEY_NEXT_LAN];
		if (ageLan >= 0 && ageLan <= NEXT_GAME_TIME)
		{
			printf("Game picker: LAN multiplayer, as picked before the app closed\n");
			_bStartWithLan = true;
			return -1;
		}
	}
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

// The pick kept (a game, or picked < 0: LAN multiplayer), the settings
// written, a "Tap to start" notification asked for, and the app closed
static void CloseForNext(int picked)
{
	NSUserDefaults* d = NSUserDefaults.standardUserDefaults;
	NSString* title;
	if (picked >= 0)
	{
		const IOSPickEntry* e = &_aEntries[picked];
		[d setObject:@(e->file) forKey:KEY_NEXT_FILE];
		[d setObject:@(e->name) forKey:KEY_NEXT_NAME];
		[d setDouble:NSDate.timeIntervalSinceReferenceDate forKey:KEY_NEXT_TIME];
		[d removeObjectForKey:KEY_NEXT_LAN];
		title = [NSString stringWithUTF8String:e->name] ?: @"the game";
	}
	else
	{
		[d setDouble:NSDate.timeIntervalSinceReferenceDate forKey:KEY_NEXT_LAN];
		[d removeObjectForKey:KEY_NEXT_FILE];
		title = @"LAN multiplayer";
	}
	[d synchronize];
	IOSGame_WriteConfig();
	printf("Switch game: %s, the app closes\n", title.UTF8String);
	fflush(stdout);

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
	// LAN multiplayer here too: the app closes, and its questions come at the
	// next start (asked here, over a game held mid-frame, they hung)
	const char** names = (const char**)calloc(_ctEntries > 0 ? _ctEntries : 1, sizeof(char*));
	for (int i = 0; i < _ctEntries; i++) names[i] = _aEntries[i].name;
	menu.lan = IOS_HasLanGames(names, _ctEntries) != 0;
	free(names);
	__weak IOSPickerController* weakMenu = menu;
	menu.done = ^(int picked) {
		if (picked == IOSPICKER_LAN)
		{
			CloseForNext(-1);
			return; // (the menu stays up until the app closes)
		}
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
