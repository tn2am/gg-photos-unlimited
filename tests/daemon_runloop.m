#import "../Daemon/GSDaemonRunLoop.h"
#include <assert.h>
static BOOL Delivered;
static void Notification(CFNotificationCenterRef center,void *observer,CFStringRef name,const void *object,CFDictionaryRef info){
 assert(NSThread.isMainThread);Delivered=YES;CFRunLoopStop(CFRunLoopGetMain());
}
int main(void){@autoreleasepool{
 NSString *name=[@"dev.tqmane.gunshot.test." stringByAppendingString:NSUUID.UUID.UUIDString];
 CFNotificationCenterRef center=CFNotificationCenterGetDarwinNotifyCenter();
 CFNotificationCenterAddObserver(center,NULL,Notification,(__bridge CFStringRef)name,NULL,CFNotificationSuspensionBehaviorDeliverImmediately);
 dispatch_semaphore_t release=dispatch_semaphore_create(0),finished=dispatch_semaphore_create(0);
 // Bound a regression where main does not process run-loop notification sources.
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_global_queue(QOS_CLASS_DEFAULT,0),^{CFRunLoopStop(CFRunLoopGetMain());});
 assert(GSRunDaemonService(^{
  assert(!NSThread.isMainThread);
  CFNotificationCenterPostNotification(center,(__bridge CFStringRef)name,NULL,NULL,YES);
  assert(dispatch_semaphore_wait(release,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);
  dispatch_semaphore_signal(finished);
 }));
 assert(Delivered);
 dispatch_semaphore_signal(release);assert(dispatch_semaphore_wait(finished,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC))==0);
 CFNotificationCenterRemoveObserver(center,NULL,(__bridge CFStringRef)name,NULL);
 NSLog(@"PASS daemon worker remains independent of main-thread Darwin notification delivery");
}}
