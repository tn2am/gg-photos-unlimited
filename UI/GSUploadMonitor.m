#import "GSUploadMonitor.h"
#import "GSNativeAccount.h"
#import "GSPhotosIntegration.h"
#import "../Shared/IPCProtocol.h"

// The host observes the same durable queue through either IPC or the embedded
// adapter. No panel, native backup request or active routing toggle is required.
static NSObject *GSLock;
static NSMutableDictionary *GSState;
static dispatch_queue_t GSQueue;
static BOOL GSForeground, GSInFlight;
static NSUInteger GSEpoch;
static NSString *GSLastIdentifier;
static NSNumber *GSLastRevision;

static void GSInitialize(void){
 static dispatch_once_t once;dispatch_once(&once,^{
  GSLock=[NSObject new];GSState=[@{@"started":@NO,@"foreground":@NO,@"polling":@NO,@"reachable":@NO,@"syncSignals":@0}mutableCopy];
  GSQueue=dispatch_queue_create("dev.tqmane.gunshot.upload-monitor",DISPATCH_QUEUE_SERIAL);
 });
}
static void GSRecord(NSDictionary *values){@synchronized(GSLock){[GSState addEntriesFromDictionary:values];}}
NSDictionary *GSUploadMonitorSnapshot(void){GSInitialize();@synchronized(GSLock){return [GSState copy];}}
BOOL GSUploadHostForeground(void){return [GSUploadMonitorSnapshot()[@"foreground"]boolValue];}

static void GSPoll(void){
 NSCAssert(NSThread.isMainThread,@"Upload lifecycle must run on main");
 if(!GSForeground||GSInFlight)return;
 NSString *identifier=[GSNativeAccountSummary()[@"identifier"]copy];
 if(!identifier.length)return;
 NSUInteger epoch=GSEpoch;GSInFlight=YES;GSRecord(@{@"polling":@YES});
 dispatch_async(GSQueue,^{@autoreleasepool{
  NSDictionary *summary=GSRequest(@{@"op":@"upload_summary"},nil);
  dispatch_async(dispatch_get_main_queue(),^{
   GSInFlight=NO;GSRecord(@{@"polling":@NO,@"reachable":summary?@YES:@NO});
   // Do not acknowledge a response from an earlier foreground/account session.
   if(!GSForeground||epoch!=GSEpoch)return;
   BOOL identityMatched=GSNativeIdentityMatches(identifier);
   GSRecord(@{@"identityMatched":@(identityMatched)});
   if(!identityMatched)return;
   if(!summary)return;
   GSRecord(@{@"uploadSummary":summary});
   if(![summary[@"conditions"][@"online"]boolValue])return;
   NSNumber *revision=summary[@"completionRevision"];
   if(![revision isKindOfClass:NSNumber.class]||revision.unsignedLongLongValue==0)return;
   if([GSLastIdentifier isEqual:identifier]&&[GSLastRevision isEqual:revision])return;
   GSLastIdentifier=identifier;GSLastRevision=revision;
   GSRecord(@{@"syncSignals":@([GSUploadMonitorSnapshot()[@"syncSignals"]unsignedIntegerValue]+1)});
   // fetchData reads real server state; it never fabricates backup completion.
   GSRefreshNativeLibrary();
  });
 }});
}
void GSSetUploadHostForeground(BOOL foreground){
 NSCAssert(NSThread.isMainThread,@"Upload lifecycle must run on main");
 GSInitialize();
 static dispatch_once_t once;dispatch_once(&once,^{
  GSRecord(@{@"started":@YES});
  [NSTimer scheduledTimerWithTimeInterval:3 repeats:YES block:^(NSTimer *timer){GSPoll();}];
 });
 if(GSForeground!=foreground){GSEpoch++;GSLastIdentifier=nil;GSLastRevision=nil;}
 GSForeground=foreground;GSRecord(@{@"foreground":@(foreground)});GSPoll();
}
