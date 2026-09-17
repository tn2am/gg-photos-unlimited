#import <Foundation/Foundation.h>
#include <assert.h>
#import "../Shared/GSMachTransport.h"
#ifndef MPO_ENFORCE_REPLY_PORT_SEMANTICS
#define MPO_ENFORCE_REPLY_PORT_SEMANTICS 0x2000
#endif
// Verify the shared reply-port helpers against the real kernel. These flags
// remain necessary for direct daemon RPC after the legacy broker is removed.
static void Exchange(BOOL timeout){
 mach_port_t server=MACH_PORT_NULL,reply=MACH_PORT_NULL;
 mach_port_options_t options={0};options.flags=MPO_ENFORCE_REPLY_PORT_SEMANTICS;
 assert(mach_port_construct(mach_task_self(),&options,0,&server)==KERN_SUCCESS);
 assert(mach_port_insert_right(mach_task_self(),server,server,MACH_MSG_TYPE_MAKE_SEND)==KERN_SUCCESS);
 assert(GSCreateReplyPort(&reply)==KERN_SUCCESS);
 dispatch_semaphore_t done=dispatch_semaphore_create(0),clientDone=dispatch_semaphore_create(0);
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT,0),^{
  struct {mach_msg_header_t header;char trailer[sizeof(mach_msg_max_trailer_t)];} incoming={0};
  assert(mach_msg(&incoming.header,MACH_RCV_MSG|MACH_RCV_TIMEOUT,0,sizeof(incoming),server,3000,0)==KERN_SUCCESS);
  assert(incoming.header.msgh_id==42);
  if(timeout){
   assert(dispatch_semaphore_wait(clientDone,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);
   mach_msg_destroy(&incoming.header);
  }else{
   mach_msg_header_t response={0};response.msgh_remote_port=incoming.header.msgh_remote_port;
   response.msgh_bits=MACH_MSGH_BITS(MACH_MSG_TYPE_MOVE_SEND_ONCE,0);response.msgh_id=43;response.msgh_size=sizeof(response);
   assert(mach_msg(&response,MACH_SEND_MSG|MACH_SEND_TIMEOUT,sizeof(response),0,0,3000,0)==KERN_SUCCESS);
  }
  dispatch_semaphore_signal(done);
 });
 struct {mach_msg_header_t header;char trailer[sizeof(mach_msg_max_trailer_t)];} message={0};
 message.header.msgh_bits=MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND,MACH_MSG_TYPE_MAKE_SEND_ONCE);
 message.header.msgh_remote_port=server;message.header.msgh_local_port=reply;message.header.msgh_id=42;message.header.msgh_size=sizeof(mach_msg_header_t);
 assert(mach_msg(&message.header,MACH_SEND_MSG|MACH_SEND_TIMEOUT,message.header.msgh_size,0,0,1000,0)==KERN_SUCCESS);
 kern_return_t kr=mach_msg(&message.header,MACH_RCV_MSG|MACH_RCV_TIMEOUT,0,sizeof(message),reply,timeout?20:3000,0);
 assert(kr==(timeout?MACH_RCV_TIMED_OUT:KERN_SUCCESS));
 if(kr==KERN_SUCCESS){assert(message.header.msgh_id==43);mach_msg_destroy(&message.header);}
 dispatch_semaphore_signal(clientDone);assert(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);
 mach_port_urefs_t refs=0;assert(mach_port_get_refs(mach_task_self(),server,MACH_PORT_RIGHT_SEND,&refs)==KERN_SUCCESS&&refs==1);
 GSDestroyReplyPort(reply);mach_port_deallocate(mach_task_self(),server);GSDestroyReplyPort(server);
}
int main(void){@autoreleasepool{
 for(NSUInteger i=0;i<10;i++){Exchange(NO);Exchange(YES);}
 GSDestroyReplyPort(MACH_PORT_NULL);
 NSLog(@"PASS direct reply-enforcing Mach round trip, timeout and repeated reply-port cleanup");
}}
