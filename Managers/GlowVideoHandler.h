// GlowVideoHandler.h
// Handles Newsfeed video download (long press)
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface GlowVideoHandler : NSObject <UIGestureRecognizerDelegate>

+ (instancetype)shared;

// Long press handler for newsfeed video cells
- (void)onNewsfeedCellLongPress:(UILongPressGestureRecognizer *)gr;

// Long press handler for VideoContainerView
- (void)onVideoContainerLongPress:(UILongPressGestureRecognizer *)gr;

// Present quality action sheet (HD/SD)
- (void)presentQualityActionSheetHD:(NSURL *)hd
                                  sd:(NSURL *)sd
                           sourceView:(UIView *)sourceView;

@end
