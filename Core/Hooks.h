// Hooks.h
// Init functions for all hook modules
#ifndef Hooks_h
#define Hooks_h

#ifdef __cplusplus
extern "C" {
#endif

// Settings & Init
void reloadPrefs(void);
void prefsChanged(CFNotificationCenterRef center, void *observer,
                  CFStringRef name, const void *object,
                  CFDictionaryRef userInfo);

// Ad block hooks
void initAdBlockHooks(void);

// Story seen hooks
void initStorySeenHooks(void);

// Story download hooks
void initStoryDownloadHooks(void);

// Newsfeed video hooks
void initNewsfeedVideoHooks(void);

// Video item URL capture hooks
void initVideoItemHooks(void);

// Playback state hooks
void initPlaybackStateHooks(void);

// Reels download hooks
void initReelsDownloadHooks(void);

// Long press hooks
void initLongPressHooks(void);

// UI Explorer hooks
void initExplorerHooks(void);

// Runtime enum hooks
void initRuntimeEnumHooks(void);

#ifdef __cplusplus
}
#endif

#endif /* Hooks_h */
