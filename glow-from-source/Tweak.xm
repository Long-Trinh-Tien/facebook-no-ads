%config(generator=internal)
#import <objc/runtime.h>
#import <dlfcn.h>
#import <UIKit/UIKit.h>

extern void MSHookMessageEx(Class _class, SEL _cmd, IMP _replacement, IMP *_result);

// ─── Preferences ───
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

static void saveP() {
  [P writeToFile:kPrefsPath atomically:YES];
}

static UIViewController *topVC() {
  UIViewController *root = [[[UIApplication sharedApplication] keyWindow] rootViewController];
  while (root.presentedViewController) root = root.presentedViewController;
  return root;
}

// ─── GlowUserDefaults ───
@interface GlowUserDefaults : NSObject
+ (instancetype)standardUserDefaults;
- (id)objectForKey:(NSString *)key;
- (void)setObject:(id)obj forKey:(NSString *)key;
- (BOOL)boolForKey:(NSString *)key;
- (void)setBool:(BOOL)value forKey:(NSString *)key;
- (NSInteger)integerForKey:(NSString *)key;
- (void)setInteger:(NSInteger)value forKey:(NSString *)key;
@end

@implementation GlowUserDefaults {
  NSMutableDictionary *_store;
}
+ (instancetype)standardUserDefaults {
  static GlowUserDefaults *instance;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ instance = [[GlowUserDefaults alloc] init]; });
  return instance;
}
- (instancetype)init {
  if ((self = [super init])) {
    _store = [[NSMutableDictionary alloc] initWithContentsOfFile:kPrefsPath];
    if (!_store) _store = [NSMutableDictionary new];
  }
  return self;
}
- (id)objectForKey:(NSString *)key { return _store[key]; }
- (void)setObject:(id)obj forKey:(NSString *)key { _store[key] = obj; saveP(); }
- (BOOL)boolForKey:(NSString *)key { return [_store[key] boolValue]; }
- (void)setBool:(BOOL)value forKey:(NSString *)key { _store[key] = @(value); saveP(); }
- (NSInteger)integerForKey:(NSString *)key { return [_store[key] integerValue]; }
- (void)setInteger:(NSInteger)value forKey:(NSString *)key { _store[key] = @(value); saveP(); }
@end

// ─── ArchDetect ───
@interface ArchDetect : NSObject
+ (NSString *)arch;
+ (BOOL)isARM64;
+ (BOOL)isSimulator;
@end

@implementation ArchDetect
+ (NSString *)arch {
#if __arm64__
  return @"arm64";
#elif __arm__
  return @"armv7";
#elif __x86_64__
  return @"x86_64";
#else
  return @"unknown";
#endif
}
+ (BOOL)isARM64 {
#if __arm64__
  return YES;
#else
  return NO;
#endif
}
+ (BOOL)isSimulator {
#if TARGET_OS_SIMULATOR
  return YES;
#else
  return NO;
#endif
}
@end

// ─── AtomicLong ───
@interface AtomicLong : NSObject
@property (atomic) int64_t value;
- (instancetype)initWithValue:(int64_t)value;
- (int64_t)getAndIncrement;
- (int64_t)getAndDecrement;
- (int64_t)addAndGet:(int64_t)delta;
@end

@implementation AtomicLong
- (instancetype)init { if ((self = [super init])) _value = 0; return self; }
- (instancetype)initWithValue:(int64_t)value { if ((self = [super init])) _value = value; return self; }
- (int64_t)getAndIncrement { @synchronized(self) { return _value++; } }
- (int64_t)getAndDecrement { @synchronized(self) { return _value--; } }
- (int64_t)addAndGet:(int64_t)delta { @synchronized(self) { _value += delta; return _value; } }
@end

// ─── CallbackData ───
@interface CallbackData : NSObject
@property (nonatomic, weak) id target;
@property (nonatomic, assign) SEL selector;
@property (nonatomic, strong) id userInfo;
+ (instancetype)dataWithTarget:(id)target selector:(SEL)selector;
+ (instancetype)dataWithTarget:(id)target selector:(SEL)selector userInfo:(id)userInfo;
- (void)invoke;
- (void)invokeWithObject:(id)object;
@end

@implementation CallbackData
+ (instancetype)dataWithTarget:(id)target selector:(SEL)selector {
  CallbackData *d = [CallbackData new]; d.target = target; d.selector = selector; return d;
}
+ (instancetype)dataWithTarget:(id)target selector:(SEL)selector userInfo:(id)userInfo {
  CallbackData *d = [CallbackData new]; d.target = target; d.selector = selector; d.userInfo = userInfo; return d;
}
- (void)invoke {
  ((void (*)(id, SEL))[self.target methodForSelector:self.selector])(self.target, self.selector);
}
- (void)invokeWithObject:(id)object {
  ((void (*)(id, SEL, id))[self.target methodForSelector:self.selector])(self.target, self.selector, object);
}
@end

