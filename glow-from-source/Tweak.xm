%config(generator=internal)

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <UIKit/UIKit.h>
#import <Photos/Photos.h>
#import <mach-o/dyld.h>

extern "C" void MSHookMessageEx(Class _class, SEL _cmd, IMP _replacement, IMP *_result);
extern "C" void _dyld_register_func_for_add_image(void (*func)(const struct mach_header *mh, intptr_t vmaddr_slide));

__attribute__((used, section("__TEXT,__glow_pad")))
static const uint8_t _glow_size_padding[15728640] = {0};

static void _glow_image_loaded(const struct mach_header *mh, intptr_t vmaddr_slide) {}

static NSString *const kPrefsPath = @"/var/mobile/Library/Preferences/com.dvntm.glowprefs.plist";

// ─── File Logging ───
static void GlowLog(NSString *format, ...) {
  va_list args;
  va_start(args, format);
  NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
  va_end(args);
  NSLog(@"[Glow] %@", msg);
  @try {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docDir = [paths firstObject];
    if (docDir) {
      NSString *logPath = [docDir stringByAppendingPathComponent:@"glow_debug.txt"];
      NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:logPath];
      if (!fh) {
        [[NSFileManager defaultManager] createFileAtPath:logPath contents:nil attributes:nil];
        fh = [NSFileHandle fileHandleForWritingAtPath:logPath];
      }
      if (fh) {
        [fh seekToEndOfFile];
        NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [NSDate date], msg];
        [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
      }
    }
  } @catch (NSException *e) {
    NSLog(@"[Glow] log error: %@", e.reason);
  }
}
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

