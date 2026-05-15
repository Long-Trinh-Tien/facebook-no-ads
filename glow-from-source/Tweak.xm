#import <objc/runtime.h>
#import <dlfcn.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// ============ PREFERENCES ============
static NSString *const kPrefPath = @"/var/mobile/Library/Preferences/com.dvntm.glowprefs.plist";
#define NOTIF "com.dvntm.glowprefs/PrefChanged"
static NSMutableDictionary *P;
#define PBOOL(k, d) [P[k] ?: @(d) boolValue]

static void loadP() {
  @autoreleasepool { P = [[NSMutableDictionary alloc] initWithContentsOfFile:kPrefPath]; if (!P) P = [NSMutableDictionary new]; }
}
static void saveP() { [P writeToFile:kPrefPath atomically:YES]; }

// ============ SETTINGS VC ============
@interface GlowVC : UITableViewController @end
@implementation GlowVC
+ (NSArray *)sections {
  return @[
    @[@{@"h":@"Main"}],
    @[@{@"k":@"RemoveAds", @"l":@"Remove Ads"},
      @{@"k":@"RemovePYMK", @"l":@"Remove PYMK"},
      @{@"k":@"RemoveReelsCarousel", @"l":@"Remove Reels Carousel"},
      @{@"k":@"RemoveRecs", @"l":@"Remove Recommendations"}],
    @[@{@"h":@"Stories"}],
    @[@{@"k":@"AnonymousStories", @"l":@"Incognito Mode"},
      @{@"k":@"DisableAutoNext", @"l":@"Disable Auto Next"}],
    @[@{@"h":@"Confirmation"}],
    @[@{@"k":@"PostLikeConfirm", @"l":@"Confirm Post Like"},
      @{@"k":@"ReelsLikeConfirm", @"l":@"Confirm Reels Like"}],
    @[@{@"h":@"Other"}],
    @[@{@"k":@"AutoClearCache", @"l":@"Auto Clear Cache"},
      @{@"k":@"HideOverlay", @"l":@"Hide Overlay"}],
  ];
}
- (id)init {
  self = [super initWithStyle:UITableViewStyleGrouped];
  self.title = @"Glow";
  self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Apply" style:UIBarButtonItemStylePlain target:self action:@selector(apply)];
  return self;
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return [[self class] sections].count; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
  return [[[self class] sections][s][0][@"h"] isEqualToString:@"h"] ? 0 : [[self class] sections][s].count;
}
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
  id item = [[self class] sections][ip.section][ip.row];
  UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"c"];
  if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"c"];
  c.textLabel.text = item[@"l"]; c.selectionStyle = UITableViewCellSelectionStyleNone;
  UISwitch *s = [[UISwitch alloc] init]; s.on = PBOOL(item[@"k"], YES);
  s.tag = ip.section*100+ip.row; [s addTarget:self action:@selector(tog:) forControlEvents:UIControlEventValueChanged];
  c.accessoryView = s; return c;
}
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
  return [[self class] sections][s][0][@"h"];
}
- (void)tog:(UISwitch *)s {
  id item = [[self class] sections][s.tag/100][s.tag%100];
  P[item[@"k"]] = @(s.on);
}
- (void)apply { saveP(); CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR(NOTIF), NULL, NULL, YES);
  UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Glow" message:@"Restart app?" preferredStyle:UIAlertControllerStyleAlert];
  [a addAction:[UIAlertAction actionWithTitle:@"Later" style:UIAlertActionStyleCancel handler:nil]];
  [a addAction:[UIAlertAction actionWithTitle:@"Restart" style:UIAlertActionStyleDefault handler:^(id _) { exit(0); }]];
  [self presentViewController:a animated:YES completion:nil];
}
@end

static void showGlowSettings() {
  dispatch_async(dispatch_get_main_queue(), ^{
    UIViewController *vc = UIApplication.sharedApplication.keyWindow.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    [vc presentViewController:[[UINavigationController alloc] initWithRootViewController:[GlowVC new]] animated:YES completion:nil];
  });
}

// ============ WELCOME POPUP ============
static void showWelcomeIfNeeded() {
  if ([NSUserDefaults.standardUserDefaults boolForKey:@"glow_welcomed"]) return;
  [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"glow_welcomed"];
  dispatch_async(dispatch_get_main_queue(), ^{
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Glow" message:@"Long press any tab to open settings" preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [UIApplication.sharedApplication.keyWindow.rootViewController presentViewController:a animated:YES completion:nil];
  });
}

// ============ HOOKS ============

// --- Ads blocking ---
%group Ads
%hook FBMemFeedStory
- (id)initWithFBTree:(void *)t { id r = %orig; return [r sponsoredData] ? nil : r; }
%end
%hook FBVideoChannelPlaylistItem
- (id)initWithFBTree:(id)t { id r = %orig; return [r isSponsored] ? nil : r; }
%end
%end

// --- Anonymous stories ---
%group Anonymous
%hook FBSnacksUnifiedSeenStateMutator
- (void)_attemptSendSeenStateAndHandleResponse:(id)r bucket:(id)b { if (PBOOL(@"AnonymousStories", YES)) return; %orig; }
- (void)_markThreadsAsSeen:(id)t fromBucket:(id)b withTrackingString:(id)s isAnonymousView:(BOOL)a completion:(id)c { if (PBOOL(@"AnonymousStories", YES)) return; %orig; }
%end
%end

// --- Auto clear cache ---
%group Cache
- (void)glow_clearCache {
  dispatch_async(dispatch_get_global_queue(0, 0), ^{
    NSString *c = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES)[0];
    [[NSFileManager defaultManager] removeItemAtPath:c error:nil];
  });
}
%end

// --- Tab bar long press for settings ---
%group Tab
%hook UITabBar
- (void)didMoveToWindow {
  %orig;
  if (self.glow_hasLP) return;
  self.glow_hasLP = YES;
  UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(glow_show)];
  lp.minimumPressDuration = 0.8; [self addGestureRecognizer:lp];
}
%property (nonatomic) BOOL glow_hasLP;
%new - (void)glow_show { if (UIGestureRecognizerStateBegan == 0) showGlowSettings(); }
%end
%end

// ============ CONSTRUCTOR ============
%ctor {
  @autoreleasepool {
    loadP();
    NSString *fw = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"Frameworks/FBSharedFramework.framework/FBSharedFramework"];
    dlopen([fw UTF8String], RTLD_NOW | RTLD_GLOBAL);

    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)loadP, CFSTR(NOTIF), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);

    if (PBOOL(@"RemoveAds", YES))          %init(Ads);
    if (PBOOL(@"AnonymousStories", YES))    %init(Anonymous);
    %init(Tab);

    // Welcome + cache clear (non-hooks, run directly)
    showWelcomeIfNeeded();
    if (PBOOL(@"AutoClearCache", NO)) {
      dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSString *c = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES)[0];
        [[NSFileManager defaultManager] removeItemAtPath:c error:nil];
      });
    }
    NSLog(@"[Glow] init OK");
  }
}
