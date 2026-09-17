#import "SideloadIdentity.h"
#import "../Shared/GSPhotosCompatibility.h"
#import <objc/message.h>
#include <stdatomic.h>
#include <stdlib.h>

static NSString *GSInstalledBundleID;
static id (*GSOriginalApplicationIdentifier)(id,SEL);
static id (*GSOriginalSSOBundleID)(id,SEL);
static atomic_bool GSApplicationIdentityUsed,GSBundleIdentityUsed;

static id GSApplicationIdentifier(id object,SEL selector){
 id value=GSOriginalApplicationIdentifier(object,selector);
 if(![value isEqual:GSInstalledBundleID])return value;
 id client=((id(*)(id,SEL))objc_msgSend)(object,NSSelectorFromString(@"clientID"));
 // This client and its registered callback scheme are shared by both audited IPAs.
 if(![client isEqual:@"278930400967-s7eptfh2d81vvi86kptt63pfa0o5usjt.apps.googleusercontent.com"])return value;
 atomic_store(&GSApplicationIdentityUsed,YES);
 return @"com.google.photos";
}
static id GSSSOBundleID(id object,SEL selector){
 id value=GSOriginalSSOBundleID(object,selector);
 if(![value isEqual:GSInstalledBundleID])return value;
 atomic_store(&GSBundleIdentityUsed,YES);
 return @"com.google.photos";
}
void GSInstallSideloadIdentity(void){
 const char *liveContainer=getenv("LC_HOME_PATH");
 if((liveContainer&&*liveContainer)||!GSPhotosHostSupported())return;
 id identifier=NSBundle.mainBundle.bundleIdentifier;
 if(![identifier isKindOfClass:NSString.class]||![identifier length]||[identifier isEqual:@"com.google.photos"])return;
 @synchronized(NSBundle.class){
  if(!GSInstalledBundleID)GSInstalledBundleID=[identifier copy];
  Class configuration=NSClassFromString(@"SSOConfiguration");
  if(!GSOriginalApplicationIdentifier&&
     GSPhotosHasMethod(configuration,@"applicationIdentifier","@16@0:8")&&
     GSPhotosHasMethod(configuration,@"clientID","@16@0:8")){
   SEL selector=NSSelectorFromString(@"applicationIdentifier");
   GSOriginalApplicationIdentifier=(void *)method_getImplementation(class_getInstanceMethod(configuration,selector));
   // AuthAdvice reads this getter after GIK configuration, including later overrides.
   class_replaceMethod(configuration,selector,(IMP)GSApplicationIdentifier,"@16@0:8");
  }
  // Optional newer SSO Objective-C entry point; absent in 7.20.2.
  Class service=NSClassFromString(@"SSOBundleIdServiceImpl");
  if(!GSOriginalSSOBundleID&&GSPhotosHasMethod(service,@"bundleId","@16@0:8")){
   SEL selector=NSSelectorFromString(@"bundleId");
   GSOriginalSSOBundleID=(void *)method_getImplementation(class_getInstanceMethod(service,selector));
   class_replaceMethod(service,selector,(IMP)GSSSOBundleID,"@16@0:8");
  }
 }
}
NSDictionary *GSSideloadIdentitySnapshot(void){
 // Status only: no installed identifier, client state, challenge, URL or credentials.
 return @{@"configurationHook":@(GSOriginalApplicationIdentifier!=NULL),
  @"bundleServiceHook":@(GSOriginalSSOBundleID!=NULL),
  @"configurationUsed":@(atomic_load(&GSApplicationIdentityUsed)),
  @"bundleServiceUsed":@(atomic_load(&GSBundleIdentityUsed))};
}