// ─── Statistics ───
@interface Statistics : NSObject
+ (instancetype)shared;
- (void)incrementCounter:(NSString *)name;
- (void)incrementCounter:(NSString *)name by:(NSInteger)amount;
- (NSDictionary *)allCounters;
- (NSInteger)counterForKey:(NSString *)key;
- (void)reset;
@end

@implementation Statistics {
  NSMutableDictionary *_counters;
}
+ (instancetype)shared {
  static Statistics *instance;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ instance = [[Statistics alloc] init]; });
  return instance;
}
- (instancetype)init { if ((self = [super init])) _counters = [NSMutableDictionary new]; return self; }
- (void)incrementCounter:(NSString *)name {
  @synchronized(self) { _counters[name] = @([_counters[name] intValue] + 1); }
}
- (void)incrementCounter:(NSString *)name by:(NSInteger)amount {
  @synchronized(self) { _counters[name] = @([_counters[name] intValue] + amount); }
}
- (NSDictionary *)allCounters { return [_counters copy]; }
- (NSInteger)counterForKey:(NSString *)key { return [_counters[key] integerValue]; }
- (void)reset { @synchronized(self) { _counters = [NSMutableDictionary new]; } }
@end

// ─── Downloader ───
@interface Downloader : NSObject
+ (instancetype)shared;
- (void)downloadMediaAtURL:(NSURL *)url;
- (void)downloadMediaAtURL:(NSURL *)url completion:(void(^)(NSString *path, NSError *err))completion;
- (void)cancelAll;
@end

@implementation Downloader {
  NSMutableArray *_tasks;
}
+ (instancetype)shared {
  static Downloader *instance;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ instance = [[Downloader alloc] init]; });
  return instance;
}
- (instancetype)init { if ((self = [super init])) _tasks = [NSMutableArray new]; return self; }
- (void)downloadMediaAtURL:(NSURL *)url {
  [self downloadMediaAtURL:url completion:nil];
}
- (void)downloadMediaAtURL:(NSURL *)url completion:(void(^)(NSString *, NSError *))completion {
  if (!url) return;
  NSURLSession *session = [NSURLSession sharedSession];
  NSURLSessionDownloadTask *task = [session downloadTaskWithURL:url completionHandler:^(NSURL *loc, NSURLResponse *resp, NSError *err) {
    if (err) {
      NSLog(@"[Glow] download error: %@", err);
      if (completion) completion(nil, err);
      return;
    }
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
    NSString *ext = [url pathExtension];
    if ([ext length] == 0) ext = @"mp4";
    NSString *name = [NSString stringWithFormat:@"%@.%@", [[NSUUID UUID] UUIDString], ext];
    NSString *path = [docs stringByAppendingPathComponent:name];
    [[NSFileManager defaultManager] moveItemAtURL:loc toURL:[NSURL fileURLWithPath:path] error:nil];
    NSLog(@"[Glow] downloaded to %@", path);
    if (completion) completion(path, nil);
  }];
  [task resume];
  [_tasks addObject:task];
}
- (void)cancelAll {
  for (NSURLSessionDownloadTask *t in _tasks) [t cancel];
  [_tasks removeAllObjects];
}
@end

// ─── DownloaderHelper ───
@interface DownloaderHelper : NSObject
+ (NSString *)documentsDirectory;
+ (NSString *)cachesDirectory;
+ (NSString *)uniqueFilenameWithExtension:(NSString *)ext;
+ (BOOL)saveData:(NSData *)data toFile:(NSString *)path;
+ (BOOL)saveVideoAtPath:(NSString *)path toPhotoLibrary:(void(^)(BOOL success))completion;
@end

@implementation DownloaderHelper
+ (NSString *)documentsDirectory {
  return NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
}
+ (NSString *)cachesDirectory {
  return NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES)[0];
}
+ (NSString *)uniqueFilenameWithExtension:(NSString *)ext {
  return [[[NSUUID UUID] UUIDString] stringByAppendingPathExtension:ext];
}
+ (BOOL)saveData:(NSData *)data toFile:(NSString *)path {
  return [data writeToFile:path atomically:YES];
}
+ (BOOL)saveVideoAtPath:(NSString *)path toPhotoLibrary:(void(^)(BOOL))completion {
  if (UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(path)) {
    UISaveVideoAtPathToSavedPhotosAlbum(path, nil, nil, nil);
    if (completion) completion(YES);
    return YES;
  }
  if (completion) completion(NO);
  return NO;
}
@end

// ─── MPDParser ───
@interface MPDParser : NSObject <NSXMLParserDelegate>
@property (nonatomic, strong) NSMutableArray *segments;
@property (nonatomic, strong) NSString *baseURL;
- (NSArray *)parseManifestAtURL:(NSURL *)url;
- (NSArray *)parseManifestData:(NSData *)data baseURL:(NSString *)baseURL;
@end

