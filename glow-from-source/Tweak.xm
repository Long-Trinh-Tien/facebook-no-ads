#import <objc/runtime.h>
#import <dlfcn.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// Forward decls
@interface FBMemFeedStory : NSObject
- (id)sponsoredData;
- (id)initWithFBTree:(void *)t;
@end
@interface FBVideoChannelPlaylistItem : NSObject
- (BOOL)isSponsored;
- (id)initWithFBTree:(id)t;
@end
@interface FBSnacksUnifiedSeenStateMutator : NSObject
@end

// Prefs
static NSString *const kP = @"/var/mobile/Library/Preferences/com.dvntm.glowprefs.plist";
#define PNOTIF "com.dvntm.glowprefs/PrefChanged"
static NSMutableDictionary *P;
#define PBOOL(k,d) [P[k] ?: @(d) boolValue]
static void loadP() { @autoreleasepool { P = [[NSMutableDictionary alloc] initWithContentsOfFile:kP]; if (!P) P = [NSMutableDictionary new]; } }
static void saveP() { [P writeToFile:kP atomically:YES]; }

// Settings VC
@interface GlowVC : UITableViewController @end
@implementation GlowVC
- (id)init {
  self = [super initWithStyle:UITableViewStyleGrouped];
  self.title = @"Glow";
  self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"OK" style:UIBarButtonItemStylePlain target:self action:@selector(done)];
  return self;
}
- (NSArray *)items {
  return @[
    @[@{@"h":@"Main"}],
    @[@{@"k":@"RemoveAds",@"l":@"Remove Ads"},@{@"k":@"RemovePYMK",@"l":@"Remove PYMK"},@{@"k":@"RemoveReelsCarousel",@"l":@"Remove Reels"},@{@"k":@"RemoveRecs",@"l":@"Remove Recs"}],
    @[@{@"h":@"Stories"}],
    @[@{@"k":@"AnonymousStories",@"l":@"Incognito Mode"},@{@"k":@"DisableAutoNext",@"l":@"Disable Auto Next"}],
    @[@{@"h":@"Other"}],
    @[@{@"k":@"AutoClearCache",@"l":@"Auto Clear Cache"}],
  ];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return [self items].count; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return [[self items][s][0][@"h"] isEqual:@"h"] ? 0 : [[self items][s] count]; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)p {
  id d = [self items][p.section][p.row]; UITableViewCell *c = [t dequeueReusableCellWithIdentifier:@"c"];
  if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"c"];
  c.textLabel.text = d[@"l"]; c.selectionStyle = UITableViewCellSelectionStyleNone;
  UISwitch *sw = [[UISwitch alloc] init]; sw.on = PBOOL(d[@"k"], YES);
  sw.tag = p.section*100+p.row; [sw addTarget:self action:@selector(t:) forControlEvents:UIControlEventValueChanged];
  c.accessoryView = sw; return c;
}
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s { return [self items][s][0][@"h"]; }
- (void)t:(UISwitch *)s { id d = [self items][s.tag/100][s.tag%100]; P[d[@"k"]] = @(s.on); }
- (void)done { saveP(); CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),CFSTR(PNOTIF),NULL,NULL,YES);
  [self dismissViewControllerAnimated:YES completion:nil]; }
@end

static void showGlow() {
  dispatch_async(dispatch_get_main_queue(), ^{
    UIViewController *vc = UIApplication.sharedApplication.keyWindow.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    [vc presentViewController:[[UINavigationController alloc] initWithRootViewController:[GlowVC new]] animated:YES completion:nil];
  });
}
static void showWelcome() {
  if ([NSUserDefaults.standardUserDefaults boolForKey:@"gw"]) return;
  [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"gw"];
  dispatch_async(dispatch_get_main_queue(), ^{
    id a = [UIAlertController alertControllerWithTitle:@"Glow" message:@"Long press any tab for settings" preferredStyle:1];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:0 handler:nil]];
    [UIApplication.sharedApplication.keyWindow.rootViewController presentViewController:a animated:YES completion:nil];
  });
}

// ============ HOOKS ============

%group Ads
%hook FBMemFeedStory
- (id)initWithFBTree:(void *)t { id r = %orig; return [r sponsoredData] ? nil : r; }
%end
%hook FBVideoChannelPlaylistItem
- (id)initWithFBTree:(id)t { id r = %orig; return [r isSponsored] ? nil : r; }
%end
%end

%group Anonymous
%hook FBSnacksUnifiedSeenStateMutator
- (void)_attemptSendSeenStateAndHandleResponse:(id)r bucket:(id)b { if (PBOOL(@"AnonymousStories", YES)) return; %orig; }
- (void)_markThreadsAsSeen:(id)t fromBucket:(id)b withTrackingString:(id)s isAnonymousView:(BOOL)a completion:(id)c { if (PBOOL(@"AnonymousStories", YES)) return; %orig; }
%end
%end

// Tab bar long press — use dispatch to add gesture after UI loads
%group Tab
%hook UITabBar
- (void)didMoveToWindow {
  %orig;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(glowLongPress:)];
    lp.minimumPressDuration = 0.8;
    [self addGestureRecognizer:lp];
  });
}
%new - (void)glowLongPress:(UILongPressGestureRecognizer *)g {
  if (g.state == UIGestureRecognizerStateBegan) showGlow();
}
%end
%end

%ctor {
  @autoreleasepool {
    loadP();
    NSString *fw = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"Frameworks/FBSharedFramework.framework/FBSharedFramework"];
    dlopen([fw UTF8String], RTLD_NOW | RTLD_GLOBAL);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),NULL,(CFNotificationCallback)loadP,CFSTR(PNOTIF),NULL,CFNotificationSuspensionBehaviorDeliverImmediately);
    if (PBOOL(@"RemoveAds", YES)) %init(Ads);
    if (PBOOL(@"AnonymousStories", YES)) %init(Anonymous);
    %init(Tab);
    showWelcome();
    if (PBOOL(@"AutoClearCache", NO)) dispatch_async(dispatch_get_global_queue(0, 0), ^{
      [[NSFileManager defaultManager] removeItemAtPath:NSSearchPathForDirectoriesInDomains(NSCachesDirectory,NSUserDomainMask,YES)[0] error:nil];
    });
    NSLog(@"[Glow] init OK");
  }
}
