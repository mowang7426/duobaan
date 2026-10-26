#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>

NS_ASSUME_NONNULL_BEGIN
// UI-only image pipeline. Never returns an unbounded full-resolution decode.
FOUNDATION_EXPORT const NSUInteger DOWallpaperMaximumPixelSize;
FOUNDATION_EXPORT CGImageRef _Nullable DOWallpaperCopyThumbnail(NSURL *url, NSError **error) CF_RETURNS_RETAINED;
FOUNDATION_EXPORT NSData * _Nullable DOWallpaperJPEGData(CGImageRef image, NSError **error);
NS_ASSUME_NONNULL_END
