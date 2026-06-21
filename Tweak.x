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
static BOOL s_downloadReels = NO;
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
@end
@implementation GlowVideoDownloadHandler

// Reels-specific: long press on Reel video view
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
        LOG("[dl/reel] downloading HD=%d SD=%d\n", hd != nil, sd != nil);
        if (hd) [self downloadVideoURL:hd quality:@"reel_hd"];
        if (sd) [self downloadVideoURL:sd quality:@"reel_sd"];
    } @catch (NSException *e) {
        LOG("[dl/reel] exc: %s\n", e.reason.UTF8String);
    }
}

- (void)downloadVideoURL:(NSURL *)url quality:(NSString *)q {
    if (!url) return;
    NSString *name = [NSString stringWithFormat:@"video_%@_%lld.mp4", q, (long long)[[NSDate date] timeIntervalSince1970]];
    NSURLRequest *req = [NSURLRequest requestWithURL:url];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
    NSURLSessionDownloadTask *task = [session downloadTaskWithRequest:req completionHandler:^(NSURL *loc, NSURLResponse *resp, NSError *err) {
        if (err || !loc) { LOG("[dl/video] err: %s\n", err ? [[err localizedDescription] UTF8String] : "nil"); return; }
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
        [[NSFileManager defaultManager] moveItemAtURL:loc toURL:[NSURL fileURLWithPath:path] error:nil];
        LOG("[dl/video] saved to %s\n", [path UTF8String]);
        dispatch_async(dispatch_get_main_queue(), ^{
            UISaveVideoAtPathToSavedPhotosAlbum(path, nil, nil, NULL);
            LOG("[dl/video] saved video to Photos\n");
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

// Reels button overlay: hook viewDidAppear (after view is on screen)
// Add a floating download button on the right side of the Reel
static IMP orig_reelsViewDidLoad = NULL;
static NSMutableSet *g_reelsViewsWithButton = nil;

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
    LOG("[dl/reel] button tapped on %s\n", class_getName(object_getClass(sender.superview)));
    // Walk up to find currentVideoPlaybackItem
    UIView *v = sender.superview;
    SEL curSel = sel_registerName("currentVideoPlaybackItem");
    id item = nil;
    int depth = 0;
    while (v && depth < 10) {
        @try {
            if ([v respondsToSelector:curSel]) {
                item = [v performSelector:curSel];
                if (item) break;
            }
            // Try KVC for controller
            id controller = [v valueForKey:@"controller"];
            if (controller && [controller respondsToSelector:curSel]) {
                item = [controller performSelector:curSel];
                if (item) break;
            }
        } @catch (...) {}
        v = v.superview;
        depth++;
    }
    if (!item) { LOG("[dl/reel] no playback item found\n"); return; }
    SEL hdSel = sel_registerName("HDPlaybackURL");
    SEL sdSel = sel_registerName("SDPlaybackURL");
    NSURL *hd = [item respondsToSelector:hdSel] ? [item performSelector:hdSel] : nil;
    NSURL *sd = [item respondsToSelector:sdSel] ? [item performSelector:sdSel] : nil;
    if (!hd && !sd) { LOG("[dl/reel] item has no URLs\n"); return; }
    LOG("[dl/reel] downloading HD=%d SD=%d\n", hd != nil, sd != nil);
    if (!g_videoHandler) g_videoHandler = [[GlowVideoDownloadHandler alloc] init];
    if (hd) [g_videoHandler downloadVideoURL:hd quality:@"reel_hd"];
    if (sd) [g_videoHandler downloadVideoURL:sd quality:@"reel_sd"];
    // Visual feedback
    sender.enabled = NO;
    sender.backgroundColor = [UIColor colorWithRed:0 green:0.7 blue:0 alpha:0.7];
    [sender setTitle:@"✓" forState:UIControlStateNormal];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        sender.enabled = YES;
        sender.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
        [sender setTitle:@"⬇" forState:UIControlStateNormal];
    });
}
@end
static GlowReelButtonHandler *g_reelButtonHandler = nil;

// Helper: remove all GlowReelButton-tagged buttons from a view (and keyWindow)
static void removeReelButtons(UIView *v) {
    if (!v) return;
    // Walk subviews, remove anything tagged as GlowReelButton
    for (UIView *sub in [v.subviews copy]) {
        if ([sub.accessibilityIdentifier isEqualToString:@"GlowReelButton"]) {
            [sub removeFromSuperview];
        }
    }
    // Also remove from keyWindow
    @try {
        UIWindow *keyWin = nil;
        for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *ws = (UIWindowScene *)s;
                for (UIWindow *w in ws.windows) {
                    if (w.isKeyWindow) { keyWin = w; break; }
                }
                if (keyWin) break;
            }
        }
        if (keyWin) {
            for (UIView *sub in [keyWin.subviews copy]) {
                if ([sub.accessibilityIdentifier isEqualToString:@"GlowReelButtonKeyWin"]) {
                    [sub removeFromSuperview];
                }
            }
        }
    } @catch (NSException *e) {}
}

