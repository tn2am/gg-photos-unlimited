#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <assert.h>
#include <stdlib.h>
#import "../Jailed/SideloadIdentity.m"

static NSString *Host=@"GooglePhotos",*InstalledID=@"com.google.photos.resigned";
static NSString *Version=@"7.92.0";
static id MainBundle(id object,SEL selector){return object;}
static id BundleIdentifier(id object,SEL selector){return InstalledID;}
static id BundleInfo(id object,SEL selector,id key){
 if([key isEqual:@"CFBundleExecutable"])return Host;
 if([key isEqual:@"CFBundleShortVersionString"])return Version;
 return nil;
}
@interface GSConfigurationFixture : NSObject
@property(nonatomic,copy) NSString *applicationIdentifier;
@property(nonatomic,copy) NSString *clientID;
@end
@implementation GSConfigurationFixture
@end
@interface GSBundleServiceFixture : NSObject
@end
@implementation GSBundleServiceFixture
- (id)bundleId{return InstalledID;}
@end
static id BadABI(id object,SEL selector){return nil;}
static id ReadBundle(id service){return ((id(*)(id,SEL))objc_msgSend)(service,NSSelectorFromString(@"bundleId"));}
static NSDictionary *AuthAdvice(GSConfigurationFixture *configuration){
 // Mirrors the two identity fields read by SSORPCService in both audited IPAs.
 return @{@"package_name":configuration.applicationIdentifier?:@"",
  @"client_id":configuration.clientID?:@"",@"device_challenge_request":@"fixture-challenge",
  @"client_state":@"fixture-state",@"redirect_uri":@"fixture-callback"};
}
int main(int argc,char **argv){@autoreleasepool{
 NSString *mode=argc>1?@(argv[1]):@"modern";
 unsetenv("LC_HOME_PATH");
 if([mode isEqual:@"livecontainer"])setenv("LC_HOME_PATH","/fixture/guest",1);
 if([mode isEqual:@"legacy"])Version=@"7.20.2";
 if([mode isEqual:@"future"])Version=@"8.0.0";
 if([mode isEqual:@"wrong-host"])Host=@"OtherApp";
 if([mode isEqual:@"original-id"])InstalledID=@"com.google.photos";
 if([mode isEqual:@"missing-id"])InstalledID=nil;
 if([mode isEqual:@"empty-id"])InstalledID=@"";
 // Only the fixture's main bundle is changed; production must not hook NSBundle.
 Method mainMethod=class_getClassMethod(NSBundle.class,@selector(mainBundle));
 IMP fixtureMain=(IMP)MainBundle;
 method_setImplementation(mainMethod,fixtureMain);
 class_addMethod(object_getClass(NSBundle.class),@selector(bundleIdentifier),(IMP)BundleIdentifier,"@16@0:8");
 class_addMethod(object_getClass(NSBundle.class),@selector(objectForInfoDictionaryKey:),(IMP)BundleInfo,"@24@0:8@16");
 Class configuration=Nil,service=Nil;
 if(![mode isEqual:@"missing-configuration"]){
  configuration=objc_allocateClassPair(GSConfigurationFixture.class,"SSOConfiguration",0);assert(configuration);
  if([mode isEqual:@"configuration-abi"])
   class_addMethod(configuration,@selector(applicationIdentifier),(IMP)BadABI,"q16@0:8");
  if([mode isEqual:@"client-abi"])
   class_addMethod(configuration,@selector(clientID),(IMP)BadABI,"q16@0:8");
  objc_registerClassPair(configuration);
 }
 if(![mode isEqual:@"legacy"]){
  service=objc_allocateClassPair(GSBundleServiceFixture.class,"SSOBundleIdServiceImpl",0);assert(service);
  if([mode isEqual:@"service-abi"])
   class_addMethod(service,NSSelectorFromString(@"bundleId"),(IMP)BadABI,"q16@0:8");
  objc_registerClassPair(service);
 }
 BOOL skip=[@[@"livecontainer",@"wrong-host",@"original-id",@"missing-id",@"empty-id"]containsObject:mode];
 BOOL configOK=!skip&&configuration&&![mode isEqual:@"configuration-abi"]&&![mode isEqual:@"client-abi"];
 BOOL serviceOK=!skip&&service&&![mode isEqual:@"service-abi"];
 GSInstallSideloadIdentity();GSInstallSideloadIdentity();
 NSDictionary *status=GSSideloadIdentitySnapshot();
 assert(status.count==4);
 assert([status[@"configurationHook"]boolValue]==configOK);
 assert([status[@"bundleServiceHook"]boolValue]==serviceOK);
 assert(![status[@"configurationUsed"]boolValue]&&![status[@"bundleServiceUsed"]boolValue]);
 if(configOK){
  GSConfigurationFixture *settings=[configuration new];
  NSString *photosClient=@"278930400967-s7eptfh2d81vvi86kptt63pfa0o5usjt.apps.googleusercontent.com";
  settings.applicationIdentifier=InstalledID;settings.clientID=@"another-client.apps.googleusercontent.com";
  assert([settings.applicationIdentifier isEqual:InstalledID]);
  settings.clientID=photosClient;settings.applicationIdentifier=@"com.google.other";
  assert([settings.applicationIdentifier isEqual:@"com.google.other"]);
  settings.applicationIdentifier=nil;assert(settings.applicationIdentifier==nil);
  assert(![GSSideloadIdentitySnapshot()[@"configurationUsed"]boolValue]);
  // Late GIK assignments and a second configuration must use the same correction.
  settings.applicationIdentifier=InstalledID;
  NSDictionary *request=AuthAdvice(settings);
  assert([request[@"package_name"]isEqual:@"com.google.photos"]);
  assert([request[@"client_id"]isEqual:photosClient]);
  assert([request[@"device_challenge_request"]isEqual:@"fixture-challenge"]);
  assert([request[@"client_state"]isEqual:@"fixture-state"]);
  assert([request[@"redirect_uri"]isEqual:@"fixture-callback"]);
  GSConfigurationFixture *second=[configuration new];second.clientID=photosClient;
  second.applicationIdentifier=InstalledID;assert([second.applicationIdentifier isEqual:@"com.google.photos"]);
  // The hook is confined to SSOConfiguration, including when its getter is inherited.
  GSConfigurationFixture *base=[GSConfigurationFixture new];base.clientID=photosClient;
  base.applicationIdentifier=InstalledID;assert([base.applicationIdentifier isEqual:InstalledID]);
  settings.clientID=nil;assert([settings.applicationIdentifier isEqual:InstalledID]);
  settings.clientID=photosClient;settings.applicationIdentifier=@"com.google.photos";
  assert([settings.applicationIdentifier isEqual:@"com.google.photos"]);
 }
 if(serviceOK){
  assert([ReadBundle([service new])isEqual:@"com.google.photos"]);
  assert([ReadBundle([GSBundleServiceFixture new])isEqual:InstalledID]);
 }
 assert(method_getImplementation(mainMethod)==fixtureMain);
 assert(NSBundle.mainBundle.bundleIdentifier==InstalledID);
 IMP first=configuration?method_getImplementation(class_getInstanceMethod(configuration,@selector(applicationIdentifier))):NULL;
 GSInstallSideloadIdentity();
 if(configuration)assert(first==method_getImplementation(class_getInstanceMethod(configuration,@selector(applicationIdentifier))));
 for(id value in GSSideloadIdentitySnapshot().allValues)assert([value isKindOfClass:NSNumber.class]);
 NSLog(@"PASS sideload SSO identity scope, AuthAdvice contract and ABI gates (%@)",mode);
}}
