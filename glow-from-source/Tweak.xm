#import <objc/runtime.h>
#import <dlfcn.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioToolbox.h>

// ============ FORWARD DECLARATIONS ============
@interface FBMemNewsFeedEdge : NSObject
- (NSString *)category;
- (id)node;
@end
@interface FBMemFeedStory : NSObject
- (id)sponsoredData;
@end
@interface FBVideoChannelPlaylistItem : NSObject
- (BOOL)isSponsored;
@end
@interface FBSnacksMediaContainerView : UIView
@end

// ============ PREFERENCES ============
#define PREFS_PATH @"/var/mobile/Library/Preferences/com.dvntm.glowprefs.plist"
#define NOTIF_NAME "com.dvntm.glowprefs/PrefChanged"

// ============ GLOBALS ============
static NSMutableDictionary *prefs;
#define GET_BOOL(key, def) [prefs[key] ?: @(def) boolValue]

static void loadPrefs() {
  @autoreleasepool {
    prefs = [[NSMutableDictionary alloc] initWithContentsOfFile:PREFS_PATH];
    if (!prefs) prefs = [NSMutableDictionary new];
  }
}
static void savePrefs() { [prefs writeToFile:PREFS_PATH atomically:YES]; }

// ============ SETTINGS VIEW CONTROLLER ============
@interface GlowSettingsController : UITableViewController
@end
@implementation GlowSettingsController

typedef struct { NSString *key, *label, *subtitle; BOOL def; } SwitchItem;
static NSArray *allSections;

- (id)init {
  self = [super initWithStyle:UITableViewStyleGrouped];
  loadPrefs();
  allSections = @[
    @[@{@"label":@"Glow", @"type":@"header"}],
    @[@{@"key":@"RemoveAds", @"label":@"Remove Ads", @"def":@YES, @"type":@"switch"},
      @{@"key":@"RemovePYMK", @"label":@"Remove PYMK", @"def":@YES, @"type":@"switch"},
      @{@"key":@"RemoveReelsCarousel", @"label":@"Remove Reels Carousel", @"def":@YES, @"type":@"switch"},
      @{@"key":@"RemoveRecs", @"label":@"Remove Recommendations", @"def":@YES, @"type":@"switch"},
      @{@"key":@"RemoveStoryPYMK", @"label":@"Remove Story PYMK", @"def":@YES, @"type":@"switch"}],
    @[@{@"label":@"Stories", @"type":@"header"}],
    @[@{@"key":@"AnonymousStories", @"label":@"Incognito Mode", @"subtitle":@"Stay unseen", @"def":@YES, @"type":@"switch"},
      @{@"key":@"DisableAutoNext", @"label":@"Disable Auto Next", @"def":@NO, @"type":@"switch"},
      @{@"key":@"DownloadStories", @"label":@"Download Stories", @"def":@YES, @"type":@"switch"}],
    @[@{@"label":@"Download", @"type":@"header"}],
    @[@{@"key":@"DownloadVideos", @"label":@"Download Videos", @"def":@YES, @"type":@"switch"},
      @{@"key":@"DownloadReels", @"label":@"Download Reels", @"def":@YES, @"type":@"switch"},
      @{@"key":@"ReelsLongTap", @"label":@"Reels Long Tap", @"def":@YES, @"type":@"switch"}],
    @[@{@"label":@"Confirmation", @"type":@"header"}],
    @[@{@"key":@"PostLikeConfirm", @"label":@"Confirm Post Like", @"def":@NO, @"type":@"switch"},
      @{@"key":@"ReelsLikeConfirm", @"label":@"Confirm Reels Like", @"def":@NO, @"type":@"switch"}],
    @[@{@"label":@"Other", @"type":@"header"}],
    @[@{@"key":@"HideOverlay", @"label":@"Hide Overlay", @"def":@NO, @"type":@"switch"},
      @{@"key":@"AutoClearCache", @"label":@"Auto Clear Cache", @"def":@NO, @"type":@"switch"}],
  ];
  self.title = @"Glow Settings";
  self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Apply" style:UIBarButtonItemStylePlain target:self action:@selector(apply)];
  return self;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return allSections.count; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)sec {
  NSArray *rows = allSections[sec];
  return [[rows[0] objectForKey:@"type"] isEqualToString:@"header"] ? 0 : rows.count;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
  NSDictionary *item = allSections[ip.section][ip.row];
  UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"cell"];
  if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"cell"];
  cell.textLabel.text = item[@"label"];
  cell.detailTextLabel.text = item[@"subtitle"];
  UISwitch *sw = [[UISwitch alloc] init];
  sw.on = [prefs[item[@"key"]] ?: item[@"def"] boolValue];
  sw.tag = ip.section * 100 + ip.row;
  [sw addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];
  cell.accessoryView = sw;
  return cell;
}
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)sec {
  NSDictionary *item = allSections[sec][0];
  return [item[@"type"] isEqualToString:@"header"] ? item[@"label"] : nil;
}