// Reels viewWillDisappear: hook — clean up button when user leaves Reels
static IMP orig_reelsViewWillDisappear = NULL;
static void hooked_reelsViewWillDisappear(id self, SEL _cmd, BOOL animated) {
    if (orig_reelsViewWillDisappear) {
        typedef void (*FnType)(id, SEL, BOOL);
        FnType fn = (FnType)(uintptr_t)orig_reelsViewWillDisappear;
        fn(self, _cmd, animated);
    }
    @try {
        UIView *v = nil;
        if ([self isKindOfClass:[UIViewController class]]) {
            v = [(UIViewController *)self view];
        } else if ([self isKindOfClass:[UIView class]]) {
            v = (UIView *)self;
        }
        if (!v) return;
        removeReelButtons(v);
        // Also remove from set so future viewWillAppear: will re-add
        if (g_reelsViewsWithButton) {
            [g_reelsViewsWithButton removeObject:[NSValue valueWithNonretainedObject:v]];
        }
        LOG("[reels/VWD] %s - removed button(s)\n", class_getName(object_getClass(self)));
    } @catch (NSException *e) {
        LOG("[reels/VWD] exc: %s\n", e.reason.UTF8String);
    }
}

// v8.2.16: Find FBShortsSideBarView (the right action column) and add
// button DIRECTLY inside it, as a sibling of Like/Comment/Share.
// FBShortsSideBarView contains the like/share column at the right side
// of every Reel. Adding our button as its child ensures:
// 1. Same parent as native action buttons (correct z-order, correct layer)
// 2. Auto-cleanup with the Reel
// 3. Position automatically below the "More" button
static UIView *findShortsSideBarView(UIView *root) {
    if (!root) return nil;
    @try {
        Class cls = object_getClass(root);
        const char *name = class_getName(cls);
        if (name && strstr(name, "FBShortsSideBarView") != NULL) {
            return root;
        }
        for (UIView *sub in root.subviews) {
            UIView *found = findShortsSideBarView(sub);
            if (found) return found;
        }
    } @catch (...) {}
    return nil;
}

// v8.2.15: Keep for fallback
static UIView *findPassthroughView(UIView *root) {
    if (!root) return nil;
    @try {
        Class cls = object_getClass(root);
        const char *name = class_getName(cls);
        if (name && strstr(name, "PassthroughView") != NULL) {
            return root;
        }
        for (UIView *sub in root.subviews) {
            UIView *found = findPassthroughView(sub);
            if (found) return found;
        }
    } @catch (...) {}
    return nil;
}

