#import "SideloadKeychain.h"
#import "../Shared/GSPhotosCompatibility.h"
#import <Security/Security.h>
#import <LocalAuthentication/LocalAuthentication.h>
#import <objc/message.h>
#include <stdlib.h>

static _Bool GSUsePrivateKeychain(id object,SEL selector){return 1;}

void GSInstallSideloadKeychain(void){
 const char *liveContainer=getenv("LC_HOME_PATH");
 if((liveContainer&&*liveContainer)||!GSPhotosHostSupported())return;
 Class configuration=NSClassFromString(@"SSOConfiguration");
 Class helper=NSClassFromString(@"SSOKeychainHelper");
 if(!GSPhotosHasMethod(configuration,@"usePrivateKeychain","B16@0:8")||
    !GSPhotosHasMethod(object_getClass(helper),@"sharedAccessGroup","@16@0:8"))return;
 @synchronized(configuration){
  static BOOL installed=NO;if(installed)return;
  id group=nil;
  @try{group=((id(*)(id,SEL))objc_msgSend)(helper,NSSelectorFromString(@"sharedAccessGroup"));}
  @catch(NSException *exception){return;}
  if(![group isKindOfClass:NSString.class]||![group length])return;
  // Check access only: no credentials, item attributes, or authentication UI.
  LAContext *context=[LAContext new];context.interactionNotAllowed=YES;
  NSDictionary *query=@{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
   (__bridge id)kSecAttrAccessGroup:group,
   (__bridge id)kSecAttrService:@"dev.tqmane.gunshot.sso-access-probe",
   (__bridge id)kSecAttrAccount:@"access-group-check",
   (__bridge id)kSecMatchLimit:(__bridge id)kSecMatchLimitOne,
   (__bridge id)kSecUseAuthenticationContext:context};
  if(SecItemCopyMatching((__bridge CFDictionaryRef)query,NULL)!=errSecMissingEntitlement)return;
  // The signed app lacks this shared group. Use SSO's own private mode.
  class_replaceMethod(configuration,NSSelectorFromString(@"usePrivateKeychain"),
   (IMP)GSUsePrivateKeychain,"B16@0:8");
  installed=YES;
 }
}
