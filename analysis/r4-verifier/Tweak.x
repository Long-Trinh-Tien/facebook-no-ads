// R4 Verifier v3 — Targeted class discovery (no global enumeration)
// Output: /var/mobile/Documents/glow_r4.txt
//
// Why v3: v1/v2 crashed in Phase 2 because objc_getClassList
// returns ~10000 classes, and iterating with strstr + fflush per line
// caused memory/IO pressure, killing the process.
//
// Fix: Skip global enumeration. Hardcode candidate class names for
// v8.2 features. Use objc_getClass to check each. Output is bounded
// and fast.

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <stdio.h>
#import <string.h>
#import <stdlib.h>
#import <dispatch/dispatch.h>
#import <errno.h>

static char g_log_path[512] = {0};
static FILE *g_log_file = NULL;

static void log_msg(const char *fmt, ...) {
    char buf[2048];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);

    // 1. NSLog — always works, visible in Console.app / syslog
    NSLog(@"[GlowR4] %s", buf);

    // 2. stderr — also works for cycript/Frida console
    fprintf(stderr, "[GlowR4] %s", buf);
    fflush(stderr);

    // 3. File — best-effort, multiple paths
    if (g_log_path[0] == 0) {
        const char *home = getenv("HOME");
        // Try multiple paths
        const char *candidates[] = {
            "%s/Documents/glow_r4.txt",       // normal sandbox
            "/var/mobile/Documents/glow_r4.txt", // direct
            "/tmp/glow_r4.txt",                  // fallback
            NULL
        };
        for (int i = 0; candidates[i]; i++) {
            if (i == 0 && !home) continue;
            if (i == 0) {
                snprintf(g_log_path, sizeof(g_log_path), candidates[i], home);
            } else {
                snprintf(g_log_path, sizeof(g_log_path), "%s", candidates[i]);
            }
            g_log_file = fopen(g_log_path, "a");  // append mode
            if (g_log_file) {
                setvbuf(g_log_file, NULL, _IOLBF, 0);
                fprintf(stderr, "[GlowR4] logging to %s\n", g_log_path);
                break;
            }
        }
    }
    if (g_log_file) {
        fputs(buf, g_log_file);
        fflush(g_log_file);
    }
}
#define LOG(fmt, ...) log_msg(fmt, ##__VA_ARGS__)

// Dump a single class (full methods + ivars + properties + superclass)
static void dumpClass(const char *name) {
    Class cls = objc_getClass(name);
    if (!cls) {
        LOG("\n=== %s ===\n", name);
        LOG("  CLASS NOT FOUND\n");
        return;
    }

    LOG("\n=== %s ===\n", name);
    LOG("  Address: %p\n", cls);

    LOG("  Superclass chain:\n");
    Class cur = cls;
    int depth = 0;
    while (cur && depth < 10) {
        LOG("    [%d] %s\n", depth++, class_getName(cur));
        cur = class_getSuperclass(cur);
    }

    unsigned int mc = 0;
    Method *methods = class_copyMethodList(cls, &mc);
    LOG("  Methods (%u):\n", mc);
    for (unsigned i = 0; i < mc; i++) {
        SEL sel = method_getName(methods[i]);
        const char *n = sel_getName(sel);
        const char *t = method_getTypeEncoding(methods[i]);
        if (t) {
            LOG("    - %s  // %s\n", n, t);
        } else {
            LOG("    - %s\n", n);
        }
    }
    free(methods);

    unsigned int ic = 0;
    Ivar *ivars = class_copyIvarList(cls, &ic);
    LOG("  Ivars (%u):\n", ic);
    for (unsigned i = 0; i < ic; i++) {
        const char *n = ivar_getName(ivars[i]);
        const char *t = ivar_getTypeEncoding(ivars[i]);
        LOG("    - %s  // %s\n", n ? n : "?", t ? t : "?");
    }
    free(ivars);

    unsigned int pc = 0;
    objc_property_t *props = class_copyPropertyList(cls, &pc);
    LOG("  Properties (%u):\n", pc);
    for (unsigned i = 0; i < pc; i++) {
        const char *n = property_getName(props[i]);
        const char *attrs = property_getAttributes(props[i]);
        LOG("    - %s  // %s\n", n ? n : "?", attrs ? attrs : "?");
    }
    free(props);
}

