#import "DOWallpaperController.h"
#import "DOWallpaperImage.h"
#import <PhotosUI/PhotosUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface DOWallpaperController () <PHPickerViewControllerDelegate>
@property (nonatomic, strong) dispatch_queue_t workQueue;
@property (nonatomic, weak) UIViewController *presenter;
@property (nonatomic, strong) UIAlertController *progressAlert;
@property (nonatomic) BOOL busy;
@property (nonatomic, strong) NSProgress *importProgress;
// Accessed under @synchronized(self) to order cancellation against atomic save.
@property (nonatomic) NSUInteger operationID;
@end

@implementation DOWallpaperController

- (instancetype)init
{
    if ((self = [super init])) {
        _workQueue = dispatch_queue_create("Dopamine.UI.Wallpaper", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0));
    }
    return self;
}

// Resolve at use time, never hard-code a container UUID or a jailbreak path.
// Only the app's own Application Support/DOWallpaper directory is touched.
- (NSURL *)wallpaperURLCreatingDirectory:(BOOL)create error:(NSError **)error
{
    NSFileManager *manager = NSFileManager.defaultManager;
    // This app has upstream no-sandbox entitlements. Fail closed if Foundation
    // does not resolve an app data container; never fall back to /var/mobile.
    NSURL *home = [[NSURL fileURLWithPath:NSHomeDirectory() isDirectory:YES] URLByResolvingSymlinksInPath];
    NSString *parent = home.URLByDeletingLastPathComponent.path;
    NSUUID *containerID = [[NSUUID alloc] initWithUUIDString:home.lastPathComponent];
    if (!containerID || ![parent hasSuffix:@"/Containers/Data/Application"]) {
        if (error) *error = [NSError errorWithDomain:@"DOWallpaper" code:3 userInfo:@{NSLocalizedDescriptionKey:@"无法确认本应用的数据容器，未读取或更改壁纸文件。"}];
        return nil;
    }
    NSURL *support = [manager URLForDirectory:NSApplicationSupportDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:NO error:error];
    if (!support) return nil;
    NSURL *directory = [support URLByAppendingPathComponent:@"DOWallpaper" isDirectory:YES];
    NSURL *file = [directory URLByAppendingPathComponent:@"wallpaper.jpg" isDirectory:NO];
    NSString *homePrefix = [home.path stringByAppendingString:@"/"];
    if (![directory.URLByResolvingSymlinksInPath.path hasPrefix:homePrefix] ||
        ![file.URLByResolvingSymlinksInPath.path hasPrefix:homePrefix]) {
        if (error) *error = [NSError errorWithDomain:@"DOWallpaper" code:3 userInfo:@{NSLocalizedDescriptionKey:@"壁纸路径不在本应用容器内，操作已取消。"}];
        return nil;
    }
    if (create && ![manager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:error]) return nil;
    return file;
}

- (void)loadSavedWallpaper
{
    dispatch_async(self.workQueue, ^{
        @autoreleasepool {
            NSURL *url = [self wallpaperURLCreatingDirectory:NO error:NULL];
            CGImageRef thumbnail = url ? DOWallpaperCopyThumbnail(url, NULL) : NULL;
            UIImage *image = thumbnail ? [UIImage imageWithCGImage:thumbnail] : nil;
            if (thumbnail) CGImageRelease(thumbnail);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.imageDidChange) self.imageDidChange(image);
            });
        }
    });
}

- (void)presentSettingsFromViewController:(UIViewController *)presenter
{
    if (self.busy || presenter.presentedViewController) return;
    self.presenter = presenter;
    // Alert avoids an unanchored action-sheet popover on iPad.
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"自定义壁纸" message:@"仅更改 Dopamine 应用背景。图片会缩小并保存在本应用内，自动压暗以保持文字清晰。" preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [menu addAction:[UIAlertAction actionWithTitle:@"从照片选择一张" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        // Wait until the menu is fully dismissed before presenting PHPicker.
        [presenter dismissViewControllerAnimated:YES completion:^{
            [weakSelf presentPickerFrom:presenter];
        }];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"恢复默认壁纸" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [presenter dismissViewControllerAnimated:YES completion:^{
            [weakSelf restoreDefault];
        }];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [presenter presentViewController:menu animated:YES completion:nil];
}

- (void)presentPickerFrom:(UIViewController *)presenter
{
    if (self.busy || presenter.presentedViewController) return;
    PHPickerConfiguration *configuration = [[PHPickerConfiguration alloc] init];
    configuration.filter = PHPickerFilter.imagesFilter;
    configuration.selectionLimit = 1;
    configuration.preferredAssetRepresentationMode = PHPickerConfigurationAssetRepresentationModeCurrent;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:configuration];
    picker.delegate = self;
    // No PHPhotoLibrary authorization, asset identifier, or full-library access.
    [presenter presentViewController:picker animated:YES completion:nil];
}

- (void)beginProgressWithTitle:(NSString *)title completion:(void (^)(void))completion
{
    self.busy = YES;
    @synchronized (self) { self.operationID++; }
    self.progressAlert = [UIAlertController alertControllerWithTitle:title message:@"请稍候，iCloud 图片可能需要下载。" preferredStyle:UIAlertControllerStyleAlert];
    if ([title isEqualToString:@"正在处理壁纸"]) {
        __weak typeof(self) weakSelf = self;
        [self.progressAlert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            @synchronized (strongSelf) { strongSelf.operationID++; }
            [strongSelf.importProgress cancel];
            strongSelf.importProgress = nil;
            strongSelf.progressAlert = nil;
            strongSelf.busy = NO;
            // If an atomic save already completed, re-read that committed state.
            [strongSelf loadSavedWallpaper];
        }]];
    }
    [self.presenter presentViewController:self.progressAlert animated:YES completion:completion];
}

