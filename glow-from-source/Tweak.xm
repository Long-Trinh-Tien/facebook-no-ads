#import <objc/runtime.h>
#import <dlfcn.h>
#import <Foundation/Foundation.h>

// ============== PREFERENCES ==============
#define PLIST_PATH "/var/mobile/Library/Preferences/com.dvntm.glowprefs.plist"
#define PREF_CHANGED_NOTIF "com.dvntm.glowprefs/PrefChanged"

// Feature toggles
static BOOL pref_removeAds = YES;
static BOOL pref_removePYMK = YES;
static BOOL pref_removeReelsCarousel = YES;
static BOOL pref_removeRecs = YES;
static BOOL pref_postLikeConfirm = NO;
static BOOL pref_reelsLikeConfirm = NO;
static BOOL pref_downloadVideos = YES;
static BOOL pref_downloadReels = YES;
static BOOL pref_downloadStories = YES;
static BOOL pref_anonymousStories = YES;
static BOOL pref_disableAutoNext = NO;
static BOOL pref_hideOverlay = NO;
static BOOL pref_clearCache = NO;

static void reloadPrefs() {
  @autoreleasepool {
    NSDictionary *s = [[NSDictionary alloc] initWithContentsOfFile:@PLIST_PATH];
    if (!s) s = @{};
    pref_removeAds = [s[@"RemoveAds"] ?: @YES boolValue];
    pref_removePYMK = [s[@"RemovePYMK"] ?: @YES boolValue];
    pref_removeReelsCarousel = [s[@"RemoveReelsCarousel"] ?: @YES boolValue];
    pref_removeRecs = [s[@"RemoveRecs"] ?: @YES boolValue];
    pref_postLikeConfirm = [s[@"PostLikeConfirm"] ?: @NO boolValue];
    pref_reelsLikeConfirm = [s[@"ReelsLikeConfirm"] ?: @NO boolValue];
    pref_downloadVideos = [s[@"DownloadVideos"] ?: @YES boolValue];
    pref_downloadReels = [s[@"DownloadReels"] ?: @YES boolValue];
    pref_downloadStories = [s[@"DownloadStories"] ?: @YES boolValue];
    pref_anonymousStories = [s[@"AnonymousStories"] ?: @YES boolValue];
    pref_disableAutoNext = [s[@"DisableAutoNext"] ?: @NO boolValue];
    pref_hideOverlay = [s[@"HideOverlay"] ?: @NO boolValue];
    pref_clearCache = [s[@"AutoClearCache"] ?: @NO boolValue];
  }
}

// ============== NO ADS ==============
%group NoAds
%hook FBMemNewsFeedEdge
- (id)initWithFBTree:(void *)arg1 {
  id orig = %orig;
  id category = [orig category];
  if (category && [category isEqualToString:@"ORGANIC"]) return orig;
  return nil;
}
%end

%hook FBMemFeedStory
- (id)initWithFBTree:(void *)arg1 {
  id orig = %orig;
  return [orig sponsoredData] == nil ? orig : nil;
}
%end

%hook FBVideoChannelPlaylistItem
- (id)initWithFBTree:(id)arg1 {
  id orig = %orig;
  return [orig isSponsored] ? nil : orig;
}
%end
%end

// ============== DOWNLOAD VIDEO ==============
%group DownloadVideo
%hook VideoContainerView
- (id)initWithFrame:(CGRect)frame {
  id orig = %orig;
  UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(glow_handleLongPress:)];
  lp.minimumPressDuration = 0.5;
  [orig addGestureRecognizer:lp];
  return orig;
}

%new
- (void)glow_handleLongPress:(UILongPressGestureRecognizer *)sender {
  if (sender.state != UIGestureRecognizerStateBegan) return;
  // Get video URL from current playback item
  id playbackItem = [self.controller currentVideoPlaybackItem];
  if (!playbackItem) return;
  NSURL *hdURL = [playbackItem valueForKey:@"HDPlaybackURL"];
  NSURL *sdURL = [playbackItem valueForKey:@"SDPlaybackURL"];
  NSURL *url = hdURL ?: sdURL;
  if (!url) return;
  // Save to photos
  UISaveVideoAtPathToSavedPhotosAlbum(url.absoluteString, nil, nil, nil);
}
%end
%end

