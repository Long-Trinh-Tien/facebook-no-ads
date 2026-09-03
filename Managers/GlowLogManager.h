// GlowLogManager.h
// Centralized logging for all modules
#import <Foundation/Foundation.h>

@interface GlowLogManager : NSObject

+ (instancetype)shared;

// Write to log file at /var/mobile/Documents/glow.txt
- (void)log:(NSString *)format, ...;

// Write to log file with arguments (variadic)
- (void)logFormat:(const char *)fmt, ...;

// Get current log file path
- (NSString *)logFilePath;

@end