// Check list of class names, dump only those that exist
static void checkCandidates(const char *category, const char *names[], int n) {
    LOG("\n### %s ###\n", category);
    int found = 0;
    for (int i = 0; i < n; i++) {
        Class c = objc_getClass(names[i]);
        if (c) {
            LOG("  [FOUND] %s\n", names[i]);
            found++;
        }
    }
    LOG("--- %d/%d found ---\n", found, n);
}

// Check then dump full if found
static void checkAndDump(const char *name) {
    if (objc_getClass(name)) {
        dumpClass(name);
    }
}

// Dump all FB-prefixed UIView/UIViewController classes.
// Why: Phase 2-7 candidates returned 0/30, 0/37. Class names have been
// completely renamed in 560.x. We need to enumerate for real.
// Strategy:
//   1. objc_copyClassList all loaded classes (safe - read-only)
//   2. Filter: name starts with "FB" or "NSKVONotifying_FB"
//   3. Check superclass chain contains UIView or UIViewController
//   4. Print matching class names to glow_fb_classes.txt
// Timing: classes are loaded lazily. We call this 4 times (0, +5, +15, +30s)
// to capture classes that get loaded when user navigates to Reels.
static int g_dump_count = 0;
static void dumpFBCurrentlyLoaded(void) {
    g_dump_count++;
    char fb_path[512];
    snprintf(fb_path, sizeof(fb_path), "%s.fb_classes.%d.txt", g_log_path, g_dump_count);
    FILE *fb_file = fopen(fb_path, "w");
    if (!fb_file) {
        LOG("  Cannot open %s\n", fb_path);
        return;
    }
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    int fb_ui = 0, fb_all = 0;
    // Buffer output, flush at end (avoid IO pressure)
    char *buf = (char *)malloc(2 * 1024 * 1024);  // 2MB
    if (!buf) { fclose(fb_file); free(classes); return; }
    size_t blen = 0;
    blen += snprintf(buf + blen, 2*1024*1024 - blen,
                     "# FB classes loaded (snapshot #%d, total %u classes)\n", g_dump_count, count);
    for (unsigned i = 0; i < count; i++) {
        const char *name = class_getName(classes[i]);
        if (!name) continue;
        if (strncmp(name, "FB", 2) != 0) continue;
        fb_all++;
        // Walk superclass chain
        Class sup = classes[i];
        int depth = 0;
        int isUI = 0;
        while (sup && depth < 20) {
            const char *sn = class_getName(sup);
            if (sn && (strcmp(sn, "UIView") == 0 || strcmp(sn, "UIViewController") == 0)) {
                isUI = 1;
                break;
            }
            sup = class_getSuperclass(sup);
            depth++;
        }
        if (isUI) {
            blen += snprintf(buf + blen, 2*1024*1024 - blen, "  %s\n", name);
            fb_ui++;
        }
    }
    blen += snprintf(buf + blen, 2*1024*1024 - blen,
                     "# Total FB classes: %d, FB UI classes: %d\n", fb_all, fb_ui);
    if (blen > 0) {
        fwrite(buf, 1, blen, fb_file);
        fflush(fb_file);
    }
    free(buf);
    free(classes);
    fclose(fb_file);
    LOG("  Snapshot #%d: %d FB classes, %d FB UI classes -> %s\n",
        g_dump_count, fb_all, fb_ui, fb_path);
}

