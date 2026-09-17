#include "GSDiscovery.h"
#include "GSXPC.h"
#include <pthread.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <dlfcn.h>

static const char *GSDiscoveryErrorStage(xpc_object_t response) {
 // Compare the public singleton identities, without dumping an XPC object or
 // retaining free-form error descriptions in diagnostics.
 if(response&&(void *)response==dlsym(RTLD_DEFAULT,"_xpc_error_connection_invalid"))return "discovery.invalid";
 if(response&&(void *)response==dlsym(RTLD_DEFAULT,"_xpc_error_connection_interrupted"))return "discovery.interrupted";
 if(response&&(void *)response==dlsym(RTLD_DEFAULT,"_xpc_error_termination_imminent"))return "discovery.terminating";
 return "discovery.error";
}

typedef struct {
 pthread_mutex_t lock;
 atomic_uint refs;
 dispatch_semaphore_t done;
 bool finished;
 kern_return_t code;
 const char *stage;
 mach_port_t port;
} GSDiscoveryAttempt;
static void GSReleaseDiscoveryAttempt(GSDiscoveryAttempt *attempt) {
 if(atomic_fetch_sub(&attempt->refs,1)!=1)return;
 dispatch_release(attempt->done);pthread_mutex_destroy(&attempt->lock);free(attempt);
}
static kern_return_t GSResolveDiscovery(xpc_connection_t connection,mach_port_t *port,uint32_t timeoutMS,const char **stage) {
 GSDiscoveryAttempt *attempt=calloc(1,sizeof(*attempt));
 if(!attempt){*stage="discovery.memory";return KERN_RESOURCE_SHORTAGE;}
 pthread_mutex_init(&attempt->lock,NULL);atomic_init(&attempt->refs,2);
 attempt->done=dispatch_semaphore_create(0);attempt->code=KERN_FAILURE;attempt->stage="discovery.connection";
 xpc_object_t request=xpc_dictionary_create(NULL,NULL,0);
 xpc_dictionary_set_int64(request,"version",1);
 xpc_connection_set_event_handler(connection,^(xpc_object_t event){(void)event;});
 xpc_connection_resume(connection);
 xpc_connection_send_message_with_reply(connection,request,dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^(xpc_object_t response){
  pthread_mutex_lock(&attempt->lock);
  // A late reply owns its descriptors through libxpc; never copy a port after
  // timeout, and never touch caller-owned stack variables from this callback.
  if(!attempt->finished){
   attempt->stage=GSDiscoveryErrorStage(response);
   if(response&&xpc_get_type(response)==XPC_TYPE_DICTIONARY){
    attempt->stage="discovery.response";
    if(xpc_dictionary_get_int64(response,"version")==1){
     attempt->stage="discovery.rejected";
     if(xpc_dictionary_get_bool(response,"ok")){
      attempt->stage="discovery.port";
      attempt->port=xpc_dictionary_copy_mach_send(response,"port");
      if(MACH_PORT_VALID(attempt->port)){attempt->code=KERN_SUCCESS;attempt->stage="discovery.ready";}
     }
    }
   }
   attempt->finished=true;dispatch_semaphore_signal(attempt->done);
  }
  pthread_mutex_unlock(&attempt->lock);GSReleaseDiscoveryAttempt(attempt);
 });
 xpc_release(request);
 dispatch_semaphore_wait(attempt->done,dispatch_time(DISPATCH_TIME_NOW,(int64_t)timeoutMS*NSEC_PER_MSEC));
 pthread_mutex_lock(&attempt->lock);
 if(!attempt->finished){attempt->finished=true;attempt->code=MACH_RCV_TIMED_OUT;attempt->stage="discovery.timeout";}
 kern_return_t code=attempt->code;*stage=attempt->stage;
 if(code==KERN_SUCCESS)*port=attempt->port;
 pthread_mutex_unlock(&attempt->lock);
 xpc_connection_cancel(connection);GSReleaseDiscoveryAttempt(attempt);return code;
}
kern_return_t GSDiscoverDaemon(mach_port_t *port,uint32_t timeoutMS,const char **stage) {
 *port=MACH_PORT_NULL;*stage="discovery.create";
 // This is a LaunchDaemon, even when launchctl reports its execution as
 // user/501. Ask libxpc for the daemon namespace explicitly; an app's local
 // namespace is not authoritative. libSandy can still mediate this lookup.
 xpc_connection_t connection=xpc_connection_create_mach_service(GS_DISCOVERY_SERVICE,NULL,XPC_CONNECTION_MACH_SERVICE_PRIVILEGED);
 if(!connection)return KERN_FAILURE;
 kern_return_t code=GSResolveDiscovery(connection,port,timeoutMS,stage);
 xpc_release(connection);return code;
}
