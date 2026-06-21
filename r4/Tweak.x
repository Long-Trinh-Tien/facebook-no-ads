// R4 Verifier — Comprehensive class/method/ivar dump
// Output to /var/mobile/Documents/glow_r4.txt
//
// Purpose: discover correct 560.x classes/methods for v8.2+ features
// (download story, download video, hide composer, hide Reels, etc.)
//
// No hooks installed — read-only introspection.

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <stdio.h>
#import <string.h>
#import <stdlib.h>
#import <dispatch/dispatch.h>

static char g_log_path[512] = {0};
static FILE *g_log_file = NULL;

static void log_msg(const char *fmt, ...) {
    if (g_log_path[0] == 0) {
        const char *home = getenv("HOME");
        if (!home) home = "/var/mobile";
        snprintf(g_log_path, sizeof(g_log_path), "%s/Documents/glow_r4.txt", home);
    }
    if (!g_log_file) {
        g_log_file = fopen(g_log_path, "w");
    }
    if (g_log_file) {
        va_list ap;
        va_start(ap, fmt);
        vfprintf(g_log_file, fmt, ap);
        va_end(ap);
        fflush(g_log_file);
    }
    // Also printf so we can see in console
    va_list ap2;
    va_start(ap2, fmt);
    vprintf(fmt, ap2);
    va_end(ap2);
}
#define LOG(fmt, ...) log_msg(fmt, ##__VA_ARGS__)

