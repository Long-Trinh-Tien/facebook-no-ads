// GlowCommon.h
// Common definitions used across all modules
#ifndef GlowCommon_h
#define GlowCommon_h

#import "Managers/GlowLogManager.h"

#import <objc/runtime.h>

// LOG macro for all modules (C-compatible)
#define LOG(fmt, ...) [[GlowLogManager shared] logFormat:fmt, ##__VA_ARGS__]

// Shorthand for showToast
#define TOAST(msg) [GlowViewUtils showSafeToast:msg]

static inline id safe_get_ivar(id obj, Ivar ivar) {
    if (!obj || !ivar) return nil;
    const char *type = ivar_getTypeEncoding(ivar);
    if (type && type[0] == '@') {
        typedef id (*GetIvarFn)(id, Ivar);
        return ((GetIvarFn)object_getIvar)(obj, ivar);
    }
    return nil;
}

#endif /* GlowCommon_h */
