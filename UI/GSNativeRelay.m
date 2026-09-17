#import "GSNativeRelay.h"
#import "GSNativeAccount.h"
#import "../Shared/IPCProtocol.h"
#include <stdlib.h>

static dispatch_queue_t GSRelayQueue(void) {
 static dispatch_queue_t queue;static dispatch_once_t once;
 dispatch_once(&once,^{queue=dispatch_queue_create("dev.tqmane.gunshot.native-auth",DISPATCH_QUEUE_SERIAL);});return queue;
}
static NSObject *GSRelayLock(void) {
 static NSObject *lock;static dispatch_once_t once;dispatch_once(&once,^{lock=[NSObject new];});return lock;
}
static NSString *GSRelayState=@"not_checked";
static void GSRecordRelay(NSString *state){@synchronized(GSRelayLock()){GSRelayState=state;}}
NSDictionary *GSNativeRelaySnapshot(void){@synchronized(GSRelayLock()){return @{@"source":@"google_photos_sso",@"authorization":GSRelayState};}}
static NSError *GSRelayError(void){return [NSError errorWithDomain:@"Gunshot.NativeAccount" code:1 userInfo:nil];}
static BOOL GSSendBearer(NSDictionary *account,BOOL connect,NSError **error) {
 NSString *identifier=account[@"identifier"],*email=account[@"email"];
 if(![identifier isKindOfClass:NSString.class]||!identifier.length||![email isKindOfClass:NSString.class]||!email.length){if(error)*error=GSRelayError();return NO;}
 GSRecordRelay(@"checking");
 // Native code checks the current identity before and after the SSO callback.
 // It authorizes an unsent request; it does not read the Keychain or cookies.
 char *raw=GSNativeBearer(identifier.UTF8String);
 NSString *bearer=raw?[NSString stringWithUTF8String:raw]:nil;free(raw);
 if(!bearer.length){
  GSRequest(@{@"op":@"native_bearer_clear"},nil);GSRecordRelay(@"waiting");
  if(error)*error=GSRelayError();return NO;
 }
 NSDictionary *reply=GSRequest(@{@"op":connect?@"account_native":@"native_bearer",@"account":email,@"nativeID":identifier,@"secret":bearer},error);
 GSRecordRelay(reply?(connect?@"validated":@"refreshed"):@"failed");
 return reply!=nil;
}
BOOL GSConnectDaemonAccount(NSDictionary *account,NSError **error) {
 if(NSThread.isMainThread){if(error)*error=GSRelayError();return NO;}
 __block BOOL success=NO;__block NSError *failure=nil;
 dispatch_sync(GSRelayQueue(),^{@autoreleasepool{success=GSSendBearer(account,YES,&failure);}});
 if(!success&&error)*error=failure?:GSRelayError();return success;
}
void GSRefreshDaemonAccount(void) {
 // The timer and foreground notification share a single in-flight refresh.
 // The serial queue also excludes a simultaneous user-requested reconnect.
 static BOOL refreshing;
 if(!NSThread.isMainThread||refreshing)return;
 refreshing=YES;
 dispatch_async(GSRelayQueue(),^{@autoreleasepool{
  __block NSDictionary *account=nil;
  dispatch_sync(dispatch_get_main_queue(),^{account=GSNativeAccountSummary();});
  NSDictionary *accounts=GSRequest(@{@"op":@"accounts"},nil);
  if(!accounts){GSRecordRelay(@"unreachable");}
  else if(!account||![accounts[@"selected"]isEqual:account[@"email"]]||![accounts[@"nativeAuthorization"]length]){
   GSRequest(@{@"op":@"native_bearer_clear"},nil);GSRecordRelay(@"waiting");
  }else{GSSendBearer(account,NO,nil);}
  dispatch_async(dispatch_get_main_queue(),^{refreshing=NO;});
 }});
}
