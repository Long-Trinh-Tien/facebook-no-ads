// GlowCacheManager.h
// Centralized cache for video URLs and items
#import <Foundation/Foundation.h>

@interface GlowCacheManager : NSObject

+ (instancetype)shared;

// Global HD/SD URL cache (last accessed)
@property (nonatomic, strong) NSURL *cachedHDURL;
@property (nonatomic, strong) NSURL *cachedSDURL;
@property (nonatomic, strong) NSDate *cachedAt;

// Currently playing item (weak reference, auto-clears on dealloc)
@property (nonatomic, weak) id currentPlayingItem;

// Per-item URL dictionary (key = FBVideoPlaybackItem, value = @{HD, SD, at})
@property (nonatomic, strong) NSMutableDictionary *itemToURLDict;

// Per-sidebar URL dictionary (key = FBShortsSideBarView, value = @{HD, SD})
@property (nonatomic, strong) NSMutableDictionary *urlCacheBySidebar;

// Track which containers already have long press
@property (nonatomic, strong) NSMutableSet *storyContainersWithLongPress;
@property (nonatomic, strong) NSMutableSet *overlaysWithButton;

// Associated Object keys
extern NSString *const kGlowTagCellLP;
extern NSString *const kGlowTagVideoContainerLP;
extern NSString *const kGlowTagPlaybackController;
extern NSString *const kGlowTagReelItem;
extern NSString *const kGlowTagReelHD;
extern NSString *const kGlowTagReelSD;

// Helper methods
- (NSDictionary *)urlsForItem:(id)item;
- (void)setURLsForItem:(id)item hd:(NSURL *)hd sd:(NSURL *)sd;
- (NSDictionary *)urlsForSidebar:(id)sidebar;
- (void)setURLsForSidebar:(id)sidebar hd:(NSURL *)hd sd:(NSURL *)sd;

- (void)clearAll;

@end