__attribute__((constructor))
static void r4_init(void) {
    @try {
        LOG("=== R4 Verifier v1.4 (NSLog + multi-path) — %s ===\n", __DATE__ " " __TIME__);
        LOG("=== Constructor entered. Will dispatch after 3s. ===\n");
    } @catch (NSException *e) {
        NSLog(@"[GlowR4] init LOG exc: %@", e.reason);
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        @try {
            LOG("\n=== Dispatch fired after 3s ===\n");
            // ─── Phase 1: Critical classes (full dump) ───
            LOG("\n########## PHASE 1: Critical classes ##########\n");
            const char *critical[] = {
                // Ad block / story seen
                "FBMemNewsFeedEdge",
                "FBMemModelObject",
                "FBSnacksBucketsSeenStateManager",
                "FBComponentCollectionViewDataSource",
                "FBNewsFeedViewController",
                "FBNewsFeedViewControllerConfiguration",

                // Story download
                "FBSnacksMediaContainerView",
                "FBSnacksNewVideoView",
                "FBSnacksPhotoView",
                "FBSnacksWebPhotoView",
                "FBWebPhotoView",
                "FBWebImageNetworkSpecifier",
                "FBWebImageMemorySpecifier",

                // Video download
                "FBVideoPlaybackItem",
                "FBVideoOverlayPluginComponentBackgroundView",

                // PYMK / Suggested
                "FBMemPeopleYouMayKnowEdge",
                "FBMemSuggestedForYouEdge",
            };
            for (int i = 0; i < (int)(sizeof(critical)/sizeof(critical[0])); i++) {
                checkAndDump(critical[i]);
            }

            // ─── Phase 2: Reels candidates ───
            LOG("\n########## PHASE 2: Reels candidates ##########\n");
            const char *reels[] = {
                // Reels carousel (tab icon)
                "FBReelsTabViewController",
                "FBReelsTabContainerView",
                "FBReelsTabView",
                "FBReelTabBarItem",
                // Reels feed
                "FBReelsFeedViewController",
                "FBReelsFeedView",
                "FBReelsCollectionView",
                "FBReelsCollectionViewDataSource",
                "FBReelsCollectionViewLayout",
                "FBReelViewController",
                "FBReelPlayerViewController",
                "FBReelView",
                "FBReelPlayerView",
                "FBReelContainerView",
                "FBReelUnitView",
                "FBReelTrayView",
                "FBReelCarouselView",
                "FBReelHeaderView",
                "FBReelVideoContainerView",
                "FBReelsUnit",
                "FBReelsUnitView",
                "FBReelsUnitLayout",
                // Reel data
                "FBMemReelEdge",
                "FBMemReelTrayEdge",
                "FBMemReelUnitEdge",
                "FBMemReelItem",
                "FBMemReelUnit",
                // Reels overlay
                "FBReelOverlayView",
                "FBReelCommentsView",
                "FBReelsOverlayContainerView",
            };
            checkCandidates("Reels", reels, sizeof(reels)/sizeof(reels[0]));

            // ─── Phase 3: Video container candidates ───
            LOG("\n########## PHASE 3: Video container candidates ##########\n");
            const char *videos[] = {
                // Old name from Glow
                "VideoContainerView",
                // Possible replacements
                "FBVideoContainerView",
                "FBFeedVideoContainerView",
                "FBInlineVideoContainerView",
                "FBNewsFeedVideoContainerView",
                "FBReelVideoContainerView",
                "FBVideoPlayerView",
                "FBVideoView",
                "FBVideoWrapperView",
                "FBVideoBackgroundView",
                "FBVideoOverlayView",
                // Compositional
                "CKComponentView",
                // Pager for reels
                "FBPagingView",
                "FBReelPagingView",
                // Snacks video
                "FBSnacksVideoView",
                "FBSnacksVideoContainer",
                "FBSnacksReelContainerView",
            };
            checkCandidates("Video containers", videos, sizeof(videos)/sizeof(videos[0]));

            // ─── Phase 4: Story viewer candidates ───
            LOG("\n########## PHASE 4: Story viewer candidates ##########\n");
            const char *story[] = {
                "FBSnacksStoryViewerViewController",
                "FBSnacksStoryViewer",
                "FBSnacksStoryViewController",
                "FBSnacksStoryView",
                "FBSnacksThreadViewerViewController",
                "FBSnacksThreadViewer",
                "FBSnacksBucketViewerViewController",
                "FBSnacksBucketViewer",
                "FBSnacksViewerController",
                "FBSnacksViewer",
                "FBSnacksContainerViewController",
                "FBSnacksTrayViewController",
                "FBSnacksTrayView",
                "FBSnacksViewController",
            };
            checkCandidates("Story viewer", story, sizeof(story)/sizeof(story[0]));

            // ─── Phase 5: Composer / PYMK / Suggested ───
            LOG("\n########## PHASE 5: UI Hide candidates ##########\n");
            const char *hide[] = {
                // Composer
                "FBComposerViewController",
                "FBNewsFeedComposerView",
                "FBNewsFeedComposerViewController",
                "FBComposerPublishTargetView",
                "FBFeedComposerView",
                "FBStatusComposerView",
                "FBInlineComposerView",
                // PYMK variants
                "FBMemPYMKEdge",
                "FBMemPYMKUnit",
                "FBMemPYMKRow",
                "FBMemPeopleYouMayKnowUnit",
                "FBMemPeopleYouMayKnowItem",
                "FBMemPeopleYouMayKnowFeedUnit",
                "FBMemPeopleYouMayKnowRow",
                "FBMemPeopleYouMayKnowCard",
                "FBMemPeopleYouMayKnowCell",
                "FBMemPeopleYouMayKnowView",
                "FBMemPeopleYouMayKnowComponent",
                // Suggested
                "FBMemSuggestedEdge",
                "FBMemSuggestedRow",
                "FBMemSuggestedUnit",
                "FBMemSuggestedItem",
                "FBMemSuggestedCell",
                "FBMemSuggestedView",
                "FBMemSuggestedComponent",
                "FBMemSuggestedForYouItem",
                "FBMemSuggestedForYouUnit",
                "FBMemSuggestedForYouRow",
                // Reel carousel (tab)
                "FBReelsTrayViewController",
                "FBReelsTrayView",
                "FBReelsCarouselView",
                "FBReelsCarouselViewController",
                "FBReelsCarouselDataSource",
            };
            checkCandidates("UI Hide", hide, sizeof(hide)/sizeof(hide[0]));

            // ─── Phase 6: Download / share / save candidates ───
            LOG("\n########## PHASE 6: Download/share candidates ##########\n");
            const char *dl[] = {
                "FBDownloadManager",
                "FBDownloader",
                "FBFeedUnitDownloader",
                "FBVideoDownloader",
                "FBStoryDownloader",
                "FBPhotoDownloader",
                "FBSaveToPhotosAction",
                "FBSaveActionSheet",
                "FBLongPressMenu",
                "FBContextMenuAction",
                "FBContextMenuProvider",
                "FBLongPressGestureHandler",
            };
            checkCandidates("Download/share", dl, sizeof(dl)/sizeof(dl[0]));

            // ─── Phase 7: Reels action button candidates ───
            // Goal: find where like/share/comment buttons are init'd in Reels
            // So we can add our download button alongside them.
            LOG("\n########## PHASE 7: Reels action button candidates ##########\n");
            const char *reelsActions[] = {
                // Action button column container
                "FBReelActionBarView",
                "FBReelActionBar",
                "FBReelActionsView",
                "FBReelActionButton",
                "FBReelSideBarView",
                "FBReelSideBar",
                "FBReelRightSideBar",
                "FBReelLeftSideBar",
                "FBReelActionStackView",
                "FBReelToolbarView",
                "FBReelsActionBarView",
                "FBReelsActionBar",
                "FBReelsSideBarView",
                "FBReelsSideBar",
                "FBReelsActionStackView",
                // Specific buttons
                "FBReelLikeButton",
                "FBReelCommentButton",
                "FBReelShareButton",
                "FBReelSaveButton",
                "FBReelMoreButton",
                "FBReelMusicButton",
                "FBReelAuthorButton",
                "FBReelFollowButton",
                // Compositional
                "FBReelActionsComponent",
                "FBReelActionBarComponent",
                "FBReelSideBarComponent",
                "FBReelToolbarComponent",
                // Possible CK-based
                "FBReelCKDataSource",
                "FBReelCKComponent",
                // Snacks (older framework used for Reels)
                "FBSnacksReelView",
                "FBSnacksReelActionView",
                "FBSnacksReelActionBar",
                // Generic
                "FBReelOverlayActionView",
                "FBReelActionMenuView",
                "FBReelActionItemView",
                "FBReelButtonStack",
                "FBReelButtonColumn",
            };
            checkCandidates("Reels action buttons", reelsActions, sizeof(reelsActions)/sizeof(reelsActions[0]));

            // ─── Phase 8: REMOVED in v1.3 (was objc_copyClassList - causes crash) ───
            // Previous v1.2 used objc_copyClassList which returns 10000+ classes.
            // Buffering + iterating all 10000 caused memory pressure -> crash.
            // New approach: walk subviews in Phase 9 hook (proven safe).
            LOG("\n########## PHASE 8: (removed - see Phase 9 subview walk) ##########\n");

            LOG("\n=== R4 Verification Complete (Phase 9 hook active) ===\n");
            LOG("Output: %s\n", g_log_path);
            if (g_log_file) {
                fflush(g_log_file);
                fclose(g_log_file);
            }
            g_log_file = NULL;
        } @catch (NSException *e) {
            LOG("EXC: %s\n", e.reason.UTF8String);
            if (g_log_file) { fflush(g_log_file); fclose(g_log_file); }
        } @catch (...) {
            LOG("EXC(c++)\n");
            if (g_log_file) { fflush(g_log_file); fclose(g_log_file); }
        }
    });
}

