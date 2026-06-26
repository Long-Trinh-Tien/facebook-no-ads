// GlowStoryHandler.h
// Handles Story download logic (photo + video stories)
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface GlowStoryHandler : NSObject

+ (instancetype)shared;

// Find media URL in story container
- (NSURL *)findMediaURLInContainer:(UIView *)container isVideo:(BOOL *)outIsVideo;

// Long press handler (legacy)
- (void)onStoryLongPress:(UILongPressGestureRecognizer *)gr;

// Button tap handler (new)
- (void)onStoryDownloadTapped:(UIButton *)sender;

// Download story media
- (void)downloadStoryFromContainer:(UIView *)container;

// Save image to Photos
- (void)saveImageToPhotos:(UIImage *)image;

// Save video to Photos
- (void)saveVideoToPhotosAtPath:(NSString *)path;

@end