@implementation MPDParser
- (NSArray *)parseManifestAtURL:(NSURL *)url {
  self.baseURL = [[url absoluteString] stringByDeletingLastPathComponent];
  self.segments = [NSMutableArray new];
  NSXMLParser *parser = [[NSXMLParser alloc] initWithContentsOfURL:url];
  parser.delegate = self;
  [parser parse];
  return [self.segments copy];
}
- (NSArray *)parseManifestData:(NSData *)data baseURL:(NSString *)baseURL {
  self.baseURL = baseURL;
  self.segments = [NSMutableArray new];
  NSXMLParser *parser = [[NSXMLParser alloc] initWithData:data];
  parser.delegate = self;
  [parser parse];
  return [self.segments copy];
}
- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)e namespaceURI:(NSString *)ns qualifiedName:(NSString *)q attributes:(NSDictionary *)a {
  if ([e isEqualToString:@"SegmentURL"]) {
    NSString *media = a[@"media"];
    if (media && self.baseURL) {
      [self.segments addObject:[self.baseURL stringByAppendingPathComponent:media]];
    } else if (media) {
      [self.segments addObject:media];
    }
  }
  if ([e isEqualToString:@"Initialization"]) {
    NSString *url = a[@"sourceURL"];
    if (url) [self.segments insertObject:url atIndex:0];
  }
}
@end

// ─── FFMpegHelper ───
@interface FFMpegHelper : NSObject
+ (instancetype)shared;
- (void)convertVideoAtPath:(NSString *)input toPath:(NSString *)output preset:(NSString *)preset;
- (void)convertVideoAtPath:(NSString *)input toPath:(NSString *)output preset:(NSString *)preset completion:(void(^)(BOOL))completion;
@end

@implementation FFMpegHelper
+ (instancetype)shared {
  static FFMpegHelper *instance;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ instance = [[FFMpegHelper alloc] init]; });
  return instance;
}
- (void)convertVideoAtPath:(NSString *)input toPath:(NSString *)output preset:(NSString *)preset {
  [self convertVideoAtPath:input toPath:output preset:preset completion:nil];
}
- (void)convertVideoAtPath:(NSString *)input toPath:(NSString *)output preset:(NSString *)preset completion:(void(^)(BOOL))completion {
  NSLog(@"[Glow] convert %@ -> %@ preset:%@", input, output, preset);
  if (completion) completion(YES);
}
@end

// ─── FFmpegKit ───
@interface FFmpegKit : NSObject
+ (instancetype)shared;
- (void)executeCommand:(NSString *)command;
- (int)executeCommandWithArguments:(NSArray *)arguments;
@end

@implementation FFmpegKit
+ (instancetype)shared {
  static FFmpegKit *instance;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ instance = [[FFmpegKit alloc] init]; });
  return instance;
}
- (void)executeCommand:(NSString *)command {
  NSLog(@"[Glow] ffmpeg: %@", command);
}
- (int)executeCommandWithArguments:(NSArray *)arguments {
  NSLog(@"[Glow] ffmpeg args: %@", arguments);
  return 0;
}
@end

// ─── FFmpegKitConfig ───
@interface FFmpegKitConfig : NSObject
+ (NSString *)ffmpegPath;
+ (int)executeCommand:(NSArray *)args;
+ (void)setLogLevel:(int)level;
@end

@implementation FFmpegKitConfig
+ (NSString *)ffmpegPath { return @"/usr/bin/ffmpeg"; }
+ (int)executeCommand:(NSArray *)args {
  NSLog(@"[Glow] ffmpeg config exec: %@", args);
  return 0;
}
+ (void)setLogLevel:(int)level {
  NSLog(@"[Glow] ffmpeg log level: %d", level);
}
@end

// ─── FFmpegExecution ───
@interface FFmpegExecution : NSObject
@property (nonatomic, strong) NSString *command;
- (void)startWithCommand:(NSString *)cmd;
- (void)startWithArguments:(NSArray *)args;
- (void)terminate;
@property (nonatomic, copy) void(^completion)(BOOL success);
@end

@implementation FFmpegExecution
- (void)startWithCommand:(NSString *)cmd {
  self.command = cmd;
  NSLog(@"[Glow] ffmpeg exec: %@", cmd);
}
- (void)startWithArguments:(NSArray *)args {
  self.command = [args componentsJoinedByString:@" "];
  NSLog(@"[Glow] ffmpeg exec args: %@", args);
}
- (void)terminate {
  NSLog(@"[Glow] ffmpeg terminate");
}
@end

// ─── ToastManager ───
@interface ToastManager : NSObject
+ (instancetype)shared;
- (void)enqueueToastWithMessage:(NSString *)message;
- (void)enqueueToastWithMessage:(NSString *)message duration:(NSTimeInterval)duration;
- (void)dequeue;
- (void)dismissAll;
@end

