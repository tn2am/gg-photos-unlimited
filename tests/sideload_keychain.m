#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <assert.h>
#include <stdlib.h>
#include <string.h>

static OSStatus GSFixtureCopy(CFDictionaryRef query,CFTypeRef *result);
static OSStatus GSUnexpectedAdd(CFDictionaryRef query,CFTypeRef *result){abort();}
static OSStatus GSUnexpectedUpdate(CFDictionaryRef query,CFDictionaryRef changes){abort();}
static OSStatus GSUnexpectedDelete(CFDictionaryRef query){abort();}
#define SecItemCopyMatching GSFixtureCopy
#define SecItemAdd GSUnexpectedAdd
#define SecItemUpdate GSUnexpectedUpdate
#define SecItemDelete GSUnexpectedDelete
#import "../Jailed/SideloadKeychain.m"
#undef SecItemCopyMatching
#undef SecItemAdd
#undef SecItemUpdate
#undef SecItemDelete

static NSString *Host=@"GooglePhotos";
static id Group=@"GOOGLE.shared";
static OSStatus Status;
static NSUInteger Probes,GroupReads,BundleReads;
static _Bool NativePrivate;
static BOOL ThrowFromHelper;
@interface GSFixtureBundle : NSObject
@end
@implementation GSFixtureBundle
- (id)objectForInfoDictionaryKey:(NSString *)key{
 BundleReads++;assert([key isEqual:@"CFBundleExecutable"]);return Host;
}
@end
static id MainBundle(id object,SEL selector){return [GSFixtureBundle new];}
static id SharedGroup(id object,SEL selector){
 GroupReads++;
 if(ThrowFromHelper)[NSException raise:@"FixtureUnavailable" format:@"helper unavailable"];
 return Group;
}
static _Bool PrivateMode(id object,SEL selector){return NativePrivate;}
// SSO copies this flag into its helper at initialization; later getter changes
// cannot repair a service that already chose the shared Keychain.
@interface GSSSOServiceFixture : NSObject
@property(nonatomic,readonly) NSDictionary *itemQuery;
- (instancetype)initWithConfiguration:(id)configuration;
@end
@implementation GSSSOServiceFixture
- (instancetype)initWithConfiguration:(id)configuration{
 if((self=[super init])){
  NSMutableDictionary *query=[@{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword}mutableCopy];
  _Bool private=((_Bool(*)(id,SEL))objc_msgSend)(configuration,NSSelectorFromString(@"usePrivateKeychain"));
  if(!private)query[(__bridge id)kSecAttrAccessGroup]=Group;
  _itemQuery=[query copy];
 }
 return self;
}
@end
static OSStatus GSFixtureCopy(CFDictionaryRef query,CFTypeRef *result){
 Probes++;assert(result==NULL);
 NSDictionary *attributes=(__bridge NSDictionary *)query;
 // An exact six-key query excludes credential data, attributes and persistent refs.
 assert(attributes.count==6);
 assert([attributes[(__bridge id)kSecClass]isEqual:(__bridge id)kSecClassGenericPassword]);
 assert([attributes[(__bridge id)kSecAttrAccessGroup]isEqual:Group]);
 assert([attributes[(__bridge id)kSecAttrService]isEqual:@"dev.tqmane.gunshot.sso-access-probe"]);
 assert([attributes[(__bridge id)kSecAttrAccount]isEqual:@"access-group-check"]);
 assert([attributes[(__bridge id)kSecMatchLimit]isEqual:(__bridge id)kSecMatchLimitOne]);
 LAContext *context=attributes[(__bridge id)kSecUseAuthenticationContext];
 assert([context isKindOfClass:LAContext.class]&&context.interactionNotAllowed);
 return Status;
}
int main(int argc,char **argv){@autoreleasepool{
 NSString *mode=argc>1?@(argv[1]):@"default";
 method_setImplementation(class_getClassMethod(NSBundle.class,@selector(mainBundle)),(IMP)MainBundle);
 unsetenv("LC_HOME_PATH");
 if([mode isEqual:@"livecontainer"])setenv("LC_HOME_PATH","/fixture/guest",1);
 if([mode isEqual:@"wrong-host"])Host=@"OtherApp";
 Class configuration=Nil,helper=Nil;
 SEL getter=NSSelectorFromString(@"usePrivateKeychain");
 if(![mode isEqual:@"missing-configuration"]){
  configuration=objc_allocateClassPair(NSObject.class,"SSOConfiguration",0);
  assert(configuration);
  assert(class_addMethod(configuration,getter,(IMP)PrivateMode,
   [mode isEqual:@"configuration-abi"]?"q16@0:8":"B16@0:8"));
  objc_registerClassPair(configuration);
 }
 if(![mode isEqual:@"missing-helper"]){
  helper=objc_allocateClassPair(NSObject.class,"SSOKeychainHelper",0);
  assert(helper);
  assert(class_addMethod(object_getClass(helper),NSSelectorFromString(@"sharedAccessGroup"),(IMP)SharedGroup,
   [mode isEqual:@"helper-abi"]?"B16@0:8":"@16@0:8"));
  objc_registerClassPair(helper);
 }
 NativePrivate=[mode isEqual:@"native-private"];
 Status=errSecMissingEntitlement;
 if(![mode isEqual:@"default"]&&![mode isEqual:@"native-private"]){
  GSInstallSideloadKeychain();GSInstallSideloadKeychain();
  assert(Probes==0&&GroupReads==0);
  if([mode isEqual:@"livecontainer"])assert(BundleReads==0);
  if(configuration)assert(method_getImplementation(class_getInstanceMethod(configuration,getter))==(IMP)PrivateMode);
 }else{
  id settings=[configuration new];
  // Invalid groups and transient failures must not select a different Keychain.
  for(id invalid in @[@"",@42,NSNull.null]){
   Group=invalid==NSNull.null?nil:invalid;GSInstallSideloadKeychain();assert(Probes==0);
  }
  Group=@"GOOGLE.shared";ThrowFromHelper=YES;
  GSInstallSideloadKeychain();assert(Probes==0);ThrowFromHelper=NO;
  for(NSNumber *status in @[@(errSecSuccess),@(errSecItemNotFound),@(errSecInteractionNotAllowed),
    @(errSecNotAvailable),@(errSecAuthFailed),@(errSecParam)]){
   Status=status.intValue;GSInstallSideloadKeychain();
   assert(method_getImplementation(class_getInstanceMethod(configuration,getter))==(IMP)PrivateMode);
   assert(((_Bool(*)(id,SEL))objc_msgSend)(settings,getter)==NativePrivate);
  }
  assert(Probes==6);
  GSSSOServiceFixture *before=[[GSSSOServiceFixture alloc]initWithConfiguration:settings];
  assert((before.itemQuery[(__bridge id)kSecAttrAccessGroup]==nil)==NativePrivate);
  // Empty LiveContainer marker is not a guest; a retry can repair an actual denial.
  setenv("LC_HOME_PATH","",1);Status=errSecMissingEntitlement;
  GSInstallSideloadKeychain();assert(Probes==7);
  assert(((_Bool(*)(id,SEL))objc_msgSend)(settings,getter));
  GSSSOServiceFixture *after=[[GSSSOServiceFixture alloc]initWithConfiguration:settings];
  assert(after.itemQuery[(__bridge id)kSecAttrAccessGroup]==nil);
  assert((before.itemQuery[(__bridge id)kSecAttrAccessGroup]==nil)==NativePrivate);
  NSUInteger reads=GroupReads;IMP repaired=method_getImplementation(class_getInstanceMethod(configuration,getter));
  for(int retry=0;retry<3;retry++)GSInstallSideloadKeychain();
  assert(Probes==7&&GroupReads==reads);
  assert(method_getImplementation(class_getInstanceMethod(configuration,getter))==repaired);
  assert(method_getImplementation(class_getClassMethod(helper,NSSelectorFromString(@"sharedAccessGroup")))==(IMP)SharedGroup);
 }
 NSLog(@"PASS sideload SSO Keychain gate, read-only probe and native private mode (%@)",mode);
}}