// Reels viewWillAppear: hook (fires every time VC appears, not just first)
static void hooked_reelsViewWillAppear(id self, SEL _cmd, BOOL animated) {
    if (!s_downloadVideo) return;
    @try {
        UIView *v = nil;
        if ([self isKindOfClass:[UIViewController class]]) {
            v = [(UIViewController *)self view];
        } else if ([self isKindOfClass:[UIView class]]) {
            v = (UIView *)self;
        }
        if (!v) {
            LOG("[reels/VWA] %s - no view\n", class_getName(object_getClass(self)));
            return;
        }
        if (!g_reelsViewsWithButton) g_reelsViewsWithButton = [[NSMutableSet alloc] init];
        if (!g_reelButtonHandler) g_reelButtonHandler = [[GlowReelButtonHandler alloc] init];
        NSValue *vkey = [NSValue valueWithNonretainedObject:v];
        if ([g_reelsViewsWithButton containsObject:vkey]) return;  // already added
        [g_reelsViewsWithButton addObject:vkey];

        CGRect screenBounds = [UIScreen mainScreen].bounds;
        CGFloat W = v.bounds.size.width > 100 ? v.bounds.size.width : screenBounds.size.width;
        CGFloat H = v.bounds.size.height > 100 ? v.bounds.size.height : screenBounds.size.height;
        CGFloat btnSize = 50;

        // v8.2.15: Find the FBVideoHomePassthroughView (full screen overlay
        // that contains like/share). Add button as its subview so it sits
        // in the same view layer.
        UIView *passthrough = findPassthroughView(v);
        UIView *targetView = passthrough ? passthrough : v;
        LOG("[reels/VWA] PassthroughView found: %s\n",
            passthrough ? "YES" : "NO");
        LOG("[reels/VWA] Target view: %s\n",
            class_getName(object_getClass(targetView)));

        // Position at right side, around y=300 (middle of where like/share column is)
        CGFloat btnX = W - btnSize - 16;
        CGFloat btnY = 250;  // below top bar (~100), above mid-screen

        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.frame = CGRectMake(btnX, btnY, btnSize, btnSize);
        btn.layer.cornerRadius = btnSize/2;
        btn.backgroundColor = [UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:1.0];
        [btn setTitle:@"⬇" forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont systemFontOfSize:26 weight:UIFontWeightBold];
        btn.layer.borderWidth = 2;
        btn.layer.borderColor = [UIColor whiteColor].CGColor;
        // Tag the button for cleanup on viewWillDisappear
        btn.accessibilityIdentifier = @"GlowReelButton";
        // Force button to be on top of all other layers
        btn.layer.zPosition = 9999;
        [btn addTarget:g_reelButtonHandler action:@selector(onReelButtonTap:) forControlEvents:UIControlEventTouchUpInside];
        [targetView addSubview:btn];
        [targetView bringSubviewToFront:btn];
        // Walk up and bring each ancestor to front too
        UIView *ancestor = targetView.superview;
        while (ancestor) {
            [ancestor bringSubviewToFront:targetView];
            ancestor = ancestor.superview;
        }
        // ALSO add to keyWindow with zPosition for absolute on-top
        @try {
            UIWindow *keyWin = nil;
            for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
                if ([s isKindOfClass:[UIWindowScene class]]) {
                    UIWindowScene *ws = (UIWindowScene *)s;
                    for (UIWindow *w in ws.windows) {
                        if (w.isKeyWindow) { keyWin = w; break; }
                    }
                    if (keyWin) break;
                }
            }
            if (keyWin && btn.superview != keyWin) {
                // Make a separate button on keyWindow to ensure it's on top
                UIButton *keyBtn = [UIButton buttonWithType:UIButtonTypeCustom];
                keyBtn.frame = CGRectMake(btnX, btnY, btnSize, btnSize);
                keyBtn.layer.cornerRadius = btnSize/2;
                keyBtn.backgroundColor = [UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:1.0];
                [keyBtn setTitle:@"⬇" forState:UIControlStateNormal];
                [keyBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
                keyBtn.titleLabel.font = [UIFont systemFontOfSize:26 weight:UIFontWeightBold];
                keyBtn.layer.borderWidth = 2;
                keyBtn.layer.borderColor = [UIColor whiteColor].CGColor;
                keyBtn.layer.zPosition = 99999;
                keyBtn.accessibilityIdentifier = @"GlowReelButtonKeyWin";
                [keyBtn addTarget:g_reelButtonHandler action:@selector(onReelButtonTap:) forControlEvents:UIControlEventTouchUpInside];
                [keyWin addSubview:keyBtn];
                [keyWin bringSubviewToFront:keyBtn];
                LOG("[reels/VWA] ALSO added keyWindow button at (%.0f,%.0f)\n", btnX, btnY);
            }
        } @catch (NSException *e) {
            LOG("[reels/VWA] keyWin exc: %s\n", e.reason.UTF8String);
        }
        LOG("[reels/VWA] ADDED BUTTON to %s W=%.0f H=%.0f at (%.0f,%.0f)\n",
            class_getName(object_getClass(targetView)), W, H, btnX, btnY);

        // Add tap recognizer to log what user taps (helps find like button class)
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
            initWithTarget:g_reelButtonHandler action:@selector(onReelTap:)];
        tap.cancelsTouchesInView = NO;
        tap.numberOfTapsRequired = 1;
        [v addGestureRecognizer:tap];
    } @catch (NSException *e) {
        LOG("[reels/VWA] exc: %s\n", e.reason.UTF8String);
    }
}

