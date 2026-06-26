// GlowSettingsManager.h
// Manages all user settings (18 s_* flags) and preferences loading
#import <Foundation/Foundation.h>

@interface GlowSettingsManager : NSObject

+ (instancetype)shared;

// Load settings from NSUserDefaults
- (void)loadSettings;

// Getters for all settings
@property (nonatomic, assign) BOOL removeAds;
@property (nonatomic, assign) BOOL disableStorySeen;
@property (nonatomic, assign) BOOL downloadVideo;
@property (nonatomic, assign) BOOL downloadStory;
@property (nonatomic, assign) BOOL removePYMK;
@property (nonatomic, assign) BOOL removeReelsCarousel;
@property (nonatomic, assign) BOOL removeSuggested;
@property (nonatomic, assign) BOOL hideComposer;
@property (nonatomic, assign) BOOL disableAutoNext;
@property (nonatomic, assign) BOOL confirmLike;
@property (nonatomic, assign) BOOL downloadReels;
@property (nonatomic, assign) BOOL hideOverlay;
@property (nonatomic, assign) BOOL confirmReelsLike;
@property (nonatomic, assign) BOOL downloadLongPress;
@property (nonatomic, assign) BOOL markAsSeen;
@property (nonatomic, assign) BOOL removeStoryPYMK;
@property (nonatomic, assign) BOOL allFormats;
@property (nonatomic, assign) BOOL clearCacheOnLaunch;
@property (nonatomic, assign) BOOL notifyUpdates;

// Localization helper
+ (NSString *)localizedString:(NSString *)key;

@end
