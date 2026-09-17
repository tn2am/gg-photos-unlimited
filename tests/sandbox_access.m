#import <Foundation/Foundation.h>
#include <assert.h>
#include <dlfcn.h>
#define dlopen GSFixtureOpen
#define dlsym GSFixtureSymbol
static void *GSFixtureOpen(const char *,int);
static void *GSFixtureSymbol(void *,const char *);
#import "../Shared/GSSandboxAccess.m"
#undef dlopen
#undef dlsym
static NSUInteger Mode,Opens,Applies;
static bool Active;
static bool Redirected(const char *name){return Active&&!strcmp(name,GS_DISCOVERY_SERVICE);}
static int Apply(const char *name){assert(!strcmp(name,GS_IPC_SANDBOX_PROFILE));Applies++;return Mode==2?1:Mode==3?2:0;}
static void *GSFixtureOpen(const char *path,int flags){
 assert(!strcmp(path,THEOS_PACKAGE_INSTALL_PREFIX "/usr/lib/libsandy.dylib"));
 assert(flags==(RTLD_NOW|RTLD_LOCAL));Opens++;return Mode?(void *)&Mode:NULL;
}
static void *GSFixtureSymbol(void *handle,const char *name){
 assert(handle==&Mode);
 if(!strcmp(name,"libSandy_applyProfile"))return Mode==1?NULL:(void *)Apply;
 if(Mode<4)return NULL;
 if(!strcmp(name,"gProcNeedsRedirection"))return &Active;
 if(!strcmp(name,"isMachIdentifierRedirected"))return (void *)Redirected;
 assert(false);return NULL;
}
int main(void){@autoreleasepool{
 assert(GSApplyIPCSandboxProfile()==GS_SANDBOX_LIBRARY_MISSING);
 Mode=1;assert(GSApplyIPCSandboxProfile()==GS_SANDBOX_API_MISSING);
 Mode=2;assert(GSApplyIPCSandboxProfile()==1);
 Mode=3;assert(GSApplyIPCSandboxProfile()==2);
 assert(GSGetSandboxAdapterState().active==-1);
 Mode=4;assert(GSApplyIPCSandboxProfile()==0);
 assert(GSGetSandboxAdapterState().active==0&&GSGetSandboxAdapterState().discoveryRedirected==0);
 assert(Opens==2&&Applies==3);
 Active=true;assert(GSApplyIPCSandboxProfile()==0);
 assert(GSGetSandboxAdapterState().active==1&&GSGetSandboxAdapterState().discoveryRedirected==1);
 assert(GSGetSandboxAdapterState().uploadRedirected==0);
 NSLog(@"PASS sandbox dependency load failures, restricted/unavailable profile and retry recovery");
}}
