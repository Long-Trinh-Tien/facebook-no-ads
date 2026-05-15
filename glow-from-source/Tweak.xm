#import <UIKit/UIKit.h>
#import <dlfcn.h>

%ctor {
  @autoreleasepool {
    NSString *fw = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"Frameworks/FBSharedFramework.framework/FBSharedFramework"];
    dlopen([fw UTF8String], RTLD_NOW | RTLD_GLOBAL);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
      UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Glow" message:@"Welcome! Test popup" preferredStyle:UIAlertControllerStyleAlert];
      [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
      [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:a animated:YES completion:nil];
    });

    NSLog(@"[Glow] minimal test loaded");
  }
}
