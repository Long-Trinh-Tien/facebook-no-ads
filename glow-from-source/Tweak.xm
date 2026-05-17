%config(generator=internal)

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <UIKit/UIKit.h>
#import <Photos/Photos.h>
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

// ─── Forward declarations ───
static void GlowLog(NSString *format, ...);
@interface GlowTabBar : NSObject
+ (void)install;
+ (UITabBar *)findInView:(UIView *)v;
+ (void)hLP:(UIGestureRecognizer *)g;
@end
@interface SettingsViewController : UITableViewController @end

// ─── verifyTypeEncoding ───
__attribute__((unused)) static BOOL verifyTypeEncoding(Class cls, SEL sel, const char *expected) {
  Method m = class_getInstanceMethod(cls, sel);
  if (!m) { GlowLog(@" SKIP: method not found %s %s", class_getName(cls), sel_getName(sel)); return NO; }
  const char *actual = method_getTypeEncoding(m);
  if (!actual || !expected) return NO;
  if (strcmp(actual, expected) == 0) return YES;
  GlowLog(@" TYPE ENCODING MISMATCH %s %s: exp=%s got=%s", class_getName(cls), sel_getName(sel), expected, actual);
  return NO;
}

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

// ─── File Logging (NSFileHandle — reliable) ───
static NSFileHandle *_logFH = nil;
static void GlowLog(NSString *format, ...) {
  va_list args;
  va_start(args, format);
  NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
  va_end(args);
  
  // Always NSLog (visible via Xcode device console)
  NSLog(@"[Glow] %@", msg);
  
  // Also write to file via NSFileHandle
  @try {
    if (!_logFH) {
      NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
      NSString *docDir = [paths firstObject];
      if (!docDir) return;
      NSString *logPath = [docDir stringByAppendingPathComponent:@"glow_log.txt"];
      [[NSFileManager defaultManager] createFileAtPath:logPath contents:nil attributes:nil];
      _logFH = [NSFileHandle fileHandleForWritingAtPath:logPath];
    }
    if (_logFH) {
      [_logFH seekToEndOfFile];
      NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [NSDate date], msg];
      [_logFH writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
      [_logFH synchronizeFile];
    }
  } @catch (NSException *e) {
    NSLog(@"[Glow] Log write error: %@", e.reason);
  }
}

// ─── Class Enumeration ───
static void enumerateFBClasses(void) {
  unsigned int count;
  Class *classes = objc_copyClassList(&count);
  if (!classes) { GlowLog(@" objc_copyClassList failed"); return; }

  GlowLog(@" ===== Class Enumeration (%d total) =====", count);
  for (unsigned int i = 0; i < count; i++) {
    const char *name = class_getName(classes[i]);
    if (!name) continue;
    BOOL isFB = (strstr(name, "Snacks") || strstr(name, "SeenState") ||
                 strstr(name, "FBStory") || strstr(name, "FBReel") ||
                 strstr(name, "Sponsored") || strstr(name, "FBMem") ||
                 strstr(name, "Bucket") || strstr(name, "Pando") ||
                 strstr(name, "FBFeed"));
    BOOL isStory = (strstr(name, "Story") && !strstr(name, "UI") && !strstr(name, "NS"));
    if (!isFB && !isStory) continue;

    unsigned int mc;
    Method *methods = class_copyMethodList(classes[i], &mc);
    if (methods) {
      NSLog(@"[Glow-FB] %s (%d methods)", name, mc);
      for (unsigned int j = 0; j < mc && j < 30; j++) {
        SEL sel = method_getName(methods[j]);
        const char *sn = sel ? sel_getName(sel) : "null";
        const char *enc = method_getTypeEncoding(methods[j]);
        if (strstr(sn, "Seen") || strstr(sn, "seen") || strstr(sn, "Mark") ||
            strstr(sn, "mark") || strstr(sn, "Thread") || strstr(sn, "Bucket") ||
            strstr(sn, "advance") || strstr(sn, "like") || strstr(sn, "Like") ||
            strstr(sn, "URL") || strstr(sn, "playable") || strstr(sn, "Sponsor") ||
            strstr(sn, "closeStory") || strstr(sn, "SeenState") || strstr(sn, "sendSeen"))
          NSLog(@"[Glow-FB]   [%d] %s -> %s", j, sn, enc ?: "(null)");
      }
      free(methods);
    }

    // Known selectors
    if ([classes[i] instancesRespondToSelector:NSSelectorFromString(@"_sendSeenThreadIDsWithBucket:session:")])
      GlowLog(@" >>> _sendSeenThreadIDsWithBucket:session: FOUND on %s", name);
    if ([classes[i] instancesRespondToSelector:NSSelectorFromString(@"advanceToNextItemWithNavigationAction:")])
      GlowLog(@" >>> advanceToNextItemWithNavigationAction: FOUND on %s", name);
    if ([classes[i] instancesRespondToSelector:NSSelectorFromString(@"closeStoryWithSource:")])
      GlowLog(@" >>> closeStoryWithSource: FOUND on %s", name);
    if ([classes[i] instancesRespondToSelector:NSSelectorFromString(@"storyBucketType")])
      GlowLog(@" >>> storyBucketType FOUND on %s", name);
    if ([classes[i] instancesRespondToSelector:NSSelectorFromString(@"performLikeAction:")])
      GlowLog(@" >>> performLikeAction: FOUND on %s", name);
    if ([classes[i] instancesRespondToSelector:NSSelectorFromString(@"isSponsored")])
      GlowLog(@" >>> isSponsored FOUND on %s", name);
    if ([classes[i] isSubclassOfClass:[UIViewController class]])
      NSLog(@"[Glow-VC] VC: %s", name);
  }
  free(classes);
  GlowLog(@"===== Class Enumeration complete =====");
}

