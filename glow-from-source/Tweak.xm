// STAGE 0 — Injection Proof
// Mục tiêu: chứng minh code execution bên trong Facebook UI process
// 
// Mỗi build chỉ trả lời 1 câu hỏi.
// Build này hỏi: "Constructor có chạy không?"
//
// KHÔNG feature
// KHÔNG Logos hooks
// KHÔNG global enumeration
// KHÔNG file IO
// KHÔNG timers

#import <UIKit/UIKit.h>

__attribute__((constructor))
static void glow_init(void) {
  dispatch_async(dispatch_get_main_queue(), ^{
    UIAlertController *alert = [UIAlertController
      alertControllerWithTitle:@"Glow STAGE 0"
      message:@"Constructor executes.\nNext: swizzle test."
      preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
      style:UIAlertActionStyleDefault handler:nil]];
    
    UIViewController *root = [UIApplication sharedApplication].keyWindow.rootViewController;
    if (root) {
      [root presentViewController:alert animated:YES completion:nil];
    }
  });
}