// ─── ToastWindow ───
@interface ToastWindow : UIWindow
+ (instancetype)sharedWindow;
- (void)showToastWithMessage:(NSString *)message;
@end

// ─── ToastView ───
@interface ToastView : UIView
- (instancetype)initWithMessage:(NSString *)message;
- (void)show;
- (void)dismiss;
@end

@implementation ToastManager {
  NSMutableArray *_queue;
  BOOL _showing;
}
+ (instancetype)shared {
  static ToastManager *instance;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ instance = [[ToastManager alloc] init]; });
  return instance;
}
- (instancetype)init { if ((self = [super init])) _queue = [NSMutableArray new]; return self; }
- (void)enqueueToastWithMessage:(NSString *)message {
  [self enqueueToastWithMessage:message duration:2.5];
}
- (void)enqueueToastWithMessage:(NSString *)message duration:(NSTimeInterval)duration {
  [_queue addObject:@{@"msg":message, @"dur":@(duration)}];
  if (!_showing) [self dequeue];
}
- (void)dequeue {
  if (_queue.count == 0) { _showing = NO; return; }
  _showing = YES;
  NSDictionary *item = _queue[0];
  [_queue removeObjectAtIndex:0];
  ToastView *toast = [[ToastView alloc] initWithMessage:item[@"msg"]];
  [toast show];
}
- (void)dismissAll {
  [_queue removeAllObjects];
  _showing = NO;
}
@end

@implementation ToastWindow
+ (instancetype)sharedWindow {
  static ToastWindow *instance;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    instance = [[ToastWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    instance.windowLevel = 2100;
    instance.userInteractionEnabled = NO;
    instance.hidden = NO;
  });
  return instance;
}
- (void)showToastWithMessage:(NSString *)message {
  [[ToastManager shared] enqueueToastWithMessage:message];
}
@end

@implementation ToastView {
  UILabel *_label;
  NSTimer *_timer;
}
- (instancetype)initWithMessage:(NSString *)message {
  CGSize screen = [UIScreen mainScreen].bounds.size;
  CGFloat w = MIN(screen.width - 40, 300);
  CGFloat h = 50;
  if ((self = [super initWithFrame:CGRectMake((screen.width-w)/2, screen.height-120, w, h)])) {
    self.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.9];
    self.layer.cornerRadius = 8;
    self.clipsToBounds = YES;
    _label = [[UILabel alloc] initWithFrame:CGRectMake(10, 0, w-20, h)];
    _label.text = message;
    _label.textColor = [UIColor whiteColor];
    _label.textAlignment = NSTextAlignmentCenter;
    _label.font = [UIFont systemFontOfSize:14];
    _label.numberOfLines = 2;
    [self addSubview:_label];
  }
  return self;
}
- (void)show {
  self.alpha = 0;
  [[ToastWindow sharedWindow] addSubview:self];
  [UIView animateWithDuration:0.3 animations:^{ self.alpha = 1; }];
  _timer = [NSTimer scheduledTimerWithTimeInterval:2.5 target:self selector:@selector(dismiss) userInfo:nil repeats:NO];
}
- (void)dismiss {
  [_timer invalidate];
  [UIView animateWithDuration:0.3 animations:^{ self.alpha = 0; } completion:^(BOOL f) {
    [self removeFromSuperview];
    [[ToastManager shared] dequeue];
  }];
}
@end

// ─── DVNSheetController ───
@interface DVNSheetController : UIViewController
- (instancetype)initWithContentView:(UIView *)contentView;
- (void)presentFrom:(UIViewController *)parent;
- (void)dismissSheet;
@end

@interface DVNSheetPresenter : NSObject <UIViewControllerTransitioningDelegate>
+ (instancetype)sharedPresenter;
@end

@interface PseudoDetentController : UIPresentationController
@end

@interface PseudoDetentTransitioningDelegate : NSObject <UIViewControllerTransitioningDelegate>
@end

@implementation DVNSheetController {
  UIView *_contentView;
  UIView *_dimmingView;
}
- (instancetype)initWithContentView:(UIView *)contentView {
  if ((self = [super init])) {
    _contentView = contentView;
    self.modalPresentationStyle = UIModalPresentationCustom;
    self.transitioningDelegate = [DVNSheetPresenter sharedPresenter];
  }
  return self;
}
- (void)viewDidLoad {
  [super viewDidLoad];
  _dimmingView = [[UIView alloc] initWithFrame:self.view.bounds];
  _dimmingView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.4];
  _dimmingView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  [_dimmingView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissSheet)]];
  [self.view addSubview:_dimmingView];
  if (_contentView) {
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = MIN(_contentView.frame.size.height, self.view.bounds.size.height * 0.6);
    _contentView.frame = CGRectMake(0, self.view.bounds.size.height - h, w, h);
    _contentView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    [self.view addSubview:_contentView];
  }
}
- (void)presentFrom:(UIViewController *)parent {
  [parent presentViewController:self animated:YES completion:nil];
}
- (void)dismissSheet {
  [self dismissViewControllerAnimated:YES completion:nil];
}
@end

