// Stage v8.0 — Framework port from original Glow 1.3.1
// 1. Multi-group %ctor with %init(group) pattern (from haoict/Glow)
// 2. Settings storage (NSUserDefaults with custom keys)
// 3. Settings UI (alertController with toggles + open long press on tab)
// 4. Long-press on tab bar to open settings
// 5. Hooks ported from glow_v7 (working 560.x):
//    - Ad block: FBMemNewsFeedEdge.node returns nil for SPONSORED
//    - Story seen: 3 paths blocked on FBSnacksBucketsSeenStateManager
//
// All output to /var/mobile/Documents/glow.txt

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <stdio.h>
#import <string.h>
#import <stdlib.h>
#import <dispatch/dispatch.h>

// ─── Logging ───
static char g_log_path[512] = {0};
static void log_msg(const char *fmt, ...) {
    if (g_log_path[0] == 0) {
        const char *home = getenv("HOME");
        if (!home) home = "/var/mobile";
        snprintf(g_log_path, sizeof(g_log_path), "%s/Documents/glow.txt", home);
    }
    FILE *f = fopen(g_log_path, "a");
    if (!f) f = fopen("/var/mobile/Documents/glow.txt", "a");
    if (f) {
        va_list ap;
        va_start(ap, fmt);
        vfprintf(f, fmt, ap);
        va_end(ap);
        fclose(f);
    }
}
#define LOG(fmt, ...) log_msg(fmt, ##__VA_ARGS__)

// ═══════════════════════════════════════════════════════════════
// SECTION 1: Settings storage
// ═══════════════════════════════════════════════════════════════

// Settings keys - same naming convention as Glow/haoict
static BOOL s_removeAds = YES;
static BOOL s_disableStorySeen = YES;
static BOOL s_downloadVideo = NO;
static BOOL s_downloadStory = NO;
static BOOL s_removePYMK = NO;
static BOOL s_removeReelsCarousel = NO;
static BOOL s_removeSuggested = NO;
static BOOL s_hideComposer = NO;
static BOOL s_disableAutoNext = NO;
static BOOL s_confirmLike = NO;
static BOOL s_downloadReels = YES;  // v8.2.25: default ON (Reels button)
static BOOL s_hideOverlay = NO;
static BOOL s_confirmReelsLike = NO;
static BOOL s_downloadLongPress = NO;
static BOOL s_markAsSeen = NO;
static BOOL s_removeStoryPYMK = NO;
static BOOL s_allFormats = NO;
static BOOL s_clearCacheOnLaunch = NO;
static BOOL s_notifyUpdates = NO;

static void reloadPrefs(void) {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    s_removeAds = [d boolForKey:@"com.tommy.glow.removeAds"];
    if (![d objectForKey:@"com.tommy.glow.removeAds"]) s_removeAds = YES;

    s_disableStorySeen = [d boolForKey:@"com.tommy.glow.disableStorySeen"];
    if (![d objectForKey:@"com.tommy.glow.disableStorySeen"]) s_disableStorySeen = YES;

    s_downloadVideo = [d boolForKey:@"com.tommy.glow.downloadVideo"];
    s_downloadStory = [d boolForKey:@"com.tommy.glow.downloadStory"];
    s_removePYMK = [d boolForKey:@"com.tommy.glow.removePYMK"];
    s_removeReelsCarousel = [d boolForKey:@"com.tommy.glow.removeReelsCarousel"];
    s_removeSuggested = [d boolForKey:@"com.tommy.glow.removeSuggested"];
    s_hideComposer = [d boolForKey:@"com.tommy.glow.hideComposer"];
    s_disableAutoNext = [d boolForKey:@"com.tommy.glow.disableAutoNext"];
    s_confirmLike = [d boolForKey:@"com.tommy.glow.confirmLike"];
    s_downloadReels = [d boolForKey:@"com.tommy.glow.downloadReels"];
    if (![d objectForKey:@"com.tommy.glow.downloadReels"]) s_downloadReels = YES;  // v8.2.25: default ON
    s_hideOverlay = [d boolForKey:@"com.tommy.glow.hideOverlay"];
    s_confirmReelsLike = [d boolForKey:@"com.tommy.glow.confirmReelsLike"];
    s_downloadLongPress = [d boolForKey:@"com.tommy.glow.downloadLongPress"];
    s_markAsSeen = [d boolForKey:@"com.tommy.glow.markAsSeen"];
    s_removeStoryPYMK = [d boolForKey:@"com.tommy.glow.removeStoryPYMK"];
    s_allFormats = [d boolForKey:@"com.tommy.glow.allFormats"];
    s_clearCacheOnLaunch = [d boolForKey:@"com.tommy.glow.clearCacheOnLaunch"];
    s_notifyUpdates = [d boolForKey:@"com.tommy.glow.notifyUpdates"];

    LOG("[prefs] reload: ads=%d seen=%d video=%d story=%d pymk=%d reels=%d\n",
        s_removeAds, s_disableStorySeen, s_downloadVideo, s_downloadStory,
        s_removePYMK, s_removeReelsCarousel);
}

// Listen for changes from Settings.app
static void prefsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    reloadPrefs();
}

// ═══════════════════════════════════════════════════════════════
// SECTION 2: Settings UI (Glow-style modal sheet)
// ═══════════════════════════════════════════════════════════════

// Localization helper
static NSString *GlowLoc(NSString *key) {
    static NSDictionary *cached = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Default to Vietnamese strings (Glow's vi translation)
        cached = @{
            // Sections
            @"section.home": @"TRANG CHỦ",
            @"section.reels": @"REELS",
            @"section.stories": @"STORIES",
            @"section.downloader": @"TRÌNH TẢI VIDEO",
            @"section.other": @"KHÁC",

            // Home section
            @"removeAds": @"Xóa quảng cáo",
            @"removePYMK": @"Xóa gợi ý kết bạn",
            @"removeReelsCarousel": @"Xóa thanh cuộn reels",
            @"confirmLike": @"Xác nhận thích bài viết",
            @"downloadVideo": @"Tải video",
            @"downloadVideo.desc": @"Nhấn giữ để tải video từ bảng tin và story",
            @"removeSuggested": @"Xóa bài viết được đề xuất",
            @"removeSuggested.desc": @"Lưu ý: Cần đủ lượt theo dõi để hoạt động chính xác nhất",

            // Reels
            @"downloadReels": @"Tải reels",
            @"hideOverlay": @"Ẩn lớp phủ",
            @"confirmReelsLike": @"Xác nhận thích reels",
            @"downloadLongPress": @"Tải xuống bằng nhấn giữ",
            @"downloadLongPress.desc": @"Dùng cho phiên bản cũ không có nút tải về",

            // Stories
            @"downloadStory": @"Tải stories",
            @"disableStorySeen": @"Xem ẩn danh",
            @"disableAutoNext": @"Tắt tự động chuyển tiếp",
            @"removeStoryPYMK": @"Xóa gợi ý kết bạn trong story",

            // Downloader
            @"allFormats": @"Bao gồm tất cả các định dạng",
            @"encodingSpeed": @"Tốc độ mã hóa",
            @"encodingSpeed.desc": @"Tốc độ mã hóa video:\n• Ultrafast: Xử lý nhanh nhất, kích thước tệp lớn hơn.\n• Faster: Cân bằng giữa tốc độ và kích thước tệp.\n• Medium: Xử lý chậm hơn, kích thước tệp nhỏ hơn.",

            // Other
            @"notifyUpdates": @"Thông báo về cập nhật mới",
            @"clearCacheOnLaunch": @"Xóa bộ nhớ đệm khi khởi động",
            @"clearCache": @"Xóa bộ nhớ đệm",

            // Misc
            @"title": @"Glow v8",
            @"close": @"Đóng",
            @"cancel": @"Hủy",
            @"notYetImplemented": @"(chưa hỗ trợ)",
        };
    });
    NSString *s = cached[key];
    return s ?: key;
}

@interface GlowSwitchCell : UITableViewCell
@property (nonatomic, strong) UISwitch *toggle;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, copy) void (^onToggle)(BOOL);
- (void)configureWithTitle:(NSString *)title subtitle:(NSString *)subtitle value:(BOOL)value onChange:(void(^)(BOOL))onChange;
@end

@implementation GlowSwitchCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightRegular];
        _titleLabel.textColor = [UIColor labelColor];
        _titleLabel.numberOfLines = 1;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_titleLabel];

        _subtitleLabel = [[UILabel alloc] init];
        _subtitleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
        _subtitleLabel.textColor = [UIColor secondaryLabelColor];
        _subtitleLabel.numberOfLines = 0;
        _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_subtitleLabel];

        _toggle = [[UISwitch alloc] init];
        _toggle.translatesAutoresizingMaskIntoConstraints = NO;
        [_toggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
        [self.contentView addSubview:_toggle];

        [NSLayoutConstraint activateConstraints:@[
            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.leadingAnchor constant:4],
            [_titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:12],
            [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_toggle.leadingAnchor constant:-12],

            [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:2],
            [_subtitleLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
            [_subtitleLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-12],

            [_toggle.trailingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.trailingAnchor],
            [_toggle.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        ]];
    }
    return self;
}

- (void)configureWithTitle:(NSString *)title subtitle:(NSString *)subtitle value:(BOOL)value onChange:(void(^)(BOOL))onChange {
    self.titleLabel.text = title;
    self.subtitleLabel.text = subtitle;
    self.subtitleLabel.hidden = (subtitle.length == 0);
    self.toggle.on = value;
    self.onToggle = onChange;
}

- (void)toggleChanged:(UISwitch *)sender {
    if (self.onToggle) self.onToggle(sender.isOn);
}

@end

@interface GlowSettingsViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<NSArray<NSDictionary *> *> *sections;
@end

@implementation GlowSettingsViewController

- (instancetype)init {
    if ((self = [super init])) {
        self.modalPresentationStyle = UIModalPresentationPageSheet;
        if (@available(iOS 15.0, *)) {
            UISheetPresentationController *sheet = self.sheetPresentationController;
            sheet.detents = @[UISheetPresentationControllerDetent.largeDetent];
            sheet.prefersGrabberVisible = YES;
        }

        // Build sections matching Glow's UI structure
        self.sections = @[
            @[  // TRANG CHỦ
                @{@"key": @"removeAds", @"title": @"removeAds", @"subtitle": @"", @"value": @(s_removeAds)},
                @{@"key": @"removePYMK", @"title": @"removePYMK", @"subtitle": @"", @"value": @(s_removePYMK)},
                @{@"key": @"removeReelsCarousel", @"title": @"removeReelsCarousel", @"subtitle": @"", @"value": @(s_removeReelsCarousel)},
                @{@"key": @"confirmLike", @"title": @"confirmLike", @"subtitle": @"", @"value": @(s_confirmLike)},
                @{@"key": @"downloadVideo", @"title": @"downloadVideo", @"subtitle": @"downloadVideo.desc", @"value": @(s_downloadVideo)},
                @{@"key": @"removeSuggested", @"title": @"removeSuggested", @"subtitle": @"removeSuggested.desc", @"value": @(s_removeSuggested)},
            ],
            @[  // REELS
                @{@"key": @"downloadReels", @"title": @"downloadReels", @"subtitle": @"", @"value": @(s_downloadReels)},
                @{@"key": @"hideOverlay", @"title": @"hideOverlay", @"subtitle": @"", @"value": @(s_hideOverlay)},
                @{@"key": @"confirmReelsLike", @"title": @"confirmReelsLike", @"subtitle": @"", @"value": @(s_confirmReelsLike)},
                @{@"key": @"downloadLongPress", @"title": @"downloadLongPress", @"subtitle": @"downloadLongPress.desc", @"value": @(s_downloadLongPress)},
            ],
            @[  // STORIES
                @{@"key": @"downloadStory", @"title": @"downloadStory", @"subtitle": @"", @"value": @(s_downloadStory)},
                @{@"key": @"disableStorySeen", @"title": @"disableStorySeen", @"subtitle": @"", @"value": @(s_disableStorySeen)},
                @{@"key": @"disableAutoNext", @"title": @"disableAutoNext", @"subtitle": @"", @"value": @(s_disableAutoNext)},
                @{@"key": @"removeStoryPYMK", @"title": @"removeStoryPYMK", @"subtitle": @"", @"value": @(s_removeStoryPYMK)},
            ],
            @[  // TRÌNH TẢI VIDEO
                @{@"key": @"allFormats", @"title": @"allFormats", @"subtitle": @"", @"value": @(s_allFormats)},
            ],
            @[  // KHÁC
                @{@"key": @"notifyUpdates", @"title": @"notifyUpdates", @"subtitle": @"", @"value": @(s_notifyUpdates)},
                @{@"key": @"clearCacheOnLaunch", @"title": @"clearCacheOnLaunch", @"subtitle": @"", @"value": @(s_clearCacheOnLaunch)},
            ],
        ];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.title = GlowLoc(@"title");

    // X close button (top right) - matches Glow's design
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemClose
        target:self
        action:@selector(closeSettings)];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.backgroundColor = [UIColor systemGroupedBackgroundColor];
    [self.tableView registerClass:[GlowSwitchCell class] forCellReuseIdentifier:@"switch"];
    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

- (void)closeSettings {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.sections[section].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    NSArray *keys = @[@"section.home", @"section.reels", @"section.stories", @"section.downloader", @"section.other"];
    if (section >= (NSInteger)keys.count) return nil;
    return GlowLoc(keys[section]);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    GlowSwitchCell *cell = [tableView dequeueReusableCellWithIdentifier:@"switch" forIndexPath:indexPath];
    NSDictionary *row = self.sections[indexPath.section][indexPath.row];
    NSString *title = GlowLoc(row[@"title"]);
    NSString *subtitleKey = row[@"subtitle"];
    NSString *subtitle = subtitleKey.length > 0 ? GlowLoc(subtitleKey) : @"";
    BOOL value = [row[@"value"] boolValue];
    NSString *key = row[@"key"];

    [cell configureWithTitle:title subtitle:subtitle value:value onChange:^(BOOL newValue) {
        NSString *fullKey = [@"com.tommy.glow." stringByAppendingString:key];
        [[NSUserDefaults standardUserDefaults] setBool:newValue forKey:fullKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
        reloadPrefs();
        LOG("[settings] %s = %d\n", key.UTF8String, newValue);
    }];
    return cell;
}

@end

// Open settings - find root VC robustly
static void openGlowSettings(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            GlowSettingsViewController *vc = [[GlowSettingsViewController alloc] init];
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];

            UIViewController *target = nil;
            UIApplication *app = [UIApplication sharedApplication];

            // Try UIScene first
            for (UIScene *scene in [app connectedScenes]) {
                if ([scene isKindOfClass:[UIWindowScene class]]) {
                    UIWindowScene *ws = (UIWindowScene *)scene;
                    for (UIWindow *w in ws.windows) {
                        if (!w.rootViewController) continue;
                        // Find the topmost presented VC
                        UIViewController *cur = w.rootViewController;
                        while (cur.presentedViewController) {
                            cur = cur.presentedViewController;
                        }
                        if (cur) { target = cur; break; }
                    }
                    if (target) break;
                }
            }

            if (!target) {
                UIWindow *w = [app keyWindow];
                if (w) target = w.rootViewController;
            }

            if (target) {
                [target presentViewController:nav animated:YES completion:^{
                    LOG("[ui] settings presented on %s\n", class_getName(object_getClass(target)));
                }];
            } else {
                LOG("[ui] no root VC found - app.windows=%lu\n", (unsigned long)app.windows.count);
            }
        } @catch (NSException *e) {
            LOG("[ui] exc: %s\n", e.reason.UTF8String);
        }
    });
}

