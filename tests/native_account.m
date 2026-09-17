#import "host_profile.h"
#import "../UI/GSNativeAccount.h"
#import <objc/runtime.h>
#include <assert.h>
#include <stdlib.h>
#include <string.h>
#if GS_TEST_DAEMON_RELAY || GS_TEST_AUTOCONNECT
#import "../UI/GSNativeRelay.h"
#import "../UI/GSAccountConnection.h"
static NSUInteger relayConnections,relayRefreshes,relayClears;
static BOOL relayReject;
NSDictionary *GSRequest(NSDictionary *request,NSError **error){
 assert(!NSThread.isMainThread);
#if GS_JAILED
 if([request[@"op"]isEqual:@"account_native"]){
  char *token=GSNativeBearer([request[@"nativeID"]UTF8String]);
  if(!token){if(error)*error=[NSError errorWithDomain:@"fixture" code:1 userInfo:nil];return nil;}
  assert(!strcmp(token,"test-native-access-token"));free(token);
 }
#endif
 __block NSDictionary *result=nil;
 dispatch_sync(dispatch_get_main_queue(),^{
  NSString *op=request[@"op"];
  if([op isEqual:@"accounts"]){result=@{@"selected":@"test@example.com",@"nativeAuthorization":@"waiting"};return;}
  if([op isEqual:@"native_bearer_clear"]){relayClears++;result=@{};return;}
  assert([op isEqual:@"account_native"]||[op isEqual:@"native_bearer"]);
#if GS_JAILED
  assert(request[@"secret"]==nil);
#else
  assert([request[@"secret"]isEqual:@"test-native-access-token"]);
#endif
  assert([request[@"nativeID"]isEqual:@"123"]&&[request[@"account"]isEqual:@"test@example.com"]);
  if([op isEqual:@"account_native"])relayConnections++;else relayRefreshes++;
  if(!relayReject)result=@{};
 });
 if(!result&&error)*error=[NSError errorWithDomain:@"fixture" code:1 userInfo:nil];
 return result;
}
static void AwaitRelay(BOOL(^ready)(void)){
 NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:5];
 while(!ready()&&deadline.timeIntervalSinceNow>0)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
 assert(ready());
}
#if GS_TEST_DAEMON_RELAY
static BOOL ConnectRelay(void){
 NSDictionary *account=GSNativeAccountSummary();__block BOOL done=NO,success=NO;
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
  NSError *error=nil;BOOL result=GSConnectDaemonAccount(account,&error);assert(result||error);
  dispatch_async(dispatch_get_main_queue(),^{success=result;done=YES;});
 });
 AwaitRelay(^BOOL{return done;});return success;
}
#endif
#endif
@interface GSFixtureBundle : NSObject
@end
@implementation GSFixtureBundle
- (id)objectForInfoDictionaryKey:(NSString *)key{return [key isEqual:@"CFBundleExecutable"]?@"GooglePhotos":GSFixtureVersion;}
@end
static id MainBundle(id object,SEL selector){static id bundle;if(!bundle)bundle=[GSFixtureBundle new];return bundle;}
@protocol SSOIdentity <NSObject>
@end
@interface GSIdentityFixture : NSObject <SSOIdentity>
@property(nonatomic) _Bool hasValidAuth;
@property(nonatomic,copy) NSString *userID;
@property(nonatomic,copy) NSString *userEmail;
@end
@implementation GSIdentityFixture
@end
@interface PHSAccount : NSObject {
@public id<SSOIdentity> _ssoIdentity;
}
@property(nonatomic,strong) id accountID;
@end
@implementation PHSAccount
@end
static void (^beforeCompletion)(void);
static NSUInteger authorizations;
@interface GSAuthorizerFixture : NSObject
@end
@implementation GSAuthorizerFixture
- (void)authorizeRequest:(NSMutableURLRequest *)request completionHandler:(void(^)(NSError *))completion{
 assert(NSThread.isMainThread);authorizations++;
 assert([request.URL.host isEqual:@"photos.googleapis.com"]);
 [request setValue:@"Bearer test-native-access-token" forHTTPHeaderField:@"Authorization"];
 if(beforeCompletion)beforeCompletion();completion(nil);
}
@end
@interface GSSSOFixture : NSObject
@end
@implementation GSSSOFixture
#ifdef GS_TEST_LEGACY
- (id)authorizationForIdentity:(id)identity scopes:(id)scopes{
 assert([identity isKindOfClass:GSIdentityFixture.class]);assert([[identity userID]isEqual:@"123"]);
 assert([scopes isEqual:@[@"https://www.googleapis.com/auth/photos.native"]]);return [GSAuthorizerFixture new];
}
#else
- (id)fetcherAuthorizerForAccountID:(id)account scopes:(id)scopes{
 assert([account isEqual:@"id-123"]);assert([scopes isEqual:@[@"https://www.googleapis.com/auth/photos.native"]]);return [GSAuthorizerFixture new];
}
#endif
@end
#ifdef GS_TEST_LEGACY
#define photosSSOService ssoService
#endif
@interface PHSAccountManagerImpl : NSObject
@property(nonatomic,strong) id viewingAccount;
@property(nonatomic,strong) id photosSSOService;
@end
@implementation PHSAccountManagerImpl
@end
static NSString *Fetch(const char *identifier){
 __block BOOL done=NO;__block NSString *result=nil;
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
  char *token=GSNativeBearer(identifier);NSString *value=token?[NSString stringWithUTF8String:token]:nil;free(token);
  dispatch_async(dispatch_get_main_queue(),^{result=value;done=YES;});
 });
 NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:5];
 while(!done&&deadline.timeIntervalSinceNow>0)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
 assert(done);return result;
}
int main(void){@autoreleasepool{
 method_setImplementation(class_getClassMethod(NSBundle.class,@selector(mainBundle)),(IMP)MainBundle);
 GSInstallNativeAccount();
 GSIdentityFixture *identity=[GSIdentityFixture new];identity.userID=@"123";identity.userEmail=@"test@example.com";identity.hasValidAuth=YES;
 PHSAccount *account=[PHSAccount new];account->_ssoIdentity=identity;account.accountID=@"id-123";
 PHSAccountManagerImpl *manager=[PHSAccountManagerImpl new];manager.viewingAccount=account;manager.photosSSOService=[GSSSOFixture new];
 assert([manager viewingAccount]==account);
 assert([GSNativeAccountSummary()[@"identifier"]isEqual:@"123"]);
 assert(GSNativeBearer("123")==NULL); // Main-thread caller must not block.
 assert([Fetch("123")isEqual:@"test-native-access-token"]);
 assert([Fetch("123")isEqual:@"test-native-access-token"]);assert(authorizations==2);
 assert(Fetch("wrong-account")==nil);assert(authorizations==2);
 identity.hasValidAuth=NO;assert(Fetch("123")==nil);identity.hasValidAuth=YES;
 beforeCompletion=^{manager.viewingAccount=nil;};assert(Fetch("123")==nil);
 assert(GSNativeAccountSummary()==nil);
#if GS_TEST_DAEMON_RELAY
 beforeCompletion=nil;manager.viewingAccount=account;
 NSError *error=nil;assert(!GSConnectDaemonAccount(GSNativeAccountSummary(),&error)&&error);
 assert(ConnectRelay());assert(relayConnections==1);
 assert([GSNativeRelaySnapshot()[@"authorization"]isEqual:@"validated"]);
 GSRefreshDaemonAccount();GSRefreshDaemonAccount(); // Coalesce foreground + timer.
 AwaitRelay(^BOOL{return relayRefreshes==1;});
 assert([GSNativeRelaySnapshot().allKeys containsObject:@"authorization"]);
 assert(GSNativeRelaySnapshot().count==2); // Status + source only, no identity/secret.
 relayReject=YES;assert(!ConnectRelay());relayReject=NO;
 NSUInteger previous=relayConnections;
 beforeCompletion=^{manager.viewingAccount=nil;};
 assert(!ConnectRelay());assert(relayConnections==previous&&relayClears>0);
 assert([GSNativeRelaySnapshot()[@"authorization"]isEqual:@"waiting"]);
#endif
#if GS_TEST_AUTOCONNECT
 // Start before the native manager has a signed-in identity. No settings view
 // or account menu is ever created by this fixture.
 beforeCompletion=nil;manager.viewingAccount=nil;
 GSStartAccountConnection();
 NSUInteger count=relayConnections;
 assert([GSAccountConnectionSnapshot()[@"state"]isEqual:@"waiting_for_account"]);
 manager.viewingAccount=account;
 AwaitRelay(^BOOL{return [GSAccountConnectionSnapshot()[@"state"]isEqual:@"connected"];});
 assert(relayConnections==count+1);
 GSStartAccountConnection();GSResumeAccountConnection();GSResumeAccountConnection();
 assert(relayConnections==count+1); // No duplicate reconnect from launch events.
 manager.viewingAccount=nil;
 AwaitRelay(^BOOL{return [GSAccountConnectionSnapshot()[@"state"]isEqual:@"waiting_for_account"];});
 manager.viewingAccount=account;
 AwaitRelay(^BOOL{return [GSAccountConnectionSnapshot()[@"state"]isEqual:@"connected"];});
 assert(relayConnections==count+2);
#endif
 return 0;
}}