// Dump a single class
static void dumpClass(const char *name) {
    Class cls = objc_getClass(name);
    if (!cls) {
        LOG("\n=== %s ===\n", name);
        LOG("  CLASS NOT FOUND\n");
        return;
    }

    LOG("\n=== %s ===\n", name);
    LOG("  Address: %p\n", cls);

    // Superclass chain
    LOG("  Superclass chain:\n");
    Class cur = cls;
    int depth = 0;
    while (cur && depth < 10) {
        LOG("    [%d] %s\n", depth++, class_getName(cur));
        cur = class_getSuperclass(cur);
    }

    // Methods
    unsigned int mc = 0;
    Method *methods = class_copyMethodList(cls, &mc);
    LOG("  Methods (%u):\n", mc);
    for (unsigned i = 0; i < mc; i++) {
        SEL sel = method_getName(methods[i]);
        const char *n = sel_getName(sel);
        const char *t = method_getTypeEncoding(methods[i]);
        // Get return type and arg types
        if (t) {
            LOG("    - %s  // %s\n", n, t);
        } else {
            LOG("    - %s\n", n);
        }
    }
    free(methods);

    // Ivars
    unsigned int ic = 0;
    Ivar *ivars = class_copyIvarList(cls, &ic);
    LOG("  Ivars (%u):\n", ic);
    for (unsigned i = 0; i < ic; i++) {
        const char *n = ivar_getName(ivars[i]);
        const char *t = ivar_getTypeEncoding(ivars[i]);
        LOG("    - %s  // %s\n", n ? n : "?", t ? t : "?");
    }
    free(ivars);

    // Properties
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

// Enumerate all classes with a substring match (just names, not full dump)
static void dumpClassesMatching(const char *substring, int maxResults) {
    int numClasses = 0;
    Class *classes = NULL;

    numClasses = objc_getClassList(NULL, 0);
    if (numClasses <= 0) return;

    classes = (Class *)malloc(sizeof(Class) * numClasses);
    numClasses = objc_getClassList(classes, numClasses);

    int shown = 0;
    for (int i = 0; i < numClasses && shown < maxResults; i++) {
        const char *name = class_getName(classes[i]);
        if (name && strstr(name, substring)) {
            // Only top-level classes (no $Subclass)
            if (strchr(name, '$') == NULL) {
                LOG("  %s\n", name);
                shown++;
            }
        }
    }
    free(classes);
    LOG("--- %d classes matching '%s' ---\n\n", shown, substring);
}

// Enumerate ALL FB* classes
static void dumpAllFBClasses(void) {
    int numClasses = 0;
    Class *classes = NULL;
    numClasses = objc_getClassList(NULL, 0);
    if (numClasses <= 0) return;

    classes = (Class *)malloc(sizeof(Class) * numClasses);
    numClasses = objc_getClassList(classes, numClasses);

    int total = 0;
    for (int i = 0; i < numClasses; i++) {
        const char *name = class_getName(classes[i]);
        if (!name) continue;
        if (strncmp(name, "FB", 2) == 0 && strchr(name, '$') == NULL) {
            // Just print name, not full dump
            LOG("  %s\n", name);
            total++;
        }
    }
    free(classes);
    LOG("\n--- Total %d FB* classes ---\n", total);
}

// Check if class exists and dump
static void checkClasses(int argc, const char *names[], int n) {
    for (int i = 0; i < n; i++) {
        dumpClass(names[i]);
    }
}

__attribute__((constructor))
static void r4_init(void) {
    LOG("=== R4 Verifier — %s ===\n\n", __DATE__ " " __TIME__);

    // Defer to main queue (wait for FB classes to be loaded)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        @try {
            // ─── Phase 1: Critical classes for v8.2 features ───
            LOG("\n########## PHASE 1: Critical classes (v8.2 features) ##########\n");
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

                // PYMK / Suggested (verify removed or renamed)
                "FBMemFeedStory",
                "FBVideoChannelPlaylistItem",
                "FBMemPeopleYouMayKnowEdge",
                "FBMemSuggestedForYouEdge",
            };
            checkClasses(NULL, critical, sizeof(critical)/sizeof(critical[0]));

            // ─── Phase 2: Search by substring ───
            LOG("\n########## PHASE 2: Classes matching keywords ##########\n");

            LOG("\n### 'Reel' ###\n");
            dumpClassesMatching("Reel", 30);

            LOG("\n### 'Snacks' ###\n");
            dumpClassesMatching("Snacks", 30);

            LOG("\n### 'Stories' ###\n");
            dumpClassesMatching("Stories", 30);

            LOG("\n### 'Pymk' or 'PYMK' ###\n");
            dumpClassesMatching("Pymk", 10);
            dumpClassesMatching("PYMK", 10);
            dumpClassesMatching("YouMayKnow", 10);

            LOG("\n### 'Suggest' ###\n");
            dumpClassesMatching("Suggest", 20);

            LOG("\n### 'Shorts' ###\n");
            dumpClassesMatching("Shorts", 10);

            LOG("\n### 'Video' ###\n");
            dumpClassesMatching("Video", 40);

            LOG("\n### 'Download' ###\n");
            dumpClassesMatching("Download", 20);

            // ─── Phase 3: All FB* classes (just names) ───
            LOG("\n########## PHASE 3: All FB* classes (names only) ##########\n");
            dumpAllFBClasses();

            // ─── Phase 4: Class hierarchy info ───
            LOG("\n########## PHASE 4: Class hierarchy ##########\n");
            const char *hierarchy[] = {
                "FBMemNewsFeedEdge",
                "FBSnacksMediaContainerView",
                "FBVideoPlaybackItem",
            };
            for (int i = 0; i < 3; i++) {
                Class c = objc_getClass(hierarchy[i]);
                if (!c) continue;
                LOG("\n%s superclass chain:\n", hierarchy[i]);
                Class cur = c;
                int depth = 0;
                while (cur && depth < 15) {
                    LOG("  [%d] %s\n", depth++, class_getName(cur));
                    cur = class_getSuperclass(cur);
                }
            }

            LOG("\n=== R4 Verification Complete ===\n");
            LOG("Output: %s\n", g_log_path);
            if (g_log_file) fclose(g_log_file);
            g_log_file = NULL;
        } @catch (NSException *e) {
            LOG("EXC: %s\n", e.reason.UTF8String);
        } @catch (...) {
            LOG("EXC(c++)\n");
        }
    });
}
