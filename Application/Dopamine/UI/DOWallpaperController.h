#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
// Retained by the navigation controller; all public methods run on main.
@interface DOWallpaperController : NSObject
@property (nonatomic, copy, nullable) void (^imageDidChange)(UIImage * _Nullable image);
- (void)loadSavedWallpaper;
- (void)presentSettingsFromViewController:(UIViewController *)presenter;
@end
NS_ASSUME_NONNULL_END
