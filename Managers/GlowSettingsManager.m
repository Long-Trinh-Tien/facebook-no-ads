// GlowSettingsManager.m
#import "GlowCommon.h"
#import "GlowSettingsManager.h"
#import "GlowLogManager.h"

void reloadPrefs(void) {
    [[GlowSettingsManager shared] loadSettings];
}

void prefsChanged(CFNotificationCenterRef center, void *observer,
                  CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    [[GlowSettingsManager shared] loadSettings];
}

@implementation GlowSettingsManager

+ (instancetype)shared {
    static GlowSettingsManager *instance = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[self alloc] init];
        [instance loadSettings];
    });
    return instance;
}

- (void)loadSettings {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];

    // Load with defaults
    self.removeAds = [d objectForKey:@"com.tommy.glow.removeAds"] ?
                     [d boolForKey:@"com.tommy.glow.removeAds"] : YES;
    self.disableStorySeen = [d objectForKey:@"com.tommy.glow.disableStorySeen"] ?
                            [d boolForKey:@"com.tommy.glow.disableStorySeen"] : YES;
    self.downloadVideo = [d boolForKey:@"com.tommy.glow.downloadVideo"];
    self.downloadStory = [d boolForKey:@"com.tommy.glow.downloadStory"];
    self.removePYMK = [d boolForKey:@"com.tommy.glow.removePYMK"];
    self.removeReelsCarousel = [d boolForKey:@"com.tommy.glow.removeReelsCarousel"];
    self.removeSuggested = [d boolForKey:@"com.tommy.glow.removeSuggested"];
    self.hideComposer = [d boolForKey:@"com.tommy.glow.hideComposer"];
    self.disableAutoNext = [d boolForKey:@"com.tommy.glow.disableAutoNext"];
    self.confirmLike = [d boolForKey:@"com.tommy.glow.confirmLike"];
    self.downloadReels = [d objectForKey:@"com.tommy.glow.downloadReels"] ?
                         [d boolForKey:@"com.tommy.glow.downloadReels"] : YES;
    self.hideOverlay = [d boolForKey:@"com.tommy.glow.hideOverlay"];
    self.confirmReelsLike = [d boolForKey:@"com.tommy.glow.confirmReelsLike"];
    self.downloadLongPress = [d boolForKey:@"com.tommy.glow.downloadLongPress"];
    self.markAsSeen = [d boolForKey:@"com.tommy.glow.markAsSeen"];
    self.removeStoryPYMK = [d boolForKey:@"com.tommy.glow.removeStoryPYMK"];
    self.allFormats = [d boolForKey:@"com.tommy.glow.allFormats"];
    self.clearCacheOnLaunch = [d boolForKey:@"com.tommy.glow.clearCacheOnLaunch"];
    self.notifyUpdates = [d boolForKey:@"com.tommy.glow.notifyUpdates"];

    LOG("[prefs] reload: ads=%d seen=%d video=%d story=%d pymk=%d reels=%d\n",
        self.removeAds, self.disableStorySeen, self.downloadVideo, self.downloadStory,
        self.removePYMK, self.removeReelsCarousel);
}

+ (NSString *)localizedString:(NSString *)key {
    static NSDictionary *cached = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
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

            // Reels
            @"downloadReels": @"Tải reels",
            @"hideOverlay": @"Ẩn lớp phủ",
            @"confirmReelsLike": @"Xác nhận thích reels",
            @"downloadLongPress": @"Tải xuống bằng nhấn giữ",

            // Stories
            @"downloadStory": @"Tải stories",
            @"disableStorySeen": @"Xem ẩn danh",
            @"disableAutoNext": @"Tắt tự động chuyển tiếp",
            @"removeStoryPYMK": @"Xóa gợi ý kết bạn trong story",

            // Downloader
            @"allFormats": @"Bao gồm tất cả các định dạng",
        };
    });

    return cached[key] ?: key;
}

@end
