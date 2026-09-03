// Logger.xm
// A stable, completely self-contained CydiaSubstrate logger tweak that dynamically hooks MSHookMessageEx in memory.
// Logs step-by-step progress immediately to locate the exact line causing any crash.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>

static void standalone_log(const char *format, ...) {
    char buffer[2048];
    va_list args;
    va_start(args, format);
    vsnprintf(buffer, sizeof(buffer), format, args);
    va_end(args);
    
    // 1. Log to NSLog (syslog)
    NSLog(@"[00GlowLogger] %s", buffer);
    
    // 2. Write to /var/mobile/Documents/glow.txt (if writable)
    FILE *f = fopen("/var/mobile/Documents/glow.txt", "a");
    if (f) {
        fputs(buffer, f);
        fflush(f);
        fclose(f);
    }
    
    // 3. Write to the app's sandbox Documents directory (always writable)
    @try {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        if (paths.count > 0) {
            NSString *docDir = paths[0];
            NSString *filePath = [docDir stringByAppendingPathComponent:@"glow_sandbox.txt"];
            FILE *fs = fopen([filePath UTF8String], "a");
            if (fs) {
                fputs(buffer, fs);
                fflush(fs);
                fclose(fs);
            }
        }
    } @catch (NSException *e) {
        NSLog(@"[00GlowLogger] Failed to write to sandbox log: %@", e.reason);
    }
}

#define LOG(fmt, ...) standalone_log(fmt, ##__VA_ARGS__)

// Signatures for CydiaSubstrate/Ellekit functions
typedef void (*MSHookMessageExType)(Class cls, SEL sel, IMP temp_imp, IMP *orig_imp);
typedef void (*MSHookFunctionType)(void *symbol, void *replace, void **result);

static MSHookMessageExType orig_MSHookMessageEx = NULL;

static void hooked_MSHookMessageEx(Class cls, SEL sel, IMP temp_imp, IMP *orig_imp) {
    @try {
        const char *className = cls ? class_getName(cls) : "nil";
        const char *selName = sel ? sel_getName(sel) : "nil";
        
        LOG("[OriginalGlow/MSHookMessageEx] Class: %s, Selector: %s, Replacement: %p\n", className, selName, temp_imp);
    } @catch (NSException *e) {
        LOG("[Logger] Exception logging MSHookMessageEx: %s\n", e.reason.UTF8String);
    }
    
    // Call the real MSHookMessageEx
    if (orig_MSHookMessageEx) {
        orig_MSHookMessageEx(cls, sel, temp_imp, orig_imp);
    }
}

%ctor {
    LOG("=== [Logger] %ctor Enter ===\n");
    
    @try {
        LOG("[Logger] Locating Substrate/Ellekit symbols in process memory...\n");
        void *msHookMsgExPtr = dlsym(RTLD_DEFAULT, "MSHookMessageEx");
        LOG("[Logger] dlsym MSHookMessageEx pointer resolved: %p\n", msHookMsgExPtr);
        
        void *msHookFnPtr = dlsym(RTLD_DEFAULT, "MSHookFunction");
        LOG("[Logger] dlsym MSHookFunction pointer resolved: %p\n", msHookFnPtr);
        
        if (msHookMsgExPtr && msHookFnPtr) {
            MSHookFunctionType msHookFn = (MSHookFunctionType)msHookFnPtr;
            
            LOG("[Logger] Calling MSHookFunction to hook MSHookMessageEx...\n");
            msHookFn(msHookMsgExPtr, (void *)hooked_MSHookMessageEx, (void **)&orig_MSHookMessageEx);
            LOG("[Logger] Successfully hooked MSHookMessageEx of Substrate dynamically\n");
        } else {
            LOG("[Logger] ERROR: MSHookMessageEx or MSHookFunction pointer was NULL!\n");
        }
    } @catch (NSException *e) {
        LOG("[Logger] Constructor exception: %s\n", e.reason.UTF8String);
    }
    
    LOG("=== [Logger] %ctor Exit ===\n");
}
