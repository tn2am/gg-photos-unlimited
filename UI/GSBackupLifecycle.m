#import <UIKit/UIKit.h>
#import "GSUploadMonitor.h"
#import "GSNativeRouting.h"
#import "GSPhotosIntegration.h"

static void GSSampleHost(void){
 BOOL foreground=UIApplication.sharedApplication.applicationState!=UIApplicationStateBackground;
 for(UIScene *scene in UIApplication.sharedApplication.connectedScenes)
  if(scene.activationState==UISceneActivationStateForegroundActive||scene.activationState==UISceneActivationStateForegroundInactive){foreground=YES;break;}
 GSSetUploadHostForeground(foreground);
}
void GSStartBackupIntegration(void){
 if(!GSIsGooglePhotos())return;
 static dispatch_once_t once;dispatch_once(&once,^{
  GSInstallNativeRouting();GSInstallPhotosIntegration();
  for(NSString *name in @[UIApplicationDidBecomeActiveNotification,UIApplicationDidEnterBackgroundNotification,UIApplicationWillEnterForegroundNotification,UISceneDidActivateNotification,UISceneWillDeactivateNotification,UISceneDidEnterBackgroundNotification,UISceneWillEnterForegroundNotification])
   [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){GSSampleHost();}];
  GSSampleHost();
 });
}
