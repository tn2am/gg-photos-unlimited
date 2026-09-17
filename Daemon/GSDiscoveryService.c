#include "../Shared/GSDiscovery.h"
#include "../Shared/GSXPC.h"

static xpc_object_t GSDiscoveryResponse(xpc_object_t request,mach_port_t port,bool allowed) {
 xpc_object_t reply=xpc_dictionary_create_reply(request);
 if(!reply)return NULL;
 bool valid=allowed&&xpc_dictionary_get_int64(request,"version")==1;
 xpc_dictionary_set_int64(reply,"version",1);xpc_dictionary_set_bool(reply,"ok",valid);
 if(valid)xpc_dictionary_set_mach_send(reply,"port",port);
 return reply;
}
static void GSConfigureDiscovery(xpc_connection_t listener,dispatch_queue_t queue,mach_port_t port,bool (*authorize)(audit_token_t)) {
 xpc_connection_set_event_handler(listener,^(xpc_object_t peer){
  if(xpc_get_type(peer)!=XPC_TYPE_CONNECTION)return;
  xpc_connection_set_target_queue(peer,queue);
  xpc_connection_set_event_handler(peer,^(xpc_object_t request){
   if(xpc_get_type(request)!=XPC_TYPE_DICTIONARY)return;
   audit_token_t token={0};xpc_connection_get_audit_token(peer,&token);
   xpc_object_t reply=GSDiscoveryResponse(request,port,authorize&&authorize(token));
   if(reply){xpc_connection_send_message(peer,reply);xpc_release(reply);}
  });
  xpc_connection_resume(peer);
 });
 xpc_connection_resume(listener);
}
bool GSStartDiscoveryService(mach_port_t port,bool (*authorize)(audit_token_t)) {
 // Own a send right so XPC can copy it to authorized callers. Requests through
 // the transferred port still undergo the existing per-message audit check.
 if(mach_port_insert_right(mach_task_self(),port,port,MACH_MSG_TYPE_MAKE_SEND)!=KERN_SUCCESS)return false;
 dispatch_queue_t queue=dispatch_queue_create("dev.tqmane.gunshot.discovery",DISPATCH_QUEUE_SERIAL);
 xpc_connection_t listener=xpc_connection_create_mach_service(GS_DISCOVERY_SERVICE,queue,XPC_CONNECTION_MACH_SERVICE_LISTENER);
 if(!listener){dispatch_release(queue);mach_port_deallocate(mach_task_self(),port);return false;}
 GSConfigureDiscovery(listener,queue,port,authorize);
 // Listener, queue and send right live for the lifetime of gotohpd.
 return true;
}
