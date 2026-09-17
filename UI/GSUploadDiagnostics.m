#import "../Shared/GSPhotosCompatibility.h"
#import "GSUploadDiagnostics.h"
#import <objc/runtime.h>
#include <stdatomic.h>

// Passive, opt-in ABI probes. Never inspect request values, invoke descriptions,
// replace callback results, start uploads, or mark native requests successful.
static atomic_bool GSEnabled;
static BOOL GSInstalled;
static NSObject *GSLock;
static NSMutableArray *GSEvents, *GSBindings;
static NSUInteger GSSequence;
static void GSRecord(NSString *binding, id result, BOOL failed) {
 if(!atomic_load(&GSEnabled))return;
 NSString *type=result?NSStringFromClass(object_getClass(result)):@"nil";
 @synchronized(GSLock){
  if(!atomic_load(&GSEnabled))return;
  if(GSEvents.count==256)[GSEvents removeObjectAtIndex:0];
  [GSEvents addObject:@{@"sequence":@(++GSSequence),@"binding":binding,@"resultClass":type,@"failed":@(failed)}];
 }
}
BOOL GSUploadDiagnosticsAvailable(void){return GSInstalled;}
BOOL GSUploadDiagnosticsEnabled(void){return atomic_load(&GSEnabled);}
void GSSetUploadDiagnostics(BOOL enabled){
 if(!GSInstalled)return;
 @synchronized(GSLock){
  atomic_store(&GSEnabled,NO);if(enabled){[GSEvents removeAllObjects];GSSequence=0;}
  atomic_store(&GSEnabled,enabled);
 }
}
NSDictionary *GSUploadDiagnosticsSnapshot(void){
 if(!GSInstalled)return @{@"schema":@1,@"available":@NO};
 @synchronized(GSLock){return @{@"schema":@1,@"available":@YES,@"enabled":@(GSUploadDiagnosticsEnabled()),@"appVersion":[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"]?:@"unknown",@"auditedHostVersion":@(GSPhotosHostAudited()),@"bindings":[GSBindings copy],@"events":[GSEvents copy],@"observedCount":@(GSSequence),@"retainedLimit":@256};}
}
// Add an override for inherited methods without mutating their superclass.
static void GSReplace(Class cls, SEL selector, Method method, IMP replacement) {
 if(!class_addMethod(cls,selector,replacement,method_getTypeEncoding(method)))
  method_setImplementation(class_getInstanceMethod(cls,selector),replacement);
}
static void GSBind(NSString *name,NSString *selectorName,const char *encoding,int kind){
 Class cls=NSClassFromString(name);SEL selector=NSSelectorFromString(selectorName);
 Method method=class_getInstanceMethod(cls,selector);
 NSString *label=[NSString stringWithFormat:@"%@.%@",name,selectorName];
 BOOL matched=method&&strcmp(method_getTypeEncoding(method),encoding)==0;
 [GSBindings addObject:@{@"binding":label,@"matched":@(matched)}];
 if(!matched)return;
 IMP original=method_getImplementation(method), replacement=NULL;
 if(kind==0)replacement=imp_implementationWithBlock(^(id object){
  GSRecord(label,nil,NO);((void(*)(id,SEL))original)(object,selector);
 });
 else if(kind==1)replacement=imp_implementationWithBlock(^(id object,BOOL success,id result,id error){
  GSRecord(label,result,!success||error!=nil);((void(*)(id,SEL,BOOL,id,id))original)(object,selector,success,result,error);
 });
 else if(kind==2)replacement=imp_implementationWithBlock(^(id object,id error,id result){
  GSRecord(label,result,error!=nil);((void(*)(id,SEL,id,id))original)(object,selector,error,result);
 });
 else if(kind==3)replacement=imp_implementationWithBlock(^(id object,id data,id error){
  GSRecord(label,data,error!=nil);((void(*)(id,SEL,id,id))original)(object,selector,data,error);
 });
 else if(kind==4)replacement=imp_implementationWithBlock(^(id object,BOOL success,id result,NSInteger code){
  GSRecord(label,result,!success);((void(*)(id,SEL,BOOL,id,NSInteger))original)(object,selector,success,result,code);
 });
 if(replacement)GSReplace(cls,selector,method,replacement);
}
static void GSBindScotty(void){
 NSString *name=@"_TtC84googlemac_iPhone_Shared_Photos_Upload_Request_Scotty_ScottyUploadServiceImpl_ImplLib23ScottyUploadServiceImpl";
 NSString *selectorName=@"uploadWithAsset:shouldAllowCellular:useBackgroundSession:start:progress:onDataReleased:completionHandler:";
 const char *encoding="v64@0:8@\"GMUUploadAsset\"16B24B28@?<v@?B>32@?<v@?d>40@?<v@?>48@?<v@?@\"NSData\"@\"NSError\">56";
 Class cls=NSClassFromString(name);SEL selector=NSSelectorFromString(selectorName);Method method=class_getInstanceMethod(cls,selector);
 BOOL matched=method&&strcmp(method_getTypeEncoding(method),encoding)==0;
 [GSBindings addObject:@{@"binding":@"Scotty.upload",@"matched":@(matched)}];
 if(!matched)return;
 IMP original=method_getImplementation(method);
 IMP replacement=imp_implementationWithBlock(^(id object,id asset,BOOL cellular,BOOL background,id start,id progress,id released,void(^completion)(id,id)){
  BOOL observing=GSUploadDiagnosticsEnabled();
  GSRecord(background?@"Scotty.background.start":@"Scotty.foreground.start",nil,NO);
  void (^wrapped)(id,id)=completion;
  if(observing&&completion)wrapped=^(id data,id error){GSRecord(@"Scotty.complete",data,error!=nil);completion(data,error);};
  ((void(*)(id,SEL,id,BOOL,BOOL,id,id,id,id))original)(object,selector,asset,cellular,background,start,progress,released,wrapped);
 });
 GSReplace(cls,selector,method,replacement);
}
static void GSBindStatelessScotty(void){
 Class cls=NSClassFromString(@"_TtC84googlemac_iPhone_Shared_Photos_Upload_Request_Scotty_ScottyUploadServiceImpl_ImplLib23ScottyUploadServiceImpl");
 SEL selector=NSSelectorFromString(@"statelessUploadWithAsset:shouldAllowCellular:progress:completionHandler:");
 Method method=class_getInstanceMethod(cls,selector);
 const char *encoding="v44@0:8@\"GMUUploadAsset\"16B24@?<v@?d>28@?<v@?@\"NSData\"@\"NSError\">36";
 BOOL matched=method&&strcmp(method_getTypeEncoding(method),encoding)==0;
 [GSBindings addObject:@{@"binding":@"Scotty.statelessUpload",@"matched":@(matched)}];
 if(!matched)return;
 IMP original=method_getImplementation(method);
 IMP replacement=imp_implementationWithBlock(^(id object,id asset,BOOL cellular,id progress,void(^completion)(id,id)){
  BOOL observing=GSUploadDiagnosticsEnabled();GSRecord(@"Scotty.stateless.start",nil,NO);
  void (^wrapped)(id,id)=completion;
  if(observing&&completion)wrapped=^(id data,id error){GSRecord(@"Scotty.stateless.complete",data,error!=nil);completion(data,error);};
  ((void(*)(id,SEL,id,BOOL,id,id))original)(object,selector,asset,cellular,progress,wrapped);
 });
 GSReplace(cls,selector,method,replacement);
}
void GSInstallUploadDiagnostics(void){
 // Install on the main thread. Start remains opt-in and resets each process launch.
 if(GSInstalled||![[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleExecutable"]isEqual:@"GooglePhotos"]||!GSPhotosHostSupported())return;
 GSLock=[NSObject new];GSEvents=[NSMutableArray array];GSBindings=[NSMutableArray array];
 for(NSString *name in @[@"GMUUploadRequest",@"GMUAssetUploadRequest",@"GMULivePhotoSingleUploadRequest",@"PHSLockedPhotoMediaUploadRequest",@"PHSLockedPhotoLivePhotoSingleUploadRequest"])
  GSBind(name,@"start","v16@0:8",0);
 GSBind(@"GMUUploadRequest",@"startFetcher","v16@0:8",0);
 for(NSString *name in @[@"GMUUploadRequest",@"GMUAssetUploadRequest"]){
  Class cls=NSClassFromString(name);NSString *completion=GSPhotosAssetCompletion(cls);
  if(completion)GSBind(name,completion,GSPhotosAssetCompletionABI(cls),GSPhotosCompletionForClass(cls)==GSPhotosCompletionCode?4:1);
 }
 GSBind(@"GMULivePhotoSingleUploadRequest",@"didCompleteWithError:resultantMediaItem:","v32@0:8@16@24",2);
 GSBind(@"GMUUploadMediaRequest",@"uploadFetcherDidCompleteWithData:error:","v32@0:8@16@24",3);
 GSBindScotty();GSBindStatelessScotty();GSInstalled=YES;
}