// Long press handler
@interface GlowLongPressHandler : NSObject
@end
@implementation GlowLongPressHandler
- (void)handleLongPress:(UILongPressGestureRecognizer *)gr {
    if (gr.state == UIGestureRecognizerStateBegan) {
        // Log topmost VC for class discovery
        UIViewController *topVC = nil;
        for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *ws = (UIWindowScene *)s;
                for (UIWindow *w in ws.windows) {
                    if (w.isKeyWindow && w.rootViewController) {
                        UIViewController *cur = w.rootViewController;
                        while (cur.presentedViewController) cur = cur.presentedViewController;
                        topVC = cur;
                        break;
                    }
                }
            }
        }
        if (topVC) {
            const char *cn = class_getName(object_getClass(topVC));
            LOG("[ui] long press on %s (topVC=%s)\n", class_getName(object_getClass(gr.view)), cn);
        } else {
            LOG("[ui] long press on %s (no topVC)\n", class_getName(object_getClass(gr.view)));
        }
        openGlowSettings();
    }
}
@end

static GlowLongPressHandler *g_longPressHandler = nil;
static NSMutableSet *g_viewsWithLongPress = nil;

// Add long press recognizer to a view (only once)
static void tryAddLongPressToView(UIView *v) {
    if (!v || !g_viewsWithLongPress) return;
    if ([g_viewsWithLongPress containsObject:[NSValue valueWithNonretainedObject:v]]) return;
    if (v.gestureRecognizers.count > 5) return;  // skip views with too many recognizers
    if (![v isUserInteractionEnabled]) return;
    if (v.frame.size.width < 100 || v.frame.size.height < 30) return;  // skip tiny views
    // Only add to scroll views, tab bars, or top-level views
    BOOL isTarget = [v isKindOfClass:[UIScrollView class]] ||
                    [v isKindOfClass:[UITabBar class]] ||
                    v.frame.size.height > 200;
    if (!isTarget) return;

    UILongPressGestureRecognizer *gr = [[UILongPressGestureRecognizer alloc]
        initWithTarget:g_longPressHandler
        action:@selector(handleLongPress:)];
    gr.minimumPressDuration = 0.6;
    gr.cancelsTouchesInView = NO;  // don't break other gestures
    [v addGestureRecognizer:gr];
    [g_viewsWithLongPress addObject:[NSValue valueWithNonretainedObject:v]];
    LOG("[ui] added long press to %s frame=(%.0f,%.0f,%.0f,%.0f)\n",
        class_getName(object_getClass(v)), v.frame.origin.x, v.frame.origin.y,
        v.frame.size.width, v.frame.size.height);
}

// Walk view hierarchy to find candidates
static void walkViewsForLongPress(UIView *v, int depth) {
    if (!v || depth > 4) return;
    tryAddLongPressToView(v);
    for (UIView *sub in v.subviews) {
        walkViewsForLongPress(sub, depth + 1);
    }
}

static void installLongPressOnCurrentUI(void) {
    if (!g_longPressHandler) {
        g_longPressHandler = [[GlowLongPressHandler alloc] init];
        g_viewsWithLongPress = [[NSMutableSet alloc] init];
    }
    UIApplication *app = [UIApplication sharedApplication];
    for (UIScene *scene in [app connectedScenes]) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            UIWindowScene *ws = (UIWindowScene *)scene;
            for (UIWindow *w in ws.windows) {
                walkViewsForLongPress(w, 0);
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// SECTION 3: Ad blocking (from v7) - hook FBMemNewsFeedEdge.node
// ═══════════════════════════════════════════════════════════════

static IMP orig_node = NULL;
static int node_blocked = 0;

static id hooked_node(id self, SEL _cmd) {
    id result = nil;
    if (orig_node) {
        typedef id (*FnType)(id, SEL);
        FnType fn = (FnType)(uintptr_t)orig_node;
        result = fn(self, _cmd);
    }
    @try {
        SEL catSel = sel_registerName("category");
        if ([self respondsToSelector:catSel]) {
            id cat = [self performSelector:catSel];
            if ([cat isKindOfClass:[NSString class]]) {
                NSString *cs = (NSString *)cat;
                if ([cs isEqualToString:@"SPONSORED"] ||
                    [cs isEqualToString:@"AD"] ||
                    [cs isEqualToString:@"IN_STREAM_AD"] ||
                    [cs isEqualToString:@"PROMOTION"]) {
                    node_blocked++;
                    if (node_blocked <= 3 || (node_blocked % 20) == 0) {
                        LOG("[ad/node] blocked SPONSORED edge (count=%d)\n", node_blocked);
                    }
                    return nil;
                }
            }
        }
    } @catch (...) {}
    return result;
}

// Walk to FBMemNewsFeedEdge
static id getMemEdge(id self, NSIndexPath *ip) {
    if (!self || !ip) return nil;
    @try {
        Class dsCls = object_getClass(self);
        Ivar tcdsIvar = class_getInstanceVariable(dsCls, "_transactionalComponentDataSource");
        if (!tcdsIvar) return nil;
        id tcds = object_getIvar(self, tcdsIvar);
        if (!tcds) return nil;
        Class tcdsCls = object_getClass(tcds);
        Ivar dsIvar = class_getInstanceVariable(tcdsCls, "_dataSource");
        if (!dsIvar) return nil;
        id ckds = object_getIvar(tcds, dsIvar);
        if (!ckds) return nil;
        Class ckdsCls = object_getClass(ckds);
        Ivar stateIvar = class_getInstanceVariable(ckdsCls, "_state");
        if (!stateIvar) return nil;
        id state = object_getIvar(ckds, stateIvar);
        if (!state) return nil;
        Class stateCls = object_getClass(state);
        Ivar secIvar = class_getInstanceVariable(stateCls, "_sections");
        if (!secIvar) return nil;
        id sections = object_getIvar(state, secIvar);
        if (![sections isKindOfClass:[NSArray class]]) return nil;
        NSArray *sa = (NSArray *)sections;
        if (ip.section < 0 || ip.section >= (NSInteger)sa.count) return nil;
        id section = sa[ip.section];
        if (![section isKindOfClass:[NSArray class]]) return nil;
        NSArray *items = (NSArray *)section;
        if (ip.row < 0 || ip.row >= (NSInteger)items.count) return nil;
        id item = items[ip.row];
        if (!item) return nil;
        Class itemCls = object_getClass(item);
        Ivar modelIvar = class_getInstanceVariable(itemCls, "_model");
        if (!modelIvar) return nil;
        id model = object_getIvar(item, modelIvar);
        if (!model) return nil;
        Class modelCls = object_getClass(model);
        Ivar modelIvar2 = class_getInstanceVariable(modelCls, "_model");
        if (!modelIvar2) return nil;
        id feedEdgeWrapper = object_getIvar(model, modelIvar2);
        if (!feedEdgeWrapper) return nil;
        Class edgeCls = object_getClass(feedEdgeWrapper);
        Ivar edgeIvar = class_getInstanceVariable(edgeCls, "_edge");
        if (!edgeIvar) return nil;
        return object_getIvar(feedEdgeWrapper, edgeIvar);
    } @catch (...) { return nil; }
}

static BOOL isAdEdge(id memEdge) {
    if (!memEdge) return NO;
    @try {
        // PYMK check (FBMemPeopleYouMayKnowEdge has 0 methods, only class check works)
        if (s_removePYMK) {
            Class pymkCls = objc_getClass("FBMemPeopleYouMayKnowEdge");
            if (pymkCls && [memEdge isKindOfClass:pymkCls]) {
                return YES;
            }
        }
        SEL catSel = sel_registerName("category");
        if ([memEdge respondsToSelector:catSel]) {
            id cat = [memEdge performSelector:catSel];
            if ([cat isKindOfClass:[NSString class]]) {
                NSString *cs = (NSString *)cat;
                if ([cs isEqualToString:@"SPONSORED"] ||
                    [cs isEqualToString:@"AD"] ||
                    [cs isEqualToString:@"IN_STREAM_AD"] ||
                    [cs isEqualToString:@"PROMOTION"]) {
                    return YES;
                }
            }
        }
    } @catch (...) {}
    return NO;
}

// ─── Category logger (v8.2 discovery) ───
// Logs every UNIQUE category string seen, with section index
// Helps discover PYMK, Suggested, etc. categories
static NSMutableSet *g_seenCategories = nil;
static void logCategoryIfNew(id memEdge, NSInteger section, NSInteger row) {
    if (!memEdge) return;
    if (!g_seenCategories) g_seenCategories = [[NSMutableSet alloc] init];
    @try {
        SEL catSel = sel_registerName("category");
        if ([memEdge respondsToSelector:catSel]) {
            id cat = [memEdge performSelector:catSel];
            if ([cat isKindOfClass:[NSString class]]) {
                NSString *cs = (NSString *)cat;
                NSString *key = [NSString stringWithFormat:@"%@|sec=%ld|row=%ld", cs, (long)section, (long)row];
                if (![g_seenCategories containsObject:key]) {
                    [g_seenCategories addObject:key];
                    LOG("[cat] sec=%ld row=%ld category=\"%s\"\n", (long)section, (long)row, cs.UTF8String);
                }
            }
        }
    } @catch (...) {}
}

// ─── Cell hiding (backup) ───
static IMP orig_cellForItem = NULL;
static int ad_hidden = 0;

static id hooked_cellForItem(id self, SEL _cmd, UICollectionView *cv, NSIndexPath *ip) {
    id result = nil;
    if (orig_cellForItem) {
        typedef id (*FnType)(id, SEL, id, id);
        FnType fn = (FnType)(uintptr_t)orig_cellForItem;
        result = fn(self, _cmd, (id)cv, (id)ip);
    }
    if (!result || !ip || ip.section <= 1) return result;
    @try {
        id memEdge = getMemEdge(self, ip);
        // Log all unique categories (v8.2 discovery)
        logCategoryIfNew(memEdge, ip.section, ip.row);
        if (memEdge && isAdEdge(memEdge)) {
            ad_hidden++;
            if ([result isKindOfClass:[UIView class]]) {
                UIView *v = (UIView *)result;
                v.hidden = YES;
                v.alpha = 0;
                v.backgroundColor = [UIColor clearColor];
                v.frame = CGRectZero;
                v.bounds = CGRectZero;
            }
            if (ad_hidden <= 3 || (ad_hidden % 20) == 0) {
                LOG("[ad/cell] hidden [%ld,%ld] total=%d\n", (long)ip.section, (long)ip.row, ad_hidden);
            }
        }
    } @catch (...) {}
    return result;
}

static IMP orig_willDisplay = NULL;
static void hooked_willDisplay(id self, SEL _cmd, UICollectionView *cv, UICollectionViewCell *cell, NSIndexPath *ip) {
    if (orig_willDisplay) {
        typedef void (*FnType)(id, SEL, id, id, id);
        FnType fn = (FnType)(uintptr_t)orig_willDisplay;
        fn(self, _cmd, (id)cv, (id)cell, (id)ip);
    }
    if (!cell || !ip || ip.section <= 1) return;
    UIView *v = [cell isKindOfClass:[UIView class]] ? (UIView *)cell : nil;
    if (!v) return;
    @try {
        id memEdge = getMemEdge(self, ip);
        if (memEdge && isAdEdge(memEdge)) {
            v.hidden = YES;
            v.alpha = 0;
            v.frame = CGRectZero;
            v.bounds = CGRectZero;
        }
    } @catch (...) {}
}

// ═══════════════════════════════════════════════════════════════
// SECTION 4: Story seen (from v7) - block 3 paths
// ═══════════════════════════════════════════════════════════════

static int seen_count = 0;
static IMP orig_seen1 = NULL, orig_seen2 = NULL, orig_seen3 = NULL;

static void noop_seen_1(id self, SEL _cmd, id a, id b) {
    seen_count++;
    if (seen_count <= 5 || (seen_count % 50) == 0) {
        LOG("[seen] blocked _sendSeenThreadIDsWithBucket (count=%d)\n", seen_count);
    }
}
static void noop_seen_2(id self, SEL _cmd, id a) {
    seen_count++;
    if (seen_count <= 5 || (seen_count % 50) == 0) {
        LOG("[seen] blocked _sendThreadIDsAsSeenInViewerSession (count=%d)\n", seen_count);
    }
}
static void noop_seen_3(id self, SEL _cmd, id a, id b, id c, BOOL d, id e, id f) {
    seen_count++;
    if (seen_count <= 5 || (seen_count % 50) == 0) {
        LOG("[seen] blocked markThreadsView (count=%d)\n", seen_count);
    }
}

// ═══════════════════════════════════════════════════════════════
// SECTION 4.5: v8.2 features (Hide Composer, PYMK, Download Story/Video)
// ═══════════════════════════════════════════════════════════════

// ─── Feature 1: Hide Composer (FBNewsFeedViewControllerConfiguration) ───
// We hook FBNewsFeedViewController viewDidLoad to walk to _configuration
// and force _shouldHideComposer = YES.
static IMP orig_newsFeed_viewDidLoad = NULL;
static int composer_hide_count = 0;

static void hooked_newsFeed_viewDidLoad(id self, SEL _cmd) {
    if (orig_newsFeed_viewDidLoad) {
        typedef void (*FnType)(id, SEL);
        FnType fn = (FnType)(uintptr_t)orig_newsFeed_viewDidLoad;
        fn(self, _cmd);
    }
    if (!s_hideComposer) return;
    @try {
        Class nfcCls = object_getClass(self);
        Ivar configIvar = class_getInstanceVariable(nfcCls, "_configuration");
        if (!configIvar) return;
        id config = object_getIvar(self, configIvar);
        if (!config) return;
        Class configCls = object_getClass(config);
        Ivar hideIvar = class_getInstanceVariable(configCls, "_shouldHideComposer");
        if (!hideIvar) return;
        // BOOL ivar — set to YES
        BOOL yes = YES;
        *(BOOL *)((uintptr_t)config + ivar_getOffset(hideIvar)) = yes;
        composer_hide_count++;
        LOG("[composer] hid (count=%d)\n", composer_hide_count);
    } @catch (...) {
        LOG("[composer] exc\n");
    }
}

// ─── Feature 2: PYMK hide (via isKindOfClass FBMemPeopleYouMayKnowEdge) ───
// Extend isAdEdge to also flag PYMK edges.
// FBMemPeopleYouMayKnowEdge has 0 methods (GraphQL stub only).
// Update isAdEdge to also check the class.

// ─── Feature 3: Download Story (button on FBSnacksMediaContainerView) ───
// Hook the NEW init signature: initWithThread:bucket:mediaViewDelegate:mediaViewGenerator:toolbox:shouldBlurMedia:
// ─── Feature 3: Download Story (LONG PRESS - matching Glow 1.3.1) ───
// Hook the NEW init signature: initWithThread:bucket:mediaViewDelegate:mediaViewGenerator:toolbox:shouldBlurMedia:
// Add a long-press recognizer to the view (not a button - that crashed).

@interface GlowToastView : UIView
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end
@implementation GlowToastView
- (instancetype)init {
    if ((self = [super initWithFrame:CGRectZero])) {
        self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.85];
        self.layer.cornerRadius = 20;
        self.alpha = 0;
        _label = [[UILabel alloc] init];
        _label.textColor = [UIColor whiteColor];
        _label.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        _label.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_label];
        _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        _spinner.color = [UIColor whiteColor];
        _spinner.translatesAutoresizingMaskIntoConstraints = NO;
        [_spinner startAnimating];
        [self addSubview:_spinner];
        [NSLayoutConstraint activateConstraints:@[
            [_spinner.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14],
            [_spinner.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_spinner.widthAnchor constraintEqualToConstant:18],
            [_spinner.heightAnchor constraintEqualToConstant:18],
            [_label.leadingAnchor constraintEqualToAnchor:_spinner.trailingAnchor constant:10],
            [_label.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14],
            [_label.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [self.heightAnchor constraintEqualToConstant:40],
        ]];
    }
    return self;
}
- (void)showInWindow:(UIWindow *)window text:(NSString *)text {
    if (!window) return;
    self.label.text = text;
    [window addSubview:self];
    self.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [self.centerXAnchor constraintEqualToAnchor:window.centerXAnchor],
        [self.topAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.topAnchor constant:8],
    ]];
    [UIView animateWithDuration:0.25 animations:^{ self.alpha = 1.0; }];
}
- (void)updateText:(NSString *)text {
    self.label.text = text;
}
- (void)dismissAfter:(NSTimeInterval)delay success:(BOOL)success {
    [UIView animateWithDuration:0.25 delay:delay options:0 animations:^{
        self.alpha = 0;
    } completion:^(BOOL finished) {
        [self.spinner stopAnimating];
        [self removeFromSuperview];
    }];
}
@end

