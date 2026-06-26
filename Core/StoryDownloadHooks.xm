// StoryDownloadHooks.xm
// Hooks for story download (FBSnacksMediaContainerView)
// RESTORED from v8.2.64 (commit 31e2fbf) - exactly as it was, working
#import "GlowCommon.h"
#import <UIKit/UIKit.h>
#import <Photos/Photos.h>
#import <objc/runtime.h>
#import "Hooks.h"
#import "GlowSettingsManager.h"
#import "GlowLogManager.h"
#import "GlowViewUtils.h"

// ═══════════════════════════════════════════════════════════════
// GlowStoryDownloadHandler - EXACT copy from v8.2.64
// ═══════════════════════════════════════════════════════════════

@interface GlowStoryDownloadHandler : NSObject
@property (nonatomic, strong) UIView *toast;
@end
@implementation GlowStoryDownloadHandler

// Find a playable item (URL) by walking FBSnacksMediaContainerView -> mediaView
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
            if (!swpv) return nil;
            Ivar wpvIvar = class_getInstanceVariable(object_getClass(swpv), "_photoView");
            id wpv = wpvIvar ? object_getIvar(swpv, wpvIvar) : nil;
            if (!wpv) return nil;
            SEL photoSel = sel_registerName("photo");
            id photo = [wpv respondsToSelector:photoSel] ? [wpv performSelector:photoSel] : nil;
            if (!photo) return nil;
            @try {
                id imageSpecifier = [photo valueForKey:@"imageSpecifier"];
                if (!imageSpecifier) return nil;
                Class netSpecCls = NSClassFromString(@"FBWebImageNetworkSpecifier");
                if (netSpecCls && [imageSpecifier isKindOfClass:netSpecCls]) {
                    SEL urlsSel = sel_registerName("allInfoURLsSortedByDescImageFlag");
                    NSArray *urls = [imageSpecifier respondsToSelector:urlsSel] ? [imageSpecifier performSelector:urlsSel] : nil;
                    if ([urls isKindOfClass:[NSArray class]] && urls.count > 0) {
                        id firstUrl = urls[0];
                        if ([firstUrl isKindOfClass:[NSURL class]]) {
                            return (NSURL *)firstUrl;
                        }
                    }
                }
            } @catch (NSException *e) {
                LOG("[dl/story] photo exc: %s\n", e.reason.UTF8String);
            }
        }
    } @catch (NSException *e) {
        LOG("[dl/story] exc: %s\n", e.reason.UTF8String);
    }
    return nil;
}

- (void)onStoryLongPress:(UILongPressGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateBegan) return;
    if (![GlowSettingsManager shared].downloadStory) return;
    @try {
        UIView *container = gr.view;
        if (!container) return;
        [self downloadStoryFromContainer:container];
    } @catch (NSException *e) {
        LOG("[dl/story] LP exc: %s\n", e.reason.UTF8String);
    }
}

- (void)onStoryDownloadTapped:(UIButton *)sender {
    if (![GlowSettingsManager shared].downloadStory) return;
    @try {
        UIView *container = sender.superview;
        if (!container) {
            LOG("[dl/story] button has no superview\n");
            return;
        }
        LOG("[dl/story] Download button tapped on container %p\n", container);
        [self downloadStoryFromContainer:container];
    } @catch (NSException *e) {
        LOG("[dl/story] Button tap exc: %s\n", e.reason.UTF8String);
    }
}

- (void)downloadStoryFromContainer:(UIView *)container {
    BOOL isVideo = NO;
    NSURL *url = [self findMediaURLInContainer:container isVideo:&isVideo];
    if (!url) { LOG("[dl/story] no URL found (maybe already saved)\n"); return; }

    // Show action sheet (like Glow 1.3.1)
    UIWindow *win = [GlowViewUtils keyWindow];
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
}

- (void)downloadURL:(NSURL *)url toFileName:(NSString *)name {
    NSURLSessionDownloadTask *task = [[NSURLSession sharedSession] downloadTaskWithURL:url
                                                                    completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        if (location) {
            NSURL *dest = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
            [[NSFileManager defaultManager] moveItemAtURL:location toURL:dest error:nil];
            if ([name hasSuffix:@".mp4"]) {
                [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                    [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:dest];
                } completionHandler:^(BOOL success, NSError * _Nullable error) {
                    if (success) {
                        LOG("[dl/story] saved video to Photos via PHPhotoLibrary\n");
                    }
                }];
            } else {
                NSData *data = [NSData dataWithContentsOfURL:dest];
                UIImage *img = [UIImage imageWithData:data];
                if (img) {
                    UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil);
                    LOG("[dl/story] saved image to Photos\n");
                }
            }
        }
    }];
    [task resume];
}

