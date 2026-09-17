#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <Network/Network.h>
#include <dlfcn.h>
#include <stddef.h>
#include <sys/stat.h>
#include <unistd.h>
#import "../Shared/IPCProtocol.h"
#import "GSDaemonRunLoop.h"
#import "../Shared/GSDiscovery.h"
#include "../.build/libgotohp.h"

static const char *GSRole(audit_token_t token) {
 // Resolve private Security SPI at runtime and fail closed if unavailable.
 typedef CFTypeRef (*CreateTask)(CFAllocatorRef,audit_token_t);
 typedef CFStringRef (*CopyID)(CFTypeRef,CFErrorRef *);
 typedef int (*ProcPath)(int,void *,uint32_t);
 static CreateTask create=(CreateTask)dlsym(RTLD_DEFAULT,"SecTaskCreateWithAuditToken");
 static CopyID copy=(CopyID)dlsym(RTLD_DEFAULT,"SecTaskCopySigningIdentifier");
 static ProcPath pathForPID=(ProcPath)dlsym(RTLD_DEFAULT,"proc_pidpath");
 if(!create||!copy||!pathForPID||token.val[1]!=501)return NULL;
 CFTypeRef task=create(kCFAllocatorDefault,token);if(!task)return NULL;
 CFStringRef identifier=copy(task,NULL);CFRelease(task);if(!identifier)return NULL;
 NSString *bundle=CFBridgingRelease(identifier);char path[4096]={0};
 if(pathForPID((int)token.val[5],path,sizeof(path))<=0)return NULL;
 NSString *exe=[NSString stringWithUTF8String:path];
 if([bundle isEqualToString:@"com.apple.mobileslideshow"] && [exe hasSuffix:@"/MobileSlideShow.app/MobileSlideShow"] && ([exe hasPrefix:@"/Applications/"]||[exe hasPrefix:@"/System/Applications/"]))return "photos";
 if([bundle isEqualToString:@"com.google.photos"] && [exe hasSuffix:@"/GooglePhotos.app/GooglePhotos"] && ([exe hasPrefix:@"/private/var/containers/Bundle/Application/"]||[exe hasPrefix:@"/var/containers/Bundle/Application/"]))return "googlephotos";
 return NULL;
}
static BOOL GSOnline=NO, GSWiFi=NO; // Accessed only on the conditions queue.
static bool GSAuthorizeDiscovery(audit_token_t token){return GSRole(token)!=NULL;}
static void GSConditions(void) {
 BOOL online=GSOnline,wifi=GSWiFi,charging=NO;
 typedef CFTypeRef (*PowerInfo)(void);typedef CFStringRef (*PowerType)(CFTypeRef);
 static void *powerFramework=dlopen("/System/Library/Frameworks/IOKit.framework/IOKit",RTLD_LAZY|RTLD_LOCAL);
 static PowerInfo powerInfo=powerFramework?(PowerInfo)dlsym(powerFramework,"IOPSCopyPowerSourcesInfo"):NULL;
 static PowerType powerType=powerFramework?(PowerType)dlsym(powerFramework,"IOPSGetProvidingPowerSourceType"):NULL;
 CFTypeRef info=powerInfo?powerInfo():NULL;if(info){CFStringRef source=powerType?powerType(info):NULL;charging=source&&CFEqual(source,CFSTR("AC Power"));CFRelease(info);}
 NSData *b=[NSJSONSerialization dataWithJSONObject:@{@"op":@"conditions",@"online":@(online),@"wifi":@(wifi),@"charging":@(charging)} options:0 error:nil];
 NSString *json=[[NSString alloc]initWithData:b encoding:NSUTF8StringEncoding];
 char *out=GunshotRequest((char *)json.UTF8String,(char *)"daemon");GunshotFree(out);
}
int main(int argc,char **argv) { @autoreleasepool {
 umask(0077);
 if(argc==2 && strcmp(argv[1],"--self-test")==0)return GunshotPing()==1?0:1;
 if(getuid()!=501 || GunshotInitialize((char *)GS_STATE_PATH)!=0)return 1;
 mach_port_t port=MACH_PORT_NULL;
 if(bootstrap_check_in(bootstrap_port,GS_SERVICE,&port)!=KERN_SUCCESS)return 2;
 if(!GSStartDiscoveryService(port,GSAuthorizeDiscovery))return 5;
 dispatch_queue_t conditionsQueue=dispatch_queue_create("dev.tqmane.gunshot.conditions",DISPATCH_QUEUE_SERIAL);
 nw_path_monitor_t monitor=nw_path_monitor_create();nw_path_monitor_set_queue(monitor,conditionsQueue);
 nw_path_monitor_set_update_handler(monitor,^(nw_path_t path){GSOnline=nw_path_get_status(path)==nw_path_status_satisfied;GSWiFi=GSOnline&&nw_path_uses_interface_type(path,nw_interface_type_wifi);GSConditions();});nw_path_monitor_start(monitor);
 dispatch_source_t timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,conditionsQueue);
 dispatch_source_set_timer(timer,DISPATCH_TIME_NOW,5*NSEC_PER_SEC,NSEC_PER_SEC);
 dispatch_source_set_event_handler(timer,^{@autoreleasepool{GSConditions();}});dispatch_resume(timer);
 return GSRunDaemonService(^{
 const size_t capacity=sizeof(GSMessage)+sizeof(mach_msg_max_trailer_t);
 while(true){@autoreleasepool{
 GSMessage *m=(GSMessage *)calloc(1,capacity);
 mach_msg_option_t opts=MACH_RCV_MSG|MACH_RCV_TRAILER_TYPE(MACH_MSG_TRAILER_FORMAT_0)|MACH_RCV_TRAILER_ELEMENTS(MACH_RCV_TRAILER_AUDIT);
 kern_return_t kr=mach_msg(&m->header,opts,0,(mach_msg_size_t)capacity,port,MACH_MSG_TIMEOUT_NONE,MACH_PORT_NULL);
 if(kr!=KERN_SUCCESS){free(m);continue;}
 size_t size=m->header.msgh_size;
 if((m->header.msgh_bits&MACH_MSGH_BITS_COMPLEX)||m->header.msgh_id!=GS_MESSAGE_ID||size<offsetof(GSMessage,json)||size>sizeof(GSMessage)||m->length>GS_MAX_JSON||m->length>size-offsetof(GSMessage,json)) {mach_msg_destroy(&m->header);free(m);continue;}
 mach_msg_audit_trailer_t *trailer=(mach_msg_audit_trailer_t *)((char *)m+((size+3)&~3));
 const char *role=NULL;
 if(trailer->msgh_trailer_type==MACH_MSG_TRAILER_FORMAT_0 && trailer->msgh_trailer_size>=sizeof(*trailer))role=GSRole(trailer->msgh_audit);
 char *request=(char *)calloc(1,m->length+1);memcpy(request,m->json,m->length);
 // Serialized receive bounds memory and prevents untrusted floods from creating threads.
 char *response=role?GunshotRequest(request,(char *)role):strdup("{\"ok\":false,\"error\":\"unauthorized\"}");
 free(request);mach_port_t reply=m->header.msgh_remote_port;
 memset(m,0,sizeof(*m));m->header.msgh_remote_port=reply;m->header.msgh_bits=MACH_MSGH_BITS(MACH_MSG_TYPE_MOVE_SEND_ONCE,0);m->header.msgh_id=GS_MESSAGE_ID;
 size_t n=strlen(response);if(n>GS_MAX_JSON)n=0;m->length=(uint32_t)n;memcpy(m->json,response,n);GunshotFree(response);
 m->header.msgh_size=(mach_msg_size_t)((offsetof(GSMessage,json)+n+3)&~3);
 kr=mach_msg(&m->header,MACH_SEND_MSG|MACH_SEND_TIMEOUT,m->header.msgh_size,0,MACH_PORT_NULL,1000,MACH_PORT_NULL);
 if(kr!=KERN_SUCCESS)mach_msg_destroy(&m->header);free(m);
 }}
 })?0:4;
 }}
