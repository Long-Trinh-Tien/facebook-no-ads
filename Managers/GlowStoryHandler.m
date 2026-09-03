// GlowStoryHandler.m
#import "GlowStoryHandler.h"
#import "GlowSettingsManager.h"
#import "GlowCacheManager.h"
#import "GlowLogManager.h"
#import "GlowViewUtils.h"
#import "GlowCommon.h"
#import <Photos/Photos.h>
#import <objc/runtime.h>

@implementation GlowStoryHandler

+ (instancetype)shared {
    static GlowStoryHandler *instance = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (NSURL *)findMediaURLInContainer:(UIView *)container isVideo:(BOOL *)outIsVideo {
    if (outIsVideo) *outIsVideo = NO;
    if (!container) return nil;
    @try {
        // FIX v8.3.1: Try multiple ivar/property names for mediaView
        // FB 560.x may have renamed the ivar
        const char *ivarNames[] = {
            "_mediaView",        // Original
            "mediaView",          // KVC variant
            "_player",            // Alternative
            "_videoView",         // Alternative
            "_contentView",       // Alternative
            NULL
        };

        id mediaView = nil;
        NSString *foundIvar = nil;

        // Try each ivar name
        for (int i = 0; ivarNames[i] != NULL; i++) {
            Ivar ivar = class_getInstanceVariable(object_getClass(container), ivarNames[i]);
            if (ivar) {
                mediaView = safe_get_ivar(container, ivar);
                if (mediaView) {
                    foundIvar = [NSString stringWithUTF8String:ivarNames[i]];
                    break;
                }
            }
        }

        // Try KVC as fallback
        if (!mediaView) {
            for (int i = 0; ivarNames[i] != NULL; i++) {
                @try {
                    NSString *key = [NSString stringWithUTF8String:ivarNames[i]];
                    if ([container respondsToSelector:@selector(valueForKey:)]) {
                        id val = [container valueForKey:key];
                        if (val && [val isKindOfClass:[UIView class]]) {
                            mediaView = val;
                            foundIvar = [NSString stringWithFormat:@"KVC:%@", key];
                            break;
                        }
                    }
                } @catch (NSException *e) {}
            }
        }

        if (!mediaView) {
            // Log all ivars to help debug
            unsigned int ivarCount = 0;
            Ivar *ivars = class_copyIvarList(object_getClass(container), &ivarCount);
            LOG("[dl/story] FAILED to find mediaView. Container class=%s, %u ivars:\n",
                class_getName(object_getClass(container)), ivarCount);
            for (unsigned int i = 0; i < ivarCount && i < 20; i++) {
                LOG("[dl/story]   ivar[%d]: %s\n", i, ivar_getName(ivars[i]));
            }
            if (ivars) free(ivars);
            return nil;
        }

        LOG("[dl/story] Found mediaView via %@, class=%s\n",
            foundIvar, class_getName(object_getClass(mediaView)));

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
            // Try multiple ivar names for photoView
            const char *photoIvars[] = {"_photoView", "photoView", NULL};
            id swpv = nil;
            for (int i = 0; photoIvars[i]; i++) {
                Ivar iv = class_getInstanceVariable(object_getClass(mediaView), photoIvars[i]);
                if (iv) swpv = safe_get_ivar(mediaView, iv);
                if (swpv) break;
            }
            if (!swpv) return nil;

            id wpv = nil;
            for (int i = 0; photoIvars[i]; i++) {
                Ivar iv = class_getInstanceVariable(object_getClass(swpv), photoIvars[i]);
                if (iv) wpv = safe_get_ivar(swpv, iv);
                if (wpv) break;
            }
            if (!wpv) return nil;

            SEL photoSel = sel_registerName("photo");
            id photo = [wpv respondsToSelector:photoSel] ? [wpv performSelector:photoSel] : nil;
            if (!photo) return nil;
            @try {
                NSURL *url = nil;
                
                // 1. Try playableURLString
                SEL playableSel = sel_registerName("playableURLString");
                id playableVal = [photo respondsToSelector:playableSel] ? [photo performSelector:playableSel] : nil;
                if ([playableVal isKindOfClass:[NSString class]]) {
                    url = [NSURL URLWithString:(NSString *)playableVal];
                } else if ([playableVal isKindOfClass:[NSURL class]]) {
                    url = (NSURL *)playableVal;
                }
                
                // 2. Try image -> uri
                if (!url) {
                    SEL imgSel = sel_registerName("image");
                    id imgObj = [photo respondsToSelector:imgSel] ? [photo performSelector:imgSel] : nil;
                    if (imgObj) {
                        SEL uriSel = sel_registerName("uri");
                        id uriVal = [imgObj respondsToSelector:uriSel] ? [imgObj performSelector:uriSel] : nil;
                        if ([uriVal isKindOfClass:[NSString class]]) {
                            url = [NSURL URLWithString:(NSString *)uriVal];
                        } else if ([uriVal isKindOfClass:[NSURL class]]) {
                            url = (NSURL *)uriVal;
                        }
                    }
                }
                
                // 3. Try fallback resolutions like image2048, image1286, image960, etc.
                if (!url) {
                    const char *imgFallbackMethods[] = {"image2048", "image1286", "image960", "image720", "image600", "image480", "image320", NULL};
                    for (int i = 0; imgFallbackMethods[i]; i++) {
                        SEL fbSel = sel_registerName(imgFallbackMethods[i]);
                        id fbImg = [photo respondsToSelector:fbSel] ? [photo performSelector:fbSel] : nil;
                        if (fbImg) {
                            SEL uriSel = sel_registerName("uri");
                            id uriVal = [fbImg respondsToSelector:uriSel] ? [fbImg performSelector:uriSel] : nil;
                            if ([uriVal isKindOfClass:[NSString class]]) {
                                url = [NSURL URLWithString:(NSString *)uriVal];
                                break;
                            } else if ([uriVal isKindOfClass:[NSURL class]]) {
                                url = (NSURL *)uriVal;
                                break;
                            }
                        }
                    }
                }
                
                if (url) {
                    LOG("[dl/story] resolved photo URL: %s\n", url.absoluteString.UTF8String);
                    return url;
                }
                
                // 4. Try legacy imageSpecifier as last resort
                id imageSpecifier = [photo respondsToSelector:@selector(valueForKey:)] ? [photo valueForKey:@"imageSpecifier"] : nil;
                if (imageSpecifier) {
                    Class netSpecCls = NSClassFromString(@"FBWebImageNetworkSpecifier");
                    Class memSpecCls = NSClassFromString(@"FBWebImageMemorySpecifier");
                    if (netSpecCls && [imageSpecifier isKindOfClass:netSpecCls]) {
                        SEL urlsSel = sel_registerName("allInfoURLsSortedByDescImageFlag");
                        NSArray *urls = [imageSpecifier respondsToSelector:urlsSel] ? [imageSpecifier performSelector:urlsSel] : nil;
                        if ([urls isKindOfClass:[NSArray class]] && urls.count > 0) {
                            id firstUrl = urls[0];
                            if ([firstUrl isKindOfClass:[NSURL class]]) {
                                return (NSURL *)firstUrl;
                            }
                        }
                    } else if (memSpecCls && [imageSpecifier isKindOfClass:memSpecCls]) {
                        SEL imgSel = sel_registerName("image");
                        UIImage *img = [imageSpecifier respondsToSelector:imgSel] ? [imageSpecifier performSelector:imgSel] : nil;
                        if (img) {
                            LOG("[dl/story] photo is in-memory, saving directly\n");
                            UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil);
                            [GlowViewUtils showSafeToast:@"✅ Đã lưu ảnh (từ bộ nhớ)"];
                            return nil;
                        }
                    }
                }
            } @catch (NSException *e) {
                LOG("[dl/story] photo resolution exc: %s\n", e.reason.UTF8String);
            }
        }

        // Unknown media type - log it
        LOG("[dl/story] Unknown mediaView class: %s (not video or photo)\n",
            class_getName(object_getClass(mediaView)));
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
    NSURL *photoURL = [self findMediaURLInContainer:container isVideo:&isVideo];
    
    // Check if we have a captured video/Reel URL in cache (e.g. for video story or Reel shared in story)
    NSURL *cachedHD = [GlowCacheManager shared].cachedHDURL;
    NSURL *cachedSD = [GlowCacheManager shared].cachedSDURL;
    NSURL *videoURL = cachedHD ? cachedHD : cachedSD;
    
    if (!photoURL && !videoURL) {
        [GlowViewUtils showSafeToast:@"❌ Không tìm thấy media"];
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *top = [GlowViewUtils topViewController];
        if (!top) return;

        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Tải media từ Story?"
                                                                       message:nil
                                                                preferredStyle:UIAlertControllerStyleActionSheet];
                                                                
        if (isVideo && photoURL) {
            // Natively resolved video story
            [alert addAction:[UIAlertAction actionWithTitle:@"Tải Video Story"
                                                      style:UIAlertActionStyleDefault
                                                    handler:^(UIAlertAction *a) {
                [self downloadVideoURL:photoURL];
            }]];
        } else {
            // Fallback video URL from cache (for Reel shared in Story, or video story with failed KVC)
            if (videoURL) {
                [alert addAction:[UIAlertAction actionWithTitle:@"Tải Video Story (HD/SD)"
                                                          style:UIAlertActionStyleDefault
                                                        handler:^(UIAlertAction *a) {
                    [self downloadVideoURL:videoURL];
                }]];
            }
            
            // Resolved photo URL
            if (photoURL) {
                [alert addAction:[UIAlertAction actionWithTitle:@"Tải Ảnh Story"
                                                          style:UIAlertActionStyleDefault
                                                        handler:^(UIAlertAction *a) {
                    [self downloadImageURL:photoURL];
                }]];
            }
        }
        
        [alert addAction:[UIAlertAction actionWithTitle:@"Hủy"
                                                  style:UIAlertActionStyleCancel
                                                handler:nil]];
                                                
        if (alert.popoverPresentationController) {
            alert.popoverPresentationController.sourceView = container;
            alert.popoverPresentationController.sourceRect = container.bounds;
        }
        [top presentViewController:alert animated:YES completion:nil];
    });
}