// ─── MediaExtractor ───
@interface MediaExtractor : NSObject
+ (NSString *)extractVideoURL:(id)obj;
@end
@implementation MediaExtractor
+ (NSString *)extractVideoURL:(id)obj {
  if (!obj) return nil;
  for (NSString *prop in @[@"videoURLString", @"playableURLString", @"hdPlayableURLString",
                           @"dashPlayableURL", @"playableURL", @"mediaURLString",
                           @"hdVideoURL", @"sdVideoURL"]) {
    SEL sel = NSSelectorFromString(prop);
    if ([obj respondsToSelector:sel]) {
      NSString *val = [obj valueForKey:prop];
      if (val && ![val hasPrefix:@"file://"]) return val;
    }
  }
  return nil;
}
@end

// ─── Download ───
@interface GlowDownloadTarget : NSObject @end
@implementation GlowDownloadTarget
+ (instancetype)shared { static GlowDownloadTarget *inst; static dispatch_once_t once; dispatch_once(&once, ^{ inst = [[GlowDownloadTarget alloc] init]; }); return inst; }
- (void)downloadTapped:(UIButton *)btn {
  NSString *url = btn.accessibilityIdentifier;
  if (!url) return;
  NSURLSessionDownloadTask *task = [[NSURLSession sharedSession] downloadTaskWithURL:[NSURL URLWithString:url]
    completionHandler:^(NSURL *loc, NSURLResponse *resp, NSError *err) {
      if (err) { GlowLog(@" download error: %@", err); return; }
      [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        [PHAssetCreationRequest creationRequestForAssetFromVideoAtFileURL:loc];
      } completionHandler:^(BOOL success, NSError *e) {
        dispatch_async(dispatch_get_main_queue(), ^{
          UIAlertController *a = [UIAlertController alertControllerWithTitle:success ? @"Saved!" : @"Failed"
            message:nil preferredStyle:UIAlertControllerStyleAlert];
          [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
          [[[[UIApplication sharedApplication] keyWindow] rootViewController] presentViewController:a animated:YES completion:nil];
        });
      }];
    }];
  [task resume];
}
@end

static void injectDownloadBtn(UIView *target, NSString *urlStr) {
  if (!urlStr.length) return;
  if ([target viewWithTag:999]) return;
  dispatch_async(dispatch_get_main_queue(), ^{
    if ([target viewWithTag:999]) return;
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.tag = 999;
    [btn setTitle:@"⬇" forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:20];
    btn.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.5];
    btn.layer.cornerRadius = 18;
    btn.frame = CGRectMake(target.bounds.size.width - 50, target.bounds.size.height - 100, 36, 36);
    btn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin;
    [btn addTarget:[GlowDownloadTarget shared] action:@selector(downloadTapped:) forControlEvents:UIControlEventTouchUpInside];
    btn.accessibilityIdentifier = urlStr;
    [target addSubview:btn];
  });
}