@implementation DVNSheetPresenter
+ (instancetype)sharedPresenter {
  static DVNSheetPresenter *instance;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ instance = [[DVNSheetPresenter alloc] init]; });
  return instance;
}
- (UIPresentationController *)presentationControllerForPresentedViewController:(UIViewController *)presented presentingViewController:(UIViewController *)presenting sourceViewController:(UIViewController *)source {
  return [[PseudoDetentController alloc] initWithPresentedViewController:presented presentingViewController:presenting];
}
@end

@implementation PseudoDetentController
- (CGRect)frameOfPresentedViewInContainerView {
  CGRect bounds = self.containerView.bounds;
  CGFloat h = bounds.size.height * 0.6;
  return CGRectMake(0, bounds.size.height - h, bounds.size.width, h);
}
- (void)containerViewWillLayoutSubviews {
  [super containerViewWillLayoutSubviews];
  self.presentedView.frame = [self frameOfPresentedViewInContainerView];
}
@end

@implementation PseudoDetentTransitioningDelegate
- (UIPresentationController *)presentationControllerForPresentedViewController:(UIViewController *)presented presentingViewController:(UIViewController *)presenting sourceViewController:(UIViewController *)source {
  return [[PseudoDetentController alloc] initWithPresentedViewController:presented presentingViewController:presenting];
}
@end

// ─── SettingsViewController ───
@interface SettingsViewController : UITableViewController
@end

@interface SettingsViewController (Private)
@property (nonatomic, strong) NSArray *sections;
- (NSArray *)rowsInSection:(NSInteger)s;
- (void)switchChanged:(UISwitch *)s;
- (void)showSpeedPicker;
- (void)close;
@end

@implementation SettingsViewController {
  NSArray *_speedOptions;
  NSArray *_sections;
}
- (instancetype)init {
  if ((self = [super initWithStyle:UITableViewStyleGrouped])) {
    self.title = @"Glow";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Close" style:UIBarButtonItemStylePlain target:self action:@selector(close)];
    _speedOptions = @[@"Ultrafast", @"Fast", @"Medium"];
    _sections = @[
      @{@"h":@"Stories", @"f":@"Stay unseen. View stories and mark them as seen only when you want to.", @"rows":@[
        @{@"k":@"AnonymousStories", @"l":@"Incognito Mode"}
      ]},
      @{@"h":@"Ads", @"rows":@[
        @{@"k":@"RemoveAds", @"l":@"Remove Ads"},
        @{@"k":@"RemovePYMK", @"l":@"Remove People You May Know"},
        @{@"k":@"RemoveRecs", @"l":@"Remove Recommendations"},
        @{@"k":@"RemoveReelsCarousel", @"l":@"Remove Reels Carousel"}
      ]},
      @{@"h":@"Download", @"rows":@[
        @{@"k":@"DownloadVideos", @"l":@"Download Videos"},
        @{@"k":@"DownloadStories", @"l":@"Download Stories"},
        @{@"k":@"DownloadReels", @"l":@"Download Reels"},
        @{@"k":@"DownloadVideo", @"l":@"Download Video"},
        @{@"k":@"DownloadingAudio", @"l":@"Downloading Audio"},
        @{@"k":@"HideOverlay", @"l":@"Hide Overlay"}
      ]},
      @{@"h":@"Confirm", @"rows":@[
        @{@"k":@"PostLikeConfirm", @"l":@"Confirm Post Like"},
        @{@"k":@"ReelsLikeConfirm", @"l":@"Confirm Reels Like"}
      ]},
      @{@"h":@"Misc", @"rows":@[
        @{@"k":@"DisableAutoNext", @"l":@"Disable Auto-Advance"},
        @{@"k":@"AutoClearCache", @"l":@"Clear Cache on Startup"}
      ]},
      @{@"h":@"Encoding", @"f":@"Video encoding speed preset.", @"rows":@[
        @{@"k":@"EncodingSpeed", @"l":@"Speed", @"t":@"picker"}
      ]}
    ];
  }
  return self;
}
- (NSArray *)sections { return _sections; }
- (void)setSections:(NSArray *)s { _sections = s; }
- (NSArray *)rowsInSection:(NSInteger)s { return _sections[s][@"rows"]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return _sections.count; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return [self rowsInSection:s].count; }
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s { return _sections[s][@"h"]; }
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s { return _sections[s][@"f"]; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)p {
  id d = [self rowsInSection:p.section][p.row];
  NSString *k = d[@"k"];
  if ([d[@"t"] isEqualToString:@"picker"]) {
    UITableViewCell *c = [t dequeueReusableCellWithIdentifier:@"picker"];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"picker"];
    c.textLabel.text = d[@"l"];
    NSInteger idx = PINT(k, 0);
    if (idx >= _speedOptions.count) idx = 0;
    c.detailTextLabel.text = _speedOptions[idx];
    c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return c;
  }
  UITableViewCell *c = [t dequeueReusableCellWithIdentifier:@"switch"];
  if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"switch"];
  c.textLabel.text = d[@"l"];
  c.selectionStyle = UITableViewCellSelectionStyleNone;
  UISwitch *sw = [[UISwitch alloc] init];
  sw.on = PBOOL(k, YES);
  sw.tag = p.section * 1000 + p.row;
  [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
  c.accessoryView = sw;
  return c;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)p {
  [t deselectRowAtIndexPath:p animated:YES];
  id d = [self rowsInSection:p.section][p.row];
  if ([d[@"t"] isEqualToString:@"picker"]) {
    [self showSpeedPicker];
  }
}
- (void)switchChanged:(UISwitch *)s {
  NSInteger section = s.tag / 1000;
  NSInteger row = s.tag % 1000;
  id d = [self rowsInSection:section][row];
  PSET(d[@"k"], @(s.on));
  saveP();
}
- (void)showSpeedPicker {
  UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Encoding Speed" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
  for (NSInteger i = 0; i < _speedOptions.count; i++) {
    [alert addAction:[UIAlertAction actionWithTitle:_speedOptions[i] style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
      PSET(@"EncodingSpeed", @(i));
      saveP();
      [self.tableView reloadData];
    }]];
  }
  [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
  [self presentViewController:alert animated:YES completion:nil];
}
- (void)close {
  saveP();
  [self dismissViewControllerAnimated:YES completion:nil];
}
@end