// (legacy hook - kept for compatibility)
static void hooked_reelsViewDidLoad(id self, SEL _cmd) {
    if (orig_reelsViewDidLoad) {
        typedef void (*FnType)(id, SEL);
        FnType fn = (FnType)(uintptr_t)orig_reelsViewDidLoad;
        fn(self, _cmd);
    }
    if (!s_downloadVideo) return;
    @try {
        if (!g_reelsViewsWithButton) g_reelsViewsWithButton = [[NSMutableSet alloc] init];
        if (!g_reelButtonHandler) g_reelButtonHandler = [[GlowReelButtonHandler alloc] init];
        UIView *v = nil;
        if ([self isKindOfClass:[UIViewController class]]) {
            v = [(UIViewController *)self view];
        } else if ([self isKindOfClass:[UIView class]]) {
            v = (UIView *)self;
        }
        if (!v) { LOG("[reels] no view found\n"); return; }
        if (![v isKindOfClass:[UIView class]]) return;
        if ([g_reelsViewsWithButton containsObject:[NSValue valueWithNonretainedObject:v]]) return;
        // Use dispatch_after to wait for layout to complete
        // viewDidLoad fires BEFORE layout, so bounds might be 0
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            @try {
                // Get screen bounds as fallback
                CGRect screenBounds = [UIScreen mainScreen].bounds;
                CGFloat W = v.bounds.size.width;
                CGFloat H = v.bounds.size.height;
                if (W < 100) W = screenBounds.size.width;
                if (H < 100) H = screenBounds.size.height;
                if (W < 100 || H < 100) return;
                if ([g_reelsViewsWithButton containsObject:[NSValue valueWithNonretainedObject:v]]) return;
                [g_reelsViewsWithButton addObject:[NSValue valueWithNonretainedObject:v]];
                CGFloat btnSize = 44;
                CGFloat btnX = W - btnSize - 16;
                CGFloat btnY = H - 200;  // above tab bar + safe area
                UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
                btn.frame = CGRectMake(btnX, btnY, btnSize, btnSize);
                btn.layer.cornerRadius = btnSize/2;
                btn.backgroundColor = [UIColor colorWithRed:1.0 green:0.3 blue:0.3 alpha:0.9];
                [btn setTitle:@"⬇" forState:UIControlStateNormal];
                [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
                btn.titleLabel.font = [UIFont systemFontOfSize:24 weight:UIFontWeightBold];
                [btn addTarget:g_reelButtonHandler action:@selector(onReelButtonTap:) forControlEvents:UIControlEventTouchUpInside];
                [v addSubview:btn];
                // Bring to front
                [v bringSubviewToFront:btn];
                LOG("[reels] added download button to %s frame=(%.0f,%.0f,%.0f,%.0f) at (%.0f,%.0f)\n",
                    class_getName(object_getClass(v)), v.frame.origin.x, v.frame.origin.y, W, H, btnX, btnY);
            } @catch (NSException *e) {
                LOG("[reels] button exc: %s\n", e.reason.UTF8String);
            }
        });
    } @catch (NSException *e) {
        LOG("[reels] exc: %s\n", e.reason.UTF8String);
    }
}