@interface GlowStoryDownloadHandler : NSObject
@property (nonatomic, strong) GlowToastView *toast;
@end
@implementation GlowStoryDownloadHandler

// Find a playable item (URL) by walking FBSnacksMediaContainerView -> mediaView
// Returns NSURL or nil. Sets outIsVideo YES/NO.
- (NSURL *)findMediaURLInContainer:(UIView *)container isVideo:(BOOL *)outIsVideo {
    if (outIsVideo) *outIsVideo = NO;
    if (!container) return nil;
    @try {
        Ivar mvIvar = class_getInstanceVariable(object_getClass(container), "_mediaView");
        id mediaView = mvIvar ? object_getIvar(container, mvIvar) : nil;
        if (!mediaView) {
            LOG("[dl/story] mediaView nil\n");
            return nil;
        }

        // Try FBSnacksNewVideoView
        Class videoCls = NSClassFromString(@"FBSnacksNewVideoView");
        if (videoCls && [mediaView isKindOfClass:videoCls]) {
            if (outIsVideo) *outIsVideo = YES;
            SEL mgrSel = sel_registerName("manager");
            id mgr = [mediaView respondsToSelector:mgrSel] ? [mediaView performSelector:mgrSel] : nil;
            if (!mgr) { LOG("[dl/story] manager nil\n"); return nil; }
            SEL curSel = sel_registerName("currentVideoPlaybackItem");
            id item = [mgr respondsToSelector:curSel] ? [mgr performSelector:curSel] : nil;
            if (!item) { LOG("[dl/story] no playback item\n"); return nil; }
            SEL hdSel = sel_registerName("HDPlaybackURL");
            NSURL *url = [item respondsToSelector:hdSel] ? [item performSelector:hdSel] : nil;
            if (!url) {
                SEL sdSel = sel_registerName("SDPlaybackURL");
                url = [item respondsToSelector:sdSel] ? [item performSelector:sdSel] : nil;
            }
            if (url) LOG("[dl/story] video URL: %s\n", [[url absoluteString] UTF8String]);
            return url;
        }

        // Try FBSnacksPhotoView
        Class photoCls = NSClassFromString(@"FBSnacksPhotoView");
        if (photoCls && [mediaView isKindOfClass:photoCls]) {
            Ivar swpvIvar = class_getInstanceVariable(object_getClass(mediaView), "_photoView");
            id swpv = swpvIvar ? object_getIvar(mediaView, swpvIvar) : nil;
            if (!swpv) { LOG("[dl/story] FBSnacksWebPhotoView nil\n"); return nil; }
            Class webPhotoCls = NSClassFromString(@"FBSnacksWebPhotoView");
            if (![swpv isKindOfClass:webPhotoCls]) {
                LOG("[dl/story] not FBSnacksWebPhotoView: %s\n", class_getName(object_getClass(swpv)));
                return nil;
            }
            Ivar wpvIvar = class_getInstanceVariable(object_getClass(swpv), "_photoView");
            id wpv = wpvIvar ? object_getIvar(swpv, wpvIvar) : nil;
            if (!wpv) { LOG("[dl/story] FBWebPhotoView nil\n"); return nil; }
            SEL photoSel = sel_registerName("photo");
            id photo = [wpv respondsToSelector:photoSel] ? [wpv performSelector:photoSel] : nil;
            if (!photo) { LOG("[dl/story] photo nil\n"); return nil; }
            @try {
                id imageSpecifier = [photo valueForKey:@"imageSpecifier"];
                if (!imageSpecifier) { LOG("[dl/story] imageSpecifier nil\n"); return nil; }
                Class netSpecCls = NSClassFromString(@"FBWebImageNetworkSpecifier");
                Class memSpecCls = NSClassFromString(@"FBWebImageMemorySpecifier");
                if (netSpecCls && [imageSpecifier isKindOfClass:netSpecCls]) {
                    SEL urlsSel = sel_registerName("allInfoURLsSortedByDescImageFlag");
                    NSArray *urls = [imageSpecifier respondsToSelector:urlsSel] ? [imageSpecifier performSelector:urlsSel] : nil;
                    if ([urls isKindOfClass:[NSArray class]] && urls.count > 0) {
                        NSURL *url = urls[0];
                        if ([url isKindOfClass:[NSURL class]]) {
                            LOG("[dl/story] photo URL: %s\n", [[url absoluteString] UTF8String]);
                            return url;
                        }
                    }
                } else if (memSpecCls && [imageSpecifier isKindOfClass:memSpecCls]) {
                    SEL imgSel = sel_registerName("image");
                    UIImage *img = [imageSpecifier respondsToSelector:imgSel] ? [imageSpecifier performSelector:imgSel] : nil;
                    if (img) {
                        // Return special sentinel via global var
                        LOG("[dl/story] photo is in-memory\n");
                        // Save directly
                        UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil);
                        return nil;  // tell caller to skip download
                    }
                }
            } @catch (NSException *e) {
                LOG("[dl/story] photo exc: %s\n", e.reason.UTF8String);
            }
            return nil;
        }
        LOG("[dl/story] unknown mediaView class: %s\n", class_getName(object_getClass(mediaView)));
    } @catch (NSException *e) {
        LOG("[dl/story] exc: %s\n", e.reason.UTF8String);
    }
    return nil;
}

- (void)onStoryLongPress:(UILongPressGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateBegan) return;
    if (!s_downloadStory) return;
    @try {
        UIView *container = gr.view;
        if (!container) return;
        BOOL isVideo = NO;
        NSURL *url = [self findMediaURLInContainer:container isVideo:&isVideo];
        if (!url) { LOG("[dl/story] no URL found (maybe already saved)\n"); return; }

        // Show action sheet (like Glow 1.3.1)
        UIWindow *win = nil;
        for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *ws = (UIWindowScene *)s;
                for (UIWindow *w in ws.windows) { if (w.isKeyWindow) { win = w; break; } }
                if (win) break;
            }
        }
        if (!win) win = [UIApplication sharedApplication].keyWindow;
        UIViewController *top = win.rootViewController;
        while (top.presentedViewController) top = top.presentedViewController;
        if (!top) { LOG("[dl/story] no top VC\n"); return; }

        NSString *title = isVideo ? @"Tải video story?" : @"Tải ảnh story?";
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                       message:nil
                                                                preferredStyle:UIAlertControllerStyleActionSheet];
        [alert addAction:[UIAlertAction actionWithTitle:isVideo ? @"Tải HD" : @"Tải ảnh" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [self downloadURL:url toFileName:[NSString stringWithFormat:@"story_%@_%lld.%@",
                                              isVideo ? @"video" : @"photo",
                                              (long long)[[NSDate date] timeIntervalSince1970],
                                              isVideo ? @"mp4" : @"jpg"]];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
        if (alert.popoverPresentationController) {
            alert.popoverPresentationController.sourceView = container;
            alert.popoverPresentationController.sourceRect = container.bounds;
        }
        [top presentViewController:alert animated:YES completion:nil];
    } @catch (NSException *e) {
        LOG("[dl/story] LP exc: %s\n", e.reason.UTF8String);
    }
}

- (void)showProgressAlert {
    UIWindow *win = nil;
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]]) {
            UIWindowScene *ws = (UIWindowScene *)s;
            for (UIWindow *w in ws.windows) { if (w.isKeyWindow) { win = w; break; } }
            if (win) break;
        }
    }
    if (!win) win = [UIApplication sharedApplication].keyWindow;
    if (!win) return;
    // Non-modal toast at top of screen - doesn't block user
    self.toast = [[GlowToastView alloc] init];
    [self.toast showInWindow:win text:@"Đang tải... 0%"];
}

- (void)updateProgress:(double)fraction {
    if (!self.toast) return;
    int pct = (int)(fraction * 100);
    [self.toast updateText:[NSString stringWithFormat:@"Đang tải... %d%%", pct]];
}

- (void)dismissProgressWithTitle:(NSString *)title message:(NSString *)msg success:(BOOL)ok {
    // Haptic feedback
    UINotificationFeedbackGenerator *gen = [[UINotificationFeedbackGenerator alloc] init];
    [gen prepare];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.1 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        [gen notificationOccurred:ok ? UINotificationFeedbackTypeSuccess : UINotificationFeedbackTypeError];
    });
    if (self.toast) {
        // Show final state in same toast, then auto-dismiss
        [self.toast updateText:ok ? [NSString stringWithFormat:@"✓ %@", title] : [NSString stringWithFormat:@"✗ %@", title]];
        [self.toast.spinner stopAnimating];
        [self.toast dismissAfter:2.0 success:ok];
        self.toast = nil;
    }
}

- (void)downloadURL:(NSURL *)url toFileName:(NSString *)name {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self showProgressAlert];
    });
    NSURLRequest *req = [NSURLRequest requestWithURL:url];
    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];
    NSURLSessionDownloadTask *task = [session downloadTaskWithRequest:req completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        if (error || !location) {
            LOG("[dl/story] download err: %s\n", error ? [[error localizedDescription] UTF8String] : "nil");
            dispatch_async(dispatch_get_main_queue(), ^{
                [self updateProgress:1.0];
                [self dismissProgressWithTitle:@"Lỗi" message:@"Không thể tải về" success:NO];
            });
            return;
        }
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
        [[NSFileManager defaultManager] moveItemAtURL:location toURL:[NSURL fileURLWithPath:path] error:nil];
        LOG("[dl/story] saved to %s\n", [path UTF8String]);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self updateProgress:1.0];
            UIImage *img = [UIImage imageWithContentsOfFile:path];
            if (img) {
                UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil);
                LOG("[dl/story] saved image to Photos\n");
                [self dismissProgressWithTitle:@"Đã lưu ảnh" message:@"Đã lưu vào Album Ảnh" success:YES];
            } else {
                UISaveVideoAtPathToSavedPhotosAlbum(path, nil, nil, NULL);
                LOG("[dl/story] saved video to Photos\n");
                [self dismissProgressWithTitle:@"Đã lưu video" message:@"Đã lưu vào Album Ảnh" success:YES];
            }
        });
    }];
    // Observe progress
    [task resume];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        while (task.state == NSURLSessionTaskStateRunning) {
            int64_t total = task.countOfBytesExpectedToReceive;
            int64_t done = task.countOfBytesReceived;
            if (total > 0) {
                double frac = (double)done / (double)total;
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self updateProgress:frac];
                });
            }
            [NSThread sleepForTimeInterval:0.2];
        }
    });
}

@end

static GlowStoryDownloadHandler *g_storyHandler = nil;

static IMP orig_storyContainer_init = NULL;
static id hooked_storyContainer_init(id self, SEL _cmd, id thread, id bucket, id mediaViewDelegate, id mediaViewGenerator, id toolbox, BOOL shouldBlurMedia) {
    id result = nil;
    if (orig_storyContainer_init) {
        typedef id (*FnType)(id, SEL, id, id, id, id, id, BOOL);
        FnType fn = (FnType)(uintptr_t)orig_storyContainer_init;
        result = fn(self, _cmd, thread, bucket, mediaViewDelegate, mediaViewGenerator, toolbox, shouldBlurMedia);
    } else {
        return result;
    }
    // NOTE: Do NOT add gesture recognizer here - view is not laid out yet.
    // Instead, hook didMoveToWindow below to add it when view is in window.
    return result;
}

// Track which story containers already have long press
static NSMutableSet *g_storyContainersWithLongPress = nil;

