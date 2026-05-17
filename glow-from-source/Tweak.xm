%config(generator=internal)

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <UIKit/UIKit.h>
#import <Photos/Photos.h>
#import <mach-o/dyld.h>

extern void MSHookMessageEx(Class _class, SEL _cmd, IMP _replacement, IMP *_result);
extern void _dyld_register_func_for_add_image(void (*func)(const struct mach_header *mh, intptr_t vmaddr_slide));

__attribute__((used, section("__TEXT,__glow_pad")))
static const uint8_t _glow_size_padding[15728640] = {0};

static void _glow_image_loaded(const struct mach_header *mh, intptr_t vmaddr_slide) {}

static NSString *const kPrefsPath = @"/var/mobile/Library/Preferences/com.dvntm.glowprefs.plist";
static NSMutableDictionary *P;
#define PBOOL(k,d) ([P[k] ?: @(d) boolValue])
#define PINT(k,d) ([P[k] ?: @(d) intValue])
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

// ─── MediaExtractor ───
@interface MediaExtractor : NSObject
+ (NSString *)extractVideoURLFromFeed:(id)feed;
+ (NSString *)extractVideoURLFromReel:(id)reel;
+ (NSString *)extractVideoURLFromStory:(id)story;
@end

@implementation MediaExtractor
+ (NSString *)extractVideoURLFromFeed:(id)feed {
  if (!feed) return nil;
  for (NSString *prop in @[@"videoURLString", @"playableURLString", @"hdPlayableURLString",
                           @"dashPlayableURL", @"playableURL", @"mediaURLString",
                           @"hdVideoURL", @"sdVideoURL"]) {
    SEL sel = NSSelectorFromString(prop);
    if ([feed respondsToSelector:sel]) {
      NSString *val = [feed valueForKey:prop];
      if (val && ![val hasPrefix:@"file://"]) return val;
    }
  }
  return nil;
}
+ (NSString *)extractVideoURLFromReel:(id)reel { return [self extractVideoURLFromFeed:reel]; }
+ (NSString *)extractVideoURLFromStory:(id)story { return [self extractVideoURLFromFeed:story]; }
@end

// ─── Downloader & Helpers ───
@interface Downloader : NSObject
+ (instancetype)shared;
- (void)downloadMediaAtURL:(NSURL *)url completion:(void(^)(NSString *path, NSError *err))completion;
- (void)cancelAll;
@end

@implementation Downloader {
  NSMutableArray *_tasks;
}
+ (instancetype)shared { static Downloader *instance; static dispatch_once_t once; dispatch_once(&once, ^{ instance = [[Downloader alloc] init]; }); return instance; }
- (instancetype)init { if ((self = [super init])) _tasks = [NSMutableArray new]; return self; }
- (void)downloadMediaAtURL:(NSURL *)url completion:(void(^)(NSString *, NSError *))completion {
  if (!url) return;
  NSURLSessionDownloadTask *task = [[NSURLSession sharedSession] downloadTaskWithURL:url completionHandler:^(NSURL *loc, NSURLResponse *resp, NSError *err) {
    if (err) { if (completion) completion(nil, err); return; }
    NSString *path = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.mp4", [[NSUUID UUID] UUIDString]]];
    [[NSFileManager defaultManager] moveItemAtURL:loc toURL:[NSURL fileURLWithPath:path] error:nil];
    if (completion) completion(path, nil);
  }];
  [task resume];
  [_tasks addObject:task];
}
- (void)cancelAll { for (NSURLSessionDownloadTask *t in _tasks) [t cancel]; [_tasks removeAllObjects]; }
@end

@interface DownloaderHelper : NSObject
+ (void)saveVideoAtPath:(NSString *)path completion:(void(^)(BOOL success, NSError *err))completion;
@end