// v8.2.16: Hook FBShortsSideBarView.layoutSubviews to add download button
// DIRECTLY as a child of the sidebar (same parent as like/share).
// This guarantees the button is in the same column with correct z-order.
//
// From R4 v1.6 log, the structure is:
//   FBShortsViewerOverlayComponentView
//     FBPassthroughView (content overlay)
//       FBShortsSideBarView (360,0,56,333) — RIGHT ACTION COLUMN
//         FDSTouchStateAnnouncingControl (0,0,56,72)   Like
//         FDSTouchStateAnnouncingControl (0,72,56,72)  Comment
//         FDSTouchStateAnnouncingControl (0,145,56,72) Share
//         FDSTouchStateAnnouncingControl (0,217,56,72) Save
//         FDSTouchStateAnnouncingControl (0,289,56,44) More
//       FBShortsDescriptionView
//       ...
//
// We add our button at (0, 333, 56, 72) - right below "More".
static NSMutableSet *g_sideBarsWithButton = nil;
static IMP orig_shortsSideBarLayoutSubviews = NULL;
static void hooked_shortsSideBarLayoutSubviews(id self, SEL _cmd) {
    if (orig_shortsSideBarLayoutSubviews) {
        typedef void (*FnType)(id, SEL);
        FnType fn = (FnType)(uintptr_t)orig_shortsSideBarLayoutSubviews;
        fn(self, _cmd);
    }
    if (!s_downloadVideo) return;
    @try {
        if (![self isKindOfClass:[UIView class]]) return;
        UIView *sideBar = (UIView *)self;
        if (!g_sideBarsWithButton) g_sideBarsWithButton = [[NSMutableSet alloc] init];
        if (!g_reelButtonHandler) g_reelButtonHandler = [[GlowReelButtonHandler alloc] init];
        NSValue *vkey = [NSValue valueWithNonretainedObject:sideBar];
        if ([g_sideBarsWithButton containsObject:vkey]) return;
        // Skip if hidden (suggests off-screen)
        if (sideBar.hidden || sideBar.alpha < 0.01) return;
        // Skip if size is too small (0x0 or 56x0)
        if (sideBar.bounds.size.width < 20 || sideBar.bounds.size.height < 100) return;
        [g_sideBarsWithButton addObject:vkey];

        // Sidebar width 56, height varies (333 in test, but we use bounds)
        CGFloat W = sideBar.bounds.size.width;
        CGFloat H = sideBar.bounds.size.height;
        CGFloat btnW = 40;   // smaller than like (56) to fit
        CGFloat btnH = 40;
        // Place at top-right of sidebar (above "Like") so it's
        // at the start of the action column, very visible
        CGFloat btnX = (W - btnW) / 2.0;  // center horizontally
        CGFloat btnY = -btnH - 8;  // ABOVE the sidebar (negative y)

        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.frame = CGRectMake(btnX, btnY, btnW, btnH);
        btn.layer.cornerRadius = btnH / 2.0;
        btn.backgroundColor = [UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:1.0];
        [btn setTitle:@"⬇" forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
        btn.layer.borderWidth = 2;
        btn.layer.borderColor = [UIColor whiteColor].CGColor;
        btn.accessibilityIdentifier = @"GlowReelButton";
        btn.layer.zPosition = 9999;
        [btn addTarget:g_reelButtonHandler action:@selector(onReelButtonTap:) forControlEvents:UIControlEventTouchUpInside];
        [sideBar addSubview:btn];
        [sideBar bringSubviewToFront:btn];
        LOG("[reels/sidebar] ADDED button to %s W=%.0f H=%.0f at (%.0f,%.0f,%.0f,%.0f)\n",
            class_getName(object_getClass(sideBar)), W, H, btnX, btnY, btnW, btnH);
    } @catch (NSException *e) {
        LOG("[reels/sidebar] exc: %s\n", e.reason.UTF8String);
    }
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
static IMP orig_viewDidLoad = NULL;

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

        // Hook 9: Download Video - hook didLongPress:
        if (s_downloadVideo) {
            Class cls = objc_getClass("FBVideoOverlayPluginComponentBackgroundView");
            if (cls) {
                SEL sel = sel_registerName("didLongPress:");
                Method m = class_getInstanceMethod(cls, sel);
                if (m) {
                    orig_didLongPress = method_getImplementation(m);
                    method_setImplementation(m, (IMP)hooked_didLongPress);
                    LOG("  hook #9: FBVideoOverlayPluginComponentBackgroundView.didLongPress: -> download video\n");
                } else {
                    LOG("  didLongPress: NOT FOUND\n");
                }
            }
        }

        // Hook 10: Reels download - hook FBVideoHomeUnifiedPlayerViewController.viewDidLoad
        // When Reels player loads, walk view hierarchy, find video view, add long press
        if (s_downloadVideo) {
            Class reelsCls = objc_getClass("FBVideoHomeUnifiedPlayerViewController");
            if (reelsCls) {
                SEL vdlSel = @selector(viewDidLoad);
                Method m = class_getInstanceMethod(reelsCls, vdlSel);
                if (m) {
                    orig_reelsViewDidLoad = method_getImplementation(m);
                    method_setImplementation(m, (IMP)hooked_reelsViewDidLoad);
                    LOG("  hook #10: FBVideoHomeUnifiedPlayerViewController.viewDidLoad -> add reel download\n");
                } else {
                    LOG("  FBVideoHomeUnifiedPlayerViewController.viewDidLoad NOT FOUND\n");
                }
            } else {
                LOG("  FBVideoHomeUnifiedPlayerViewController NOT FOUND\n");
            }

            // v8.2.16: Hook FBShortsSideBarView.layoutSubviews
            // FBShortsSideBarView is the right action column in Reels
            // (contains like/comment/share/save/more). Adding our button
            // as its child puts it in the same view as the native buttons,
            // guaranteeing correct layer and z-order.
            Class sideBarCls = objc_getClass("FBShortsSideBarView");
            if (sideBarCls) {
                SEL lsSel = @selector(layoutSubviews);
                Method m2 = class_getInstanceMethod(sideBarCls, lsSel);
                if (m2) {
                    orig_shortsSideBarLayoutSubviews = method_getImplementation(m2);
                    method_setImplementation(m2, (IMP)hooked_shortsSideBarLayoutSubviews);
                    LOG("  hook #11: FBShortsSideBarView.layoutSubviews -> add download button as child\n");
                } else {
                    LOG("  FBShortsSideBarView.layoutSubviews NOT FOUND\n");
                }
            } else {
                LOG("  FBShortsSideBarView NOT FOUND (will retry when Reels opens)\n");
                // Lazy install when Reels VC appears
                orig_shortsSideBarLayoutSubviews = NULL;  // mark for lazy install
            }
        }

        LOG("=== Done ===\n");
    } @catch (NSException *e) {
        LOG("  EXC: %s\n", e.reason.UTF8String);
    } @catch (...) {
        LOG("  EXC(c++)\n");
    }
}