// Hook didMoveToWindow: add long press when view enters window
static IMP orig_storyContainer_didMoveToWindow = NULL;
static void hooked_storyContainer_didMoveToWindow(id self, SEL _cmd, UIWindow *window) {
    if (orig_storyContainer_didMoveToWindow) {
        typedef void (*FnType)(id, SEL, id);
        FnType fn = (FnType)(uintptr_t)orig_storyContainer_didMoveToWindow;
        fn(self, _cmd, (id)window);
    }
    if (!s_downloadStory) return;
    if (!window) return;  // removing from window
    if (!g_storyContainersWithLongPress) g_storyContainersWithLongPress = [[NSMutableSet alloc] init];
    @try {
        if ([g_storyContainersWithLongPress containsObject:[NSValue valueWithNonretainedObject:self]]) return;
        if (!g_storyHandler) g_storyHandler = [[GlowStoryDownloadHandler alloc] init];
        UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
            initWithTarget:g_storyHandler
            action:@selector(onStoryLongPress:)];
        lp.minimumPressDuration = 0.5;
        lp.cancelsTouchesInView = NO;
        [self addGestureRecognizer:lp];
        [g_storyContainersWithLongPress addObject:[NSValue valueWithNonretainedObject:self]];
        LOG("[dl/story] added long press to container\n");
    } @catch (NSException *e) {
        LOG("[dl/story] didMoveToWindow exc: %s\n", e.reason.UTF8String);
    }
}

// ─── Feature 4: Download Video (long press) ───
// Hook FBVideoOverlayPluginComponentBackgroundView.didLongPress:
// Walk view hierarchy to find VideoContainerView, get current playback item.
@interface GlowVideoDownloadHandler : NSObject
- (void)showToast:(NSString *)msg;
@end
@implementation GlowVideoDownloadHandler

// v8.2.34: Helper - present MODAL alert (not action sheet) for quality choice.
// UIAlertControllerStyleAlert is more reliable than action sheet in Reels
// fullscreen context where action sheet gets dismissed by Reels gestures.
// For newsfeed long press, used as backup if UIMenu doesn't work.
- (void)presentQualityActionSheetHD:(NSURL *)hd
                                  sd:(NSURL *)sd
                          sourceView:(UIView *)srcView {
    UIWindow *win = nil;
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]]) {
            for (UIWindow *w in ((UIWindowScene *)s).windows) {
                if (w.isKeyWindow) { win = w; break; }
            }
        }
        if (win) break;
    }
    UIViewController *top = nil;
    if (win) {
        top = win.rootViewController;
        while (top.presentedViewController) top = top.presentedViewController;
    }
    if (!top) {
        // Fallback: download HD if available, else SD
        if (hd) [self downloadVideoURL:hd quality:@"hd"];
        else if (sd) [self downloadVideoURL:sd quality:@"sd"];
        return;
    }
    // v8.2.34: Use UIAlertControllerStyleAlert (modal) instead of action sheet
    // Modal alerts are more visible and harder to dismiss accidentally
    NSMutableString *msg = [NSMutableString string];
    if (hd) [msg appendString:@"HD = 720p\n"];
    if (sd) [msg appendString:@"SD = 360p"];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"📥 Tải video"
                                                                   message:msg
                                                            preferredStyle:UIAlertControllerStyleAlert];
    if (hd) {
        [alert addAction:[UIAlertAction actionWithTitle:@"📥 Tải HD (720p)"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *a) {
            [self downloadVideoURL:hd quality:@"HD"];
        }]];
    }
    if (sd) {
        [alert addAction:[UIAlertAction actionWithTitle:@"📥 Tải SD (360p)"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *a) {
            [self downloadVideoURL:sd quality:@"SD"];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"Hủy"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [top presentViewController:alert animated:YES completion:nil];
}

// Reels-specific: long press on Reel video view
// v8.2.33: Show action sheet (HD/SD/Cancel) instead of auto-downloading both
- (void)onReelLongPress:(UILongPressGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateBegan) return;
    if (!s_downloadVideo) return;
    @try {
        // Walk up the view hierarchy looking for currentVideoPlaybackItem
        SEL curSel = sel_registerName("currentVideoPlaybackItem");
        id item = [self findObjectRespondingTo:curSel startingAt:gr.view];
        if (!item) {
            LOG("[dl/reel] no playback item in hierarchy\n");
            return;
        }
        SEL hdSel = sel_registerName("HDPlaybackURL");
        SEL sdSel = sel_registerName("SDPlaybackURL");
        NSURL *hd = [item respondsToSelector:hdSel] ? [item performSelector:hdSel] : nil;
        NSURL *sd = [item respondsToSelector:sdSel] ? [item performSelector:sdSel] : nil;
        if (!hd && !sd) {
            LOG("[dl/reel] item has no URLs\n");
            return;
        }
        LOG("[dl/reel] LP: action sheet HD=%d SD=%d\n", hd != nil, sd != nil);
        [self presentQualityActionSheetHD:hd sd:sd sourceView:gr.view];
    } @catch (NSException *e) {
        LOG("[dl/reel] exc: %s\n", e.reason.UTF8String);
    }
}

// v8.2.33: Download with proper completion callback.
// On success: save to Photos, show "Đã lưu" toast, success haptic.
// On failure: show "Lỗi tải" toast, error haptic.
// Use quality label in toast so user knows which quality was saved.
- (void)downloadVideoURL:(NSURL *)url quality:(NSString *)q {
    if (!url) return;
    NSString *name = [NSString stringWithFormat:@"video_%@_%lld.mp4", q, (long long)[[NSDate date] timeIntervalSince1970]];
    NSURLRequest *req = [NSURLRequest requestWithURL:url];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
    NSURLSessionDownloadTask *task = [session downloadTaskWithRequest:req completionHandler:^(NSURL *loc, NSURLResponse *resp, NSError *err) {
        if (err || !loc) {
            LOG("[dl/video] err: %s\n", err ? [[err localizedDescription] UTF8String] : "nil");
            dispatch_async(dispatch_get_main_queue(), ^{
                [self showToast:[NSString stringWithFormat:@"❌ Lỗi tải %@", q]];
                UINotificationFeedbackGenerator *gen = [[UINotificationFeedbackGenerator alloc] init];
                [gen notificationOccurred:UINotificationFeedbackTypeError];
            });
            return;
        }
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
        [[NSFileManager defaultManager] moveItemAtURL:loc toURL:[NSURL fileURLWithPath:path] error:nil];
        LOG("[dl/video] saved to %s\n", [path UTF8String]);
        dispatch_async(dispatch_get_main_queue(), ^{
            UISaveVideoAtPathToSavedPhotosAlbum(path, nil, nil, NULL);
            [self showToast:[NSString stringWithFormat:@"✅ Đã lưu %@ vào Photos", q]];
            LOG("[dl/video] saved video to Photos\n");
            UINotificationFeedbackGenerator *gen = [[UINotificationFeedbackGenerator alloc] init];
            [gen notificationOccurred:UINotificationFeedbackTypeSuccess];
        });
    }];
    [task resume];
}

// Helper: search up the view hierarchy for an object that responds to selector
// Returns the object or nil. Logs the class if found.
- (id)findObjectRespondingTo:(SEL)sel startingAt:(UIView *)start {
    UIView *v = start;
    int depth = 0;
    while (v && depth < 12) {
        // Check self
        @try {
            if ([v respondsToSelector:sel]) {
                id result = [v performSelector:sel];
                if (result) {
                    LOG("[dl/video] found at depth %d: %s\n", depth, class_getName(object_getClass(v)));
                    return result;
                }
            }
        } @catch (...) {}
        // Check KVC for controller
        if (sel == @selector(currentVideoPlaybackItem) || sel == sel_registerName("currentVideoPlaybackItem")) {
            @try {
                id controller = [v valueForKey:@"controller"];
                if (controller && [controller respondsToSelector:sel]) {
                    id result = [controller performSelector:sel];
                    if (result) {
                        LOG("[dl/video] found via controller at depth %d: %s\n", depth, class_getName(object_getClass(v)));
                        return result;
                    }
                }
            } @catch (...) {}
            // Try manager ivar
            Ivar mgrIvar = class_getInstanceVariable(object_getClass(v), "_manager");
            if (mgrIvar) {
                @try {
                    id mgr = object_getIvar(v, mgrIvar);
                    if (mgr && [mgr respondsToSelector:sel]) {
                        id result = [mgr performSelector:sel];
                        if (result) {
                            LOG("[dl/video] found via _manager at depth %d: %s\n", depth, class_getName(object_getClass(v)));
                            return result;
                        }
                    }
                } @catch (...) {}
            }
        }
        v = v.superview;
        depth++;
    }
    return nil;
}

- (void)onLongPress:(UILongPressGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateBegan) return;
    if (!s_downloadVideo) return;
    @try {
        UIView *v = gr.view;
        SEL curSel = sel_registerName("currentVideoPlaybackItem");
        // Walk the view hierarchy looking for currentVideoPlaybackItem
        id item = [self findObjectRespondingTo:curSel startingAt:v];
        if (!item) {
            LOG("[dl/video] no current playback item in hierarchy\n");
            return;
        }
        SEL hdSel = sel_registerName("HDPlaybackURL");
        SEL sdSel = sel_registerName("SDPlaybackURL");
        NSURL *hd = [item respondsToSelector:hdSel] ? [item performSelector:hdSel] : nil;
        NSURL *sd = [item respondsToSelector:sdSel] ? [item performSelector:sdSel] : nil;
        if (!hd && !sd) {
            LOG("[dl/video] item has no URLs\n");
            return;
        }
        // Show action sheet to pick quality (matches Glow 1.3.1)
        UIWindow *win = nil;
        for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *ws = (UIWindowScene *)s;
                for (UIWindow *w in ws.windows) { if (w.isKeyWindow) { win = w; break; } }
                if (win) break;
            }
        }
        if (!win) win = [UIApplication sharedApplication].keyWindow;
        UIViewController *top = win.rootViewController;
        while (top.presentedViewController) top = top.presentedViewController;
        if (!top) {
            // Just download both if no UI
            if (hd) [self downloadVideoURL:hd quality:@"hd"];
            if (sd) [self downloadVideoURL:sd quality:@"sd"];
            return;
        }
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Tải video?" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
        if (hd) {
            [alert addAction:[UIAlertAction actionWithTitle:@"Tải HD" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
                [self downloadVideoURL:hd quality:@"hd"];
            }]];
        }
        if (sd) {
            [alert addAction:[UIAlertAction actionWithTitle:@"Tải SD" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
                [self downloadVideoURL:sd quality:@"sd"];
            }]];
        }
        [alert addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
        if (alert.popoverPresentationController) {
            alert.popoverPresentationController.sourceView = v;
            alert.popoverPresentationController.sourceRect = v.bounds;
        }
        [top presentViewController:alert animated:YES completion:nil];
    } @catch (NSException *e) {
        LOG("[dl/video] exc: %s\n", e.reason.UTF8String);
    }
}

@end

static GlowVideoDownloadHandler *g_videoHandler = nil;

// v8.2.28: Cache the last Reel video URLs (HD/SD). When FBVideoPlaybackItem's
// HDPlaybackURL/SDPlaybackURL getter is called (which FB does to play the
// video), we capture the URL into globals. On tap, use the cached URLs.
// This is the most reliable way to get the URL.
static NSURL *g_cachedHDURL = nil;
static NSURL *g_cachedSDURL = nil;
static NSDate *g_cachedAt = nil;
static IMP orig_HDPlaybackURL = NULL;
static IMP orig_SDPlaybackURL = NULL;

// v8.2.32: Glow-style class enumeration + setVideoItem: hook.
// Cache mapping VC_instance -> {HD, SD, item, time}.
// Key: NSValue (non-retained pointer to VC).
// Value: NSDictionary with @"HD"/@"SD" (NSURL* or NSNull), @"item" (FBVideoPlaybackItem),
//        @"at" (NSDate).
// This solves the "wrong Reel" problem: each VC has its OWN URL.
static NSMutableDictionary *g_vcToURLDict = nil;
static int g_glowStyleInstalled = 0;

// v8.2.34: didLongPress: hook for NEWSFEED video long press.
// The class name "FBVideoOverlayPluginComponentBackgroundView" was REMOVED
// in FB 560.x. We use runtime enumeration: find ALL FB classes that
// respond to didLongPress:, hook them all.
// When the hook fires, check if the long-pressed view is a video context
// (has AVPlayer or currentVideoPlaybackItem in hierarchy). If yes,
// show action sheet for HD/SD download.
static IMP orig_didLongPress_newsfeed = NULL;
static void hooked_didLongPress_newsfeed(id self, SEL _cmd, id arg) {
    // Always call original first (don't break FB's normal long press)
    if (orig_didLongPress_newsfeed) {
        typedef void (*FnType)(id, SEL, id);
        FnType fn = (FnType)(uintptr_t)orig_didLongPress_newsfeed;
        fn(self, _cmd, arg);
    }
    @try {
        // Check if the long-pressed view is a video view
        // (has AVPlayer or currentVideoPlaybackItem in hierarchy)
        UIView *view = nil;
        if ([self isKindOfClass:[UIView class]]) {
            view = (UIView *)self;
        } else if ([arg isKindOfClass:[UIGestureRecognizer class]]) {
            view = [(UIGestureRecognizer *)arg view];
        }
        if (!view) {
            LOG("[dl/news] long press but no view\n");
            return;
        }
        // Walk up to find a VC with currentVideoPlaybackItem
        UIView *v = view;
        int depth = 0;
        SEL curItemSel = sel_registerName("currentVideoPlaybackItem");
        while (v && depth < 8) {
            if ([v respondsToSelector:curItemSel]) {
                id item = [v performSelector:curItemSel];
                if (item) {
                    SEL hdSel = sel_registerName("HDPlaybackURL");
                    SEL sdSel = sel_registerName("SDPlaybackURL");
                    NSURL *hd = [item respondsToSelector:hdSel] ? [item performSelector:hdSel] : nil;
                    NSURL *sd = [item respondsToSelector:sdSel] ? [item performSelector:sdSel] : nil;
                    if (hd || sd) {
                        LOG("[dl/news] long press on video: HD=%d SD=%d class=%s\n",
                            hd != nil, sd != nil, class_getName(object_getClass(self)));
                        if (!g_videoHandler) g_videoHandler = [[GlowVideoDownloadHandler alloc] init];
                        [g_videoHandler presentQualityActionSheetHD:hd sd:sd sourceView:view];
                    }
                    return;
                }
            }
            v = v.superview;
            depth++;
        }
    } @catch (NSException *e) {
        LOG("[dl/news] exc: %s\n", e.reason.UTF8String);
    }
}