@implementation DownloaderHelper
+ (void)saveVideoAtPath:(NSString *)path completion:(void(^)(BOOL, NSError *))completion {
  [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
    [PHAssetCreationRequest creationRequestForAssetFromVideoAtFileURL:[NSURL fileURLWithPath:path]];
  } completionHandler:^(BOOL success, NSError *err) { if (completion) completion(success, err); }];
}
@end

// ─── Toast ───
@interface ToastView : UIView
- (instancetype)initWithMessage:(NSString *)message;
@end

@interface ToastWindow : UIWindow
+ (instancetype)sharedWindow;
- (void)enqueueToastWithMessage:(NSString *)message duration:(NSTimeInterval)duration;
@end

@interface ToastManager : NSObject
+ (instancetype)shared;
- (void)showToastWithMessage:(NSString *)message;
@end

@implementation ToastView
- (instancetype)initWithMessage:(NSString *)message {
  if ((self = [super init])) {
    UILabel *label = [[UILabel alloc] init];
    label.text = message; label.textColor = [UIColor whiteColor]; label.font = [UIFont systemFontOfSize:14];
    label.numberOfLines = 0; [label sizeToFit];
    self.frame = CGRectMake(0, 0, label.frame.size.width + 30, label.frame.size.height + 20);
    label.center = CGPointMake(self.frame.size.width / 2, self.frame.size.height / 2);
    self.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.8];
    self.layer.cornerRadius = 8; [self addSubview:label];
  }
  return self;
}
@end

@implementation ToastWindow {
  NSMutableArray *_queue; BOOL _showing;
}
+ (instancetype)sharedWindow {
  static ToastWindow *instance;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ instance = [[ToastWindow alloc] initWithFrame:[UIScreen mainScreen].bounds]; instance.windowLevel = UIWindowLevelAlert; instance.hidden = NO; });
  return instance;
}
- (instancetype)initWithFrame:(CGRect)frame {
  if ((self = [super initWithFrame:frame])) { _queue = [NSMutableArray new]; self.userInteractionEnabled = NO; }
  return self;
}
- (void)enqueueToastWithMessage:(NSString *)message duration:(NSTimeInterval)duration {
  [_queue addObject:@{@"message": message ?: @"", @"duration": @(duration)}];
  if (!_showing) [self showNext];
}
- (void)showNext {
  if (_queue.count == 0) { _showing = NO; return; }
  _showing = YES;
  NSDictionary *item = _queue[0]; [_queue removeObjectAtIndex:0];
  ToastView *toast = [[ToastView alloc] initWithMessage:item[@"message"]];
  toast.center = CGPointMake(self.center.x, self.frame.size.height - 120);
  toast.alpha = 0; [self addSubview:toast];
  [UIView animateWithDuration:0.3 animations:^{ toast.alpha = 1; } completion:^(BOOL done) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)([item[@"duration"] doubleValue] * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      [UIView animateWithDuration:0.3 animations:^{ toast.alpha = 0; } completion:^(BOOL done) { [toast removeFromSuperview]; [self showNext]; }];
    });
  }];
}
@end

@implementation ToastManager
+ (instancetype)shared { static ToastManager *instance; static dispatch_once_t once; dispatch_once(&once, ^{ instance = [[ToastManager alloc] init]; }); return instance; }
- (void)showToastWithMessage:(NSString *)message { [[ToastWindow sharedWindow] enqueueToastWithMessage:message duration:2.0]; }
@end

// ─── Sheet Presenter ───
@interface DVNSheetController : UIViewController
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIView *dimmingView;
@property (nonatomic, strong) UIView *containerView;
- (instancetype)initWithContentView:(UIView *)view;
@end
@interface DVNSheetPresenter : UIPresentationController @end
@interface PseudoDetentController : NSObject @end
@interface PseudoDetentTransitioningDelegate : NSObject <UIViewControllerTransitioningDelegate> @end

