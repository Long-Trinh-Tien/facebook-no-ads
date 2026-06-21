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
static BOOL s_downloadVideo = NO;     // not implemented yet
static BOOL s_downloadStory = NO;     // not implemented yet
static BOOL s_removePYMK = NO;         // not implemented yet
static BOOL s_removeReelsCarousel = NO;// not implemented yet
static BOOL s_removeSuggested = NO;    // not implemented yet
static BOOL s_hideComposer = NO;       // not implemented yet
static BOOL s_disableAutoNext = NO;    // not implemented yet
static BOOL s_confirmLike = NO;        // not implemented yet
static BOOL s_markAsSeen = NO;         // not implemented yet
static BOOL s_clearCacheOnLaunch = NO; // not implemented yet
static BOOL s_notifyUpdates = NO;      // not implemented yet

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
    s_markAsSeen = [d boolForKey:@"com.tommy.glow.markAsSeen"];
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
                @{@"key": @"downloadReels", @"title": @"downloadReels", @"subtitle": @"", @"value": @NO},
                @{@"key": @"hideOverlay", @"title": @"hideOverlay", @"subtitle": @"", @"value": @NO},
                @{@"key": @"confirmReelsLike", @"title": @"confirmReelsLike", @"subtitle": @"", @"value": @NO},
                @{@"key": @"downloadLongPress", @"title": @"downloadLongPress", @"subtitle": @"downloadLongPress.desc", @"value": @NO},
            ],
            @[  // STORIES
                @{@"key": @"downloadStory", @"title": @"downloadStory", @"subtitle": @"", @"value": @(s_downloadStory)},
                @{@"key": @"disableStorySeen", @"title": @"disableStorySeen", @"subtitle": @"", @"value": @(s_disableStorySeen)},
                @{@"key": @"disableAutoNext", @"title": @"disableAutoNext", @"subtitle": @"", @"value": @(s_disableAutoNext)},
                @{@"key": @"removeStoryPYMK", @"title": @"removeStoryPYMK", @"subtitle": @"", @"value": @NO},
            ],
            @[  // TRÌNH TẢI VIDEO
                @{@"key": @"allFormats", @"title": @"allFormats", @"subtitle": @"", @"value": @NO},
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
        LOG("[ui] long press detected on %s\n", class_getName(object_getClass(gr.view)));
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
                    [cs isEqualToString:@"IN_STREAM_AD"]) {
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
                    [cs isEqualToString:@"IN_STREAM_AD"]) {
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
// Add a download button to the view.

@interface GlowStoryDownloadHandler : NSObject
@end
@implementation GlowStoryDownloadHandler

- (void)onStoryDownloadTap:(UIButton *)sender {
    @try {
        UIView *container = (UIView *)sender.superview;
        Class storyCls = NSClassFromString(@"FBSnacksMediaContainerView");
        while (container && ![container isKindOfClass:storyCls]) {
            container = container.superview;
        }
        if (!container) { LOG("[dl/story] container not found\n"); return; }
        // Get mediaView via ivar _mediaView (UIView<FBSnacksMediaViewProtocol>)
        Ivar mvIvar = class_getInstanceVariable(object_getClass(container), "_mediaView");
        id mediaView = mvIvar ? object_getIvar(container, mvIvar) : nil;
        if (!mediaView) { LOG("[dl/story] mediaView nil\n"); return; }

        // Try FBSnacksNewVideoView
        Class videoCls = NSClassFromString(@"FBSnacksNewVideoView");
        if (videoCls && [mediaView isKindOfClass:videoCls]) {
            // Get manager
            SEL mgrSel = sel_registerName("manager");
            id mgr = [mediaView respondsToSelector:mgrSel] ? [mediaView performSelector:mgrSel] : nil;
            if (!mgr) { LOG("[dl/story] manager nil\n"); return; }
            SEL curSel = sel_registerName("currentVideoPlaybackItem");
            id item = [mgr respondsToSelector:curSel] ? [mgr performSelector:curSel] : nil;
            if (!item) { LOG("[dl/story] no playback item\n"); return; }
            SEL hdSel = sel_registerName("HDPlaybackURL");
            NSURL *url = [item respondsToSelector:hdSel] ? [item performSelector:hdSel] : nil;
            if (!url) {
                SEL sdSel = sel_registerName("SDPlaybackURL");
                url = [item respondsToSelector:sdSel] ? [item performSelector:sdSel] : nil;
            }
            if (url) {
                LOG("[dl/story] video URL: %s\n", [[url absoluteString] UTF8String]);
                [self downloadURL:url toFileName:[NSString stringWithFormat:@"story_video_%lld.mp4", (long long)[[NSDate date] timeIntervalSince1970]]];
            }
            return;
        }

        // Try FBSnacksPhotoView
        Class photoCls = NSClassFromString(@"FBSnacksPhotoView");
        if (photoCls && [mediaView isKindOfClass:photoCls]) {
            // Walk: FBSnacksPhotoView._photoView (FBSnacksWebPhotoView) -> _photoView (FBWebPhotoView) -> .photo
            Ivar swpvIvar = class_getInstanceVariable(object_getClass(mediaView), "_photoView");
            id swpv = swpvIvar ? object_getIvar(mediaView, swpvIvar) : nil;
            if (!swpv) { LOG("[dl/story] FBSnacksWebPhotoView nil\n"); return; }
            Class webPhotoCls = NSClassFromString(@"FBSnacksWebPhotoView");
            if (![swpv isKindOfClass:webPhotoCls]) { LOG("[dl/story] not FBSnacksWebPhotoView: %s\n", class_getName(object_getClass(swpv))); return; }
            Ivar wpvIvar = class_getInstanceVariable(object_getClass(swpv), "_photoView");
            id wpv = wpvIvar ? object_getIvar(swpv, wpvIvar) : nil;
            if (!wpv) { LOG("[dl/story] FBWebPhotoView nil\n"); return; }
            // .photo
            SEL photoSel = sel_registerName("photo");
            id photo = [wpv respondsToSelector:photoSel] ? [wpv performSelector:photoSel] : nil;
            if (!photo) { LOG("[dl/story] photo nil\n"); return; }
            // imageSpecifier — try KVC
            @try {
                id imageSpecifier = [photo valueForKey:@"imageSpecifier"];
                if (!imageSpecifier) { LOG("[dl/story] imageSpecifier nil\n"); return; }
                Class netSpecCls = NSClassFromString(@"FBWebImageNetworkSpecifier");
                Class memSpecCls = NSClassFromString(@"FBWebImageMemorySpecifier");
                if (netSpecCls && [imageSpecifier isKindOfClass:netSpecCls]) {
                    SEL urlsSel = sel_registerName("allInfoURLsSortedByDescImageFlag");
                    NSArray *urls = [imageSpecifier respondsToSelector:urlsSel] ? [imageSpecifier performSelector:urlsSel] : nil;
                    if ([urls isKindOfClass:[NSArray class]] && urls.count > 0) {
                        NSURL *url = urls[0];
                        if ([url isKindOfClass:[NSURL class]]) {
                            LOG("[dl/story] photo URL: %s\n", [[url absoluteString] UTF8String]);
                            [self downloadURL:url toFileName:[NSString stringWithFormat:@"story_photo_%lld.jpg", (long long)[[NSDate date] timeIntervalSince1970]]];
                        }
                    }
                } else if (memSpecCls && [imageSpecifier isKindOfClass:memSpecCls]) {
                    SEL imgSel = sel_registerName("image");
                    UIImage *img = [imageSpecifier respondsToSelector:imgSel] ? [imageSpecifier performSelector:imgSel] : nil;
                    if (img) {
                        UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil);
                        LOG("[dl/story] saved photo to Photos\n");
                    }
                }
            } @catch (NSException *e) {
                LOG("[dl/story] photo exc: %s\n", e.reason.UTF8String);
            }
            return;
        }
        LOG("[dl/story] unknown mediaView class: %s\n", class_getName(object_getClass(mediaView)));
    } @catch (NSException *e) {
        LOG("[dl/story] exc: %s\n", e.reason.UTF8String);
    }
}