// v8.2.32: setVideoItem: hook implementation. Called when FB sets a new
// video item on the Reels player VC. We capture the URL here because this
// is the EXACT moment when player switches to a new Reel.
static IMP orig_setVideoItem = NULL;
static void hooked_setVideoItem(id self, SEL _cmd, id newItem) {
    if (orig_setVideoItem) {
        typedef void (*FnType)(id, SEL, id);
        FnType fn = (FnType)(uintptr_t)orig_setVideoItem;
        fn(self, _cmd, newItem);
    }
    @try {
        if (!self || !newItem) return;
        if (!g_vcToURLDict) g_vcToURLDict = [[NSMutableDictionary alloc] init];
        NSValue *key = [NSValue valueWithNonretainedObject:self];
        // Read HD/SD from newItem
        NSURL *hd = nil, *sd = nil;
        SEL hdSel = sel_registerName("HDPlaybackURL");
        SEL sdSel = sel_registerName("SDPlaybackURL");
        if ([newItem respondsToSelector:hdSel]) {
            hd = [newItem performSelector:hdSel];
        }
        if ([newItem respondsToSelector:sdSel]) {
            sd = [newItem performSelector:sdSel];
        }
        NSMutableDictionary *entry = [NSMutableDictionary dictionary];
        entry[@"HD"] = hd ?: [NSNull null];
        entry[@"SD"] = sd ?: [NSNull null];
        entry[@"item"] = newItem;
        entry[@"at"] = [NSDate date];
        g_vcToURLDict[key] = entry;
        LOG("[dl/reel] setVideoItem: VC=%s item=%s HD=%s SD=%s\n",
            class_getName(object_getClass(self)),
            class_getName(object_getClass(newItem)),
            hd ? "YES" : "NO",
            sd ? "YES" : "NO");
    } @catch (NSException *e) {
        LOG("[dl/reel] setVideoItem exc: %s\n", e.reason.UTF8String);
    }
}

// v8.2.32: currentVideoPlaybackItem GETTER hook. Some FB versions use
// KVO on this property to detect Reel changes. Capturing the URL when
// this getter is called is also reliable (FB reads it to update UI).
static IMP orig_currentVideoPlaybackItem = NULL;
static id hooked_currentVideoPlaybackItem(id self, SEL _cmd) {
    id item = nil;
    if (orig_currentVideoPlaybackItem) {
        typedef id (*FnType)(id, SEL);
        item = ((FnType)orig_currentVideoPlaybackItem)(self, _cmd);
    }
    @try {
        if (!self || !item) return item;
        if (!g_vcToURLDict) g_vcToURLDict = [[NSMutableDictionary alloc] init];
        // Don't overwrite setVideoItem's cache (which is more reliable)
        NSValue *key = [NSValue valueWithNonretainedObject:self];
        if (g_vcToURLDict[key]) return item;  // already cached
        NSURL *hd = nil, *sd = nil;
        SEL hdSel = sel_registerName("HDPlaybackURL");
        SEL sdSel = sel_registerName("SDPlaybackURL");
        if ([item respondsToSelector:hdSel]) hd = [item performSelector:hdSel];
        if ([item respondsToSelector:sdSel]) sd = [item performSelector:sdSel];
        NSMutableDictionary *entry = [NSMutableDictionary dictionary];
        entry[@"HD"] = hd ?: [NSNull null];
        entry[@"SD"] = sd ?: [NSNull null];
        entry[@"item"] = item;
        entry[@"at"] = [NSDate date];
        g_vcToURLDict[key] = entry;
        LOG("[dl/reel] currentVideoPlaybackItem: VC=%s item=%s\n",
            class_getName(object_getClass(self)),
            class_getName(object_getClass(item)));
    } @catch (NSException *e) {
        LOG("[dl/reel] currentVideoPlaybackItem exc: %s\n", e.reason.UTF8String);
    }
    return item;
}

// v8.2.32: installGlowStyleReelsHook - enumerate FB classes, find those
// that have setVideoItem: and currentVideoPlaybackItem, swizzle them.
// Called from installHooks() (deferred init, after FB is loaded).
void installGlowStyleReelsHook(void) {
    if (g_glowStyleInstalled) return;
    @try {
        int count = objc_getClassList(NULL, 0);
        if (count <= 0) {
            LOG("[dl/reel] objc_getClassList returned %d\n", count);
            return;
        }
        Class *classes = (__unsafe_unretained Class *)malloc(sizeof(Class) * count);
        objc_getClassList(classes, count);

        int setVideoItemHooked = 0;
        int cvpiHooked = 0;
        int didLongPressHooked = 0;
        SEL setSel = sel_registerName("setVideoItem:");
        SEL getSel = sel_registerName("currentVideoPlaybackItem");
        SEL lpSel = sel_registerName("didLongPress:");
        for (int i = 0; i < count; i++) {
            Class cls = classes[i];
            if (!cls) continue;
            const char *name = class_getName(cls);
            if (!name) continue;
            // Only FB classes
            if (strncmp(name, "FB", 2) != 0) continue;

            // Hook setVideoItem: setter
            if (class_respondsToSelector(cls, setSel)) {
                Method m = class_getInstanceMethod(cls, setSel);
                if (m) {
                    // If we haven't hooked any setVideoItem: yet, save the original
                    if (!orig_setVideoItem) {
                        orig_setVideoItem = method_getImplementation(m);
                    }
                    // Always replace (the original is the same across all classes)
                    method_setImplementation(m, (IMP)hooked_setVideoItem);
                    setVideoItemHooked++;
                }
            }

            // Hook currentVideoPlaybackItem getter
            if (class_respondsToSelector(cls, getSel)) {
                Method m = class_getInstanceMethod(cls, getSel);
                if (m) {
                    if (!orig_currentVideoPlaybackItem) {
                        orig_currentVideoPlaybackItem = method_getImplementation(m);
                    }
                    method_setImplementation(m, (IMP)hooked_currentVideoPlaybackItem);
                    cvpiHooked++;
                }
            }

            // v8.2.34: Hook didLongPress: for NEWSFEED video long press
            // Skip obvious wrong classes (BugReport etc.)
            if (class_respondsToSelector(cls, lpSel)) {
                // Skip if it's a known non-video class
                if (strstr(name, "BugReport") != NULL) continue;
                if (strstr(name, "NavigationCoordinator") != NULL) continue;
                Method m = class_getInstanceMethod(cls, lpSel);
                if (m) {
                    if (!orig_didLongPress_newsfeed) {
                        orig_didLongPress_newsfeed = method_getImplementation(m);
                    }
                    method_setImplementation(m, (IMP)hooked_didLongPress_newsfeed);
                    didLongPressHooked++;
                    LOG("[dl/news] hooked didLongPress: on %s\n", name);
                }
            }
        }
        free(classes);
        g_glowStyleInstalled = 1;
        LOG("[dl/reel] Glow-style hooks installed: setVideoItem:=%d currentVideoPlaybackItem=%d didLongPress:=%d\n",
            setVideoItemHooked, cvpiHooked, didLongPressHooked);
    } @catch (NSException *e) {
        LOG("[dl/reel] installGlowStyleReelsHook exc: %s\n", e.reason.UTF8String);
    } @catch (...) {
        LOG("[dl/reel] installGlowStyleReelsHook exc(c++)\n");
    }
}

// v8.2.29: Per-sidebar URL cache. Key = sidebar instance, Value = NSDictionary
// with HD/SD URLs. Solves:
// - "download next Reel": URL was global, didn't change when user scrolled
// - "download from story": URL was global, captured from wrong context
// - "duplicate download": global cache reused old URL
// Now each sidebar has its own URL. Different Reels = different sidebars.
static NSMutableDictionary *g_urlCacheBySidebar = nil;

// v8.2.18: Reels button is added by hooked_shortsSideBarLayoutSubviews.
// No more viewWillAppear:/viewDidLoad hooks. No keyWindow button.

@interface GlowReelButtonHandler : NSObject
@end
@implementation GlowReelButtonHandler
// Track taps in Reels - logs class of any tapped view
- (void)onReelTap:(UITapGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateRecognized) return;
    UIView *v = gr.view;
    if (!v) return;
    LOG("[reels/tap] class=%s frame=(%.0f,%.0f,%.0f,%.0f)\n",
        class_getName(object_getClass(v)), v.frame.origin.x, v.frame.origin.y,
        v.frame.size.width, v.frame.size.height);
    // Walk up 3 levels to find button or action class
    UIView *cur = v;
    for (int i = 0; i < 5 && cur; i++) {
        LOG("[reels/tap]   +%d %s\n", i, class_getName(object_getClass(cur)));
        cur = cur.superview;
    }
}

- (void)onReelButtonTap:(UIButton *)sender {
    LOG("[dl/reel] TAP on %s (parent=%s)\n",
        class_getName(object_getClass(sender)),
        class_getName(object_getClass(sender.superview)));
    [self downloadReelVideoFromView:sender];
}

// v8.2.22: Backup long-press handler
- (void)onReelButtonLongPress:(UILongPressGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateBegan) return;
    LOG("[dl/reel] LONGPRESS backup\n");
    [self downloadReelVideoFromView:gr.view];
}