- (void)downloadImageURL:(NSURL *)url {
    if (!url) return;
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url
                                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (data) {
            UIImage *image = [UIImage imageWithData:data];
            if (image) {
                [self saveImageToPhotos:image];
            }
        }
    }];
    [task resume];
}

- (void)downloadVideoURL:(NSURL *)url {
    if (!url) return;
    NSString *fileName = [NSString stringWithFormat:@"story_video_%lld.mp4",
                          (long long)[[NSDate date] timeIntervalSince1970]];
    NSURL *destURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:fileName]];
    NSURLSessionDownloadTask *task = [[NSURLSession sharedSession] downloadTaskWithURL:url
                                                                    completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        if (location) {
            [[NSFileManager defaultManager] moveItemAtURL:location toURL:destURL error:nil];
            [self saveVideoToPhotosAtPath:[destURL path]];
        }
    }];
    [task resume];
}

- (void)saveImageToPhotos:(UIImage *)image {
    if (!image) return;
    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil);
    [GlowViewUtils showSafeToast:@"✅ Đã lưu ảnh"];
}

- (void)saveVideoToPhotosAtPath:(NSString *)path {
    if (!path) return;
    NSURL *fileURL = [NSURL fileURLWithPath:path];
    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:fileURL];
    } completionHandler:^(BOOL success, NSError * _Nullable error) {
        if (success) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [GlowViewUtils showSafeToast:@"✅ Đã lưu video"];
            });
        }
    }];
}

@end
