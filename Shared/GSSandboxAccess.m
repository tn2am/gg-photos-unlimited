#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <stdbool.h>
#import "GSSandboxAccess.h"
#import "GSDiscovery.h"

#ifndef THEOS_PACKAGE_INSTALL_PREFIX
#define THEOS_PACKAGE_INSTALL_PREFIX ""
#endif

static GSSandboxAdapterState GSAdapterState={-1,-1,-1};
static NSObject *GSSandboxLock(void){
 static NSObject *lock;static dispatch_once_t once;
 dispatch_once(&once,^{lock=[NSObject new];});
 return lock;
}
GSSandboxAdapterState GSGetSandboxAdapterState(void){@synchronized(GSSandboxLock()){return GSAdapterState;}}
int GSApplyIPCSandboxProfile(void) {
 @synchronized(GSSandboxLock()) {
  GSAdapterState=(GSSandboxAdapterState){-1,-1,-1};
  // Keep the library resident: libSandy may install its scoped iOS 16 lookup
  // adapter. A missing dependency must produce a diagnostic, not a dyld crash.
  static void *library;
  if(!library)library=dlopen(THEOS_PACKAGE_INSTALL_PREFIX "/usr/lib/libsandy.dylib",RTLD_NOW|RTLD_LOCAL);
  if(!library)return GS_SANDBOX_LIBRARY_MISSING;
  int (*apply)(const char *)=(int (*)(const char *))dlsym(library,"libSandy_applyProfile");
  if(!apply)return GS_SANDBOX_API_MISSING;
  // Do not cache a failed attempt: sandyd may be starting or restarting.
  // The root-owned profile grants only our two services to the Photos and
  // Google Photos signing IDs.
  int code=apply(GS_IPC_SANDBOX_PROFILE);
  // Successful token issuance does not imply that lookup redirection is active.
  // These optional provider exports let the diagnostic distinguish those cases.
  bool *active=(bool *)dlsym(library,"gProcNeedsRedirection");
  bool (*redirected)(const char *)=(bool (*)(const char *))dlsym(library,"isMachIdentifierRedirected");
  if(active)GSAdapterState.active=*active;
  if(redirected){
   GSAdapterState.uploadRedirected=redirected("dev.tqmane.gunshot.service");
   GSAdapterState.discoveryRedirected=redirected(GS_DISCOVERY_SERVICE);
  }
  return code;
 }
}