@implementation DVNSheetController
- (instancetype)initWithContentView:(UIView *)view {
  if ((self = [super init])) { self.contentView = view; self.modalPresentationStyle = UIModalPresentationCustom; self.transitioningDelegate = [PseudoDetentTransitioningDelegate new]; }
  return self;
}
- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor = [UIColor clearColor];
  self.dimmingView = [[UIView alloc] initWithFrame:self.view.bounds];
  self.dimmingView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.4];
  self.dimmingView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  [self.view addSubview:self.dimmingView];
  self.containerView = [[UIView alloc] initWithFrame:CGRectMake(0, self.view.bounds.size.height * 0.4, self.view.bounds.size.width, self.view.bounds.size.height * 0.6)];
  self.containerView.backgroundColor = [UIColor whiteColor];
  self.containerView.layer.cornerRadius = 16;
  self.containerView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
  [self.containerView addSubview:self.contentView]; self.contentView.frame = self.containerView.bounds;
  self.contentView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  [self.view addSubview:self.containerView];
  UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismiss)];
  [self.dimmingView addGestureRecognizer:tap];
}
- (void)dismiss { [self dismissViewControllerAnimated:YES completion:nil]; }
@end
@implementation DVNSheetPresenter
- (CGRect)frameOfPresentedViewInContainerView { return CGRectMake(0, self.containerView.bounds.size.height * 0.4, self.containerView.bounds.size.width, self.containerView.bounds.size.height * 0.6); }
- (void)containerViewWillLayoutSubviews { self.presentedView.frame = [self frameOfPresentedViewInContainerView]; }
@end
@implementation PseudoDetentController @end
@implementation PseudoDetentTransitioningDelegate
- (UIPresentationController *)presentationControllerForPresentedViewController:(UIViewController *)presented presentingViewController:(UIViewController *)presenting sourceViewController:(UIViewController *)source { return [[DVNSheetPresenter alloc] initWithPresentedViewController:presented presentingViewController:presenting]; }
@end

// ─── Settings ───
@interface SettingsViewController : UITableViewController @end

@implementation SettingsViewController { NSMutableArray *_sections; }
- (instancetype)init {
  if ((self = [super initWithStyle:UITableViewStyleGrouped])) {
    self.title = @"Glow";
    _sections = [@[
      @{@"title": @"Download", @"items": @[
        @{@"label": @"Videos", @"key": @"DownloadVideos", @"def": @YES},
        @{@"label": @"Stories", @"key": @"DownloadStories", @"def": @YES},
        @{@"label": @"Reels", @"key": @"DownloadReels", @"def": @YES}]},
      @{@"title": @"Privacy", @"items": @[
        @{@"label": @"Anonymous Stories", @"key": @"AnonymousStories", @"def": @YES}]},
      @{@"title": @"Content", @"items": @[
        @{@"label": @"Remove Ads", @"key": @"RemoveAds", @"def": @YES},
        @{@"label": @"Remove PYMK", @"key": @"RemovePYMK", @"def": @YES},
        @{@"label": @"Remove Recs", @"key": @"RemoveRecs", @"def": @YES},
        @{@"label": @"Remove Reels Carousel", @"key": @"RemoveReelsCarousel", @"def": @YES}]},
      @{@"title": @"Interaction", @"items": @[
        @{@"label": @"Confirm Like", @"key": @"PostLikeConfirm", @"def": @NO},
        @{@"label": @"Disable Auto Next", @"key": @"DisableAutoNext", @"def": @NO}]}] mutableCopy];
  }
  return self;
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return _sections.count; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return [_sections[s][@"items"] count]; }
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s { return _sections[s][@"title"]; }
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
  UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"cell"];
  if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"cell"];
  NSDictionary *item = _sections[ip.section][@"items"][ip.row];
  cell.textLabel.text = item[@"label"]; cell.selectionStyle = UITableViewCellSelectionStyleNone;
  UISwitch *sw = [[UISwitch alloc] init];
  sw.on = PBOOL(item[@"key"], [item[@"def"] boolValue]);
  sw.tag = ip.section * 100 + ip.row;
  [sw addTarget:self action:@selector(swChanged:) forControlEvents:UIControlEventValueChanged];
  cell.accessoryView = sw;
  return cell;
}
- (void)swChanged:(UISwitch *)sw {
  NSInteger s = sw.tag / 100, r = sw.tag % 100;
  PSET(_sections[s][@"items"][r][@"key"], @(sw.isOn)); saveP();
}
@end

