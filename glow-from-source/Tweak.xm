%config(generator=internal)

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>

extern "C" void MSHookMessageEx(Class _class, SEL _cmd, IMP _replacement, IMP *_result);
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

static UIViewController *topVC() {
  UIViewController *root = [[[UIApplication sharedApplication] keyWindow] rootViewController];
  while (root.presentedViewController) root = root.presentedViewController;
  return root;
}

// ─── Settings ───
@interface GlowSettingsVC : UITableViewController @end
@implementation GlowSettingsVC {
  NSArray *_sections;
}
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
        @{@"l": @"Remove Ads", @"k": @"RemoveAds", @"d": @YES},
        @{@"l": @"Remove PYMK", @"k": @"RemovePYMK", @"d": @YES}]},
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

// ─── Long Press Gesture ───
@interface GlowLongPress : UILongPressGestureRecognizer @end
@implementation GlowLongPress
- (instancetype)initWithTarget:(id)target action:(SEL)action {
  if ((self = [super initWithTarget:target action:action])) self.minimumPressDuration = 0.5;
  return self;
}
@end

// ─── Tab Bar Installer ───
@interface GlowTabBar : NSObject @end
@implementation GlowTabBar
+ (UITabBar *)findInView:(UIView *)v {
  if ([v isKindOfClass:[UITabBar class]]) return (UITabBar *)v;
  for (UIView *s in v.subviews) { UITabBar *f = [self findInView:s]; if (f) return f; }
  return nil;
}
+ (void)install {
  UITabBar *tb = nil;
  if (@available(iOS 13, *)) {
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
      if (![s isKindOfClass:[UIWindowScene class]]) continue;
      for (UIWindow *w in [(UIWindowScene *)s windows]) { tb = [self findInView:w]; if (tb) break; }
      if (tb) break;
    }
  }
  if (!tb) tb = [self findInView:UIApplication.sharedApplication.keyWindow];
  if (tb) {
    for (UIGestureRecognizer *g in tb.gestureRecognizers)
      if ([NSStringFromClass(g.class) containsString:@"Glow"]) return;
    [tb addGestureRecognizer:[[GlowLongPress alloc] initWithTarget:self action:@selector(hLP:)]];
  }
}
+ (void)hLP:(UIGestureRecognizer *)g {
  if (g.state == UIGestureRecognizerStateBegan) {
    UINavigationController *n = [[UINavigationController alloc] initWithRootViewController:[[GlowSettingsVC alloc] init]];
    [topVC() presentViewController:n animated:YES completion:nil];
  }
}
@end

// ─── Constructor (NO HOOKS — debug only) ───
%ctor {
  @autoreleasepool {
    loadP();
    _dyld_register_func_for_add_image(_glow_image_loaded);

    // Hook 1: viewDidLoad (minimal — just call original)
    {
      static IMP orig_vdl;
      MSHookMessageEx([UIViewController class], @selector(viewDidLoad),
        imp_implementationWithBlock(^(id self, SEL _cmd) {
          ((void(*)(id, SEL))orig_vdl)(self, _cmd);
          NSLog(@"[Glow] viewDidLoad: %s", class_getName([self class]));
        }), &orig_vdl);
    }

    // Test: dlopen FBSharedFramework
    @try {
      NSString *fwPath = [[NSBundle mainBundle].bundlePath
        stringByAppendingPathComponent:@"Frameworks/FBSharedFramework.framework/FBSharedFramework"];
      if (fwPath) {
        void *h = dlopen([fwPath UTF8String], RTLD_NOW | RTLD_GLOBAL);
        NSLog(@"[Glow] dlopen: %p err=%s", h, h ? "" : (dlerror() ?: "none"));
        if (h) dlclose(h);
      }
    } @catch (NSException *e) {
      NSLog(@"[Glow] dlopen exception: %@", e.reason);
    }

    // Tab bar long press
    [GlowTabBar install];

    // Welcome
    if (!PBOOL(@"hasLaunched", NO)) {
      PSET(@"hasLaunched", @YES); saveP();
      dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Glow v1.3.1"
          message:@"No hooks — debug build.\nTest: is this alert showing?"
          preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [topVC() presentViewController:a animated:YES completion:nil];
      });
    }

    NSLog(@"[Glow] minimal debug loaded");
  }
}
