#pragma once
// C-only declarations for libxpc APIs omitted from public iPhoneOS SDKs.
// Keep XPC ownership explicit in .c files; no OS_OBJECT / ARC type bridging.
#include <dispatch/dispatch.h>
#include <mach/mach.h>
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
typedef struct _xpc_object_s *xpc_object_t;
typedef xpc_object_t xpc_connection_t;
typedef xpc_object_t xpc_endpoint_t;
typedef const struct _xpc_type_s *xpc_type_t;
extern const struct _xpc_type_s _xpc_type_dictionary, _xpc_type_connection;
#define XPC_TYPE_DICTIONARY (&_xpc_type_dictionary)
#define XPC_TYPE_CONNECTION (&_xpc_type_connection)
#define XPC_CONNECTION_MACH_SERVICE_LISTENER (1ULL << 0)
#define XPC_CONNECTION_MACH_SERVICE_PRIVILEGED (1ULL << 1)
extern xpc_type_t xpc_get_type(xpc_object_t);
extern xpc_object_t xpc_retain(xpc_object_t);
extern void xpc_release(xpc_object_t);
extern xpc_connection_t xpc_connection_create_mach_service(const char *,dispatch_queue_t,uint64_t);
extern void xpc_connection_set_target_queue(xpc_connection_t,dispatch_queue_t);
extern void xpc_connection_set_event_handler(xpc_connection_t,void (^)(xpc_object_t));
extern void xpc_connection_resume(xpc_connection_t);
extern void xpc_connection_cancel(xpc_connection_t);
extern void xpc_connection_send_message(xpc_connection_t,xpc_object_t);
extern void xpc_connection_send_message_with_reply(xpc_connection_t,xpc_object_t,dispatch_queue_t,void (^)(xpc_object_t));
extern void xpc_connection_get_audit_token(xpc_connection_t,audit_token_t *);
extern xpc_object_t xpc_dictionary_create(const char *const *,const xpc_object_t *,size_t);
extern xpc_object_t xpc_dictionary_create_reply(xpc_object_t);
extern void xpc_dictionary_set_int64(xpc_object_t,const char *,int64_t);
extern int64_t xpc_dictionary_get_int64(xpc_object_t,const char *);
extern void xpc_dictionary_set_bool(xpc_object_t,const char *,bool);
extern bool xpc_dictionary_get_bool(xpc_object_t,const char *);
extern mach_port_t xpc_dictionary_copy_mach_send(xpc_object_t,const char *);
extern void xpc_dictionary_set_mach_send(xpc_object_t,const char *,mach_port_t);