- (void)finishWithImage:(UIImage *)image error:(NSError *)error
{
    // All callbacks and UIKit work are on main; failures preserve the old image.
    if (!error && self.imageDidChange) self.imageDidChange(image);
    UIAlertController *progress = self.progressAlert;
    self.progressAlert = nil;
    [progress dismissViewControllerAnimated:YES completion:^{
        self.busy = NO;
        if (error && self.presenter && !self.presenter.presentedViewController) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"壁纸未更改" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
            [self.presenter presentViewController:alert animated:YES completion:nil];
        }
    }];
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results
{
    [picker dismissViewControllerAnimated:YES completion:^{
        if (results.count == 0) return; // Cancel does not touch persisted state.
        NSItemProvider *provider = results.firstObject.itemProvider;
        [self beginProgressWithTitle:@"正在处理壁纸" completion:^{
            if (!self.busy) return;
            __block NSUInteger operation;
            @synchronized (self) { operation = self.operationID; }
            self.importProgress = [provider loadFileRepresentationForTypeIdentifier:UTTypeImage.identifier completionHandler:^(NSURL *url, NSError *providerError) {
                // NSItemProvider calls on a background queue. Its URL is valid only
                // until this callback returns: decode and atomically save before returning.
                // A serial worker also orders startup loading, importing and restoring.
                dispatch_sync(self.workQueue, ^{
                    @autoreleasepool {
                        @synchronized (self) { if (operation != self.operationID) return; }
                        NSError *error = providerError;
                        UIImage *image = nil;
                        if (!error && !url) error = [NSError errorWithDomain:@"DOWallpaper" code:1 userInfo:@{NSLocalizedDescriptionKey:@"无法取得照片，请检查 iCloud 下载状态后重试。"}];
                        CGImageRef thumbnail = error ? NULL : DOWallpaperCopyThumbnail(url, &error);
                        if (thumbnail) {
                            NSData *data = DOWallpaperJPEGData(thumbnail, &error);
                            @synchronized (self) {
                                if (operation == self.operationID) {
                                    NSURL *destination = data ? [self wallpaperURLCreatingDirectory:YES error:&error] : nil;
                                    if (destination && [data writeToURL:destination options:NSDataWritingAtomic | NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication error:&error]) {
                                        image = [UIImage imageWithCGImage:thumbnail];
                                    }
                                }
                            }
                            CGImageRelease(thumbnail);
                        }
                        if (!image && !error) error = [NSError errorWithDomain:@"DOWallpaper" code:2 userInfo:@{NSLocalizedDescriptionKey:@"保存失败，原有壁纸未更改。"}];
                        dispatch_async(dispatch_get_main_queue(), ^{
                            @synchronized (self) { if (operation != self.operationID) return; }
                            self.importProgress = nil;
                            [self finishWithImage:image error:error];
                        });
                    }
                });
            }];
        }];
    }];
}

- (void)restoreDefault
{
    if (self.busy) return;
    [self beginProgressWithTitle:@"正在恢复默认壁纸" completion:^{
        dispatch_async(self.workQueue, ^{
            NSError *error = nil;
            NSURL *url = [self wallpaperURLCreatingDirectory:NO error:&error];
            if (url) [NSFileManager.defaultManager removeItemAtURL:url error:&error];
            if ([error.domain isEqualToString:NSCocoaErrorDomain] && (error.code == NSFileNoSuchFileError || error.code == NSFileReadNoSuchFileError)) error = nil;
            dispatch_async(dispatch_get_main_queue(), ^{ [self finishWithImage:nil error:error]; });
        });
    }];
}

@end
