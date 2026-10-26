#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "DOWallpaperImage.h"
#import <fcntl.h>
#import <unistd.h>

static NSUInteger checks = 0;
static void Check(BOOL condition, NSString *message) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
    checks++;
}

static void MakeImage(NSURL *url, size_t width, size_t height, CFStringRef type, int orientation) {
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, 0, colorSpace, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(colorSpace);
    Check(context != NULL, @"fixture bitmap");
    CGContextSetRGBFillColor(context, 0.2, 0.5, 0.9, 1);
    CGContextFillRect(context, CGRectMake(0, 0, width, height));
    CGImageRef image = CGBitmapContextCreateImage(context);
    CGImageDestinationRef destination = CGImageDestinationCreateWithURL((__bridge CFURLRef)url, type, 1, NULL);
    Check(destination != NULL, @"fixture destination");
    CGImageDestinationAddImage(destination, image, (__bridge CFDictionaryRef)@{(__bridge NSString *)kCGImagePropertyOrientation:@(orientation)});
    Check(CGImageDestinationFinalize(destination), @"fixture encoding");
    CFRelease(destination);
    CGImageRelease(image);
    CGContextRelease(context);
}

int main(void) {
    @autoreleasepool {
        // Tests only create/read files in this project's ignored build directory.
        NSURL *directory = [NSURL fileURLWithPath:@".build/wallpaper/fixtures" isDirectory:YES];
        NSError *error = nil;
        Check([NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:&error], @"test directory");
        NSURL *large = [directory URLByAppendingPathComponent:@"large.jpg"];
        MakeImage(large, 4096, 1024, (__bridge CFStringRef)UTTypeJPEG.identifier, 1);
        CGImageRef image = DOWallpaperCopyThumbnail(large, &error);
        Check(image != NULL && !error, @"large image decode");
        Check(CGImageGetWidth(image) == 2048 && CGImageGetHeight(image) == 512, @"2048 pixel cap and aspect ratio");
        NSData *encoded = DOWallpaperJPEGData(image, &error);
        CGImageRelease(image);
        Check(encoded.length > 0 && !error, @"JPEG re-encoding");
        NSURL *saved = [directory URLByAppendingPathComponent:@"saved.jpg"];
        Check([encoded writeToURL:saved options:NSDataWritingAtomic error:&error], @"atomic save");
        image = DOWallpaperCopyThumbnail(saved, &error);
        Check(image && CGImageGetWidth(image) == 2048, @"reload saved thumbnail");
        CGImageRelease(image);
        CGImageSourceRef savedSource = CGImageSourceCreateWithURL((__bridge CFURLRef)saved, NULL);
        NSDictionary *metadata = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(savedSource, 0, NULL));
        Check(metadata[(__bridge NSString *)kCGImagePropertyGPSDictionary] == nil, @"no source GPS metadata");
        CFRelease(savedSource);
        NSURL *rotated = [directory URLByAppendingPathComponent:@"rotated.jpg"];
        MakeImage(rotated, 512, 256, (__bridge CFStringRef)UTTypeJPEG.identifier, 6);
        image = DOWallpaperCopyThumbnail(rotated, &error);
        Check(image && CGImageGetWidth(image) == 256 && CGImageGetHeight(image) == 512, @"EXIF orientation applied");
        CGImageRelease(image);
        NSURL *png = [directory URLByAppendingPathComponent:@"small.png"];
        MakeImage(png, 80, 40, (__bridge CFStringRef)UTTypePNG.identifier, 1);
        image = DOWallpaperCopyThumbnail(png, &error);
        Check(image && CGImageGetWidth(image) == 80 && CGImageGetHeight(image) == 40, @"small PNG not enlarged");
        CGImageRelease(image);
        NSURL *invalid = [directory URLByAppendingPathComponent:@"invalid.jpg"];
        Check([[@"not an image" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:invalid options:NSDataWritingAtomic error:&error], @"invalid fixture");
        error = nil;
        image = DOWallpaperCopyThumbnail(invalid, &error);
        Check(!image && error != nil, @"corrupt file rejected");
        error = nil;
        image = DOWallpaperCopyThumbnail([directory URLByAppendingPathComponent:NSUUID.UUID.UUIDString], &error);
        Check(!image && error != nil, @"missing file rejected");
        NSURL *huge = [directory URLByAppendingPathComponent:@"oversize.jpg"];
        int descriptor = open(huge.fileSystemRepresentation, O_WRONLY | O_CREAT | O_TRUNC, 0600);
        Check(descriptor >= 0 && ftruncate(descriptor, 64LL * 1024 * 1024 + 1) == 0, @"sparse oversized fixture");
        close(descriptor);
        error = nil;
        image = DOWallpaperCopyThumbnail(huge, &error);
        Check(!image && error != nil, @"64 MB file cap");
        [NSFileManager.defaultManager removeItemAtURL:huge error:NULL];

        NSData *projectData = [NSData dataWithContentsOfFile:@"Application/Dopamine.xcodeproj/project.pbxproj"];
        error = nil;
        NSDictionary *project = [NSPropertyListSerialization propertyListWithData:projectData options:NSPropertyListImmutable format:NULL error:&error];
        Check(project != nil && !error, @"Xcode project parses");
        NSDictionary *objects = project[@"objects"];
        NSArray *sources = objects[@"8C7198112ABF0E82003C6658"][@"files"];
        for (NSString *identifier in @[@"D0A110000000000000000001", @"D0A110000000000000000002"]) {
            Check([sources filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF == %@", identifier]].count == 1, @"wallpaper source registered exactly once");
            NSString *reference = objects[identifier][@"fileRef"];
            NSString *path = objects[reference][@"path"];
            Check([NSFileManager.defaultManager fileExistsAtPath:[@"Application/Dopamine/UI" stringByAppendingPathComponent:path]], @"registered source exists");
        }
        for (NSString *configuration in @[@"8C71982F2ABF0E84003C6658", @"8C7198302ABF0E84003C6658"]) {
            NSDictionary *settings = objects[configuration][@"buildSettings"];
            Check([settings[@"PRODUCT_BUNDLE_IDENTIFIER"] isEqual:@"com.opa334.Dopamine"], @"upstream identifier preserved");
            NSArray *flags = settings[@"OTHER_LDFLAGS"];
            Check([flags containsObject:@"PhotosUI"] && [flags containsObject:@"ImageIO"] && [flags containsObject:@"UniformTypeIdentifiers"], @"framework linkage declared");
        }
        printf("PASS: %lu checks (image pipeline and project registration only; not app execution).\n", (unsigned long)checks);
    }
    return 0;
}
