%config(generator=internal)

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>

extern "C" void _dyld_register_func_for_add_image(void (*func)(const struct mach_header *mh, intptr_t vmaddr_slide));

__attribute__((used, section("__TEXT,__glow_pad")))
static const uint8_t _glow_size_padding[15728640] = {0};
static void _glow_image_loaded(const struct mach_header *mh, intptr_t vmaddr_slide) {}

static NSString *const kPrefsPath = @"/var/mobile/Library/Preferences/com.dvntm.glowprefs.plist";
static NSMutableDictionary *P;
#define PBOOL(k,d) ([P[k] ?: @(d) boolValue])
#define PSET(k,v) (P[k] = v)

static void loadP() {
  @autoreleasepool {
    P = [[NSMutableDictionary alloc] initWithContentsOfFile:kPrefsPath];
    if (!P) P = [NSMutableDictionary new];
  }
}
static void saveP() { [P writeToFile:kPrefsPath atomically:YES]; }

static UIViewController *topVC(void) {
  UIViewController *root = nil;
  if (@available(iOS 15.0, *)) {
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
      if (![scene isKindOfClass:[UIWindowScene class]]) continue;
      for (UIWindow *w in [(UIWindowScene *)scene windows]) {
        if (w.rootViewController) { root = w.rootViewController; break; }
      }
      if (root) break;
    }
  }
  if (!root) root = [[[UIApplication sharedApplication] keyWindow] rootViewController];
  while (root.presentedViewController) root = root.presentedViewController;
  return root;
}

@interface SettingsViewController : UITableViewController @end
@implementation SettingsViewController { NSArray *_sections; }
- (instancetype)init {
  if ((self = [super initWithStyle:UITableViewStyleGrouped])) {
    self.title = @"Glow";
    _sections = @[
      @{@"title": @"Download", @"items": @[
        @{@"l": @"Videos", @"k": @"DownloadVideos", @"d": @YES},
        @{@"l": @"Stories", @"k": @"DownloadStories", @"d": @YES},
        @{@"l": @"Reels", @"k": @"DownloadReels", @"d": @YES},
        @{@"l": @"All Formats", @"k": @"AllFormats", @"d": @NO},
        @{@"l": @"Encoding Speed", @"k": @"EncodingSpeed", @"d": @0}]},
      @{@"title": @"Privacy", @"items": @[
        @{@"l": @"Anonymous Stories", @"k": @"AnonymousStories", @"d": @YES},
        @{@"l": @"Mark as Seen", @"k": @"MarkAsSeen", @"d": @NO}]},
      @{@"title": @"Content", @"items": @[
        @{@"l": @"Remove Ads", @"k": @"RemoveAds", @"d": @YES},
        @{@"l": @"Remove PYMK", @"k": @"RemovePYMK", @"d": @YES},
        @{@"l": @"Remove Recs", @"k": @"RemoveRecs", @"d": @YES},
        @{@"l": @"Remove Reels Carousel", @"k": @"RemoveReelsCarousel", @"d": @NO}]},
      @{@"title": @"Interaction", @"items": @[
        @{@"l": @"Confirm Like", @"k": @"PostLikeConfirm", @"d": @NO},
        @{@"l": @"Confirm Reels Like", @"k": @"ReelsLikeConfirm", @"d": @NO},
        @{@"l": @"Disable Auto Next", @"k": @"DisableAutoNext", @"d": @NO}]},
      @{@"title": @"UI", @"items": @[
        @{@"l": @"Hide Overlay", @"k": @"HideOverlay", @"d": @NO},
        @{@"l": @"Auto Clear Cache", @"k": @"AutoClearCache", @"d": @NO}]}];
  }
  return self;
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return _sections.count; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return [_sections[s][@"items"] count]; }
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s { return _sections[s][@"title"]; }
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
  UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"c"];
  if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"c"];
  NSDictionary *item = _sections[ip.section][@"items"][ip.row];
  cell.textLabel.text = item[@"l"];
  UISwitch *sw = [[UISwitch alloc] init];
  sw.on = PBOOL(item[@"k"], [item[@"d"] boolValue]);
  sw.tag = ip.section * 100 + ip.row;
  [sw addTarget:self action:@selector(swChanged:) forControlEvents:UIControlEventValueChanged];
  cell.accessoryView = sw;
  return cell;
}
- (void)swChanged:(UISwitch *)sw {
  NSInteger s = sw.tag / 100, r = sw.tag % 100;
  PSET(_sections[s][@"items"][r][@"k"], @(sw.isOn)); saveP();
}
@end

@interface GlowTabBar : NSObject @end
@interface GlowLongPress : UILongPressGestureRecognizer @end
@implementation GlowLongPress
- (instancetype)initWithTarget:(id)target action:(SEL)action {
  if ((self = [super initWithTarget:target action:action])) self.minimumPressDuration = 0.5;
  return self;
}
@end
@implementation GlowTabBar
+ (UITabBar *)findInView:(UIView *)v {
  if ([v isKindOfClass:[UITabBar class]]) return (UITabBar *)v;
  for (UIView *s in v.subviews) { UITabBar *f = [self findInView:s]; if (f) return f; }
  return nil;
}
+ (UITabBar *)findTabBar {
  UITabBar *tb = nil;
  // Try all windows/scenes
  if (@available(iOS 13, *)) {
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
      if (![s isKindOfClass:[UIWindowScene class]]) continue;
      for (UIWindow *w in [(UIWindowScene *)s windows]) {
        tb = [self findInView:w]; if (tb) break;
        // Also check root VC's tabBar
        if (w.rootViewController && [w.rootViewController isKindOfClass:[UITabBarController class]])
          tb = [(UITabBarController *)w.rootViewController tabBar];
        if (tb) break;
      }
      if (tb) break;
    }
  }
  if (!tb) {
    tb = [self findInView:UIApplication.sharedApplication.keyWindow];
    // Check root VC
    UIViewController *root = UIApplication.sharedApplication.keyWindow.rootViewController;
    if (!tb && [root isKindOfClass:[UITabBarController class]])
      tb = [(UITabBarController *)root tabBar];
  }
  return tb;
}
+ (void)installWithRetry:(int)retries {
  UITabBar *tb = [self findTabBar];
  if (tb) {
    for (UIGestureRecognizer *g in tb.gestureRecognizers)
      if ([NSStringFromClass(g.class) containsString:@"Glow"]) return;
    [tb addGestureRecognizer:[[GlowLongPress alloc] initWithTarget:self action:@selector(hLP:)]];
  } else if (retries > 0) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
      dispatch_get_main_queue(), ^{ [self installWithRetry:retries - 1]; });
  }
}
+ (void)install { [self installWithRetry:3]; }
+ (void)hLP:(UIGestureRecognizer *)g {
  if (g.state == UIGestureRecognizerStateBegan) {
    UINavigationController *n = [[UINavigationController alloc] initWithRootViewController:[[SettingsViewController alloc] init]];
    [topVC() presentViewController:n animated:YES completion:nil];
  }
}
@end

%ctor {
  @autoreleasepool {
    loadP();
    _dyld_register_func_for_add_image(_glow_image_loaded);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
      dispatch_get_main_queue(), ^{
        [GlowTabBar install];
    });
  }
}
