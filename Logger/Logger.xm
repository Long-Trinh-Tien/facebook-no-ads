// Logger.xm
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>

static void (*orig_MSHookMessageEx)(Class cls, SEL sel, IMP temp_imp, IMP *orig_imp) = NULL;
static IMP (*orig_class_replaceMethod)(Class cls, SEL name, IMP imp, const char *types) = NULL;

static void my_MSHookMessageEx(Class cls, SEL sel, IMP temp_imp, IMP *orig_imp) {
    const char *className = cls ? class_getName(cls) : "nil";
    const char *selName = sel ? sel_getName(sel) : "nil";
    
    FILE *f = fopen("/var/mobile/Documents/glow_logger.txt", "a");
    if (f) {
        fprintf(f, "[MSHookMessageEx] Class: %s, Selector: %s, Replacement: %p\n", className, selName, temp_imp);
        fclose(f);
    }
    
    NSLog(@"[GlowLogger] MSHookMessageEx: class=%s, sel=%s, rep=%p", className, selName, temp_imp);
    
    if (orig_MSHookMessageEx) {
        orig_MSHookMessageEx(cls, sel, temp_imp, orig_imp);
    }
}

static IMP my_class_replaceMethod(Class cls, SEL name, IMP imp, const char *types) {
    const char *className = cls ? class_getName(cls) : "nil";
    const char *selName = name ? sel_getName(name) : "nil";
    
    FILE *f = fopen("/var/mobile/Documents/glow_logger.txt", "a");
    if (f) {
        fprintf(f, "[class_replaceMethod] Class: %s, Selector: %s, Replacement: %p\n", className, selName, imp);
        fclose(f);
    }
    
    NSLog(@"[GlowLogger] class_replaceMethod: class=%s, sel=%s, rep=%p", className, selName, imp);
    
    if (orig_class_replaceMethod) {
        return orig_class_replaceMethod(cls, name, imp, types);
    }
    return NULL;
}

__attribute__((constructor))
static void logger_init(void) {
    NSLog(@"=== 00GlowLogger Initialized ===");
    
    FILE *f = fopen("/var/mobile/Documents/glow_logger.txt", "w");
    if (f) {
        fprintf(f, "=== Glow Original 1.3.1 Hook Log ===\n");
        fclose(f);
    }
    
    // Resolve MSHookMessageEx dynamically from substrate / loader
    void *mshook = dlsym(RTLD_DEFAULT, "MSHookMessageEx");
    if (mshook) {
        // Hook MSHookMessageEx using method replacement or similar
        // Wait, MSHookMessageEx is a C function, so we hook it using MSHookFunction
        void (*mshook_fn)(Class, SEL, IMP, IMP*) = (void (*)(Class, SEL, IMP, IMP*))mshook;
        
        // Resolve MSHookFunction dynamically
        void *mshookfunc = dlsym(RTLD_DEFAULT, "MSHookFunction");
        if (mshookfunc) {
            typedef void (*MSHookFunctionType)(void *, void *, void **);
            ((MSHookFunctionType)mshookfunc)((void *)mshook_fn, (void *)my_MSHookMessageEx, (void **)&orig_MSHookMessageEx);
            NSLog(@"[GlowLogger] MSHookMessageEx hooked successfully");
        }
    } else {
        NSLog(@"[GlowLogger] WARNING: MSHookMessageEx symbol not found");
    }
    
    // Hook class_replaceMethod using MSHookFunction
    void *replace_method = dlsym(RTLD_DEFAULT, "class_replaceMethod");
    if (replace_method) {
        void *mshookfunc = dlsym(RTLD_DEFAULT, "MSHookFunction");
        if (mshookfunc) {
            typedef void (*MSHookFunctionType)(void *, void *, void **);
            ((MSHookFunctionType)mshookfunc)(replace_method, (void *)my_class_replaceMethod, (void **)&orig_class_replaceMethod);
            NSLog(@"[GlowLogger] class_replaceMethod hooked successfully");
        }
    }
}
