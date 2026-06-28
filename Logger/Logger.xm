// Logger.xm
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>

typedef void (*MSHookMessageExType)(Class cls, SEL sel, IMP temp_imp, IMP *orig_imp);

// Export MSHookMessageEx publicly to interpose Glow's calls
extern "C" void MSHookMessageEx(Class cls, SEL sel, IMP temp_imp, IMP *orig_imp) {
    const char *className = cls ? class_getName(cls) : "nil";
    const char *selName = sel ? sel_getName(sel) : "nil";
    
    FILE *f = fopen("/var/mobile/Documents/glow_logger.txt", "a");
    if (f) {
        fprintf(f, "[MSHookMessageEx] Class: %s, Selector: %s, Replacement: %p\n", className, selName, temp_imp);
        fclose(f);
    }
    
    NSLog(@"[GlowLogger] MSHookMessageEx: class=%s, sel=%s, rep=%p", className, selName, temp_imp);
    
    // Resolve the real MSHookMessageEx from CydiaSubstrate loaded next
    static MSHookMessageExType real_MSHookMessageEx = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        real_MSHookMessageEx = (MSHookMessageExType)dlsym(RTLD_NEXT, "MSHookMessageEx");
    });
    
    if (real_MSHookMessageEx) {
        real_MSHookMessageEx(cls, sel, temp_imp, orig_imp);
    } else {
        NSLog(@"[GlowLogger] ERROR: Failed to resolve real MSHookMessageEx via RTLD_NEXT");
    }
}

__attribute__((constructor))
static void logger_init(void) {
    NSLog(@"=== 00GlowLogger Loaded (Symbol Interpositioning Active) ===");
    
    FILE *f = fopen("/var/mobile/Documents/glow_logger.txt", "w");
    if (f) {
        fprintf(f, "=== Glow Original 1.3.1 Hook Log ===\n");
        fclose(f);
    }
}