- (void)downloadURL:(NSURL *)url toFileName:(NSString *)name {
    NSURLRequest *req = [NSURLRequest requestWithURL:url];
    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];
    NSURLSessionDownloadTask *task = [session downloadTaskWithRequest:req completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        if (error || !location) {
            LOG("[dl/story] download err: %s\n", error ? [[error localizedDescription] UTF8String] : "nil");
            return;
        }
        // Save to Photos
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
        [[NSFileManager defaultManager] moveItemAtURL:location toURL:[NSURL fileURLWithPath:path] error:nil];
        LOG("[dl/story] saved to %s\n", [path UTF8String]);
        dispatch_async(dispatch_get_main_queue(), ^{
            UIImage *img = [UIImage imageWithContentsOfFile:path];
            if (img) {
                UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil);
                LOG("[dl/story] saved image to Photos\n");
            } else {
                // Treat as video
                UISaveVideoAtPathToSavedPhotosAlbum(path, nil, nil, NULL);
                LOG("[dl/story] saved video to Photos\n");
            }
        });
    }];
    [task resume];
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
    if (!s_downloadStory) return result;
    if (!result) return result;
    if (!g_storyHandler) g_storyHandler = [[GlowStoryDownloadHandler alloc] init];
    @try {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.frame = CGRectMake(0, 0, 32, 32);
        [btn setTitle:@"⬇" forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont systemFontOfSize:18];
        btn.layer.cornerRadius = 16;
        btn.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6];
        [btn addTarget:g_storyHandler action:@selector(onStoryDownloadTap:) forControlEvents:UIControlEventTouchUpInside];
        [result addSubview:btn];
        // Top-right corner
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            @try {
                UIView *parent = (UIView *)result;
                CGFloat w = parent.bounds.size.width;
                btn.frame = CGRectMake(w - 44, 60, 32, 32);
            } @catch (...) {}
        });
        LOG("[dl/story] added button to container\n");
    } @catch (NSException *e) {
        LOG("[dl/story] init exc: %s\n", e.reason.UTF8String);
    }
    return result;
}