// (Reels hooks declared above installHooks)

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
        // Always log VC class (for class discovery) - filter out common ones
        if (cn && (strstr(cn, "FB") || strstr(cn, "Feed") || strstr(cn, "Reel"))) {
            // Skip common ones we already know
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
            // Lazy install: hook Reels classes when they appear
            if (s_downloadVideo &&
                (strstr(cn, "FBVideoHome") != NULL || strstr(cn, "FBReel") != NULL)) {
                // Strip NSKVONotifying_ prefix
                const char *real = cn;
                if (strncmp(cn, "NSKVONotifying_", 15) == 0) real = cn + 15;
                NSString *clsName = [NSString stringWithUTF8String:real];
                Class reelsCls = NSClassFromString(clsName);
                if (reelsCls) {
                    // Hook viewWillAppear: - fires every time VC appears
                    // Try to hook on the actual class (not the KVO wrapper)
                    SEL vwaSel = @selector(viewWillAppear:);
                    Method mwa = class_getInstanceMethod(reelsCls, vwaSel);
                    if (mwa) {
                        // Use class_replaceMethod to override globally
                        // This works for both the class and its KVO subclass
                        Method mwa_super = class_getInstanceMethod(class_getSuperclass(reelsCls), vwaSel);
                        if (mwa_super) {
                            // Override on the actual class
                            method_setImplementation(mwa_super, (IMP)hooked_reelsViewWillAppear);
                            // For KVO subclass, also override
                            Method mwa_sub = class_getInstanceMethod(reelsCls, vwaSel);
                            if (mwa_sub != mwa_super) {
                                method_setImplementation(mwa_sub, (IMP)hooked_reelsViewWillAppear);
                            }
                            LOG("[reels] HOOKED viewWillAppear on %s\n", [clsName UTF8String]);
                        } else {
                            method_setImplementation(mwa, (IMP)hooked_reelsViewWillAppear);
                            LOG("[reels] HOOKED viewWillAppear on %s (no super)\n", [clsName UTF8String]);
                        }
                    }
                    // Also hook viewWillDisappear: to remove button when user leaves Reels
                    SEL vwdSel = @selector(viewWillDisappear:);
                    Method mwd = class_getInstanceMethod(reelsCls, vwdSel);
                    if (mwd) {
                        Method mwd_super = class_getInstanceMethod(class_getSuperclass(reelsCls), vwdSel);
                        if (mwd_super) {
                            orig_reelsViewWillDisappear = method_getImplementation(mwd_super);
                            method_setImplementation(mwd_super, (IMP)hooked_reelsViewWillDisappear);
                            Method mwd_sub = class_getInstanceMethod(reelsCls, vwdSel);
                            if (mwd_sub != mwd_super) {
                                method_setImplementation(mwd_sub, (IMP)hooked_reelsViewWillDisappear);
                            }
                            LOG("[reels] HOOKED viewWillDisappear on %s\n", [clsName UTF8String]);
                        } else {
                            orig_reelsViewWillDisappear = method_getImplementation(mwd);
                            method_setImplementation(mwd, (IMP)hooked_reelsViewWillDisappear);
                            LOG("[reels] HOOKED viewWillDisappear on %s (no super)\n", [clsName UTF8String]);
                        }
                    }
                }
            }
        }
        // Reels discovery: try to find video view in this VC
        if (cn) {
            @try {
                UIViewController *vcSelf = (UIViewController *)self;
                UIView *v = vcSelf.view;
                Class videoContainerCls = NSClassFromString(@"VideoContainerView");
                // Walk children looking for a view that has a video item
                NSMutableArray *queue = [NSMutableArray arrayWithObject:v];
                int depth = 0;
                int foundCount = 0;
                while (queue.count > 0 && depth < 25 && foundCount < 3) {
                    UIView *cur = [queue firstObject];
                    [queue removeObjectAtIndex:0];
                    @try {
                        if (videoContainerCls && [cur isKindOfClass:videoContainerCls]) {
                            LOG("[reels] found VideoContainerView at depth %d\n", depth);
                            foundCount++;
                        }
                    } @catch (...) {}
                    for (UIView *sub in cur.subviews) [queue addObject:sub];
                    depth++;
                }
            } @catch (...) {}
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
    LOG("\n=== Glow v8.2.16 (R3.5+v8.2) — %s ===\n", __DATE__ " " __TIME__);

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