// ═══════════════════════════════════════════════════════════════
// PHASE 9: Hook UIViewController.viewDidAppear: + walk subviews
// Why: dumps only happen at startup, but Reels classes load later.
// Hooking viewDidAppear: gives us the real class name of every VC
// the user navigates to. Then walk subviews to find action buttons.
// ═══════════════════════════════════════════════════════════════

// Walk subviews recursively, up to maxDepth levels
// Logs class + frame of each subview. v1.5: HIGHLIGHT UIButton class
// to find like/share/comment buttons. Also print accessibility label
// (FB usually sets these on action buttons).
static int g_walkCount = 0;
static int g_buttonCount = 0;
static void walkSubviews(UIView *view, int depth, int maxDepth) {
    if (!view || depth > maxDepth) return;
    if (g_walkCount > 1000) {
        LOG("  ... (walkCount > 1000, stopping)\n");
        return;
    }
    g_walkCount++;
    @try {
        Class cls = object_getClass(view);
        const char *name = class_getName(cls);
        if (!name) return;
        // Indent
        char indent[64] = {0};
        for (int i = 0; i < depth && i < 30; i++) indent[i] = ' ';
        // Print class + frame + subview count
        CGRect f = view.frame;
        unsigned long subCount = (unsigned long)view.subviews.count;
        // Highlight UIButton + UIControl + CKComponentHostingView
        BOOL isButton = [view isKindOfClass:[UIControl class]];
        const char *marker = isButton ? ">>> " : "    ";
        if (isButton) g_buttonCount++;
        // Get accessibility label (FB usually sets it on action buttons)
        NSString *accLabel = view.accessibilityLabel;
        const char *labelStr = accLabel ? [accLabel UTF8String] : "";
        if (isButton) {
            LOG("  %s%s[%d] %s frame=(%.0f,%.0f,%.0f,%.0f) subs=%lu label=\"%s\"\n",
                marker, indent, depth, name,
                f.origin.x, f.origin.y, f.size.width, f.size.height,
                subCount, labelStr);
        } else {
            LOG("  %s%s[%d] %s frame=(%.0f,%.0f,%.0f,%.0f) subs=%lu hidden=%d alpha=%.2f\n",
                marker, indent, depth, name,
                f.origin.x, f.origin.y, f.size.width, f.size.height,
                subCount,
                view.hidden, view.alpha);
        }
        // Recurse
        for (UIView *sub in view.subviews) {
            walkSubviews(sub, depth + 1, maxDepth);
        }
    } @catch (NSException *e) {
        LOG("  ... walk exc at depth %d: %s\n", depth, e.reason.UTF8String);
    }
}

