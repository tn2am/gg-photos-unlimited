#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include "../Shared/GSXPC.h"
// Anonymous listeners are test-only: production always uses a launchd service.
extern xpc_connection_t xpc_connection_create(const char *,dispatch_queue_t);
extern xpc_endpoint_t xpc_endpoint_create(xpc_connection_t);
extern xpc_connection_t xpc_connection_create_from_endpoint(xpc_endpoint_t);
extern xpc_object_t xpc_connection_send_message_with_reply_sync(xpc_connection_t,xpc_object_t);
static xpc_endpoint_t Endpoint;
static xpc_connection_t FixtureConnection(const char *name,dispatch_queue_t queue,uint64_t flags){
 assert(!strcmp(name,"dev.tqmane.gunshot.discovery")&&flags==XPC_CONNECTION_MACH_SERVICE_PRIVILEGED);
 (void)queue;return Endpoint?xpc_connection_create_from_endpoint(Endpoint):NULL;
}
#define xpc_connection_create_mach_service FixtureConnection
#include "../Shared/GSDiscovery.c"
#undef xpc_connection_create_mach_service
#include "../Daemon/GSDiscoveryService.c"
static atomic_bool Allowed;
static atomic_uint Authorizations;
static bool Authorize(audit_token_t token){
 atomic_fetch_add(&Authorizations,1);
 assert(token.val[1]==getuid());assert(token.val[5]==getpid());
 return atomic_load(&Allowed);
}
static void CheckRefs(mach_port_t port,mach_port_urefs_t expected){
 mach_port_urefs_t count;assert(mach_port_get_refs(mach_task_self(),port,MACH_PORT_RIGHT_SEND,&count)==KERN_SUCCESS&&count==expected);
}
int main(void){
 alarm(20);
 assert(!strcmp(GSDiscoveryErrorStage(dlsym(RTLD_DEFAULT,"_xpc_error_connection_invalid")),"discovery.invalid"));
 assert(!strcmp(GSDiscoveryErrorStage(dlsym(RTLD_DEFAULT,"_xpc_error_connection_interrupted")),"discovery.interrupted"));
 mach_port_t server;assert(mach_port_allocate(mach_task_self(),MACH_PORT_RIGHT_RECEIVE,&server)==KERN_SUCCESS);
 assert(mach_port_insert_right(mach_task_self(),server,server,MACH_MSG_TYPE_MAKE_SEND)==KERN_SUCCESS);
 dispatch_queue_t queue=dispatch_queue_create("gunshot.discovery.test",DISPATCH_QUEUE_SERIAL);
 xpc_connection_t listener=xpc_connection_create(NULL,queue);
 GSConfigureDiscovery(listener,queue,server,Authorize);Endpoint=xpc_endpoint_create(listener);
 for(unsigned i=0;i<5;i++){
  atomic_store(&Allowed,true);mach_port_t resolved=MACH_PORT_NULL;const char *stage=NULL;
  assert(GSDiscoverDaemon(&resolved,3000,&stage)==KERN_SUCCESS);
  assert(resolved==server&&!strcmp(stage,"discovery.ready"));
  mach_port_deallocate(mach_task_self(),resolved);
  atomic_store(&Allowed,false);
  assert(GSDiscoverDaemon(&resolved,3000,&stage)==KERN_FAILURE);
  assert(!MACH_PORT_VALID(resolved)&&!strcmp(stage,"discovery.rejected"));
 }
 assert(atomic_load(&Authorizations)==10);
 // Invalid protocol cannot obtain the port even from an authorized peer.
 atomic_store(&Allowed,true);
 xpc_connection_t invalid=xpc_connection_create_from_endpoint(Endpoint);
 xpc_connection_set_event_handler(invalid,^(xpc_object_t event){(void)event;});xpc_connection_resume(invalid);
 xpc_object_t request=xpc_dictionary_create(NULL,NULL,0);xpc_dictionary_set_int64(request,"version",99);
 xpc_object_t reply=xpc_connection_send_message_with_reply_sync(invalid,request);
 assert(xpc_get_type(reply)==XPC_TYPE_DICTIONARY&&!xpc_dictionary_get_bool(reply,"ok"));
 assert(!MACH_PORT_VALID(xpc_dictionary_copy_mach_send(reply,"port")));
 xpc_release(reply);xpc_release(request);xpc_connection_cancel(invalid);xpc_release(invalid);
 xpc_release(Endpoint);xpc_connection_cancel(listener);xpc_release(listener);
 // A late port-bearing reply after timeout must never overwrite the caller's
 // output or leave an extra send right behind.
 dispatch_semaphore_t late=dispatch_semaphore_create(0);
 listener=xpc_connection_create(NULL,queue);
 xpc_connection_set_event_handler(listener,^(xpc_object_t peer){
  if(xpc_get_type(peer)!=XPC_TYPE_CONNECTION)return;
  xpc_connection_set_target_queue(peer,queue);
  xpc_connection_set_event_handler(peer,^(xpc_object_t message){
   if(xpc_get_type(message)!=XPC_TYPE_DICTIONARY)return;
   xpc_object_t response=GSDiscoveryResponse(message,server,true);
   xpc_retain(peer);
   dispatch_after(dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),queue,^{
    xpc_connection_send_message(peer,response);xpc_release(response);xpc_release(peer);dispatch_semaphore_signal(late);
   });
  });xpc_connection_resume(peer);
 });xpc_connection_resume(listener);Endpoint=xpc_endpoint_create(listener);
 mach_port_t resolved;const char *stage;
 assert(GSDiscoverDaemon(&resolved,10,&stage)==MACH_RCV_TIMED_OUT);
 assert(resolved==MACH_PORT_NULL&&!strcmp(stage,"discovery.timeout"));
 assert(dispatch_semaphore_wait(late,dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC))==0);
 xpc_release(Endpoint);Endpoint=NULL;xpc_connection_cancel(listener);xpc_release(listener);
 assert(GSDiscoverDaemon(&resolved,10,&stage)==KERN_FAILURE&&!strcmp(stage,"discovery.create"));
 // libxpc teardown is asynchronous; allow bounded cleanup before counting.
 for(unsigned i=0;i<100;i++){mach_port_urefs_t count=0;mach_port_get_refs(mach_task_self(),server,MACH_PORT_RIGHT_SEND,&count);if(count==1)break;usleep(10000);}
 CheckRefs(server,1);mach_port_deallocate(mach_task_self(),server);mach_port_mod_refs(mach_task_self(),server,MACH_PORT_RIGHT_RECEIVE,-1);
 dispatch_release(late);dispatch_release(queue);
 puts("PASS real XPC discovery, peer audit, denied/invalid requests, timeout, late reply and send-right cleanup");
}