// v8.2.22: Reel video download - find URL via multiple methods:
//   1. Walk up view hierarchy looking for currentVideoPlaybackItem
//   2. Walk up nextResponder chain to find UIViewController
//      then try common property names (currentVideoPlaybackItem,
//      currentItem, videoController, playbackController, etc.)
//   3. Walk down from VC's view to find AVPlayerLayer and get URL
//   4. Use cached URL (from hooked_HDPlaybackURL/SDPlaybackURL)
- (void)downloadReelVideoFromView:(UIView *)startView {
    @try {
        SEL curSel = sel_registerName("currentVideoPlaybackItem");
        id item = nil;
        UIView *btnView = (UIView *)startView;
        UIView *thisSideBar = btnView.superview;
        NSValue *sbKey = [NSValue valueWithNonretainedObject:thisSideBar];
        NSURL *hd = nil, *sd = nil;

        // v8.2.32: Method -1 (HIGHEST PRIORITY) - check GLOW-style per-VC cache
        // The cache is keyed by VC instance. Walk up nextResponder to find VC,
        // then look up the URL captured by setVideoItem: hook.
        // This is the MOST RELIABLE method because setVideoItem: fires ONLY
        // when FB switches to a new Reel (not for preloads).
        @try {
            UIResponder *r = btnView.nextResponder;
            int rd = 0;
            UIViewController *vcForCache = nil;
            while (r && rd < 8) {
                if ([r isKindOfClass:[UIViewController class]]) {
                    vcForCache = (UIViewController *)r;
                    break;
                }
                r = r.nextResponder;
                rd++;
            }
            if (vcForCache && g_vcToURLDict) {
                NSValue *vcKey = [NSValue valueWithNonretainedObject:vcForCache];
                NSDictionary *entry = g_vcToURLDict[vcKey];
                if (entry) {
                    id hdObj = entry[@"HD"];
                    id sdObj = entry[@"SD"];
                    if (hdObj && hdObj != [NSNull null] && [hdObj isKindOfClass:[NSURL class]]) hd = (NSURL *)hdObj;
                    if (sdObj && sdObj != [NSNull null] && [sdObj isKindOfClass:[NSURL class]]) sd = (NSURL *)sdObj;
                    id entryItem = entry[@"item"];
                    LOG("[dl/reel] M-1: VC cache hit VC=%s HD=%d SD=%d item=%s\n",
                        class_getName(object_getClass(vcForCache)),
                        hd != nil, sd != nil,
                        entryItem ? class_getName(object_getClass(entryItem)) : "nil");
                } else {
                    LOG("[dl/reel] M-1: VC cache miss for VC=%s (dict has %lu entries)\n",
                        class_getName(object_getClass(vcForCache)),
                        (unsigned long)g_vcToURLDict.count);
                }
            }
        } @catch (NSException *e) {
            LOG("[dl/reel] M-1: VC cache lookup exc: %s\n", e.reason.UTF8String);
        }

        // v8.2.29: Method 0 - check PER-SIDEBAR cached URL
        // Key = sidebar instance the URL was captured for. This prevents
        // downloading wrong Reel when FB preloads next Reel in background.
        NSDictionary *cached = g_urlCacheBySidebar[sbKey];
        if (!hd && !sd && cached) {
            id hdObj = cached[@"HD"];
            id sdObj = cached[@"SD"];
            if (hdObj && hdObj != [NSNull null] && [hdObj isKindOfClass:[NSURL class]]) hd = (NSURL *)hdObj;
            if (sdObj && sdObj != [NSNull null] && [sdObj isKindOfClass:[NSURL class]]) sd = (NSURL *)sdObj;
            LOG("[dl/reel] M0: per-sidebar cache HD=%d SD=%d for sidebar=%s\n",
                hd != nil, sd != nil, class_getName(object_getClass(thisSideBar)));
        }
        // v8.2.30: On tap, if per-sidebar cache is empty, FORCE-READ URL.
        // Pre-warm in layoutSubviews may run BEFORE FB loads the URL.
        // By the time user taps, video should be loaded - force-read now.
        if (!hd && !sd) {
            @try {
                UIResponder *r = btnView.nextResponder;
                int rd = 0;
                while (r && rd < 8) {
                    if ([r isKindOfClass:[UIViewController class]]) {
                        UIViewController *vc = (UIViewController *)r;
                        SEL curItemSel = sel_registerName("currentVideoPlaybackItem");
                        if ([vc respondsToSelector:curItemSel]) {
                            id item = [vc performSelector:curItemSel];
                            if (item) {
                                SEL hdSel = sel_registerName("HDPlaybackURL");
                                SEL sdSel = sel_registerName("SDPlaybackURL");
                                NSURL *hdURL = nil, *sdURL = nil;
                                if ([item respondsToSelector:hdSel]) {
                                    hdURL = [item performSelector:hdSel];
                                }
                                if ([item respondsToSelector:sdSel]) {
                                    sdURL = [item performSelector:sdSel];
                                }
                                if (hdURL || sdURL) {
                                    if (!g_urlCacheBySidebar) g_urlCacheBySidebar = [[NSMutableDictionary alloc] init];
                                    NSMutableDictionary *entry = [NSMutableDictionary dictionary];
                                    entry[@"HD"] = hdURL ?: [NSNull null];
                                    entry[@"SD"] = sdURL ?: [NSNull null];
                                    g_urlCacheBySidebar[sbKey] = entry;
                                    hd = hdURL;
                                    sd = sdURL;
                                    LOG("[dl/reel] M0: FORCE-READ on tap: HD=%d SD=%d\n",
                                        hd != nil, sd != nil);
                                } else {
                                    LOG("[dl/reel] M0: FORCE-READ returned nil URLs\n");
                                }
                            }
                        }
                        break;
                    }
                    r = r.nextResponder;
                    rd++;
                }
            } @catch (NSException *e) {
                LOG("[dl/reel] M0: FORCE-READ exc: %s\n", e.reason.UTF8String);
            }
        }
        if (hd || sd) {
            // v8.2.33: Use shared action sheet helper (1 tap = 1 download)
            if (!g_videoHandler) g_videoHandler = [[GlowVideoDownloadHandler alloc] init];
            [g_videoHandler presentQualityActionSheetHD:hd sd:sd sourceView:btnView];
            return;
        }
        LOG("[dl/reel] M0: no per-sidebar cache, trying other methods\n");

        // Method 1: walk up view hierarchy (existing)
        UIView *v = startView;
        int depth = 0;
        while (v && depth < 12) {
            @try {
                if ([v respondsToSelector:curSel]) {
                    item = [v performSelector:curSel];
                    if (item) { LOG("[dl/reel] M1: found on view depth %d (%s)\n", depth, class_getName(object_getClass(v))); break; }
                }
                id controller = [v valueForKey:@"controller"];
                if (controller && [controller respondsToSelector:curSel]) {
                    item = [controller performSelector:curSel];
                    if (item) { LOG("[dl/reel] M1b: found via controller (%s)\n", class_getName(object_getClass(v))); break; }
                }
            } @catch (...) {}
            v = v.superview;
            depth++;
        }

        // Method 2: walk up nextResponder chain to find VC
        if (!item) {
            UIResponder *r = startView.nextResponder;
            int rd = 0;
            while (r && rd < 8) {
                if ([r isKindOfClass:[UIViewController class]]) {
                    UIViewController *vc = (UIViewController *)r;
                    const char *vcn = class_getName(object_getClass(vc));
                    LOG("[dl/reel] M2: VC=%s\n", vcn);
                    // Try common property names on VC
                    NSArray *props = @[@"currentVideoPlaybackItem", @"currentVideoItem",
                                       @"playbackController", @"videoController",
                                       @"mediaController", @"playerController",
                                       @"videoItem", @"currentItem"];
                    for (NSString *p in props) {
                        @try {
                            if ([vc respondsToSelector:NSSelectorFromString(p)]) {
                                id val = [vc valueForKey:p];
                                if (val) {
                                    // If val has currentVideoPlaybackItem, dig deeper
                                    if ([val respondsToSelector:curSel]) {
                                        item = [val performSelector:curSel];
                                        if (item) { LOG("[dl/reel] M2: found via VC.%@.%s\n", p, "currentVideoPlaybackItem"); break; }
                                    }
                                    // If val is FBVideoPlaybackItem directly
                                    if ([val respondsToSelector:@selector(HDPlaybackURL)]) {
                                        item = val;
                                        LOG("[dl/reel] M2: VC.%@ is FBVideoPlaybackItem\n", p);
                                        break;
                                    }
                                }
                            }
                        } @catch (...) {}
                    }
                    break;
                }
                r = r.nextResponder;
                rd++;
            }
        }

        // Method 3: find AVPlayerLayer in VC's view
        NSURL *directURL = nil;
        if (!item) {
            UIResponder *r = startView.nextResponder;
            while (r && ![r isKindOfClass:[UIViewController class]]) r = r.nextResponder;
            if (r && [r isKindOfClass:[UIViewController class]]) {
                UIViewController *vc = (UIViewController *)r;
                UIView *rv = vc.view;
                // BFS for AVPlayerLayer
                Class avPlayerLayerCls = NSClassFromString(@"AVPlayerLayer");
                if (avPlayerLayerCls) {
                    NSMutableArray *queue = [NSMutableArray arrayWithObject:rv];
                    int d2 = 0;
                    while (queue.count > 0 && d2 < 50) {
                        UIView *c = [queue firstObject];
                        [queue removeObjectAtIndex:0];
                        @try {
                            CALayer *playerLayer = nil;
                            if ([c.layer isKindOfClass:avPlayerLayerCls]) {
                                playerLayer = c.layer;
                            }
                            if (playerLayer) {
                                // Use KVC to get player from layer
                                id player = [playerLayer valueForKey:@"player"];
                                if ([player respondsToSelector:@selector(currentItem)]) {
                                    id avItem = [player performSelector:@selector(currentItem)];
                                    SEL assetSel = sel_registerName("asset");
                                    if ([avItem respondsToSelector:assetSel]) {
                                        id asset = [avItem performSelector:assetSel];
                                        SEL urlSel = sel_registerName("URL");
                                        if ([asset respondsToSelector:urlSel]) {
                                            directURL = (NSURL *)[asset performSelector:urlSel];
                                            LOG("[dl/reel] M3: AVPlayerLayer URL found\n");
                                            break;
                                        }
                                    }
                                }
                            }
                        } @catch (...) {}
                        for (UIView *s in c.subviews) [queue addObject:s];
                        d2++;
                    }
                }
            }
        }

        // Method 4 (v8.2.27): BFS the ENTIRE rootVC view hierarchy, check
        // each view's VC for currentVideoPlaybackItem. The Reel video item
        // might be on a different VC than expected.
        if (!item && !directURL) {
            @try {
                UIWindow *win = startView.window;
                if (win && win.rootViewController) {
                    UIView *rv = win.rootViewController.view;
                    NSMutableArray *queue = [NSMutableArray arrayWithObject:rv];
                    int d2 = 0;
                    while (queue.count > 0 && d2 < 200) {
                        UIView *c = [queue firstObject];
                        [queue removeObjectAtIndex:0];
                        @try {
                            // Check view's VC for currentVideoPlaybackItem
                            UIResponder *r = c.nextResponder;
                            if (r && [r isKindOfClass:[UIViewController class]]) {
                                UIViewController *vc = (UIViewController *)r;
                                SEL curItemSel = sel_registerName("currentVideoPlaybackItem");
                                if ([vc respondsToSelector:curItemSel]) {
                                    id vItem = [vc performSelector:curItemSel];
                                    if (vItem && [vItem respondsToSelector:@selector(HDPlaybackURL)]) {
                                        item = vItem;
                                        LOG("[dl/reel] M4: found via VC=%s\n", class_getName(object_getClass(vc)));
                                        break;
                                    }
                                }
                            }
                        } @catch (...) {}
                        for (UIView *s in c.subviews) [queue addObject:s];
                        d2++;
                    }
                }
            } @catch (...) {}
        }

        // Method 5 (v8.2.27): BFS for AVPlayerLayer from sender's window
        // (not just VC.view). The Reel player layer might be in a different
        // view hierarchy.
        if (!item && !directURL) {
            @try {
                Class avPlayerLayerCls = NSClassFromString(@"AVPlayerLayer");
                if (avPlayerLayerCls) {
                    UIWindow *win = startView.window;
                    if (win) {
                        NSMutableArray *queue = [NSMutableArray arrayWithObject:win];
                        int d2 = 0;
                        while (queue.count > 0 && d2 < 100) {
                            UIView *c = [queue firstObject];
                            [queue removeObjectAtIndex:0];
                            @try {
                                if ([c.layer isKindOfClass:avPlayerLayerCls]) {
                                    id player = [c.layer valueForKey:@"player"];
                                    if ([player respondsToSelector:@selector(currentItem)]) {
                                        id avItem = [player performSelector:@selector(currentItem)];
                                        SEL assetSel = sel_registerName("asset");
                                        if ([avItem respondsToSelector:assetSel]) {
                                            id asset = [avItem performSelector:assetSel];
                                            SEL urlSel = sel_registerName("URL");
                                            if ([asset respondsToSelector:urlSel]) {
                                                directURL = (NSURL *)[asset performSelector:urlSel];
                                                LOG("[dl/reel] M5: AVPlayerLayer URL found from window\n");
                                                break;
                                            }
                                        }
                                    }
                                }
                            } @catch (...) {}
                            for (UIView *s in c.subviews) [queue addObject:s];
                            d2++;
                        }
                    }
                }
            } @catch (...) {}
        }

        if (!item && !directURL) {
            // v8.2.31: LAST RESORT - use global URL captured by hook.
            // The hook fires when FB reads HDPlaybackURL/SDPlaybackURL.
            // The global might be from a different Reel (FB preload), but
            // better than "không tìm thấy video".
            if (g_cachedHDURL || g_cachedSDURL) {
                LOG("[dl/reel] M0: using GLOBAL cached URL as fallback (age=%.1fs)\n",
                    g_cachedAt ? -[g_cachedAt timeIntervalSinceNow] : 0);
                hd = g_cachedHDURL;
                sd = g_cachedSDURL;
                if (!g_urlCacheBySidebar) g_urlCacheBySidebar = [[NSMutableDictionary alloc] init];
                NSMutableDictionary *entry = [NSMutableDictionary dictionary];
                entry[@"HD"] = hd ?: [NSNull null];
                entry[@"SD"] = sd ?: [NSNull null];
                g_urlCacheBySidebar[sbKey] = entry;
                // Don't return - let it fall through to action sheet
            } else {
                LOG("[dl/reel] no playback item AND no AVPlayerLayer URL found\n");
                [self showToast:@"❌ Không tìm thấy video"];
                return;
            }
        }

        if (item) {
            SEL hdSel = sel_registerName("HDPlaybackURL");
            SEL sdSel = sel_registerName("SDPlaybackURL");
            hd = [item respondsToSelector:hdSel] ? [item performSelector:hdSel] : nil;
            sd = [item respondsToSelector:sdSel] ? [item performSelector:sdSel] : nil;
        }
        if (!hd && !sd && directURL) {
            hd = directURL;  // fallback to direct URL
        }
        if (!hd && !sd) {
            LOG("[dl/reel] no URLs found\n");
            [self showToast:@"❌ Video chưa tải"];
            return;
        }
        LOG("[dl/reel] downloading HD=%d SD=%d\n", hd != nil, sd != nil);
        if (!g_videoHandler) g_videoHandler = [[GlowVideoDownloadHandler alloc] init];
        // Visual feedback
        UIButton *btn = (UIButton *)startView;
        if ([btn isKindOfClass:[UIButton class]]) {
            btn.enabled = NO;
            btn.backgroundColor = [UIColor colorWithRed:0 green:0.7 blue:0 alpha:0.7];
            [btn setTitle:@"✓" forState:UIControlStateNormal];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                btn.enabled = YES;
                btn.backgroundColor = [UIColor clearColor];
                [btn setTitle:@"⬇" forState:UIControlStateNormal];
            });
        }
        [self showToast:@"⬇ Đang tải..."];
        if (hd) [g_videoHandler downloadVideoURL:hd quality:@"reel_hd"];
        if (sd && sd != hd) [g_videoHandler downloadVideoURL:sd quality:@"reel_sd"];
    } @catch (NSException *e) {
        LOG("[dl/reel] exc: %s\n", e.reason.UTF8String);
    }
}

// Simple toast
- (void)showToast:(NSString *)msg {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            UIWindow *win = nil;
            for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
                if ([s isKindOfClass:[UIWindowScene class]]) {
                    for (UIWindow *w in ((UIWindowScene *)s).windows) {
                        if (w.isKeyWindow) { win = w; break; }
                    }
                }
                if (win) break;
            }
            if (!win) return;
            UILabel *lbl = [[UILabel alloc] init];
            lbl.text = msg;
            lbl.textColor = [UIColor whiteColor];
            lbl.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
            lbl.textAlignment = NSTextAlignmentCenter;
            lbl.backgroundColor = [UIColor colorWithWhite:0 alpha:0.75];
            lbl.layer.cornerRadius = 10;
            lbl.layer.masksToBounds = YES;
            lbl.numberOfLines = 0;
            lbl.alpha = 0;
            [win addSubview:lbl];
            CGSize sz = [msg boundingRectWithSize:CGSizeMake(win.bounds.size.width - 80, 200)
                                          options:NSStringDrawingUsesLineFragmentOrigin
                                       attributes:@{NSFontAttributeName: lbl.font}
                                          context:nil].size;
            lbl.frame = CGRectMake((win.bounds.size.width - sz.width - 30) / 2,
                                   win.bounds.size.height - 200,
                                   sz.width + 30, sz.height + 18);
            [UIView animateWithDuration:0.25 animations:^{ lbl.alpha = 1.0; }];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                [UIView animateWithDuration:0.25 animations:^{ lbl.alpha = 0; }
                                 completion:^(BOOL ok) { [lbl removeFromSuperview]; }];
            });
        } @catch (...) {}
    });
}
@end
static GlowReelButtonHandler *g_reelButtonHandler = nil;

// v8.2.21: REELS DOWNLOAD - INSERT INTO MAIN SIDEBAR (1 button per Reel)
// Hook FBShortsSideBarView.layoutSubviews. The MAIN sidebar contains
// 5 FDSTouchStateAnnouncingControl children (Like, Comment, Share,
// Save, More). Other sidebars have 1-2 children. We only add our
// button to the MAIN sidebar (4+ FDS children), placed ABOVE Like
// (y = -72), making it visually part of the action column.
//
// v8.2.21 fix (vs v8.2.20): User suggested (correct!) - just add
// button to the main sidebar, don't walk up to overlay. Main sidebar
// is identified by having 4+ FDSTouchStateAnnouncingControl children.
// This is simpler and more robust.
//
// v8.2.20 structure:
//   FBShortsSideBarView (360,0,56,333) ← MAIN (has 5 FDS children)
//     FDSTouchStateAnnouncingControl Like (0,0,56,72)
//     FDSTouchStateAnnouncingControl Comment (0,72,56,72)
//     FDSTouchStateAnnouncingControl Share (0,145,56,72)
//     FDSTouchStateAnnouncingControl Save (0,217,56,72)
//     FDSTouchStateAnnouncingControl More (0,289,56,44)
//     [OUR BUTTON (0,-72,56,72)]  ← v8.2.21: inserted above Like
//
// Other sidebars (description/profile/sound) have 0-2 FDS children
// and are ignored.
static NSMutableSet *g_mainSideBarsWithButton = nil;
static IMP orig_shortsSideBarLayoutSubviews = NULL;

// g_cachedHDURL/g_cachedSDURL/g_cachedAt/orig_HDPlaybackURL/orig_SDPlaybackURL
// are declared at the top of the file (before GlowReelButtonHandler)

// v8.2.24: Reel download button - SEPARATE from Like (not overlap).
// Hook FBShortsSideBarView.layoutSubviews. The MAIN sidebar has 4+
// FDSTouchStateAnnouncingControl children. We add our button as a
// child of the Reels overlay (FBShortsViewerOverlayComponentView) at
// the position above the sidebar, NOT inside the sidebar (so we
// don't overlap Like). The overlay has full-screen frame, so the
// button is tappable.
//
// v8.2.24 fix (vs v8.2.23):
//   - User feedback: 'đặt nó riêng, trên nút like, cách nút like ra'
//     (place it separately, above Like, with spacing)
//   - v8.2.23 placed button at (0,0) inside sidebar, overlapping Like
//   - Now: place at overlay, above sidebar, in the area between
//     Reels description and Like button (no overlap)
//
// v8.2.24 fix (vs v8.2.21) - bug in comments:
//   - User screenshot showed button appearing in Reel posted as comment
//   - Reel in comment has same sidebar structure -> 5 FDS children
//   - Now: walk up from sidebar, REJECT if any ancestor is FBComment*/
//     FBBottomSheet*/FBFeedAttachment*/FBCommentStream*/FBCommentAttachmentView
//
// Structure (v8.2.24):
//   FBShortsViewerOverlayComponentView (full-screen Reels-only parent)
//     FBPassthroughView (overlay container)
//       FBShortsSideBarView (360,0,56,333) ← MAIN (5 FDS children)
//         FDSTouchStateAnnouncingControl Like (0,0,56,72)
//         FDSTouchStateAnnouncingControl Comment (0,72,56,72)
//         ...
//       [OUR BUTTON at sidebar position, ABOVE sidebar in overlay coords]
static NSMutableSet *g_overlaysWithButton = NULL;