// v1.5: hook viewDidLayoutSubviews of UIView to catch later subview adds
// Reels buttons are added AFTER viewDidAppear (lazy render)
static IMP orig_viewDidLayoutSubviews = NULL;
static int g_layoutHookCount = 0;
static void hooked_viewDidLayoutSubviews(id self, SEL _cmd) {
    if (orig_viewDidLayoutSubviews) {
        typedef void (*FnType)(id, SEL);
        FnType fn = (FnType)(uintptr_t)orig_viewDidLayoutSubviews;
        fn(self, _cmd);
    }
    @try {
        if (![self isKindOfClass:[UIView class]]) return;
        Class cls = object_getClass(self);
        const char *name = class_getName(cls);
        if (!name) return;
        // Only for Reels-related views
        BOOL isReelsView = (strstr(name, "VideoHome") != NULL ||
                            strstr(name, "ComponentHosting") != NULL ||
                            strstr(name, "Passthrough") != NULL ||
                            strstr(name, "Surface") != NULL);
        if (!isReelsView) return;
        // Only first 3 layout passes to avoid spam
        g_layoutHookCount++;
        if (g_layoutHookCount > 20) return;
        LOG("\n[Layout #%d] %s subs=%lu\n", g_layoutHookCount, name, (unsigned long)[(UIView *)self subviews].count);
        g_walkCount = 0;
        g_buttonCount = 0;
        walkSubviews(self, 0, 5);
        LOG("  --- found %d UIButton/UIControl views ---\n", g_buttonCount);
    } @catch (NSException *e) {
        LOG("[Layout] exc: %s\n", e.reason.UTF8String);
    }
}

