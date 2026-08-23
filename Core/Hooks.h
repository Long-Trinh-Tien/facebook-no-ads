// Core/Hooks.h
// Forward declarations for all hook initializers
#ifndef HOOKS_H
#define HOOKS_H

#ifdef __cplusplus
extern "C" {
#endif

void initAdBlockHooks(void);
void initStorySeenHooks(void);
void initStoryDownloadHooks(void);
void initNewsfeedVideoHooks(void);
void initVideoItemHooks(void);
void initPlaybackStateHooks(void);
void initReelsDownloadHooks(void);
void initLongPressHooks(void);
void initExplorerHooks(void);
void initRuntimeEnumHooks(void);
void initLikeConfirmHooks(void);
void initNoAutoRefreshHooks(void);

// UI helper
void installLongPressOnCurrentUI(void);
void reloadPrefs(void);

#ifdef __cplusplus
}
#endif

#endif // HOOKS_H