// Walk up from sidebar. Reject if IMMEDIATE ancestor (depth 0-5) is a
// comment-context class. Accept if ANY ancestor has 'FBShorts' (Reels-only).
// v8.2.27: looser filter - some Reels don't have FBShortsViewerOverlayComponentView
// but have other FBShorts* classes.
static BOOL isInReelsFullScreen(UIView *sideBar) {
    if (!sideBar) return NO;
    // Pass 1: check immediate 5 ancestors for comment/sheet (REJECT)
    UIView *cur = sideBar.superview;
    for (int depth = 0; cur && depth < 5; depth++) {
        const char *name = class_getName(object_getClass(cur));
        if (name) {
            if (strstr(name, "FBCommentStream") != NULL) return NO;
            if (strstr(name, "FBBottomSheetView") != NULL) return NO;
            if (strstr(name, "FBFeedAttachmentView") != NULL) return NO;
        }
        cur = cur.superview;
    }
    // Pass 2: check full 30 ancestors for FBShorts (ACCEPT)
    cur = sideBar.superview;
    for (int depth = 0; cur && depth < 30; depth++) {
        const char *name = class_getName(object_getClass(cur));
        if (name && strstr(name, "FBShorts") != NULL) return YES;
        cur = cur.superview;
    }
    return NO;
}

// Find the FBShortsViewerOverlayComponentView (strstr match) - the
// Reels-only parent that contains the sidebar. Returns nil if not found.
static UIView *findReelsOverlay(UIView *sideBar) {
    UIView *cur = sideBar.superview;
    int depth = 0;
    while (cur && depth < 30) {
        Class cls = object_getClass(cur);
        const char *name = class_getName(cls);
        if (name && strstr(name, "FBShortsViewerOverlayComponentView") != NULL) {
            return cur;
        }
        cur = cur.superview;
        depth++;
    }
    return nil;
}

static void hooked_shortsSideBarLayoutSubviews(id self, SEL _cmd) {
    if (orig_shortsSideBarLayoutSubviews) {
        typedef void (*FnType)(id, SEL);
        FnType fn = (FnType)(uintptr_t)orig_shortsSideBarLayoutSubviews;
        fn(self, _cmd);
    }
    if (!s_downloadReels) return;  // v8.2.25: separate from s_downloadVideo
    @try {
        if (![self isKindOfClass:[UIView class]]) return;
        UIView *sideBar = (UIView *)self;
        if (!g_overlaysWithButton) g_overlaysWithButton = [[NSMutableSet alloc] init];
        if (!g_reelButtonHandler) g_reelButtonHandler = [[GlowReelButtonHandler alloc] init];

        // Skip if hidden
        if (sideBar.hidden || sideBar.alpha < 0.01) return;
        // Skip if too small (the main sidebar is at least 56x300+)
        if (sideBar.bounds.size.width < 40 || sideBar.bounds.size.height < 200) return;

        // v8.2.21: MAIN sidebar = has 4+ FDSTouchStateAnnouncingControl children
        Class fdsCls = NSClassFromString(@"FDSTouchStateAnnouncingControl");
        if (!fdsCls) {
            LOG("[reels/main] FDSTouchStateAnnouncingControl class NOT FOUND\n");
            return;
        }
        int fdsCount = 0;
        for (UIView *sub in sideBar.subviews) {
            if ([sub isKindOfClass:fdsCls]) fdsCount++;
        }
        if (fdsCount < 4) return;  // not the main action column

        // v8.2.24: REJECT if sidebar is in a comment / sheet context
        // (Reels posted as comments also have 5 FDS children, so we
        // need to check the parent chain to differentiate)
        if (!isInReelsFullScreen(sideBar)) {
            LOG("[reels/main] SKIP (not in Reels full-screen)\n");
            return;
        }

        // Find the Reels-only overlay (exact class match)
        UIView *overlay = findReelsOverlay(sideBar);
        if (!overlay) {
            LOG("[reels/main] SKIP (no FBShortsViewerOverlayComponentView ancestor)\n");
            return;
        }
        NSValue *okey = [NSValue valueWithNonretainedObject:overlay];
        if ([g_overlaysWithButton containsObject:okey]) return;  // already added

        // v8.2.24: Position button ABOVE the sidebar, as child of OVERLAY.
        // This makes it tappable (overlay has full-screen frame) and
        // separates it from Like with spacing.
        // Convert sidebar's frame to overlay's coordinate system
        CGRect sbFrameInOverlay = [sideBar convertRect:sideBar.bounds toView:overlay];
        CGFloat btnW = 56;   // matches sidebar width
        CGFloat btnH = 56;   // slightly smaller than Like (72), but visible
        CGFloat btnX = sbFrameInOverlay.origin.x;  // align with sidebar
        CGFloat btnY = sbFrameInOverlay.origin.y - btnH - 8;  // 8px gap above sidebar

        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.frame = CGRectMake(btnX, btnY, btnW, btnH);
        btn.layer.cornerRadius = 0;
        // v8.2.24: FULLY TRANSPARENT (user feedback)
        btn.backgroundColor = [UIColor clearColor];
        [btn setTitle:@"⬇" forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont systemFontOfSize:28 weight:UIFontWeightBold];
        // No border
        btn.accessibilityIdentifier = @"GlowReelButton";
        btn.layer.zPosition = 9999;  // on top
        // v8.2.34: Use UIMenu as primary action (replaces action sheet)
        // UIMenu is iOS 14+ native menu - shows on tap, no alert controller needed
        // More reliable in Reels context where alert sheet gets dismissed by gestures
        // v8.2.34b: REMOVED long-press recognizer (it was firing BOTH tap+longpress,
        // causing duplicate download of HD+SD). UIMenu is the only path now.
        if (@available(iOS 14.0, *)) {
            btn.showsMenuAsPrimaryAction = YES;
            // Menu is set LATER (after URLs are captured in pre-warm below)
            // Mark as pending menu setup
            objc_setAssociatedObject(btn, "GlowMenuPending", @YES, OBJC_ASSOCIATION_RETAIN);
        } else {
            // iOS < 14: use target/action (no UIMenu)
            [btn addTarget:g_reelButtonHandler action:@selector(onReelButtonTap:) forControlEvents:UIControlEventTouchUpInside];
        }
        [overlay addSubview:btn];
        [overlay bringSubviewToFront:btn];
        [g_overlaysWithButton addObject:okey];
        LOG("[reels/main] ADDED button to overlay %s (FDS children=%d) at (%.0f,%.0f,%.0f,%.0f) [sidebar at (%.0f,%.0f)]\n",
            class_getName(object_getClass(overlay)), fdsCount,
            btnX, btnY, btnW, btnH,
            sbFrameInOverlay.origin.x, sbFrameInOverlay.origin.y);

        // v8.2.28: PRE-WARM - force FBVideoPlaybackItem.HDPlaybackURL/SDPlaybackURL
        // to be read NOW, so our hook captures the URL. This ensures the
        // URL is available when user taps the button.
        // v8.2.29: Store URL PER-SIDEBAR in g_urlCacheBySidebar dictionary
        // to prevent wrong-Reel downloads (FB preloads next Reel).
        // v8.2.34: After pre-warm, set the UIMenu on the button with the URLs
        @try {
            if (!g_urlCacheBySidebar) g_urlCacheBySidebar = [[NSMutableDictionary alloc] init];
            UIResponder *r = sideBar.nextResponder;
            int rd = 0;
            while (r && rd < 8) {
                if ([r isKindOfClass:[UIViewController class]]) {
                    UIViewController *vc = (UIViewController *)r;
                    SEL curItemSel = sel_registerName("currentVideoPlaybackItem");
                    if ([vc respondsToSelector:curItemSel]) {
                        id item = [vc performSelector:curItemSel];
                        if (item) {
                            // Force read HD/SD URLs (triggers our hook)
                            SEL hdSel = sel_registerName("HDPlaybackURL");
                            SEL sdSel = sel_registerName("SDPlaybackURL");
                            NSURL *hdURL = nil, *sdURL = nil;
                            if ([item respondsToSelector:hdSel]) {
                                hdURL = [item performSelector:hdSel];
                            }
                            if ([item respondsToSelector:sdSel]) {
                                sdURL = [item performSelector:sdSel];
                            }
                            // v8.2.29: cache per-sidebar
                            if (hdURL || sdURL) {
                                NSValue *sbKey = [NSValue valueWithNonretainedObject:sideBar];
                                NSMutableDictionary *entry = [NSMutableDictionary dictionary];
                                if (hdURL) entry[@"HD"] = hdURL; else entry[@"HD"] = [NSNull null];
                                if (sdURL) entry[@"SD"] = sdURL; else entry[@"SD"] = [NSNull null];
                                g_urlCacheBySidebar[sbKey] = entry;
                                LOG("[reels/main] PRE-WARM cached for sidebar: HD=%d SD=%d\n",
                                    hdURL != nil, sdURL != nil);

                                // v8.2.34: Set UIMenu on button with HD/SD options
                                if (@available(iOS 14.0, *)) {
                                    id pending = objc_getAssociatedObject(btn, "GlowMenuPending");
                                    if (pending) {
                                        objc_setAssociatedObject(btn, "GlowMenuPending", nil, OBJC_ASSOCIATION_RETAIN);
                                        if (!g_videoHandler) g_videoHandler = [[GlowVideoDownloadHandler alloc] init];
                                        NSMutableArray *actions = [NSMutableArray array];
                                        if (hdURL) {
                                            [actions addObject:[UIAction actionWithTitle:@"📥 Tải HD (720p)"
                                                                                 image:nil
                                                                            identifier:nil
                                                                               handler:^(UIAction *a) {
                                                [g_videoHandler downloadVideoURL:hdURL quality:@"HD"];
                                            }]];
                                        }
                                        if (sdURL) {
                                            [actions addObject:[UIAction actionWithTitle:@"📥 Tải SD (360p)"
                                                                                 image:nil
                                                                            identifier:nil
                                                                               handler:^(UIAction *a) {
                                                [g_videoHandler downloadVideoURL:sdURL quality:@"SD"];
                                            }]];
                                        }
                                        if (actions.count > 0) {
                                            UIMenu *menu = [UIMenu menuWithTitle:@""
                                                                              image:nil
                                                                         identifier:nil
                                                                            options:UIMenuOptionsDisplayInline
                                                                           children:actions];
                                            btn.menu = menu;
                                            LOG("[reels/main] UIMenu SET on button (HD=%d SD=%d)\n",
                                                hdURL != nil, sdURL != nil);
                                        }
                                    }
                                }
                            }
                        }
                    }
                    break;
                }
                r = r.nextResponder;
                rd++;
            }
        } @catch (...) {}
    } @catch (NSException *e) {
        LOG("[reels/main] exc: %s\n", e.reason.UTF8String);
    }
}

// v8.2.28: Hook FBVideoPlaybackItem.HDPlaybackURL getter.
// When FB reads the URL (to play the video), we capture it.
// On Reels button tap, use the captured URL directly.
static NSURL *hooked_HDPlaybackURL(id self, SEL _cmd) {
    NSURL *url = nil;
    if (orig_HDPlaybackURL) {
        typedef NSURL *(*FnType)(id, SEL);
        url = ((FnType)orig_HDPlaybackURL)(self, _cmd);
    }
    if (url) {
        g_cachedHDURL = url;
        g_cachedAt = [NSDate date];
        LOG("[dl/reel] CAPTURED HD: %s\n", [[url absoluteString] UTF8String]);
    }
    return url;
}

// v8.2.28: Hook FBVideoPlaybackItem.SDPlaybackURL getter.
static NSURL *hooked_SDPlaybackURL(id self, SEL _cmd) {
    NSURL *url = nil;
    if (orig_SDPlaybackURL) {
        typedef NSURL *(*FnType)(id, SEL);
        url = ((FnType)orig_SDPlaybackURL)(self, _cmd);
    }
    if (url) {
        g_cachedSDURL = url;
        g_cachedAt = [NSDate date];
        LOG("[dl/reel] CAPTURED SD: %s\n", [[url absoluteString] UTF8String]);
    }
    return url;
}

static IMP orig_didLongPress = NULL;
static void hooked_didLongPress(id self, SEL _cmd, id recognizer) {
    // Always call orig first
    if (orig_didLongPress) {
        typedef void (*FnType)(id, SEL, id);
        FnType fn = (FnType)(uintptr_t)orig_didLongPress;
        fn(self, _cmd, recognizer);
    }
    if (!g_videoHandler) g_videoHandler = [[GlowVideoDownloadHandler alloc] init];
    if (recognizer && [recognizer isKindOfClass:[UILongPressGestureRecognizer class]]) {
        [g_videoHandler onLongPress:(UILongPressGestureRecognizer *)recognizer];
    }
}

// ═══════════════════════════════════════════════════════════════
// SECTION 5: Long press to open settings (on any view)
// ═══════════════════════════════════════════════════════════════

// (long press is added in installLongPressOnCurrentUI, called after hooks install)

// ═══════════════════════════════════════════════════════════════
// SECTION 6: Install hooks (deferred until NewsFeed is ready)
// ═══════════════════════════════════════════════════════════════

static IMP orig_viewDidAppear = NULL;
static int setupDone = 0;

