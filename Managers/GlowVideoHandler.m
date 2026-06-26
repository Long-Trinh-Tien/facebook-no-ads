// GlowVideoHandler.m
#import "GlowVideoHandler.h"
#import "GlowSettingsManager.h"
#import "GlowCacheManager.h"
#import "GlowViewUtils.h"
#import "GlowCommon.h"
#import <objc/runtime.h>
@implementation GlowVideoHandler

+ (instancetype)shared {
    static GlowVideoHandler *instance = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

#pragma mark - Newsfeed Cell Long Press

- (void)onNewsfeedCellLongPress:(UILongPressGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateBegan) return;
    if (![GlowSettingsManager shared].downloadVideo) return;

    UIView *v = gr.view;
    if (!v) return;

    @try {
        // Use global cache from VideoItemHooks
        NSURL *hd = [GlowCacheManager shared].cachedHDURL;
        NSURL *sd = [GlowCacheManager shared].cachedSDURL;
        if (!hd && !sd) {
            [GlowViewUtils showSafeToast:@"❌ Chưa có video để tải"];
            return;
        }
        [self presentQualityActionSheetHD:hd sd:sd sourceView:v];
    } @catch (NSException *e) {
        LOG("[dl/news] CELL long press exc: %s\n", e.reason.UTF8String);
    }
}

#pragma mark - VideoContainerView Long Press

- (void)onVideoContainerLongPress:(UILongPressGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateBegan) return;
    if (![GlowSettingsManager shared].downloadVideo) return;

    UIView *container = gr.view;
    if (!container) return;

    LOG("[dl/news] LONG PRESS on VideoContainer %s\n",
        class_getName(object_getClass(container)));

    @try {
        // Get controller from container
        id controller = nil;

        // Try 'controller' property first
        if ([container respondsToSelector:@selector(controller)]) {
            controller = [container performSelector:@selector(controller)];
        }

        // Try _videoPlaybackController ivar
        if (!controller) {
            Ivar vpcIvar = class_getInstanceVariable(object_getClass(container),
                                                     "_videoPlaybackController");
            if (vpcIvar) {
                controller = object_getIvar(container, vpcIvar);
            }
        }

        if (!controller) {
            // Walk responder chain
            UIResponder *r = container;
            int depth = 0;
            while (r && depth < 20) {
                r = [r nextResponder];
                if ([r respondsToSelector:@selector(currentVideoPlaybackItem)]) {
                    controller = r;
                    break;
                }
                depth++;
            }
        }

        if (!controller) {
            [GlowViewUtils showSafeToast:@"❌ Không tìm thấy video controller"];
            return;
        }

        // Get current video item
        id item = nil;
        if ([controller respondsToSelector:@selector(currentVideoPlaybackItem)]) {
            item = [controller performSelector:@selector(currentVideoPlaybackItem)];
        }

        if (!item) {
            [GlowViewUtils showSafeToast:@"❌ Không có video đang phát"];
            return;
        }

        // Get URLs
        NSURL *hdURL = nil, *sdURL = nil;
        if ([item respondsToSelector:@selector(HDPlaybackURL)]) {
            hdURL = [item performSelector:@selector(HDPlaybackURL)];
        }
        if ([item respondsToSelector:@selector(SDPlaybackURL)]) {
            sdURL = [item performSelector:@selector(SDPlaybackURL)];
        }

        if (!hdURL && !sdURL) {
            [GlowViewUtils showSafeToast:@"❌ Không có URL video"];
            return;
        }

        [self presentQualityActionSheetHD:hdURL sd:sdURL sourceView:container];
    } @catch (NSException *e) {
        LOG("[dl/news] long press exc: %s\n", e.reason.UTF8String);
    }
}

#pragma mark - Quality Action Sheet

- (void)presentQualityActionSheetHD:(NSURL *)hd sd:(NSURL *)sd sourceView:(UIView *)sourceView {
    if (!hd && !sd) return;

    UIViewController *top = [GlowViewUtils topViewController];
    if (!top) return;

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Tải video?"
        message:nil
        preferredStyle:UIAlertControllerStyleActionSheet];

    if (hd) {
        [alert addAction:[UIAlertAction
            actionWithTitle:@"Tải HD"
            style:UIAlertActionStyleDefault
            handler:^(UIAlertAction *a) {
                [self downloadURL:hd];
            }]];
    }

    if (sd) {
        [alert addAction:[UIAlertAction
            actionWithTitle:@"Tải SD"
            style:UIAlertActionStyleDefault
            handler:^(UIAlertAction *a) {
                [self downloadURL:sd];
            }]];
    }

    [alert addAction:[UIAlertAction
        actionWithTitle:@"Hủy"
        style:UIAlertActionStyleCancel
        handler:nil]];

    if (alert.popoverPresentationController) {
        alert.popoverPresentationController.sourceView = sourceView;
        alert.popoverPresentationController.sourceRect = sourceView.bounds;
    }

    [top presentViewController:alert animated:YES completion:nil];
}

- (void)downloadURL:(NSURL *)url {
    if (!url) return;
    NSString *fileName = [NSString stringWithFormat:@"newsfeed_video_%lld.mp4",
                          (long long)[[NSDate date] timeIntervalSince1970]];
    NSURL *destURL = [NSURL fileURLWithPath:
                      [NSTemporaryDirectory() stringByAppendingPathComponent:fileName]];

    NSURLSessionDownloadTask *task = [[NSURLSession sharedSession]
        downloadTaskWithURL:url
        completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
            if (location) {
                [[NSFileManager defaultManager] moveItemAtURL:location toURL:destURL error:nil];
                [GlowViewUtils showSafeToast:@"✅ Đã tải video"];
            } else {
                [GlowViewUtils showSafeToast:@"❌ Lỗi tải video"];
            }
        }];
    [task resume];
}

@end