@end

// ═══════════════════════════════════════════════════════════════
// Hook installation - EXACT copy from v8.2.64
// ═══════════════════════════════════════════════════════════════

static GlowStoryDownloadHandler *g_storyHandler = nil;

static IMP orig_storyContainer_init = NULL;
static id hooked_storyContainer_init(id self, SEL _cmd, id thread, id bucket, id mediaViewDelegate, id mediaViewGenerator, id toolbox, BOOL shouldBlurMedia) {
    id result = nil;
    if (orig_storyContainer_init) {
        typedef id (*FnType)(id, SEL, id, id, id, id, id, BOOL);
        result = ((FnType)orig_storyContainer_init)(self, _cmd, thread, bucket,
                                                   mediaViewDelegate, mediaViewGenerator,
                                                   toolbox, shouldBlurMedia);
    }
    return result;
}

static IMP orig_storyContainer_didMoveToWindow = NULL;
static NSMutableSet *g_storyContainersWithLongPress = nil;

static void hooked_storyContainer_didMoveToWindow(id self, SEL _cmd, UIWindow *window) {
    if (orig_storyContainer_didMoveToWindow) {
        typedef void (*FnType)(id, SEL, id);
        ((FnType)orig_storyContainer_didMoveToWindow)(self, _cmd, (id)window);
    }
    if (![GlowSettingsManager shared].downloadStory) return;
    if (!window) return;
    if (!g_storyContainersWithLongPress) g_storyContainersWithLongPress = [[NSMutableSet alloc] init];
    @try {
        if ([g_storyContainersWithLongPress containsObject:[NSValue valueWithNonretainedObject:self]]) return;
        if (!g_storyHandler) g_storyHandler = [[GlowStoryDownloadHandler alloc] init];

        UIWindow *keyWindow = [GlowViewUtils keyWindow];
        if (!keyWindow) {
            LOG("[dl/story] keyWindow is nil, cannot add button\n");
            return;
        }

        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        btn.frame = CGRectMake(keyWindow.frame.size.width - 60, keyWindow.frame.size.height - 120, 44, 44);
        [btn setImage:[UIImage systemImageNamed:@"arrow.down.circle.fill"] forState:UIControlStateNormal];
        btn.tintColor = [UIColor whiteColor];
        btn.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.6];
        btn.layer.cornerRadius = 22;
        btn.clipsToBounds = YES;
        btn.tag = 999888;
        [btn addTarget:g_storyHandler action:@selector(onStoryDownloadTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:btn];

        [g_storyContainersWithLongPress addObject:[NSValue valueWithNonretainedObject:self]];
        LOG("[dl/story] added download BUTTON to container at (%.0f, %.0f)\n",
            keyWindow.frame.size.width - 60, keyWindow.frame.size.height - 120);
    } @catch (NSException *e) {
        LOG("[dl/story] didMoveToWindow exc: %s\n", e.reason.UTF8String);
    }
}

void initStoryDownloadHooks(void) {
    if (![GlowSettingsManager shared].downloadStory) return;
    @try {
        Class cls = objc_getClass("FBSnacksMediaContainerView");
        if (cls) {
            SEL sel = sel_registerName("initWithThread:bucket:mediaViewDelegate:mediaViewGenerator:toolbox:shouldBlurMedia:");
            Method m = class_getInstanceMethod(cls, sel);
            if (m) {
                orig_storyContainer_init = method_getImplementation(m);
                method_setImplementation(m, (IMP)hooked_storyContainer_init);
                LOG("  hook #8: FBSnacksMediaContainerView init (passive)\n");
            }

            SEL dmwSel = @selector(didMoveToWindow);
            Method dmwM = class_getInstanceMethod(cls, dmwSel);
            if (dmwM) {
                orig_storyContainer_didMoveToWindow = method_getImplementation(dmwM);
                method_setImplementation(dmwM, (IMP)hooked_storyContainer_didMoveToWindow);
                LOG("  hook #8b: FBSnacksMediaContainerView didMoveToWindow -> add button\n");
            }
        }
    } @catch (NSException *e) {
        LOG("[dl/story] init exc: %s\n", e.reason.UTF8String);
    }
}