// ─── WelcomeVC ───
@interface WelcomeVC : UIViewController @end
@implementation WelcomeVC
- (void)viewDidLoad {
  [super viewDidLoad];
  self.title = @"Welcome"; self.view.backgroundColor = [UIColor whiteColor];
  UILabel *label = [[UILabel alloc] initWithFrame:CGRectInset(self.view.bounds, 20, 100)];
  label.text = @"Glow v1.3.1\n\n• Download Videos, Stories, Reels\n• Remove Ads\n• Anonymous Stories\n• Long press tab bar for settings"; label.numberOfLines = 0; label.textAlignment = NSTextAlignmentCenter;
  label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  [self.view addSubview:label];
  self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Done" style:UIBarButtonItemStyleDone target:self action:@selector(dismissWelcome)];
}
- (void)dismissWelcome { [self dismissViewControllerAnimated:YES completion:nil]; }
+ (void)show {
  UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:[[WelcomeVC alloc] init]];
  [topVC() presentViewController:nav animated:YES completion:nil];
}
@end

// ─── DVNLongPressGestureRecognizer ───
@interface DVNLongPressGestureRecognizer : UILongPressGestureRecognizer @end
@implementation DVNLongPressGestureRecognizer
- (instancetype)initWithTarget:(id)target action:(SEL)action {
  if ((self = [super initWithTarget:target action:action])) self.minimumPressDuration = 0.5;
  return self;
}
@end

// ─── Tab Bar Installer ───
@interface DVNTabBarInstaller : NSObject @end
@implementation DVNTabBarInstaller
+ (UITabBar *)findTabBarInView:(UIView *)view {
  if ([view isKindOfClass:[UITabBar class]]) return (UITabBar *)view;
  for (UIView *sub in view.subviews) { UITabBar *found = [self findTabBarInView:sub]; if (found) return found; }
  return nil;
}
+ (void)installOnTabBar {
  UITabBar *tabBar = nil;
  if (@available(iOS 13.0, *)) {
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
      if (![scene isKindOfClass:[UIWindowScene class]]) continue;
      for (UIWindow *window in [(UIWindowScene *)scene windows]) {
        tabBar = [self findTabBarInView:window]; if (tabBar) break;
      }
      if (tabBar) break;
    }
  }
  if (!tabBar) tabBar = [self findTabBarInView:[[UIApplication sharedApplication] keyWindow]];
  if (tabBar) {
    for (UIGestureRecognizer *g in tabBar.gestureRecognizers)
      if ([NSStringFromClass([g class]) containsString:@"DVN"]) return;
    DVNLongPressGestureRecognizer *g = [[DVNLongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    [tabBar addGestureRecognizer:g];
  }
}
+ (void)handleLongPress:(UIGestureRecognizer *)g {
  if (g.state == UIGestureRecognizerStateBegan) {
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:[[SettingsViewController alloc] init]];
    [topVC() presentViewController:nav animated:YES completion:nil];
  }
}
@end

// ─── Download Target ───
@interface GlowDownloadTarget : NSObject @end
@implementation GlowDownloadTarget
+ (instancetype)shared { static GlowDownloadTarget *inst; static dispatch_once_t once; dispatch_once(&once, ^{ inst = [[GlowDownloadTarget alloc] init]; }); return inst; }
- (void)downloadTapped:(UIButton *)btn {
  NSString *url = btn.accessibilityIdentifier; if (!url) return;
  [[Downloader shared] downloadMediaAtURL:[NSURL URLWithString:url] completion:^(NSString *path, NSError *err) {
    if (path) [DownloaderHelper saveVideoAtPath:path completion:^(BOOL ok, NSError *e) {
      dispatch_async(dispatch_get_main_queue(), ^{ [[ToastManager shared] showToastWithMessage:ok ? @"Saved!" : @"Failed"]; });
    }];
  }];
}
@end

