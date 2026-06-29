// Logger.xm
// Fake CydiaSubstrate that intercepts calls, queues them in memory, and writes to file post-launch
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <pthread.h>

typedef void (*MSHookMessageExType)(Class cls, SEL sel, IMP temp_imp, IMP *orig_imp);
typedef void (*MSHookFunctionType)(void *symbol, void *replace, void **result);

// Globals to store real implementations
static MSHookMessageExType real_MSHookMessageEx = NULL;
static MSHookFunctionType real_MSHookFunction = NULL;

// Safe in-memory log queue
static NSMutableArray<NSString *> *logQueue = nil;
static pthread_mutex_t logMutex = PTHREAD_MUTEX_INITIALIZER;

static void queue_log(NSString *logStr) {
    NSLog(@"[FakeSubstrate] %@", logStr); // Print to console immediately
    
    pthread_mutex_lock(&logMutex);
    if (!logQueue) {
        logQueue = [[NSMutableArray alloc] init];
    }
    [logQueue addObject:logStr];
    pthread_mutex_unlock(&logMutex);
}

static void write_logs_to_file(void) {
    pthread_mutex_lock(&logMutex);
    NSArray<NSString *> *logsToWrite = [logQueue copy];
    [logQueue removeAllObjects];
    pthread_mutex_unlock(&logMutex);
    
    if (logsToWrite.count == 0) return;
    
    NSString *logPath = @"/var/mobile/Documents/glow_logger.txt";
    
    NSFileManager *fm = [NSFileManager defaultManager];
    // Write header if file does not exist
    if (![fm fileExistsAtPath:logPath]) {
        NSString *header = @"=== Glow Original 1.3.1 Hook Log (Via Fake Substrate) ===\n";
        [header writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:logPath];
    if (fh) {
        @try {
            [fh seekToEndOfFile];
            for (NSString *line in logsToWrite) {
                NSString *formatted = [line stringByAppendingString:@"\n"];
                [fh writeData:[formatted dataUsingEncoding:NSUTF8StringEncoding]];
            }
            [fh synchronizeFile];
        } @catch (NSException *e) {
            NSLog(@"[FakeSubstrate] Write log exception: %@", e.reason);
        } @finally {
            [fh closeFile];
        }
    }
}

static void resolve_real_substrate(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void *handle = dlopen("@loader_path/CydiaSubstrateReal", RTLD_LAZY);
        if (!handle) {
            handle = dlopen("@rpath/CydiaSubstrate.framework/CydiaSubstrateReal", RTLD_LAZY);
        }
        if (!handle) {
            handle = dlopen("@executable_path/Frameworks/CydiaSubstrate.framework/CydiaSubstrateReal", RTLD_LAZY);
        }
        if (!handle) {
            NSString *frameworksPath = [[NSBundle mainBundle] privateFrameworksPath];
            NSString *substratePath = [frameworksPath stringByAppendingPathComponent:@"CydiaSubstrate.framework/CydiaSubstrateReal"];
            handle = dlopen([substratePath UTF8String], RTLD_LAZY);
        }
        
        if (handle) {
            real_MSHookMessageEx = (MSHookMessageExType)dlsym(handle, "MSHookMessageEx");
            real_MSHookFunction = (MSHookFunctionType)dlsym(handle, "MSHookFunction");
            NSLog(@"[FakeSubstrate] Successfully loaded CydiaSubstrateReal and resolved symbols");
        } else {
            NSLog(@"[FakeSubstrate] ERROR: Failed to load CydiaSubstrateReal");
        }
        
        // Start delayed writer (5 seconds after first call) to flush logs safely when sandbox is ready
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSLog(@"[FakeSubstrate] Flushing early logs to file...");
            write_logs_to_file();
            
            // Set up a repeating timer to periodically write logs
            [NSTimer scheduledTimerWithTimeInterval:3.0 repeats:YES block:^(NSTimer * _Nonnull timer) {
                write_logs_to_file();
            }];
        });
    });
}

extern "C" void MSHookMessageEx(Class cls, SEL sel, IMP temp_imp, IMP *orig_imp) {
    resolve_real_substrate();
    
    const char *className = cls ? class_getName(cls) : "nil";
    const char *selName = sel ? sel_getName(sel) : "nil";
    
    NSString *logMsg = [NSString stringWithFormat:@"[MSHookMessageEx] Class: %s, Selector: %s, Replacement: %p", className, selName, temp_imp];
    queue_log(logMsg);
    
    // CRITICAL: Protect against nil class to prevent crash!
    if (!cls) {
        queue_log([NSString stringWithFormat:@"[FakeSubstrate] WARNING: cls is nil for selector %s! Skipping hook to prevent crash.", selName]);
        return;
    }
    
    if (real_MSHookMessageEx) {
        real_MSHookMessageEx(cls, sel, temp_imp, orig_imp);
    }
}

extern "C" void MSHookFunction(void *symbol, void *replace, void **result) {
    resolve_real_substrate();
    
    const char *symName = "unknown";
    Dl_info info;
    if (dladdr(symbol, &info) && info.dli_sname) {
        symName = info.dli_sname;
    }
    
    NSString *logMsg = [NSString stringWithFormat:@"[MSHookFunction] Symbol: %p (%s), Replacement: %p", symbol, symName, replace];
    queue_log(logMsg);
    
    if (real_MSHookFunction) {
        real_MSHookFunction(symbol, replace, result);
    }
}

extern "C" void *MSHookIvar(id self, const char *name) {
    Ivar ivar = class_getInstanceVariable(object_getClass(self), name);
    return ivar ? (void *)((char *)(__bridge void *)self + ivar_getOffset(ivar)) : NULL;
}

__attribute__((constructor))
static void fake_substrate_init(void) {
    NSLog(@"=== Fake CydiaSubstrate loaded (In-Memory Logging Ready) ===");
}
