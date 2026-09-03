// Managers/GlowSettingsManager.m
#import "Managers/GlowSettingsManager.h"

@implementation GlowSettingsManager

+ (instancetype)shared {
    static GlowSettingsManager *s = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        s = [[GlowSettingsManager alloc] init];
        [s loadSettings];
    });
    return s;
}

- (void)loadSettings {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];

    self.removeAds = [d objectForKey:@"com.tommy.glow.removeAds"] ? [d boolForKey:@"com.tommy.glow.removeAds"] : YES;
    self.disableStorySeen = [d objectForKey:@"com.tommy.glow.disableStorySeen"] ? [d boolForKey:@"com.tommy.glow.disableStorySeen"] : YES;
    self.downloadVideo = [d objectForKey:@"com.tommy.glow.downloadVideo"] ? [d boolForKey:@"com.tommy.glow.downloadVideo"] : YES;
    self.downloadStory = [d objectForKey:@"com.tommy.glow.downloadStory"] ? [d boolForKey:@"com.tommy.glow.downloadStory"] : YES;
    self.downloadReels = [d objectForKey:@"com.tommy.glow.downloadReels"] ? [d boolForKey:@"com.tommy.glow.downloadReels"] : YES;

    self.removePYMK = [d boolForKey:@"com.tommy.glow.removePYMK"];
    self.removeReelsCarousel = [d boolForKey:@"com.tommy.glow.removeReelsCarousel"];
    self.removeSuggested = [d boolForKey:@"com.tommy.glow.removeSuggested"];
    self.hideComposer = [d boolForKey:@"com.tommy.glow.hideComposer"];
    self.disableAutoNext = [d boolForKey:@"com.tommy.glow.disableAutoNext"];
    self.confirmLike = [d boolForKey:@"com.tommy.glow.confirmLike"];
    self.hideOverlay = [d boolForKey:@"com.tommy.glow.hideOverlay"];
    self.confirmReelsLike = [d boolForKey:@"com.tommy.glow.confirmReelsLike"];
    self.downloadLongPress = [d boolForKey:@"com.tommy.glow.downloadLongPress"];
    self.markAsSeen = [d boolForKey:@"com.tommy.glow.markAsSeen"];
    self.removeStoryPYMK = [d boolForKey:@"com.tommy.glow.removeStoryPYMK"];
    self.allFormats = [d boolForKey:@"com.tommy.glow.allFormats"];
    self.clearCacheOnLaunch = [d boolForKey:@"com.tommy.glow.clearCacheOnLaunch"];
    self.notifyUpdates = [d boolForKey:@"com.tommy.glow.notifyUpdates"];
    self.disableAutoRefresh = [d objectForKey:@"com.tommy.glow.disableAutoRefresh"] ? [d boolForKey:@"com.tommy.glow.disableAutoRefresh"] : YES;
}

+ (NSString *)localizedString:(NSString *)key {
    static NSDictionary *dict = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dict = @{
            @"section.home": @"Bảng tin (Home Feed)",
            @"section.reels": @"Video ngắn (Reels)",
            @"section.stories": @"Tin (Stories)",
            @"section.downloader": @"Tải xuống (Downloader)",
            @"section.other": @"Khác (Other)",

            @"removeAds": @"Chặn quảng cáo",
            @"removePYMK": @"Ẩn gợi ý kết bạn (PYMK)",
            @"removeReelsCarousel": @"Ẩn Reels trên Bảng tin",
            @"removeSuggested": @"Ẩn bài viết gợi ý",
            @"confirmLike": @"Xác nhận khi Thích bài viết",
            @"confirmLike.desc": @"Hiện popup hỏi trước khi thả Like bài viết",
            @"disableAutoRefresh": @"Không tự làm mới Feed (Giữ vị trí)",
            @"disableAutoRefresh.desc": @"Không tự reload/cuộn lên đầu khi mở lại app",
            @"downloadVideo": @"Tải video Bảng tin",
            @"downloadVideo.desc": @"Ấn giữ video để tải",

            @"downloadReels": @"Tải video Reels",
            @"hideOverlay": @"Ẩn giao diện khi xem Reels",
            @"confirmReelsLike": @"Xác nhận khi Thích Reels",
            @"downloadLongPress": @"Ấn giữ để tải",

            @"downloadStory": @"Tải Story",
            @"disableStorySeen": @"Xem Story ẩn danh (Không hiện Đã xem)",
            @"disableAutoNext": @"Tắt tự động chuyển Story",
            @"removeStoryPYMK": @"Ẩn gợi ý trong Story",

            @"allFormats": @"Hiện tất cả định dạng tải",
            @"notifyUpdates": @"Thông báo cập nhật",
            @"clearCacheOnLaunch": @"Tự động dọn rác khi mở app",
        };
    });

    return dict[key] ?: key;
}

@end
