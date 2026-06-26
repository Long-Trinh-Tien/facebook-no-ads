// GlowCommon.h
// Common definitions used across all modules
#ifndef GlowCommon_h
#define GlowCommon_h

#import "Managers/GlowLogManager.h"

// LOG macro for all modules (C-compatible)
#define LOG(fmt, ...) [[GlowLogManager shared] logFormat:fmt, ##__VA_ARGS__]

// Shorthand for showToast
#define TOAST(msg) [GlowViewUtils showSafeToast:msg]

#endif /* GlowCommon_h */
