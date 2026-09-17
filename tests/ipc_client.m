#import <Foundation/Foundation.h>
#include <assert.h>
#define bootstrap_look_up GSFixtureLookup
#define GSApplyIPCSandboxProfile GSFixtureApplyProfile
#define GSGetSandboxAdapterState GSFixtureSandboxState
#define GSDiscoverDaemon GSFixtureDiscover
#import "../Shared/IPCClient.m"
#undef bootstrap_look_up
#undef GSApplyIPCSandboxProfile
#undef GSGetSandboxAdapterState
#undef GSDiscoverDaemon
#ifndef MPO_ENFORCE_REPLY_PORT_SEMANTICS
#define MPO_ENFORCE_REPLY_PORT_SEMANTICS 0x2000
#endif
static mach_port_t Server;
// 0: direct; 1: profile then raw lookup; 2: discovery; 3: denied; 4: lookup error.
static NSUInteger Route,Lookups,ProfileCalls,Discoveries;
static int ProfileCode;
static kern_return_t LookupCode=1100,DiscoveryCode=KERN_FAILURE;
static const char *DiscoveryFailure="discovery.connection";
static BOOL ProfileApplied;
int GSFixtureApplyProfile(void){ProfileCalls++;ProfileApplied=ProfileCode==0;return ProfileCode;}
GSSandboxAdapterState GSFixtureSandboxState(void){return (GSSandboxAdapterState){1,1,1};}
kern_return_t GSFixtureDiscover(mach_port_t *port,uint32_t timeoutMS,const char **stage){
 Discoveries++;assert(ProfileApplied&&timeoutMS==5000);*port=MACH_PORT_NULL;
 if(Route!=2){*stage=DiscoveryFailure;return DiscoveryCode;}
 *stage="discovery.ready";*port=Server;
 return mach_port_mod_refs(mach_task_self(),*port,MACH_PORT_RIGHT_SEND,1);
}
kern_return_t GSFixtureLookup(mach_port_t bootstrap,const char *name,mach_port_t *port){
 assert(MACH_PORT_VALID(bootstrap));
 // No redirected name or unrelated broker service may be queried, even on failure.
 assert(!strcmp(name,GS_SERVICE));Lookups++;*port=MACH_PORT_NULL;
 if(Route==0||(Route==1&&ProfileApplied))*port=Server;
 if(!MACH_PORT_VALID(*port))return Route==4?KERN_FAILURE:LookupCode;
 return mach_port_mod_refs(mach_task_self(),*port,MACH_PORT_RIGHT_SEND,1);
}
static mach_port_t Endpoint(void){
 mach_port_options_t options={0};options.flags=MPO_ENFORCE_REPLY_PORT_SEMANTICS;
 mach_port_t port;assert(mach_port_construct(mach_task_self(),&options,0,&port)==KERN_SUCCESS);
 assert(mach_port_insert_right(mach_task_self(),port,port,MACH_MSG_TYPE_MAKE_SEND)==KERN_SUCCESS);return port;
}
// Exercise the real GSRequest/Mach exchange. Only name resolution is a fixture.
// Replies: 0 valid, 1 wrong message ID, 2 unexpected descriptor, 3 unauthorized.
static void Exchange(NSUInteger route,NSUInteger replyMode){
 Route=route;Lookups=0;ProfileCode=0;ProfileCalls=0;Discoveries=0;ProfileApplied=NO;Server=Endpoint();
 dispatch_semaphore_t done=dispatch_semaphore_create(0);
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT,0),^{@autoreleasepool{
  size_t capacity=sizeof(GSMessage)+sizeof(mach_msg_max_trailer_t);GSMessage *message=calloc(1,capacity);
  assert(mach_msg(&message->header,MACH_RCV_MSG|MACH_RCV_TIMEOUT,0,(mach_msg_size_t)capacity,Server,3000,0)==KERN_SUCCESS);
  assert(message->header.msgh_id==GS_MESSAGE_ID);
  NSDictionary *request=[NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:message->json length:message->length] options:0 error:nil];
  assert([request[@"op"]isEqual:@"queue"]);
  mach_port_t reply=message->header.msgh_remote_port;memset(message,0,sizeof(*message));
  NSString *json=replyMode==3?@"{\"ok\":false,\"error\":\"unauthorized\"}":@"{\"ok\":true,\"data\":{\"jobs\":[]}}";
  NSData *data=[json dataUsingEncoding:NSUTF8StringEncoding];
  message->header.msgh_remote_port=reply;message->header.msgh_bits=MACH_MSGH_BITS(MACH_MSG_TYPE_MOVE_SEND_ONCE,0);
  message->header.msgh_id=replyMode==1?999:GS_MESSAGE_ID;message->length=(uint32_t)data.length;
  memcpy(message->json,data.bytes,data.length);message->header.msgh_size=(mach_msg_size_t)((offsetof(GSMessage,json)+data.length+3)&~3);
  if(replyMode==2){
   struct {mach_msg_header_t header;mach_msg_body_t body;mach_msg_port_descriptor_t port;} *complex=(void *)message;
   complex->header.msgh_bits|=MACH_MSGH_BITS_COMPLEX;complex->header.msgh_size=sizeof(*complex);
   complex->body.msgh_descriptor_count=1;complex->port=(mach_msg_port_descriptor_t){0};complex->port.name=Server;
   complex->port.type=MACH_MSG_PORT_DESCRIPTOR;complex->port.disposition=MACH_MSG_TYPE_COPY_SEND;
  }
  assert(mach_msg(&message->header,MACH_SEND_MSG|MACH_SEND_TIMEOUT,message->header.msgh_size,0,0,3000,0)==KERN_SUCCESS);
  free(message);dispatch_semaphore_signal(done);
 }});
 NSError *error=nil;NSDictionary *response=GSRequest(@{@"op":@"queue"},&error);
 assert(Lookups==(route?2:1)&&ProfileCalls==(route?1:0)&&Discoveries==(route==2?1:0));
 NSDictionary *snapshot=GSIPCDiagnosticsSnapshot();
 assert([snapshot[@"steps"][0][@"stage"]isEqual:@"lookup.bootstrap"]);
 if(route){
  assert([snapshot[@"steps"][1][@"code"]intValue]==LookupCode);
  assert([snapshot[@"steps"][2][@"stage"]isEqual:@"sandbox.profile"]);
  assert([snapshot[@"steps"][2][@"adapterActive"]intValue]==1);
  assert([snapshot[@"steps"][2][@"discoveryRedirected"]intValue]==1);
  assert([snapshot[@"steps"][3][@"stage"]isEqual:@"lookup.authorized"]);
 }
 if(replyMode){
  NSString *stage=replyMode==3?@"request.rejected":@"request.response";
  assert(!response&&error&&[snapshot[@"stage"]isEqual:stage]);assert([error.localizedDescription containsString:stage]);
  assert([snapshot[@"reachable"]boolValue]==(replyMode==3));
 }else{assert(!error&&[response[@"jobs"]isEqual:@[]]);assert([snapshot[@"reachable"]boolValue]);}
 assert(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);
 mach_port_urefs_t refs=0;
 assert(mach_port_get_refs(mach_task_self(),Server,MACH_PORT_RIGHT_SEND,&refs)==KERN_SUCCESS&&refs==1);
 mach_port_deallocate(mach_task_self(),Server);GSDestroyReplyPort(Server);
}
int main(void){@autoreleasepool{
 for(NSUInteger mode=0;mode<4;mode++)Exchange(0,mode);
 for(NSNumber *initial in @[@1100,@1102]){
  LookupCode=initial.intValue;
  for(NSUInteger route=1;route<=2;route++)for(NSUInteger mode=0;mode<4;mode++)Exchange(route,mode);
  Route=3;ProfileCalls=0;
  for(NSNumber *status in @[@(-1),@(-2),@1,@2,@0]){
   ProfileCode=status.intValue;Lookups=0;Discoveries=0;NSError *denied=nil;
   assert(!GSRequest(@{@"op":@"queue"},&denied));
   NSDictionary *attempt=GSIPCDiagnosticsSnapshot();
   assert(![attempt[@"reachable"]boolValue]);
   assert([attempt[@"stage"]isEqual:ProfileCode?@"sandbox.profile":@"discovery.connection"]);
   assert([attempt[@"code"]intValue]==(ProfileCode?:KERN_FAILURE));
   assert(Lookups==(ProfileCode?1:2)&&Discoveries==(ProfileCode?0:1));
  }
  assert(ProfileCalls==5); // Retry failed profile applications; a grant alone is not a connection.
 }
 for(NSString *stage in @[@"discovery.rejected",@"discovery.invalid",@"discovery.timeout"]){
  DiscoveryFailure=stage.UTF8String;DiscoveryCode=[stage isEqual:@"discovery.timeout"]?MACH_RCV_TIMED_OUT:KERN_FAILURE;
  assert(!GSRequest(@{@"op":@"queue"},nil));NSDictionary *snapshot=GSIPCDiagnosticsSnapshot();
  assert([snapshot[@"stage"]isEqual:stage]&&[snapshot[@"code"]intValue]==DiscoveryCode);
 }
 Route=4;Lookups=0;ProfileCalls=0;Discoveries=0;NSError *error=nil;
 assert(!GSRequest(@{@"op":@"accounts",@"secret":@"must-never-appear-in-diagnostics"},&error));
 NSDictionary *snapshot=GSIPCDiagnosticsSnapshot();assert([snapshot[@"stage"]isEqual:@"lookup.direct"]);
 assert(Lookups==1&&ProfileCalls==0&&Discoveries==0);
 NSData *data=[NSJSONSerialization dataWithJSONObject:snapshot options:0 error:nil];
 assert(![[[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding]containsString:@"must-never"]);
 NSLog(@"PASS direct/scoped/XPC lookup without a broker, namespace recovery, denial, malformed/complex RPC, retry and right cleanup");
}}