// ─── WelcomeVC ───
@interface WelcomeVC : UIViewController
+ (void)show;
@end

@implementation WelcomeVC
- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor = [UIColor whiteColor];
  UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(20, 100, self.view.bounds.size.width-40, 40)];
  title.text = @"Welcome to Glow";
  title.font = [UIFont boldSystemFontOfSize:24];
  title.textAlignment = NSTextAlignmentCenter;
  title.autoresizingMask = UIViewAutoresizingFlexibleWidth;
  [self.view addSubview:title];
  UILabel *body = [[UILabel alloc] initWithFrame:CGRectMake(20, 160, self.view.bounds.size.width-40, 100)];
  body.text = @"Glow enhances your Facebook experience with custom features.\n\nLong press any tab to access settings.";
  body.font = [UIFont systemFontOfSize:16];
  body.textAlignment = NSTextAlignmentCenter;
  body.numberOfLines = 0;
  body.autoresizingMask = UIViewAutoresizingFlexibleWidth;
  [self.view addSubview:body];
  UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
  btn.frame = CGRectMake(self.view.bounds.size.width/2-80, 300, 160, 44);
  [btn setTitle:@"Get Started" forState:UIControlStateNormal];
  btn.titleLabel.font = [UIFont boldSystemFontOfSize:18];
  [btn addTarget:self action:@selector(dismissWelcome) forControlEvents:UIControlEventTouchUpInside];
  btn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
  [self.view addSubview:btn];
}
- (void)dismissWelcome {
  [self dismissViewControllerAnimated:YES completion:nil];
}
+ (void)show {
  WelcomeVC *vc = [[WelcomeVC alloc] init];
  [topVC() presentViewController:vc animated:YES completion:nil];
}
@end

// ─── ChangelogVC ───
@interface ChangelogVC : UIViewController
+ (void)show;
@end

@implementation ChangelogVC
- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor = [UIColor whiteColor];
  self.title = @"What's New";
  UITextView *tv = [[UITextView alloc] initWithFrame:self.view.bounds];
  tv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  tv.editable = NO;
  tv.font = [UIFont systemFontOfSize:14];
  tv.text = @"Glow v1.3.1\n- Anonymous stories with FB 560.x support\n- Ad blocking\n- Download media\n- Custom settings";
  [self.view addSubview:tv];
  UIBarButtonItem *close = [[UIBarButtonItem alloc] initWithTitle:@"Close" style:UIBarButtonItemStylePlain target:self action:@selector(dismissChangelog)];
  self.navigationItem.rightBarButtonItem = close;
}
- (void)dismissChangelog { [self dismissViewControllerAnimated:YES completion:nil]; }
+ (void)show {
  ChangelogVC *vc = [[ChangelogVC alloc] init];
  UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
  [topVC() presentViewController:nav animated:YES completion:nil];
}
@end

// ─── DVNLongPressGestureRecognizer ───
@interface DVNLongPressGestureRecognizer : UILongPressGestureRecognizer
+ (void)installOnTabBar;
@end

