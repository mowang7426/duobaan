#import "DOWallpaperImage.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <math.h>

const NSUInteger DOWallpaperMaximumPixelSize = 2048;
static const unsigned long long DOMaximumInputBytes = 64ULL * 1024 * 1024;

static void DOImageError(NSError **error, NSString *message)
{
    if (error) *error = [NSError errorWithDomain:@"DOWallpaperImage" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
}

CGImageRef DOWallpaperCopyThumbnail(NSURL *url, NSError **error)
{
    NSNumber *size = nil;
    if (![url getResourceValue:&size forKey:NSURLFileSizeKey error:error]) return NULL;
    if (!size || size.unsignedLongLongValue == 0 || size.unsignedLongLongValue > DOMaximumInputBytes) {
        DOImageError(error, @"请选择不超过 64 MB 的有效图片。");
        return NULL;
    }
    NSDictionary *sourceOptions = @{(__bridge NSString *)kCGImageSourceShouldCache:@NO};
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, (__bridge CFDictionaryRef)sourceOptions);
    if (!source || CGImageSourceGetCount(source) == 0) {
        if (source) CFRelease(source);
        DOImageError(error, @"无法读取这张图片，请尝试 JPEG、PNG 或 HEIC 图片。");
        return NULL;
    }
    NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL));
    double width = [properties[(__bridge NSString *)kCGImagePropertyPixelWidth] doubleValue];
    double height = [properties[(__bridge NSString *)kCGImagePropertyPixelHeight] doubleValue];
    // Reject extreme/decompression-bomb inputs before asking ImageIO to decode.
    if (!isfinite(width) || !isfinite(height) || width < 1 || height < 1 ||
        width > 50000 || height > 50000 || width * height > 120000000) {
        CFRelease(source);
        DOImageError(error, @"图片尺寸过大或无效，请选择不超过 1.2 亿像素的图片。");
        return NULL;
    }
    NSDictionary *options = @{
        (__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways:@YES,
        (__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform:@YES,
        (__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize:@(DOWallpaperMaximumPixelSize),
        (__bridge NSString *)kCGImageSourceShouldCacheImmediately:@YES
    };
    CGImageRef thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
    CFRelease(source);
    if (thumbnail && (CGImageGetWidth(thumbnail) > DOWallpaperMaximumPixelSize || CGImageGetHeight(thumbnail) > DOWallpaperMaximumPixelSize)) {
        CGImageRelease(thumbnail);
        thumbnail = NULL;
    }
    if (!thumbnail) DOImageError(error, @"图片解码失败，原有壁纸未更改。");
    return thumbnail;
}

NSData *DOWallpaperJPEGData(CGImageRef image, NSError **error)
{
    NSMutableData *data = [NSMutableData data];
    CGImageDestinationRef destination = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data, (__bridge CFStringRef)UTTypeJPEG.identifier, 1, NULL);
    if (!destination) {
        DOImageError(error, @"无法创建壁纸文件。");
        return nil;
    }
    // Encode pixels only: do not persist source GPS, EXIF, asset IDs or paths.
    CGImageDestinationAddImage(destination, image, (__bridge CFDictionaryRef)@{(__bridge NSString *)kCGImageDestinationLossyCompressionQuality:@0.85});
    BOOL success = CGImageDestinationFinalize(destination);
    CFRelease(destination);
    if (!success) {
        DOImageError(error, @"无法保存壁纸图片。");
        return nil;
    }
    return data;
}