// ─── Timer View Scan ───
@interface GlowMediaScanner : NSObject
+ (void)scanView:(UIView *)view depth:(int)depth;
+ (void)scanAllWindows;
@end
@implementation GlowMediaScanner
+ (void)scanView:(UIView *)view depth:(int)depth {
  if (depth > 10 || !view) return;
  const char *name = class_getName([view class]);
  if (strstr(name, "Story") || strstr(name, "Reel") || strstr(name, "Snacks")) {
    if (!strstr(name, "Cell") && !strstr(name, "Collection") && !strstr(name, "Tray")) {
      id responder = view;
      while (responder && ![responder isKindOfClass:[UIViewController class]])
        responder = [responder nextResponder];
      if (responder) {
        NSString *url = [MediaExtractor extractVideoURL:responder];
        if (url) {
          NSLog(@"[Glow-SCAN] Video URL on %s: %@", name, url);
          injectDownloadBtn(view, url);
        }
      }
    }
  }
  for (UIView *sub in view.subviews) [self scanView:sub depth:depth+1];
}
+ (void)scanAllWindows {
  if (@available(iOS 15.0, *)) {
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
      if (![scene isKindOfClass:[UIWindowScene class]]) continue;
      for (UIWindow *w in [(UIWindowScene *)scene windows]) [self scanView:w depth:0];
    }
  } else {
    [self scanView:[[UIApplication sharedApplication] keyWindow] depth:0];
  }
}
@end

static void startScannerTimer(void) {
  [NSTimer scheduledTimerWithTimeInterval:1.5 repeats:YES block:^(NSTimer *t) {
    [GlowMediaScanner scanAllWindows];
  }];
  GlowLog(@" Scanner timer started (1.5s interval)");
}

// ─── setupAllHooks ───
static void setupAllHooks(void) {
  @autoreleasepool {
    // First GlowLog call initializes the log file
    GlowLog(@"===== Phase 2 debug start =====");
    @try {
      NSString *fw = [[NSBundle mainBundle].bundlePath
        stringByAppendingPathComponent:@"Frameworks/FBSharedFramework.framework/FBSharedFramework"];
      if (fw) dlopen([fw UTF8String], RTLD_NOW | RTLD_GLOBAL);
    } @catch (NSException *e) { GlowLog(@" dlopen error: %@", e.reason); }
    enumerateFBClasses();
    startScannerTimer();
    if (PBOOL(@"AutoClearCache", NO)) [[NSURLCache sharedURLCache] removeAllCachedResponses];
    if (!PBOOL(@"hasLaunched", NO)) {
      PSET(@"hasLaunched", @YES); saveP();
      UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Glow v1.3.1"
        message:@"Phase 2 debug — class enum + timer scan.\nCheck glow_log.txt for FB classes." preferredStyle:UIAlertControllerStyleAlert];
      [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
      UIViewController *root = [[[UIApplication sharedApplication] keyWindow] rootViewController];
      if (root) [root presentViewController:a animated:YES completion:nil];
    }
    GlowLog(@" Phase 2 debug — setupAllHooks complete");
  }
}

// ─── Constructor ───
%ctor {
  @autoreleasepool {
    loadP();
    _dyld_register_func_for_add_image(_glow_image_loaded);
    dispatch_async(dispatch_get_main_queue(), ^{
      [[NSNotificationCenter defaultCenter]
        addObserverForName:UIApplicationDidFinishLaunchingNotification
        object:nil queue:[NSOperationQueue mainQueue]
        usingBlock:^(NSNotification *note) {
          [GlowTabBar install];
          dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{ setupAllHooks(); });
        }];
    });
    GlowLog(@" Phase 2 debug — constructor done");
  }
}

// ─── Tab Bar ───
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
    UINavigationController *n = [[UINavigationController alloc] initWithRootViewController:[[SettingsViewController alloc] init]];
    [topVC() presentViewController:n animated:YES completion:nil];
  }
}
@end

// ─── Settings ───
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
