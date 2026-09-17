#pragma once
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>

static void GSDaemonKeepAlive(void *info) { (void)info; }
// Serve Mach requests on a worker so Foundation/run-loop callbacks can still
// run on main. Discovery and condition monitors have their own dispatch queues.
static inline BOOL GSRunDaemonService(void (^serve)(void)) {
 if(!NSThread.isMainThread)return NO;
 CFRunLoopRef loop=CFRunLoopGetMain();
 CFRunLoopSourceContext context={0};context.perform=GSDaemonKeepAlive;
 CFRunLoopSourceRef keepAlive=CFRunLoopSourceCreate(kCFAllocatorDefault,0,&context);
 if(!keepAlive)return NO;
 CFRunLoopAddSource(loop,keepAlive,kCFRunLoopDefaultMode);
 dispatch_queue_t queue=dispatch_queue_create("dev.tqmane.gunshot.ipc",DISPATCH_QUEUE_SERIAL);
 dispatch_async(queue,serve);
 CFRunLoopRun();
 CFRunLoopRemoveSource(loop,keepAlive,kCFRunLoopDefaultMode);CFRelease(keepAlive);
 return YES;
}
