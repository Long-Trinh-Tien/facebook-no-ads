// GlowLogManager.m
#import "GlowCommon.h"
#import "GlowLogManager.h"

@implementation GlowLogManager {
    char _logPath[512];
}

+ (instancetype)shared {
    static GlowLogManager *instance = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        const char *home = getenv("HOME");
        if (home) {
            snprintf(_logPath, sizeof(_logPath), "%s/Documents/glow.txt", home);
        }
    }
    return self;
}

- (NSString *)logFilePath {
    if (_logPath[0] == 0) {
        return @"/var/mobile/Documents/glow.txt";
    }
    return [NSString stringWithUTF8String:_logPath];
}

- (void)log:(NSString *)format, ... {
    if (!format) return;

    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    [self writeToFile:message];
}

- (void)logFormat:(const char *)fmt, ... {
    if (!fmt) return;

    char buffer[2048];
    va_list args;
    va_start(args, fmt);
    vsnprintf(buffer, sizeof(buffer), fmt, args);
    va_end(args);

    [self writeToFile:[NSString stringWithUTF8String:buffer]];
}

- (void)writeToFile:(NSString *)message {
    FILE *f = fopen(_logPath, "a");
    if (!f) f = fopen("/var/mobile/Documents/glow.txt", "a");
    if (f) {
        fprintf(f, "%s", [message UTF8String]);
        fclose(f);
    }
}

@end

// C-compatible LOG macro for backward compatibility
// Usage: LOG("format %s\n", value)
static inline void glow_log(const char *fmt, ...) {
    char buffer[2048];
    va_list args;
    va_start(args, fmt);
    vsnprintf(buffer, sizeof(buffer), fmt, args);
    va_end(args);

    NSString *msg = [NSString stringWithUTF8String:buffer];
    [[GlowLogManager shared] log:@"%@", msg];
}

#define LOG(fmt, ...) glow_log(fmt, ##__VA_ARGS__)