// ─── Feature 4: Download Video (long press) ───
// Hook FBVideoOverlayPluginComponentBackgroundView.didLongPress:
// Walk view hierarchy to find VideoContainerView, get current playback item.
@interface GlowVideoDownloadHandler : NSObject
@end
@implementation GlowVideoDownloadHandler

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

- (void)onLongPress:(UILongPressGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateBegan) return;
    if (!s_downloadVideo) return;
    @try {
        UIView *v = gr.view;
        // Walk up to find VideoContainerView
        UIView *container = v;
        Class videoContainerCls = NSClassFromString(@"VideoContainerView");
        int maxDepth = 8;
        while (container && maxDepth-- > 0) {
            if (videoContainerCls && [container isKindOfClass:videoContainerCls]) break;
            container = container.superview;
        }
        if (!container) {
            LOG("[dl/video] no VideoContainerView found\n");
            return;
        }
        // Get currentVideoPlaybackItem from container.controller (per Glow 1.3.1)
        // Try KVC: container -> controller -> currentVideoPlaybackItem
        id controller = nil;
        @try {
            controller = [container valueForKey:@"controller"];
        } @catch (...) {}
        if (!controller) {
            // Walk siblings
            for (UIView *sub in container.subviews) {
                @try {
                    controller = [sub valueForKey:@"controller"];
                    if (controller) break;
                } @catch (...) {}
            }
        }
        if (!controller) { LOG("[dl/video] no controller\n"); return; }
        SEL curSel = sel_registerName("currentVideoPlaybackItem");
        id item = [controller respondsToSelector:curSel] ? [controller performSelector:curSel] : nil;
        if (!item) { LOG("[dl/video] no current playback item\n"); return; }
        SEL hdSel = sel_registerName("HDPlaybackURL");
        SEL sdSel = sel_registerName("SDPlaybackURL");
        NSURL *hd = [item respondsToSelector:hdSel] ? [item performSelector:hdSel] : nil;
        NSURL *sd = [item respondsToSelector:sdSel] ? [item performSelector:sdSel] : nil;
        if (hd) [self downloadVideoURL:hd quality:@"hd"];
        if (sd) [self downloadVideoURL:sd quality:@"sd"];
        LOG("[dl/video] downloaded HD=%d SD=%d\n", hd != nil, sd != nil);
    } @catch (NSException *e) {
        LOG("[dl/video] exc: %s\n", e.reason.UTF8String);
    }
}

@end

static GlowVideoDownloadHandler *g_videoHandler = nil;

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
        if (s_downloadStory) {
            Class cls = objc_getClass("FBSnacksMediaContainerView");
            if (cls) {
                SEL sel = sel_registerName("initWithThread:bucket:mediaViewDelegate:mediaViewGenerator:toolbox:shouldBlurMedia:");
                Method m = class_getInstanceMethod(cls, sel);
                if (m) {
                    orig_storyContainer_init = method_getImplementation(m);
                    method_setImplementation(m, (IMP)hooked_storyContainer_init);
                    LOG("  hook #8: FBSnacksMediaContainerView init (new sig) -> add download button\n");
                } else {
                    LOG("  FBSnacksMediaContainerView new init NOT FOUND\n");
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

        LOG("=== Done ===\n");
    } @catch (NSException *e) {
        LOG("  EXC: %s\n", e.reason.UTF8String);
    } @catch (...) {
        LOG("  EXC(c++)\n");
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
        // Re-install long press for new VCs (catches push/pop, tab switches)
        const char *cn = class_getName(object_getClass(self));
        if (cn && (strstr(cn, "ViewController") || strstr(cn, "View"))) {
            dispatch_async(dispatch_get_main_queue(), ^{
                @try { installLongPressOnCurrentUI(); } @catch (...) {}
            });
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
    LOG("\n=== Glow v8.0 (Glow framework port) — %s ===\n", __DATE__ " " __TIME__);

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
