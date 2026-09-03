// GlowCacheManager.m
#import "GlowCacheManager.h"

NSString *const kGlowTagCellLP = @"GlowCellLP";
NSString *const kGlowTagVideoContainerLP = @"GlowVideoContainerLP";
NSString *const kGlowTagPlaybackController = @"GlowPlaybackController";
NSString *const kGlowTagReelItem = @"GlowReelItem";
NSString *const kGlowTagReelHD = @"GlowReelHD";
NSString *const kGlowTagReelSD = @"GlowReelSD";

@implementation GlowCacheManager

+ (instancetype)shared {
    static GlowCacheManager *instance = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _itemToURLDict = [[NSMutableDictionary alloc] init];
        _urlCacheBySidebar = [[NSMutableDictionary alloc] init];
        _storyContainersWithLongPress = [[NSMutableSet alloc] init];
        _overlaysWithButton = [[NSMutableSet alloc] init];
    }
    return self;
}

- (NSDictionary *)urlsForItem:(id)item {
    if (!item) return nil;
    NSValue *key = [NSValue valueWithNonretainedObject:item];
    return [self.itemToURLDict objectForKey:key];
}

- (void)setURLsForItem:(id)item hd:(NSURL *)hd sd:(NSURL *)sd {
    if (!item) return;
    NSValue *key = [NSValue valueWithNonretainedObject:item];
    NSMutableDictionary *entry = [[self.itemToURLDict objectForKey:key] mutableCopy];
    if (!entry) entry = [[NSMutableDictionary alloc] init];

    if (hd) [entry setObject:hd forKey:@"HD"];
    if (sd) [entry setObject:sd forKey:@"SD"];
    [entry setObject:[NSDate date] forKey:@"at"];

    [self.itemToURLDict setObject:entry forKey:key];
}

- (NSDictionary *)urlsForSidebar:(id)sidebar {
    if (!sidebar) return nil;
    NSValue *key = [NSValue valueWithNonretainedObject:sidebar];
    return [self.urlCacheBySidebar objectForKey:key];
}

- (void)setURLsForSidebar:(id)sidebar hd:(NSURL *)hd sd:(NSURL *)sd {
    if (!sidebar) return;
    NSValue *key = [NSValue valueWithNonretainedObject:sidebar];
    NSMutableDictionary *entry = [[NSMutableDictionary alloc] init];
    if (hd) [entry setObject:hd forKey:@"HD"];
    if (sd) [entry setObject:sd forKey:@"SD"];
    [self.urlCacheBySidebar setObject:entry forKey:key];
}

- (void)clearAll {
    [self.itemToURLDict removeAllObjects];
    [self.urlCacheBySidebar removeAllObjects];
    [self.storyContainersWithLongPress removeAllObjects];
    [self.overlaysWithButton removeAllObjects];
    self.cachedHDURL = nil;
    self.cachedSDURL = nil;
    self.cachedAt = nil;
    self.currentPlayingItem = nil;
}

@end
