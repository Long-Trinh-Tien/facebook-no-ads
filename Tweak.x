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
// SECTION 2: Settings UI
// ═══════════════════════════════════════════════════════════════

// Forward decl
@class GlowSettingsViewController;

@interface GlowSettingsViewController : UIViewController
@end

@implementation GlowSettingsViewController {
    UITableView *_tableView;
    NSArray<NSDictionary *> *_items;
}

- (instancetype)init {
    if ((self = [super init])) {
        self.title = @"Glow v8";
        _items = @[
            @{@"section": @"Ad Blocking", @"rows": @[
                @{@"key": @"removeAds", @"label": @"Remove Ads", @"value": @(s_removeAds)},
            ]},
            @{@"section": @"Privacy", @"rows": @[
                @{@"key": @"disableStorySeen", @"label": @"Disable Story Seen", @"value": @(s_disableStorySeen)},
            ]},
            @{@"section": @"Downloads (not yet implemented)", @"rows": @[
                @{@"key": @"downloadVideo", @"label": @"Download Video (long press)", @"value": @(s_downloadVideo)},
                @{@"key": @"downloadStory", @"label": @"Download Story (button)", @"value": @(s_downloadStory)},
            ]},
            @{@"section": @"Hide UI (not yet implemented)", @"rows": @[
                @{@"key": @"removePYMK", @"label": @"Hide People You May Know", @"value": @(s_removePYMK)},
                @{@"key": @"removeReelsCarousel", @"label": @"Hide Reels Carousel", @"value": @(s_removeReelsCarousel)},
                @{@"key": @"removeSuggested", @"label": @"Hide Suggested for You", @"value": @(s_removeSuggested)},
                @{@"key": @"hideComposer", @"label": @"Hide Composer", @"value": @(s_hideComposer)},
            ]},
            @{@"section": @"Reels (not yet implemented)", @"rows": @[
                @{@"key": @"disableAutoNext", @"label": @"Disable Auto-Advance Reels", @"value": @(s_disableAutoNext)},
                @{@"key": @"confirmLike", @"label": @"Confirm Reels Like", @"value": @(s_confirmLike)},
                @{@"key": @"markAsSeen", @"label": @"Mark Story as Seen", @"value": @(s_markAsSeen)},
            ]},
            @{@"section": @"Other (not yet implemented)", @"rows": @[
                @{@"key": @"clearCacheOnLaunch", @"label": @"Clear Cache on Launch", @"value": @(s_clearCacheOnLaunch)},
                @{@"key": @"notifyUpdates", @"label": @"Notify Updates", @"value": @(s_notifyUpdates)},
            ]},
        ];
    }
    return self;
}

- (void)loadView {
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view = _tableView;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return _items.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [_items[section][@"rows"] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return _items[section][@"section"];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellId];
    }
    NSDictionary *row = _items[indexPath.section][@"rows"][indexPath.row];
    cell.textLabel.text = row[@"label"];
    BOOL val = [row[@"value"] boolValue];
    cell.accessoryType = val ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.userInteractionEnabled = YES;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *row = _items[indexPath.section][@"rows"][indexPath.row];
    NSString *key = row[@"key"];
    NSString *label = row[@"label"];

    // Toggle
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    BOOL current = [d boolForKey:[@"com.tommy.glow." stringByAppendingString:key]];
    BOOL newVal = !current;
    [d setBool:newVal forKey:[@"com.tommy.glow." stringByAppendingString:key]];
    [d synchronize];

    reloadPrefs();

    // Update UI
    NSMutableArray *newItems = [_items mutableCopy];
    NSMutableArray *newRows = [newItems[indexPath.section][@"rows"] mutableCopy];
    newRows[indexPath.row] = @{@"key": key, @"label": label, @"value": @(newVal)};
    newItems[indexPath.section] = @{@"section": newItems[indexPath.section][@"section"], @"rows": newRows};
    _items = newItems;
    [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];

    LOG("[settings] toggled %s = %d (re-installation required for hook change)\n", key.UTF8String, newVal);

    // Show feedback
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:label message:newVal ? @"Enabled" : @"Disabled" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

// Open settings - find root VC robustly
static void openGlowSettings(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            GlowSettingsViewController *vc = [[GlowSettingsViewController alloc] init];
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
            nav.modalPresentationStyle = UIModalPresentationFormSheet;

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
