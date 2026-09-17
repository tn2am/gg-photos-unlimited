#pragma once
#import <UIKit/UIKit.h>
#import <Photos/Photos.h>
@interface GSPanel : UITableViewController
@property(nonatomic) BOOL settingsMode;
- (void)importAssets:(NSArray<PHAsset *> *)assets;
- (void)importURLs:(NSArray<NSURL *> *)urls;
@end
FOUNDATION_EXPORT void GSPresentSettings(UIViewController *host);
FOUNDATION_EXPORT void GSPresent(UIViewController *host);
FOUNDATION_EXPORT void GSInstallButton(UIWindow *window);
@interface GSUploadActivity : UIActivity
@end
