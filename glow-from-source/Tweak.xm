%config(generator=internal)

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <os/log.h>

extern "C" void _dyld_register_func_for_add_image(void (*func)(const struct mach_header *mh, intptr_t vmaddr_slide));

// Padding (placeholder — cần investigate root cause sau)
__attribute__((used, section("__TEXT,__glow_pad")))
static const uint8_t _glow_size_padding[15728640] = {0};
static void _glow_image_loaded(const struct mach_header *mh, intptr_t vmaddr_slide) {}

static os_log_t glowLog(void) {
  static os_log_t l;
  static dispatch_once_t t;
  dispatch_once(&t, ^{ l = os_log_create("com.glow.fb", "Glow"); });
  return l;
}
#define GLog(fmt, ...) os_log_info(glowLog(), "[glow] " fmt, ##__VA_ARGS__)

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

// ─── Settings ───
@interface GlowSettingsVC : UITableViewController @end
@implementation GlowSettingsVC { NSArray *_sections; }
- (instancetype)init {
  if ((self = [super initWithStyle:UITableViewStyleGrouped])) {
    self.title = @"Glow";
    _sections = @[
      @{@"title": @"Download", @"items": @[
        @{@"l": @"Videos", @"k": @"DownloadVideos", @"d": @YES},
        @{@"l": @"Stories", @"k": @"DownloadStories", @"d": @YES},
        @{@"l": @"Reels", @"k": @"DownloadReels", @"d": @YES}]},
      @{@"title": @"Privacy", @"items": @[
        @{@"l": @"Anonymous Stories", @"k": @"AnonymousStories", @"d": @YES}]},
      @{@"title": @"Content", @"items": @[
        @{@"l": @"Remove Ads", @"k": @"RemoveAds", @"d": @YES}]},
      @{@"title": @"Interaction", @"items": @[
        @{@"l": @"Confirm Like", @"k": @"PostLikeConfirm", @"d": @NO},
        @{@"l": @"Disable Auto Next", @"k": @"DisableAutoNext", @"d": @NO}]}];
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

// ─── Layer 1: UITabBar.layoutSubviews → long press → settings ───
%hook UITabBar
- (void)layoutSubviews {
  %orig;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    GLog("UITabBar ready — installing long press");
    for (UIView *v in self.subviews) {
      GLog("tab child: %@", NSStringFromClass([v class]));
    }
    UILongPressGestureRecognizer *g = [[UILongPressGestureRecognizer alloc]
      initWithTarget:[GlowSettingsVC class] action:@selector(glowHold:)];
    g.minimumPressDuration = 0.5;
    [self addGestureRecognizer:g];
  });
}
@end

@implementation GlowSettingsVC (LongPress)
+ (void)glowHold:(UILongPressGestureRecognizer *)g {
  if (g.state != UIGestureRecognizerStateBegan) return;
  UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:[[GlowSettingsVC alloc] init]];
  [topVC() presentViewController:nav animated:YES completion:nil];
}
@end

// ─── Layer 2: UIViewController.viewDidAppear — discover FB classes from instances ───
%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
  %orig;
  NSString *name = NSStringFromClass([self class]);
  if ([name containsString:@"Feed"] || [name containsString:@"Story"] ||
      [name containsString:@"Reel"] || [name containsString:@"Snacks"] ||
      [name containsString:@"Tab"] || [name containsString:@"Bucket"] ||
      [name containsString:@"Seen"] || [name containsString:@"Video"] ||
      [name containsString:@"Player"]) {
    GLog("VC appeared: %@", name);
  }
}
@end

// ─── Constructor — ABSOLUTE MINIMAL ───
%ctor {
  @autoreleasepool {
    loadP();
    _dyld_register_func_for_add_image(_glow_image_loaded);
    // NO file I/O
    // NO objc_copyClassList
    // NO dlopen
    // NO NSTimer
    // Just %init — Logos handles hook registration
    %init;
  }
}