// ============== DOWNLOAD STORY ==============
%group DownloadStory
%hook FBSnacksMediaContainerView
%property (nonatomic, retain) UIButton *glow_downloadBtn;

- (id)initWithThread:(id)arg1 bucket:(id)arg2 mediaViewDelegate:(id)arg3 mediaViewGenerator:(id *)arg4 toolbox:(id)arg5 {
  self = %orig;
  self.glow_downloadBtn = [UIButton buttonWithType:UIButtonTypeCustom];
  [self.glow_downloadBtn setTitle:@"↓" forState:UIControlStateNormal];
  [self.glow_downloadBtn addTarget:self action:@selector(glow_saveStory) forControlEvents:UIControlEventTouchUpInside];
  self.glow_downloadBtn.frame = CGRectMake([UIScreen mainScreen].bounds.size.width - 50, 100, 40, 40);
  [self addSubview:self.glow_downloadBtn];
  return self;
}

%new
- (void)glow_saveStory {
  id mediaView = [self valueForKey:@"mediaView"];
  if ([mediaView isKindOfClass:NSClassFromString(@"FBSnacksPhotoView")]) {
    // Save image
    id photoView = [mediaView valueForKey:@"_photoView"];
    id imageView = [photoView valueForKey:@"_photoView"];
    id specifier = [imageView valueForKey:@"imageSpecifier"];
    if ([specifier isKindOfClass:NSClassFromString(@"FBWebImageNetworkSpecifier")]) {
      NSURL *url = [[specifier valueForKey:@"allInfoURLsSortedByDescImageFlag"] firstObject];
      if (url) {
        NSData *data = [NSData dataWithContentsOfURL:url];
        UIImage *img = [UIImage imageWithData:data];
        UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil);
      }
    }
  } else if ([mediaView isKindOfClass:NSClassFromString(@"FBSnacksNewVideoView")]) {
    id manager = [mediaView valueForKey:@"manager"];
    id item = [manager currentVideoPlaybackItem];
    NSURL *url = [item valueForKey:@"HDPlaybackURL"] ?: [item valueForKey:@"SDPlaybackURL"];
    if (url) UISaveVideoAtPathToSavedPhotosAlbum(url.absoluteString, nil, nil, nil);
  }
}
%end
%end

// ============== ANONYMOUS STORIES (FIX) ==============
static IMP orig_attemptSend = NULL;
static void hook_attemptSend(id self, SEL _cmd, id response, id bucket) {
  // No-op — block sending seen state to server
}
static IMP orig_markSeen = NULL;
static void hook_markSeen(id self, SEL _cmd, id threads, id bucket, id tracking, BOOL isAnonymous, id completion) {
  // No-op — block marking as seen
}

%group AnonymousStories
%hook FBSnacksUnifiedSeenStateMutator
- (void)_attemptSendSeenStateAndHandleResponse:(id)response bucket:(id)bucket {
  if (pref_anonymousStories) return;
  %orig;
}
- (void)_markThreadsAsSeen:(id)threads fromBucket:(id)bucket withTrackingString:(id)tracking isAnonymousView:(BOOL)anon completion:(id)block {
  if (pref_anonymousStories) return;
  %orig;
}
%end
%end

// ============== CONSTRUCTOR ==============
%ctor {
  @autoreleasepool {
    reloadPrefs();

    CFNotificationCenterAddObserver(
      CFNotificationCenterGetDarwinNotifyCenter(),
      NULL,
      (CFNotificationCallback)reloadPrefs,
      CFSTR(PREF_CHANGED_NOTIF),
      NULL,
      CFNotificationSuspensionBehaviorDeliverImmediately
    );

    // Load FBSharedFramework (needed for story classes)
    NSString *fw = [[NSBundle mainBundle].bundlePath
      stringByAppendingPathComponent:@"Frameworks/FBSharedFramework.framework/FBSharedFramework"];
    dlopen([fw UTF8String], RTLD_NOW | RTLD_GLOBAL);

    if (pref_removeAds)         %init(NoAds);
    if (pref_downloadVideos || pref_downloadReels)  %init(DownloadVideo);
    if (pref_downloadStories)   %init(DownloadStory);
    if (pref_anonymousStories)  %init(AnonymousStories);

    NSLog(@"[Glow] init done");
  }
}