static void installHooks(void) {
    if (setupDone) return;
    setupDone = 1;
    LOG("\n=== Installing v8.0 hooks ===\n");

    @try {
        // Hook 0: FBMemNewsFeedEdge.node - return nil for SPONSORED
        if (s_removeAds) {
            Class memEdgeCls = objc_getClass("FBMemNewsFeedEdge");
            if (memEdgeCls) {
                SEL nodeSel = sel_registerName("node");
                Method m = class_getInstanceMethod(memEdgeCls, nodeSel);
                if (m) {
                    orig_node = method_getImplementation(m);
                    method_setImplementation(m, (IMP)hooked_node);
                    LOG("  hook #0: FBMemNewsFeedEdge.node -> nil for SPONSORED\n");
                } else {
                    LOG("  FBMemNewsFeedEdge.node NOT FOUND\n");
                }
            } else {
                LOG("  FBMemNewsFeedEdge class NOT FOUND\n");
            }

            // Hook 1-2: cellForItem, willDisplay
            Class dsCls = objc_getClass("FBComponentCollectionViewDataSource");
            if (dsCls) {
                Method m1 = class_getInstanceMethod(dsCls, @selector(collectionView:cellForItemAtIndexPath:));
                if (m1) {
                    orig_cellForItem = method_getImplementation(m1);
                    method_setImplementation(m1, (IMP)hooked_cellForItem);
                    LOG("  hook #1: cellForItem\n");
                }
                Method m2 = class_getInstanceMethod(dsCls, @selector(collectionView:willDisplayCell:forItemAtIndexPath:));
                if (m2) {
                    orig_willDisplay = method_getImplementation(m2);
                    method_setImplementation(m2, (IMP)hooked_willDisplay);
                    LOG("  hook #2: willDisplay\n");
                }
            }
        }

        // Hook 3-5: Story seen
        if (s_disableStorySeen) {
            Class seenCls = objc_getClass("FBSnacksBucketsSeenStateManager");
            if (seenCls) {
                SEL sel1 = sel_registerName("_sendSeenThreadIDsWithBucket:session:");
                Method m1 = class_getInstanceMethod(seenCls, sel1);
                if (m1) {
                    orig_seen1 = method_getImplementation(m1);
                    method_setImplementation(m1, (IMP)noop_seen_1);
                    LOG("  hook #3: _sendSeenThreadIDsWithBucket:session: -> no-op\n");
                }
                SEL sel2 = sel_registerName("_sendThreadIDsAsSeenInViewerSession:");
                Method m2 = class_getInstanceMethod(seenCls, sel2);
                if (m2) {
                    orig_seen2 = method_getImplementation(m2);
                    method_setImplementation(m2, (IMP)noop_seen_2);
                    LOG("  hook #4: _sendThreadIDsAsSeenInViewerSession: -> no-op\n");
                }
                SEL sel3 = sel_registerName("markThreadsViewReceiptsAndLightweightReactionsAsSeen:bucket:session:isHighlight:successBlock:noThreadsToMarkAsSeenBlock:");
                Method m3 = class_getInstanceMethod(seenCls, sel3);
                if (m3) {
                    orig_seen3 = method_getImplementation(m3);
                    method_setImplementation(m3, (IMP)noop_seen_3);
                    LOG("  hook #5: markThreadsView... -> no-op\n");
                }
            }
        }

        // Hook 6: install long press on current view hierarchy
        // (called once after hooks install, then re-called when new VCs appear)
        installLongPressOnCurrentUI();

        // Hook 7: Hide Composer - hook FBNewsFeedViewController.viewDidLoad
        if (s_hideComposer) {
            Class nfcCls = objc_getClass("FBNewsFeedViewController");
            if (nfcCls) {
                Method m = class_getInstanceMethod(nfcCls, @selector(viewDidLoad));
                if (m) {
                    orig_newsFeed_viewDidLoad = method_getImplementation(m);
                    method_setImplementation(m, (IMP)hooked_newsFeed_viewDidLoad);
                    LOG("  hook #7: FBNewsFeedViewController.viewDidLoad -> _shouldHideComposer=YES\n");
                } else {
                    LOG("  FBNewsFeedViewController.viewDidLoad NOT FOUND\n");
                }
            }
        }

        // Hook 8: Download Story - hook FBSnacksMediaContainerView new init
        // (long press added in didMoveToWindow to avoid lifecycle crash)
        if (s_downloadStory) {
            Class cls = objc_getClass("FBSnacksMediaContainerView");
            if (cls) {
                SEL sel = sel_registerName("initWithThread:bucket:mediaViewDelegate:mediaViewGenerator:toolbox:shouldBlurMedia:");
                Method m = class_getInstanceMethod(cls, sel);
                if (m) {
                    orig_storyContainer_init = method_getImplementation(m);
                    method_setImplementation(m, (IMP)hooked_storyContainer_init);
                    LOG("  hook #8: FBSnacksMediaContainerView init (new sig)\n");
                } else {
                    LOG("  FBSnacksMediaContainerView new init NOT FOUND\n");
                }
                // Also hook didMoveToWindow to add long press safely
                SEL dmwSel = sel_registerName("didMoveToWindow");
                Method dmwM = class_getInstanceMethod(cls, dmwSel);
                if (dmwM) {
                    orig_storyContainer_didMoveToWindow = method_getImplementation(dmwM);
                    method_setImplementation(dmwM, (IMP)hooked_storyContainer_didMoveToWindow);
                    LOG("  hook #8b: FBSnacksMediaContainerView didMoveToWindow -> add long press\n");
                } else {
                    LOG("  didMoveToWindow NOT FOUND\n");
                }
            }
        }

        // Hook 9: Download Video - newsfeed long press
        // v8.2.34: REMOVED hardcoded class name. The class
        // FBVideoOverlayPluginComponentBackgroundView doesn't exist in FB 560.x.
        // Replaced by runtime enumeration in installGlowStyleReelsHook (called below).
        // We keep a stub here for backward compat with hook # numbering.
        if (s_downloadVideo) {
            // Legacy: try the class name (will fail in 560.x, no harm)
            Class cls = objc_getClass("FBVideoOverlayPluginComponentBackgroundView");
            if (cls) {
                SEL sel = sel_registerName("didLongPress:");
                Method m = class_getInstanceMethod(cls, sel);
                if (m) {
                    orig_didLongPress = method_getImplementation(m);
                    method_setImplementation(m, (IMP)hooked_didLongPress);
                    LOG("  hook #9: FBVideoOverlayPluginComponentBackgroundView.didLongPress: -> download video\n");
                }
            } else {
                // The real hook is via runtime enumeration in installGlowStyleReelsHook
                LOG("  hook #9: legacy class NOT FOUND, using runtime enum\n");
            }
        }

        // Hook 10 (REMOVED in v8.2.18): viewDidLoad on Reels VC.
        //   This was the v8.2.15 fallback that added button to
        //   FBVideoHomePassthroughView + keyWindow. The keyWindow button
        //   persisted across modal sheets (comment viewer) -> CRASH.
        //
        // Hook 11 (v8.2.18): FBShortsSideBarView.layoutSubviews
        //   Only way Reels button is added. STRICT filter
        //   (isInReelsContext) prevents button in comment sheet.
        if (s_downloadVideo) {
            Class sideBarCls = objc_getClass("FBShortsSideBarView");
            if (sideBarCls) {
                SEL lsSel = @selector(layoutSubviews);
                Method m2 = class_getInstanceMethod(sideBarCls, lsSel);
                if (m2) {
                    orig_shortsSideBarLayoutSubviews = method_getImplementation(m2);
                    method_setImplementation(m2, (IMP)hooked_shortsSideBarLayoutSubviews);
                    LOG("  hook #11: FBShortsSideBarView.layoutSubviews -> add download button as child (v8.2.18 strict filter)\n");
                } else {
                    LOG("  FBShortsSideBarView.layoutSubviews NOT FOUND\n");
                }
            } else {
                LOG("  FBShortsSideBarView NOT FOUND (will retry when Reels opens)\n");
            }
        }

        // Hook #12 (v8.2.28): FBVideoPlaybackItem.HDPlaybackURL/SDPlaybackURL
        // Method swizzling to capture URLs when FB reads them for playback.
        // The URLs are cached in globals and used by the Reels button tap.
        // This is the most reliable way to get the URL - no view walking.
        if (s_downloadVideo) {
            Class vpiCls = objc_getClass("FBVideoPlaybackItem");
            if (vpiCls) {
                SEL hdSel = sel_registerName("HDPlaybackURL");
                Method hdM = class_getInstanceMethod(vpiCls, hdSel);
                if (hdM) {
                    orig_HDPlaybackURL = method_getImplementation(hdM);
                    method_setImplementation(hdM, (IMP)hooked_HDPlaybackURL);
                    LOG("  hook #12a: FBVideoPlaybackItem.HDPlaybackURL -> capture URL\n");
                } else {
                    LOG("  FBVideoPlaybackItem.HDPlaybackURL NOT FOUND\n");
                }
                SEL sdSel = sel_registerName("SDPlaybackURL");
                Method sdM = class_getInstanceMethod(vpiCls, sdSel);
                if (sdM) {
                    orig_SDPlaybackURL = method_getImplementation(sdM);
                    method_setImplementation(sdM, (IMP)hooked_SDPlaybackURL);
                    LOG("  hook #12b: FBVideoPlaybackItem.SDPlaybackURL -> capture URL\n");
                } else {
                    LOG("  FBVideoPlaybackItem.SDPlaybackURL NOT FOUND\n");
                }
            } else {
                LOG("  FBVideoPlaybackItem NOT FOUND\n");
            }

            // Hook #13 (v8.2.32): GLOW-STYLE CLASS ENUMERATION + setVideoItem: SETTER
            // From analysis of original Glow.dylib (v1.3.1 from dayanch96):
            //   - Glow has ZERO hardcoded FB class names in its binary
            //   - Glow uses MSHookMessageEx to swizzle class methods
            //   - Glow swizzles 'setVideoItem:' setter on Reels VCs
            //   - When FB calls setVideoItem with new item, the URL is captured
            //   - This fires EXACTLY when player switches to new Reel (not preload)
            //
            // Our approach: enumerate all classes via objc_getClassList,
            // find FB classes that respond to setVideoItem:, swizzle the setter.
            // The setter captures: (vc=self, item=newItem, url=item.HDPlaybackURL)
            // We cache the URL keyed by VC instance pointer.
            //
            // v8.2.32 also hooks 'currentVideoPlaybackItem' GETTER (alternative path)
            // because some FB versions use property KVO instead of explicit setter.
            extern void installGlowStyleReelsHook(void);
            installGlowStyleReelsHook();
        }

        LOG("=== Done ===\n");
    } @catch (NSException *e) {
        LOG("  EXC: %s\n", e.reason.UTF8String);
    } @catch (...) {
        LOG("  EXC(c++)\n");
    }
}

// (Reels hooks declared above installHooks)

// v8.2.19: Lazy install hook for FBShortsSideBarView.layoutSubviews
// The class is NOT loaded at app startup (only when Reels opens).
// installHooks() at startup can't find it, so we hook it here when
// a Reels VC appears (which forces the class to load).
static int g_shortsSideBarHooked = 0;

static void tryLazyInstallShortsSideBarHook(void) {
    if (g_shortsSideBarHooked) return;
    if (orig_shortsSideBarLayoutSubviews) return;  // already hooked in installHooks
    @try {
        Class sideBarCls = objc_getClass("FBShortsSideBarView");
        if (!sideBarCls) {
            LOG("[reels/lazy] FBShortsSideBarView still NOT FOUND\n");
            return;
        }
        SEL lsSel = @selector(layoutSubviews);
        Method m2 = class_getInstanceMethod(sideBarCls, lsSel);
        if (m2) {
            orig_shortsSideBarLayoutSubviews = method_getImplementation(m2);
            method_setImplementation(m2, (IMP)hooked_shortsSideBarLayoutSubviews);
            g_shortsSideBarHooked = 1;
            LOG("  hook #11 (LAZY): FBShortsSideBarView.layoutSubviews -> add download button as child\n");
        } else {
            LOG("[reels/lazy] FBShortsSideBarView.layoutSubviews NOT FOUND\n");
        }
    } @catch (NSException *e) {
        LOG("[reels/lazy] exc: %s\n", e.reason.UTF8String);
    } @catch (...) {
        LOG("[reels/lazy] exc(c++)\n");
    }
}

static void hooked_viewDidAppear(id self, SEL _cmd, BOOL animated) {
    if (orig_viewDidAppear) {
        typedef void (*FnType)(id, SEL, BOOL);
        FnType fn = (FnType)(uintptr_t)orig_viewDidAppear;
        fn(self, _cmd, animated);
    }
    if (!setupDone) {
        const char *cn = class_getName(object_getClass(self));
        if (cn && strstr(cn, "FBNewsFeedViewController")) {
            dispatch_async(dispatch_get_main_queue(), ^{ installHooks(); });
        }
    } else {
        // Reinstall long press for new VCs (catches push/pop, tab switches)
        const char *cn = class_getName(object_getClass(self));
        if (cn && (strstr(cn, "ViewController") || strstr(cn, "View"))) {
            dispatch_async(dispatch_get_main_queue(), ^{
                @try { installLongPressOnCurrentUI(); } @catch (...) {}
            });
        }
        // v8.2.19: Lazy install Reels hook when Reels VC appears.
        // FBShortsSideBarView is loaded as part of Reels view hierarchy,
        // so by viewDidAppear of a Reels VC, the class is available.
        if (cn && (strstr(cn, "FBVideoHome") != NULL ||
                   strstr(cn, "FBReel") != NULL ||
                   strstr(cn, "FBShorts") != NULL)) {
            tryLazyInstallShortsSideBarHook();
        }
        // Always log VC class (for class discovery) - filter out common ones
        if (cn && (strstr(cn, "FB") || strstr(cn, "Feed") || strstr(cn, "Reel"))) {
            BOOL common = (strstr(cn, "NewsFeed") != NULL) ||
                         (strstr(cn, "TopBar") != NULL) ||
                         (strstr(cn, "Navigation") != NULL) ||
                         (strstr(cn, "StackView") != NULL) ||
                         (strstr(cn, "BottomSheet") != NULL) ||
                         (strstr(cn, "Comment") != NULL) ||
                         (strstr(cn, "Window") != NULL) ||
                         (strstr(cn, "View") == NULL);
            if (!common) {
                LOG("[disc] VC: %s\n", cn);
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// SECTION 7: %ctor - init
// ═══════════════════════════════════════════════════════════════

__attribute__((constructor))
static void glow_init(void) {
    const char *home = getenv("HOME");
    if (home) snprintf(g_log_path, sizeof(g_log_path), "%s/Documents/glow.txt", home);
    LOG("\n=== Glow v8.2.34 (R3.5+v8.2) — %s ===\n", __DATE__ " " __TIME__);

    // Load preferences
    reloadPrefs();

    // Listen for changes from Settings.app
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        (CFNotificationCallback)prefsChanged,
        CFSTR("com.tommy.glow.prefsChanged"),
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );

    // Defer hook installation to main queue
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            Class vcClass = objc_getClass("UIViewController");
            if (vcClass) {
                Method m = class_getInstanceMethod(vcClass, @selector(viewDidAppear:));
                if (m) {
                    orig_viewDidAppear = method_getImplementation(m);
                    method_setImplementation(m, (IMP)hooked_viewDidAppear);
                    LOG("[ctor] viewDidAppear hook installed\n");
                }
            }
        } @catch (...) {}

        // Also install long press after a short delay (catches late UI)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{
            @try { installLongPressOnCurrentUI(); } @catch (...) {}
        });
    });
}
