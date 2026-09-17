#import "GSLocalization.h"
#import "IPCProtocol.h"
#include <stddef.h>
#include <string.h>
#import "GSMachTransport.h"
#import "GSSandboxAccess.h"
#import "GSDiscovery.h"

// Each request owns its trace; concurrent polls cannot combine unrelated stages.
static NSDictionary *GSLastIPC;
static NSObject *GSIPCLock(void){static NSObject *lock;static dispatch_once_t once;dispatch_once(&once,^{lock=[NSObject new];});return lock;}
NSDictionary *GSIPCDiagnosticsSnapshot(void){@synchronized(GSIPCLock()){return GSLastIPC?:@{@"schemaVersion":@1,@"stage":@"not-attempted"};}}
static void GSTrace(NSMutableArray *trace,const char *stage,kern_return_t code){[trace addObject:@{@"stage":@(stage),@"code":@(code)}];}
static void GSRecordIPC(NSArray *trace,const char *stage,kern_return_t code,BOOL reachable){
 NSDictionary *snapshot=@{@"schemaVersion":@1,@"stage":@(stage),@"code":@(code),@"reachable":@(reachable),@"steps":[trace copy]};
 @synchronized(GSIPCLock()){GSLastIPC=snapshot;}
}
static NSError *GSIPCError(NSString *message,const char *stage,kern_return_t code){
 return [NSError errorWithDomain:@"Gunshot.IPC" code:code userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"%@ [%@: 0x%08x]",message,@(stage),(unsigned int)code]}];
}
static kern_return_t GSLookupDaemon(mach_port_t *server,NSMutableArray *trace,const char **stage) {
 // Acquire the calling task's current bootstrap port, including user-domain
 // changes, instead of relying on libSystem's process-global cached value.
 mach_port_t bootstrap=MACH_PORT_NULL;
 *stage="lookup.bootstrap";
 kern_return_t kr=task_get_bootstrap_port(mach_task_self(),&bootstrap);GSTrace(trace,*stage,kr);
 if(kr!=KERN_SUCCESS)return kr;
 *stage="lookup.direct";kr=bootstrap_look_up(bootstrap,GS_SERVICE,server);GSTrace(trace,*stage,kr);
 if(kr==KERN_SUCCESS)goto done;
 // A running LaunchDaemon may be denied (1100) or absent from the calling
 // app's bootstrap namespace (1102). Apply only our signing-ID-restricted
 // profile, then let privileged XPC discovery resolve the daemon if needed.
 if(kr==1100||kr==1102){
  int profileCode=GSApplyIPCSandboxProfile();
  *stage="sandbox.profile";
  GSSandboxAdapterState adapter=GSGetSandboxAdapterState();
  [trace addObject:@{@"stage":@(*stage),@"code":@(profileCode),@"adapterActive":@(adapter.active),@"uploadRedirected":@(adapter.uploadRedirected),@"discoveryRedirected":@(adapter.discoveryRedirected)}];
  if(profileCode==0){
   *stage="lookup.authorized";kr=bootstrap_look_up(bootstrap,GS_SERVICE,server);GSTrace(trace,*stage,kr);
   if(kr==KERN_SUCCESS)goto done;
   kr=GSDiscoverDaemon(server,5000,stage);GSTrace(trace,*stage,kr);
  }else kr=profileCode;
 }
done:
 mach_port_deallocate(mach_task_self(),bootstrap);return kr;
}
NSDictionary *GSRequest(NSDictionary *request, NSError **error) {
 NSData *data=[NSJSONSerialization dataWithJSONObject:request options:0 error:error];
 if (!data || data.length>GS_MAX_JSON) return nil;
 mach_port_t server=MACH_PORT_NULL, reply=MACH_PORT_NULL;
 NSMutableArray *trace=[NSMutableArray array];const char *stage="lookup.bootstrap";
 kern_return_t kr=GSLookupDaemon(&server,trace,&stage);
 if(kr!=KERN_SUCCESS) goto fail;
 stage="request.reply-port";kr=GSCreateReplyPort(&reply);GSTrace(trace,stage,kr);
 if(kr!=KERN_SUCCESS) goto fail;
 {
 GSMessage *message=calloc(1,sizeof(GSMessage)+sizeof(mach_msg_max_trailer_t));
 if(!message){stage="request.buffer";kr=KERN_RESOURCE_SHORTAGE;GSTrace(trace,stage,kr);goto fail;}
 message->header.msgh_bits=MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND,MACH_MSG_TYPE_MAKE_SEND_ONCE);
 message->header.msgh_remote_port=server;message->header.msgh_local_port=reply;
 message->header.msgh_id=GS_MESSAGE_ID;message->length=(uint32_t)data.length;
 memcpy(message->json,data.bytes,data.length);
 message->header.msgh_size=(mach_msg_size_t)((offsetof(GSMessage,json)+data.length+3)&~3);
 stage="request.send";kr=mach_msg(&message->header,MACH_SEND_MSG|MACH_SEND_TIMEOUT,message->header.msgh_size,0,MACH_PORT_NULL,5000,MACH_PORT_NULL);
 GSTrace(trace,stage,kr);
 if(kr==KERN_SUCCESS){stage="request.receive";kr=mach_msg(&message->header,MACH_RCV_MSG|MACH_RCV_TIMEOUT,0,sizeof(GSMessage)+sizeof(mach_msg_max_trailer_t),reply,120000,MACH_PORT_NULL);GSTrace(trace,stage,kr);}
 NSDictionary *result=nil;BOOL reachable=NO;
 if(kr==KERN_SUCCESS)stage="request.response";
 if(kr==KERN_SUCCESS && !(message->header.msgh_bits&MACH_MSGH_BITS_COMPLEX) && message->header.msgh_id==GS_MESSAGE_ID && message->header.msgh_size>=offsetof(GSMessage,json) && message->length<=GS_MAX_JSON && message->length<=message->header.msgh_size-offsetof(GSMessage,json)) {
 id parsed=[NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:message->json length:message->length] options:0 error:nil];
 if([parsed isKindOfClass:NSDictionary.class]){
  reachable=YES;stage="request.rejected";
  if([parsed[@"ok"] boolValue])result=parsed[@"data"]==NSNull.null?@{}:parsed[@"data"];
 }
 }
 if(kr==KERN_SUCCESS)mach_msg_destroy(&message->header);
 free(message);GSDestroyReplyPort(reply);mach_port_deallocate(mach_task_self(),server);
 if(result){GSTrace(trace,"connected",KERN_SUCCESS);GSRecordIPC(trace,"connected",KERN_SUCCESS,YES);return result;}
 if(kr==KERN_SUCCESS)kr=KERN_FAILURE;
 GSTrace(trace,stage,kr);GSRecordIPC(trace,stage,kr,reachable);
 if(error)*error=GSIPCError(GSL(@"GoToHP request failed. Check the daemon, account and queue."),stage,kr);return nil;
 }
fail:
 GSDestroyReplyPort(reply);
 if(server!=MACH_PORT_NULL)mach_port_deallocate(mach_task_self(),server);
 GSRecordIPC(trace,stage,kr,NO);
 if(error)*error=GSIPCError(GSL(@"GoToHP daemon connection failed."),stage,kr);return nil;
}
