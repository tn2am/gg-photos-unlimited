#import "UI/GSAccountMenu.h"
#import <UIKit/UIKit.h>
#import "UI/GSPanel.h"
#import "UI/GSNativeAccount.h"
#import "UI/GSNativeRelay.h"
#import "UI/GSAccountConnection.h"
#import "UI/GSUploadMonitor.h"
#import "UI/GSBatchImport.h"
%hook UIWindow
- (void)becomeKeyWindow {
 %orig;
 GSInstallButton(self);
}
%end
%hook UIActivityViewController
- (instancetype)initWithActivityItems:(NSArray *)items applicationActivities:(NSArray *)activities {
 NSMutableArray *all=activities?[activities mutableCopy]:[NSMutableArray array];
 GSUploadActivity *upload=[GSUploadActivity new];
 if([upload canPerformWithActivityItems:items])[all addObject:upload];
 return %orig(items,all);
}
%end

%ctor {
 %init;
 dispatch_async(dispatch_get_main_queue(),^{
  GSInstallNativeAccount();GSInstallAccountMenu();
  if(![[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleExecutable"]isEqual:@"GooglePhotos"])return;
  GSStartAccountConnection();
  GSStartBackupIntegration();
  GSAutoScanIfEnabled();
  [NSTimer scheduledTimerWithTimeInterval:60 repeats:YES block:^(NSTimer *timer){GSRefreshDaemonAccount();}];
  [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){GSResumeAccountConnection();}];
 });
}
