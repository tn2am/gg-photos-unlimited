#pragma once
#include <mach/mach.h>

// XNU 8792 reply-port semantics; older SDKs may omit the public flag name.
#ifndef MPO_REPLY_PORT
#define MPO_REPLY_PORT 0x1000
#endif
static inline kern_return_t GSCreateReplyPort(mach_port_t *port) {
 *port=MACH_PORT_NULL;
 mach_port_options_t options={0};
 if(__builtin_available(iOS 16.0, macOS 13.0, *))options.flags=MPO_REPLY_PORT;
 // Never retry with an ordinary port on a kernel enforcing reply semantics.
 return mach_port_construct(mach_task_self(),&options,0,port);
}
static inline void GSDestroyReplyPort(mach_port_t port) {
 if(MACH_PORT_VALID(port))mach_port_mod_refs(mach_task_self(),port,MACH_PORT_RIGHT_RECEIVE,-1);
}