static void injectDownloadBtn(UIView *target, NSString *urlStr) {
  if (!urlStr.length) return;
  if (!PBOOL(@"DownloadVideos", YES) && !PBOOL(@"DownloadStories", YES) && !PBOOL(@"DownloadReels", YES)) return;
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

    @try {
      dlopen([[[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"Frameworks/FBSharedFramework.framework/FBSharedFramework"] UTF8String], RTLD_NOW | RTLD_GLOBAL);
    } @catch (NSException *e) { NSLog(@"[Glow] dlopen error: %@", e.reason); }

    // ── 1. Hook UIViewController.viewDidLoad ──
    {
      static IMP orig_vdl;
      MSHookMessageEx([UIViewController class], @selector(viewDidLoad),
        imp_implementationWithBlock(^(UIViewController *self, SEL _cmd) {
          ((void(*)(UIViewController *, SEL))orig_vdl)(self, _cmd);
          const char *name = class_getName([self class]);

          // Seen fix for story viewers
          if (PBOOL(@"AnonymousStories", YES) && strstr(name, "Story")) {
            static dispatch_once_t once;
            dispatch_once(&once, ^{
              SEL sels[] = {
                NSSelectorFromString(@"_canMarkStoryAsSeen"),
                NSSelectorFromString(@"MarkStoryAsSeen"),
                NSSelectorFromString(@"_markThreadAsSeen:bucket:session:shouldMarkThreadSeenStateUpdates:"),
              };
              for (int i = 0; i < 3; i++) {
                if ([self respondsToSelector:sels[i]]) {
                  Method m = class_getInstanceMethod([self class], sels[i]);
                  if (m) method_setImplementation(m, imp_implementationWithBlock(^(id self_, SEL _cmd) {
                    if (!PBOOL(@"AnonymousStories", YES))
                      ((void(*)(id, SEL))method_getImplementation(m))(self_, _cmd);
                  }));
                }
              }
            });
          }

          // Download button injection
          NSString *url = nil;
          if (strstr(name, "Story")) url = [MediaExtractor extractVideoURLFromStory:self];
          else if (strstr(name, "Reel")) url = [MediaExtractor extractVideoURLFromReel:self];
          if (url) injectDownloadBtn(self.view, url);
        }), &orig_vdl);
    }

    // ── 2. Hook UIView.addSubview: for download injection ──
    {
      static IMP orig_asv;
      MSHookMessageEx([UIView class], @selector(addSubview:),
        imp_implementationWithBlock(^(UIView *self, SEL _cmd, UIView *subview) {
          ((void(*)(UIView *, SEL, UIView *))orig_asv)(self, _cmd, subview);
          const char *name = class_getName([subview class]);
          if (strstr(name, "Story") || strstr(name, "Reel")) {
            NSString *url = [MediaExtractor extractVideoURLFromFeed:subview];
            if (url) injectDownloadBtn(subview, url);
          }
        }), &orig_asv);
    }

    // ── 3. Long press on tab bar ──
    [DVNTabBarInstaller installOnTabBar];

    // ── 4. Welcome screen ──
    if (!PBOOL(@"hasLaunched", NO)) {
      PSET(@"hasLaunched", @YES); saveP();
      dispatch_async(dispatch_get_main_queue(), ^{
        if ([[UIApplication sharedApplication] keyWindow].rootViewController) [WelcomeVC show];
      });
    }

    // ── 5. Auto clear cache ──
    if (PBOOL(@"AutoClearCache", NO)) [[NSURLCache sharedURLCache] removeAllCachedResponses];

    NSLog(@"[Glow] v1.3.1 loaded");
  }
}