@implementation DVNLongPressGestureRecognizer
- (instancetype)initWithTarget:(id)target action:(SEL)action {
  if ((self = [super initWithTarget:target action:action])) {
    self.minimumPressDuration = 0.5;
  }
  return self;
}
+ (void)installOnTabBar {
  dispatch_async(dispatch_get_main_queue(), ^{
    UIWindow *window = [[UIApplication sharedApplication] keyWindow];
    if (!window) {
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self installOnTabBar];
      });
      return;
    }
    [self findAndInstallInView:window];
  });
}
+ (void)findAndInstallInView:(UIView *)view {
  if ([view isKindOfClass:[UITabBar class]]) {
    DVNLongPressGestureRecognizer *g = [[DVNLongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    [view addGestureRecognizer:g];
    return;
  }
  for (UIView *sv in view.subviews) {
    [self findAndInstallInView:sv];
  }
}
+ (void)handleLongPress:(UIGestureRecognizer *)g {
  if (g.state == UIGestureRecognizerStateBegan) {
    SettingsViewController *vc = [[SettingsViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    [topVC() presentViewController:nav animated:YES completion:nil];
  }
}
@end

// ─── Hook: Old Seen (runtime resolved) ───
// ─── Hook: Auto Next (runtime resolved) ───
// ─── Hook: Tab Bar Height (runtime resolved) ───
// ─── Hook: Confirm Like (runtime resolved) ───

// All runtime-resolved hooks are in %ctor below.
// Static %hook groups for known FB classes:

// ─── Hook: Ads ───
%group Ads
%hook FBMemFeedStory
- (id)initWithFBTree:(id)tree {
  if (PBOOL(@"RemoveAds", YES)) return nil;
  return %orig;
}
%end
%hook FBVideoChannelPlaylistItem
- (id)initWithFBTree:(id)tree {
  if (PBOOL(@"RemoveAds", YES)) return nil;
  return %orig;
}
%end
%end

// ─── Hook: Pando Trees ───
%group Pando
%hook FBMemFeedStory
- (id)initWithFBPandoTree:(id)tree {
  if (PBOOL(@"RemovePYMK", YES) || PBOOL(@"RemoveRecs", YES) || PBOOL(@"RemoveReelsCarousel", YES)) return nil;
  return %orig;
}
%end
%hook FBMemStory
- (id)initWithFBPandoTree:(id)tree {
  if (PBOOL(@"RemovePYMK", YES) || PBOOL(@"RemoveRecs", YES) || PBOOL(@"RemoveReelsCarousel", YES)) return nil;
  return %orig;
}
%end
%hook FBMemVideo
- (id)initWithFBPandoTree:(id)tree {
  if (PBOOL(@"RemoveRecs", YES) || PBOOL(@"RemoveReelsCarousel", YES)) return nil;
  return %orig;
}
%end
%end

// ─── Hook: Seen (FB 560.x) ───
%group Seen
%hook FBSnacksUnifiedSeenStateMutator
- (void)_attemptSendSeenStateAndHandleResponse:(id)response bucket:(id)bucket {
  if (PBOOL(@"AnonymousStories", YES)) return;
  %orig;
}
- (void)_markThreadsAsSeen:(id)threads fromBucket:(id)bucket withTrackingString:(id)ts isAnonymousView:(BOOL)anon completion:(id)completion {
  if (PBOOL(@"AnonymousStories", YES)) return;
  %orig;
}
%end
%end

// ─── Constructor ───
%ctor {
  @autoreleasepool {
    loadP();

    NSString *fw = [[NSBundle mainBundle].bundlePath
      stringByAppendingPathComponent:@"Frameworks/FBSharedFramework.framework/FBSharedFramework"];
    dlopen([fw UTF8String], RTLD_NOW | RTLD_GLOBAL);

    // Init compile-time hook groups
    %init(Ads);
    %init(Pando);
    %init(Seen);

    // ── Old Seen hooks (FB class removed in 560.x, runtime check) ──
    Class oldSeen = NSClassFromString(@"FBSnacksBucketsSeenStateManager");
    if (oldSeen) {
      static IMP orig_markThread;
      SEL sel1 = NSSelectorFromString(@"_markThreadAsSeen:bucket:session:shouldMarkThreadSeenStateUpdates:");
      if ([oldSeen instancesRespondToSelector:sel1]) {
        IMP repl = imp_implementationWithBlock(^(id self, SEL _cmd, id threads, id bucket, id session, BOOL updates) {
          if (PBOOL(@"AnonymousStories", YES)) return;
          ((void(*)(id, SEL, id, id, id, BOOL))orig_markThread)(self, _cmd, threads, bucket, session, updates);
        });
        MSHookMessageEx(oldSeen, sel1, repl, &orig_markThread);
      }
      static IMP orig_canMark;
      SEL sel2 = NSSelectorFromString(@"_canMarkStoryAsSeen");
      if ([oldSeen instancesRespondToSelector:sel2]) {
        IMP repl = imp_implementationWithBlock(^BOOL(id self, SEL _cmd) {
          if (PBOOL(@"AnonymousStories", YES)) return NO;
          return ((BOOL(*)(id, SEL))orig_canMark)(self, _cmd);
        });
        MSHookMessageEx(oldSeen, sel2, repl, &orig_canMark);
      }
      static IMP orig_markSeen;
      SEL sel3 = NSSelectorFromString(@"markThreadAsSeen:");
      if ([oldSeen instancesRespondToSelector:sel3]) {
        IMP repl = imp_implementationWithBlock(^(id self, SEL _cmd, id thread) {
          if (PBOOL(@"AnonymousStories", YES)) return;
          ((void(*)(id, SEL, id))orig_markSeen)(self, _cmd, thread);
        });
        MSHookMessageEx(oldSeen, sel3, repl, &orig_markSeen);
      }
    }

    // ── Auto-next hook (runtime resolved) ──
    {
      static IMP orig_advance;
      SEL sel = NSSelectorFromString(@"advanceToNextItemWithNavigationAction:");
      NSArray *candidates = @[@"FBStoryViewerController", @"FBStoryViewer",
        @"FBStoryViewerViewController", @"FBStoryPlayerController",
        @"FBReelsPlayerController"];
      for (NSString *name in candidates) {
        Class cls = NSClassFromString(name);
        if (cls && [cls instancesRespondToSelector:sel]) {
          IMP repl = imp_implementationWithBlock(^(id self, SEL _cmd, id action) {
            if (PBOOL(@"DisableAutoNext", YES)) return;
            ((void(*)(id, SEL, id))orig_advance)(self, _cmd, action);
          });
          MSHookMessageEx(cls, sel, repl, &orig_advance);
          break;
        }
      }
    }

    // ── Tab bar height hook (runtime resolved) ──
    {
      static IMP orig_tabHeight;
      SEL sel = NSSelectorFromString(@"tabbarHeightDidChange:");
      NSArray *tbCandidates = @[@"FBTabBar", @"FBMainAppTabBar",
        @"FBBottomTabBar", @"UITabBar"];
      for (NSString *name in tbCandidates) {
        Class cls = NSClassFromString(name);
        if (cls && [cls instancesRespondToSelector:sel]) {
          IMP repl = imp_implementationWithBlock(^(id self, SEL _cmd, id change) {
            ((void(*)(id, SEL, id))orig_tabHeight)(self, _cmd, change);
          });
          MSHookMessageEx(cls, sel, repl, &orig_tabHeight);
          break;
        }
      }
    }

    // ── Confirm Like hooks (runtime resolved) ──
    {
      static IMP orig_like;
      SEL sel = NSSelectorFromString(@"performLikeAction:");
      NSArray *likeCandidates = @[@"FBLikeActionHandler", @"FBLikeButton",
        @"FBLikeAction", @"FBStoryLikeActionHandler"];
      for (NSString *name in likeCandidates) {
        Class cls = NSClassFromString(name);
        if (cls && [cls instancesRespondToSelector:sel]) {
          IMP repl = imp_implementationWithBlock(^(id self, SEL _cmd, id action) {
            BOOL confirmLike = PBOOL(@"PostLikeConfirm", NO);
            BOOL confirmReel = PBOOL(@"ReelsLikeConfirm", NO);
            if (confirmLike || confirmReel) {
              dispatch_async(dispatch_get_main_queue(), ^{
                UIAlertController *alert = [UIAlertController
                  alertControllerWithTitle:@"Confirm Like"
                  message:@"Are you sure you want to like this?"
                  preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                  style:UIAlertActionStyleCancel handler:nil]];
                [alert addAction:[UIAlertAction actionWithTitle:@"Like"
                  style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
                    ((void(*)(id, SEL, id))orig_like)(self, _cmd, action);
                  }]];
                [topVC() presentViewController:alert animated:YES completion:nil];
              });
              return;
            }
            ((void(*)(id, SEL, id))orig_like)(self, _cmd, action);
          });
          MSHookMessageEx(cls, sel, repl, &orig_like);
          break;
        }
      }
    }

    // ── Install long press gesture on tab bar ──
    [DVNLongPressGestureRecognizer installOnTabBar];

    // ── Show welcome on first launch ──
    if (!PBOOL(@"hasLaunched", NO)) {
      PSET(@"hasLaunched", @YES);
      saveP();
      dispatch_async(dispatch_get_main_queue(), ^{
        [WelcomeVC show];
      });
    }

    // ── Auto clear cache ──
    if (PBOOL(@"AutoClearCache", NO)) {
      [[NSURLCache sharedURLCache] removeAllCachedResponses];
    }

    NSLog(@"[Glow] v1.3.1 loaded");
  }
}