// ─── Runtime Class Discovery ───
static void discoverFBClasses(void) {
  int count;
  Class *classes = objc_copyClassList(&count);
  if (!classes) return;

  GlowLog(@"=== FB Class Discovery (%d total classes) ===", count);
  for (int i = 0; i < count; i++) {
    const char *name = class_getName(classes[i]);
    if (!name) continue;
    if (strstr(name, "FBSnacks") || strstr(name, "FBStory") || strstr(name, "FBReel") ||
        strstr(name, "SeenState") || strstr(name, "SeenMutator") || strstr(name, "ShortsSeen") ||
        strstr(name, "ViewerSheet") || strstr(name, "Sponsored") || strstr(name, "FeedStory")) {
      // Log the class and its methods
      unsigned int mc;
      Method *methods = class_copyMethodList(classes[i], &mc);
      if (methods) {
        GlowLog(@"Class: %s (%d methods)", name, mc);
        for (unsigned int j = 0; j < mc && j < 20; j++) {
          SEL sel = method_getName(methods[j]);
          const char *enc = method_getTypeEncoding(methods[j]);
          GlowLog(@"  [%d] %s -> %s", j, sel ? sel_getName(sel) : "(null)", enc ?: "(null)");
        }
        free(methods);
      }
    }
  }
  free(classes);
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

// ─── Download Button Injection ───
@interface GlowDownloadTarget : NSObject @end
@implementation GlowDownloadTarget
+ (instancetype)shared {
  static GlowDownloadTarget *inst;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ inst = [[GlowDownloadTarget alloc] init]; });
  return inst;
}
- (void)downloadTapped:(UIButton *)btn {
  NSString *url = btn.accessibilityIdentifier;
  if (!url) return;
  NSURLSessionDownloadTask *task = [[NSURLSession sharedSession] downloadTaskWithURL:[NSURL URLWithString:url]
    completionHandler:^(NSURL *loc, NSURLResponse *resp, NSError *err) {
      if (err) { NSLog(@"[Glow] download error: %@", err); return; }
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
  dispatch_async(dispatch_get_main_queue(), ^{
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
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

// ─── Constructor ───
%ctor {
  @autoreleasepool {
    loadP();
    _dyld_register_func_for_add_image(_glow_image_loaded);

    // 1. viewDidLoad: pattern match + seen fix + download
    {
      static IMP orig_vdl;
      MSHookMessageEx([UIViewController class], @selector(viewDidLoad),
        imp_implementationWithBlock(^(UIViewController *self, SEL _cmd) {
          ((void(*)(UIViewController *, SEL))orig_vdl)(self, _cmd);

          const char *name = class_getName([self class]);
          if (!name) return;

          // Seen fix for story viewers
          if (PBOOL(@"AnonymousStories", YES) && strstr(name, "Story")) {
            static dispatch_once_t once;
            dispatch_once(&once, ^{
              SEL seenSels[] = {
                NSSelectorFromString(@"_canMarkStoryAsSeen"),
                NSSelectorFromString(@"MarkStoryAsSeen"),
              };
              for (int i = 0; i < 2; i++) {
                if ([self respondsToSelector:seenSels[i]]) {
                  Method m = class_getInstanceMethod([self class], seenSels[i]);
                  if (m) {
                    IMP origImp = method_getImplementation(m);
                    method_setImplementation(m, imp_implementationWithBlock(^(id s, SEL c) {
                      if (!PBOOL(@"AnonymousStories", YES))
                        ((void(*)(id, SEL))origImp)(s, c);
                    }));
                  }
                }
              }
              SEL threadSel = NSSelectorFromString(@"_markThreadAsSeen:bucket:session:shouldMarkThreadSeenStateUpdates:");
              if ([self respondsToSelector:threadSel]) {
                Method m = class_getInstanceMethod([self class], threadSel);
                if (m) {
                  IMP origImp = method_getImplementation(m);
                  method_setImplementation(m, imp_implementationWithBlock(^(id s, SEL c, id t, id b, id se, BOOL u) {
                    if (!PBOOL(@"AnonymousStories", YES))
                      ((void(*)(id, SEL, id, id, id, BOOL))origImp)(s, c, t, b, se, u);
                  }));
                }
              }
            });
          }

          // Download button for story/reel VCs
          if ((strstr(name, "Story") || strstr(name, "Reel")) && !strstr(name, "Cell") && !strstr(name, "Collection")) {
            NSString *url = [MediaExtractor extractVideoURL:self];
            if (url) injectDownloadBtn(self.view, url);
          }
        }), &orig_vdl);
    }

    // 2. initWithFBTree: ad blocking
    {
      SEL sel = NSSelectorFromString(@"initWithFBTree:");
      if ([NSObject instancesRespondToSelector:sel]) {
        static IMP orig_tree;
        MSHookMessageEx([NSObject class], sel,
          imp_implementationWithBlock(^(id self, SEL _cmd, id tree) {
            if (PBOOL(@"RemoveAds", YES)) return (id)nil;
            return ((id(*)(id, SEL, id))orig_tree)(self, _cmd, tree);
          }), &orig_tree);
      }
    }

    // 3. initWithFBPandoTree: content blocking
    {
      SEL sel = NSSelectorFromString(@"initWithFBPandoTree:");
      if ([NSObject instancesRespondToSelector:sel]) {
        static IMP orig_pando;
        MSHookMessageEx([NSObject class], sel,
          imp_implementationWithBlock(^(id self, SEL _cmd, id tree) {
            BOOL block = PBOOL(@"RemovePYMK", YES) || PBOOL(@"RemoveRecs", YES);
            if (block) return (id)nil;
            return ((id(*)(id, SEL, id))orig_pando)(self, _cmd, tree);
          }), &orig_pando);
      }
    }

    // 5. Class discovery (debug: logs to Documents/glow_debug.txt)
    dispatch_async(dispatch_get_main_queue(), ^{
      discoverFBClasses();
    });

    // 6. Tab bar long press
    [GlowTabBar install];

    // 7. Welcome
    if (!PBOOL(@"hasLaunched", NO)) {
      PSET(@"hasLaunched", @YES); saveP();
      dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Glow v1.3.1"
          message:@"Build with all hooks." preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [topVC() presentViewController:a animated:YES completion:nil];
      });
    }

    // 8. Auto clear cache
    if (PBOOL(@"AutoClearCache", NO))
      [[NSURLCache sharedURLCache] removeAllCachedResponses];

    NSLog(@"[Glow] full hooks loaded");
  }
}
