#import <UIKit/UIKit.h>
#import <dlfcn.h>

__attribute__((constructor))
static void glow_init() {
    @autoreleasepool {
        NSLog(@"[Glow] v1.3.1 loaded (ZERO classes test)");
    }
}
