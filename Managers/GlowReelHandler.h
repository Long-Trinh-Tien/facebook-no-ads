// GlowReelHandler.h
// Handles Reels video download (button + long press)
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface GlowReelHandler : NSObject

+ (instancetype)shared;

// Button tap handler
- (void)onReelButtonTap:(UIButton *)sender;

// Find Reels overlay (parent view)
- (UIView *)findReelsOverlayFrom:(UIView *)view;

// Check if view is in Reels fullscreen context
- (BOOL)isInReelsFullScreen:(UIView *)sideBar;

// Add download button to Reels sidebar
- (void)addDownloadButtonToSidebar:(UIView *)sideBar;

// Pre-warm URLs for sidebar
- (void)preWarmURLsForSidebar:(UIView *)sideBar;

@end