static IMP orig_vc_viewDidAppear = NULL;
static int g_vcLog_count = 0;
static void hooked_vc_viewDidAppear(id self, SEL _cmd, BOOL animated) {
    if (orig_vc_viewDidAppear) {
        typedef void (*FnType)(id, SEL, BOOL);
        FnType fn = (FnType)(uintptr_t)orig_vc_viewDidAppear;
        fn(self, _cmd, animated);
    }
    @try {
        if (![self isKindOfClass:[UIViewController class]]) return;
        Class realCls = object_getClass(self);
        const char *name = class_getName(realCls);
        if (!name) return;
        // Only log FB* and NSKVONotifying_*
        if (strncmp(name, "FB", 2) != 0 && strncmp(name, "NSKVONotifying_", 15) != 0) return;
        g_vcLog_count++;
        // Print class + superclass chain
        LOG("\n[VC #%d] viewDidAppear: %s\n", g_vcLog_count, name);
        Class sup = class_getSuperclass(realCls);
        int d = 1;
        while (sup && d < 10) {
            LOG("  [%d] %s\n", d, class_getName(sup));
            sup = class_getSuperclass(sup);
            d++;
        }
        // Walk self.view subviews to find action buttons (5 levels deep in v1.5)
        // Trigger only for Reels-related VCs to avoid spam
        BOOL isReels = (strstr(name, "VideoHome") != NULL ||
                        strstr(name, "Reel") != NULL ||
                        strstr(name, "SurfaceView") != NULL);
        if (isReels) {
            LOG("  --- Reels subview walk (5 levels) ---\n");
            g_walkCount = 0;
            g_buttonCount = 0;
            UIView *root = nil;
            @try {
                root = [(UIViewController *)self view];
            } @catch (NSException *e) {
                LOG("  exc getting self.view: %s\n", e.reason.UTF8String);
            }
            if (root) {
                walkSubviews(root, 0, 5);
                LOG("  --- found %d UIButton/UIControl views ---\n", g_buttonCount);
            } else {
                LOG("  no root view\n");
            }
        }
    } @catch (NSException *e) {
        LOG("[VC] exc: %s\n", e.reason.UTF8String);
    }
}

static void installViewControllerHook(void) {
    Class vcCls = objc_getClass("UIViewController");
    if (!vcCls) return;
    SEL sel = @selector(viewDidAppear:);
    Method m = class_getInstanceMethod(vcCls, sel);
    if (!m) return;
    orig_vc_viewDidAppear = method_getImplementation(m);
    method_setImplementation(m, (IMP)hooked_vc_viewDidAppear);
    LOG("[R4] HOOKED UIViewController.viewDidAppear:\n");
}

static void installViewLayoutHook(void) {
    Class viewCls = objc_getClass("UIView");
    if (!viewCls) return;
    SEL sel = @selector(layoutSubviews);
    Method m = class_getInstanceMethod(viewCls, sel);
    if (!m) return;
    orig_viewDidLayoutSubviews = method_getImplementation(m);
    method_setImplementation(m, (IMP)hooked_viewDidLayoutSubviews);
    LOG("[R4] HOOKED UIView.layoutSubviews\n");
}

__attribute__((constructor))
static void r4_install_hooks(void) {
    // Delay slightly to ensure UIViewController/UIView are loaded
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        @try {
            installViewControllerHook();
            installViewLayoutHook();
        } @catch (NSException *e) {
            LOG("[R4] installHook exc: %s\n", e.reason.UTF8String);
        }
    });
}
