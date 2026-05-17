// STAGE 1 — Haoict pattern: %ctor instead of __attribute__((constructor))
// File renamed to Tweak.x (Logos format) — haoict uses this

#import <UIKit/UIKit.h>

%ctor {
  @autoreleasepool {
    NSString *docs = NSSearchPathForDirectoriesInDomains(
      NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *path = [docs stringByAppendingPathComponent:@"glow_hook.txt"];
    
    NSMutableString *log = [NSMutableString string];
    [log appendString:@"%ctor executed\n"];
    [log appendFormat:@"NSObject class: %@\n", [NSObject class]];
    [log appendFormat:@"NSString class: %@\n", [NSString class]];
    
    // Test method_setImplementation on NSObject.description
    Class cls = [NSObject class];
    SEL sel = @selector(description);
    Method m = class_getInstanceMethod(cls, sel);
    IMP orig = method_getImplementation(m);
    
    [log appendFormat:@"description IMP: %p\n", orig];
    [log appendFormat:@"description output: %@\n", [[NSObject new] description]];
    
    // Try hooking
    static IMP (*origDesc)(id, SEL);
    method_setImplementation(m, imp_implementationWithBlock(^id(id self) {
      return @"HOOKED_DESCRIPTION";
    }));
    
    [log appendFormat:@"hooked description: %@\n", [[NSObject new] description]];
    
    // Restore
    method_setImplementation(m, orig);
    
    [log writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
  }
}