- (void)toggle:(UISwitch *)sw {
  NSInteger section = sw.tag / 100, row = sw.tag % 100;
  NSDictionary *item = allSections[section][row];
  prefs[item[@"key"]] = @(sw.on);
}
- (void)apply {
  savePrefs();
  CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
    CFSTR(NOTIF_NAME), NULL, NULL, YES);
  UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Glow" message:@"Settings saved. Restart app to apply?" preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:@"Later" style:UIAlertActionStyleCancel handler:nil]];
  [alert addAction:[UIAlertAction actionWithTitle:@"Restart" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { exit(0); }]];
  [self presentViewController:alert animated:YES completion:nil];
}
@end

// ============ SETTINGS LAUNCHER ============
static void showGlowSettings(UIViewController *vc) {
  GlowSettingsController *s = [[GlowSettingsController alloc] init];
  UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:s];
  [vc presentViewController:nav animated:YES completion:nil];
}

// ============ HOOK GROUPS ============

// --- ADS ---
%group Ads
%hook FBMemNewsFeedEdge
- (id)initWithFBTree:(void *)t {
  id r = %orig; id c = [r category];
  return (c && [c isEqualToString:@"ORGANIC"]) ? r : nil;
}
%end
%hook FBMemFeedStory
- (id)initWithFBTree:(void *)t {
  id r = %orig; return [r sponsoredData] ? nil : r;
}
%end
%hook FBVideoChannelPlaylistItem
- (id)initWithFBTree:(id)t {
  id r = %orig; return [r isSponsored] ? nil : r;
}
%end
%end

// --- CONFIRM LIKE (FBLikeActionHandler removed in 560.x - placeholder for future) ---
%group ConfirmLike
// TODO: find new like handler class in FB 560.x
%end

// --- DOWNLOAD VIDEO (VideoContainerView removed in 560.x - placeholder) ---
%group DownloadVideo
// TODO: find new video container class in FB 560.x
%end

// --- DOWNLOAD STORY (placeholder - need to find new class for FB 560.x) ---
%group DownloadStory
%end

// --- ANONYMOUS STORIES ---
%group AnonymousStories
%hook FBSnacksUnifiedSeenStateMutator
- (void)_attemptSendSeenStateAndHandleResponse:(id)r bucket:(id)b {
  if (GET_BOOL(@"AnonymousStories", YES)) return; %orig;
}
- (void)_markThreadsAsSeen:(id)t fromBucket:(id)b withTrackingString:(id)s isAnonymousView:(BOOL)a completion:(id)c {
  if (GET_BOOL(@"AnonymousStories", YES)) return; %orig;
}
%end
%end

// --- DISABLE AUTO NEXT ---
%group DisableAutoNext
%hook FBSnacksBucketViewProgressBarUpdateController
- (void)startProgressUpdateWithStartProgress:(double)p {
  if (GET_BOOL(@"DisableAutoNext", NO)) return;
  %orig;
}
%end
%end

// --- AUTO CLEAR CACHE ---
%group AutoClearCache
%hook FBApplication
- (void)applicationDidFinishLaunching:(id)arg1 {
  %orig;
  if (GET_BOOL(@"AutoClearCache", NO)) {
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
      NSString *cache = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES)[0];
      [[NSFileManager defaultManager] removeItemAtPath:cache error:nil];
    });
  }
}
%end
%end

// ============ TAB LONG PRESS (Glow Settings) ============
%group Settings
%hook UITabBarController
- (void)tabBar:(id)tb didSelectItem:(id)item {
  %orig;
}
%end
// Hook long press on tab bar
%hook UITabBar
- (void)glow_setupLongPress {
  for (UIGestureRecognizer *g in self.gestureRecognizers)
    if ([g isKindOfClass:[UILongPressGestureRecognizer class]]) return;
  UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(glow_showSettings)];
  lp.minimumPressDuration = 0.8;
  [self addGestureRecognizer:lp];
}
%new - (void)glow_showSettings {
  UIViewController *vc = [UIApplication sharedApplication].keyWindow.rootViewController;
  while (vc.presentedViewController) vc = vc.presentedViewController;
  showGlowSettings(vc);
}
%end
%end

// ============ CONSTRUCTOR ============
%ctor {
  @autoreleasepool {
    loadPrefs();

    CFNotificationCenterAddObserver(
      CFNotificationCenterGetDarwinNotifyCenter(), NULL,
      (CFNotificationCallback)loadPrefs, CFSTR(NOTIF_NAME), NULL,
      CFNotificationSuspensionBehaviorDeliverImmediately
    );

    NSString *fw = [[NSBundle mainBundle].bundlePath
      stringByAppendingPathComponent:@"Frameworks/FBSharedFramework.framework/FBSharedFramework"];
    dlopen([fw UTF8String], RTLD_NOW | RTLD_GLOBAL);

    if (GET_BOOL(@"RemoveAds", YES))              %init(Ads);
    if (GET_BOOL(@"PostLikeConfirm", NO))          %init(ConfirmLike);
    if (GET_BOOL(@"DownloadVideos", YES))          %init(DownloadVideo);
    if (GET_BOOL(@"DownloadStories", YES))         %init(DownloadStory);
    if (GET_BOOL(@"AnonymousStories", YES))        %init(AnonymousStories);
    if (GET_BOOL(@"DisableAutoNext", NO))          %init(DisableAutoNext);
    if (GET_BOOL(@"AutoClearCache", NO))           %init(AutoClearCache);
    %init(Settings);

    NSLog(@"[Glow] v1.3.1 initialized");
  }
}
