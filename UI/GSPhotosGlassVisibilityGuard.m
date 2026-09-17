#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

static IMP GSOriginalSetTabBarHiddenAnimated;
static IMP GSOriginalSetTabBarIsHidden;
static IMP GSOriginalOverlaySetContentSuppressed;
static IMP GSOriginalOverlayRootSetHidden;
static Class GSHookedOverlayRootClass;
static BOOL GSVisibilityGuardInstalled;
static char GSExplicitHiddenStateKey;
static char GSVisibilityStateArmedKey;

static BOOL GSIsPhotosGlassOverlayWindow(UIWindow *window){
 if(!window)return NO;
 return [NSStringFromClass(window.class)isEqualToString:@"GSPhotosGlassOverlayWindow"]&&
        [window.rootViewController isKindOfClass:UITabBarController.class];
}

static UIViewController *GSFindPhotosTabController(UIViewController *controller){
 if(!controller)return nil;
 Class cls=NSClassFromString(@"PHSTabBarController");
 if(cls&&[controller isKindOfClass:cls])return controller;
 for(UIViewController *child in controller.childViewControllers){
  UIViewController *match=GSFindPhotosTabController(child);if(match)return match;
 }
 UIViewController *presented=controller.presentedViewController;
 if(presented&&!presented.isBeingDismissed){
  UIViewController *match=GSFindPhotosTabController(presented);if(match)return match;
 }
 return nil;
}

static UIWindow *GSPhotosHostWindow(UIWindowScene *scene,UIViewController **tabControllerOut){
 if(tabControllerOut)*tabControllerOut=nil;
 UIWindow *fallback=nil;UIViewController *fallbackTabs=nil;
 for(UIWindow *window in scene.windows){
  if(GSIsPhotosGlassOverlayWindow(window)||!window.rootViewController||window.hidden||window.alpha<=0.01)continue;
  UIViewController *tabs=GSFindPhotosTabController(window.rootViewController);
  if(!tabs)continue;
  if(window.isKeyWindow){if(tabControllerOut)*tabControllerOut=tabs;return window;}
  if(!fallback){fallback=window;fallbackTabs=tabs;}
 }
 if(tabControllerOut)*tabControllerOut=fallbackTabs;
 return fallback;
}

static UIWindow *GSGlassOverlayWindow(UIWindowScene *scene){
 for(UIWindow *window in scene.windows)if(GSIsPhotosGlassOverlayWindow(window))return window;
 return nil;
}

static void GSSetExplicitHidden(id controller,BOOL hidden){
 if(!controller)return;
 objc_setAssociatedObject(controller,&GSExplicitHiddenStateKey,@(hidden),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static BOOL GSExplicitlyHidden(id controller){
 NSNumber *value=controller?objc_getAssociatedObject(controller,&GSExplicitHiddenStateKey):nil;
 return value.boolValue;
}
static void GSSetVisibilityStateArmed(id controller,BOOL armed){
 if(!controller)return;
 objc_setAssociatedObject(controller,&GSVisibilityStateArmedKey,@(armed),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static BOOL GSVisibilityStateArmed(id controller){
 NSNumber *value=controller?objc_getAssociatedObject(controller,&GSVisibilityStateArmedKey):nil;
 return value.boolValue;
}

static BOOL GSOverlayNativeTabsReady(UIWindow *overlayWindow){
 if(!GSIsPhotosGlassOverlayWindow(overlayWindow)||overlayWindow.hidden)return NO;
 UITabBarController *tabs=(UITabBarController *)overlayWindow.rootViewController;
 return tabs.isViewLoaded&&tabs.tabBar&&tabs.tabBar.window==overlayWindow;
}

static id GSCallObjectGetter(id object,NSString *name){
 SEL selector=NSSelectorFromString(name);
 return object&&[object respondsToSelector:selector]?((id(*)(id,SEL))objc_msgSend)(object,selector):nil;
}

static BOOL GSViewGeometricallyVisible(UIView *view,UIWindow *window){
 if(!view||!window||view.window!=window)return NO;
 for(UIView *node=view;node&&node!=window;node=node.superview)if(node.hidden||node.alpha<=0.01)return NO;
 CGRect rect=[view convertRect:view.bounds toView:window];
 if(CGRectIsNull(rect)||CGRectIsEmpty(rect))return NO;
 CGRect visible=CGRectIntersection(rect,window.bounds);
 return !CGRectIsNull(visible)&&!CGRectIsEmpty(visible)&&CGRectGetWidth(visible)>8.0&&CGRectGetHeight(visible)>8.0;
}

static BOOL GSPhotosSourceBarVisible(UIViewController *tabs,UIWindow *hostWindow){
 UIView *bar=GSCallObjectGetter(tabs,@"floatingBottomTabBar");
 return [bar isKindOfClass:UIView.class]&&GSViewGeometricallyVisible(bar,hostWindow);
}

static BOOL GSControllerHasPresentedOverlay(UIViewController *controller,UIWindow *hostWindow){
 if(!controller)return NO;
 UIViewController *presented=controller.presentedViewController;
 if(presented&&!presented.isBeingDismissed){
  if(!presented.isViewLoaded)return YES;
  UIView *view=presented.view;
  if(!view.hidden&&view.alpha>0.01&&(view.window==hostWindow||view.window==nil))return YES;
 }
 for(UIViewController *child in controller.childViewControllers)
  if(GSControllerHasPresentedOverlay(child,hostWindow))return YES;
 return NO;
}

static BOOL GSClassLoadedFromPhotosBundle(Class cls){
 if(!cls)return NO;
 const char *image=class_getImageName(cls);if(!image)return NO;
 NSString *path=[NSString stringWithUTF8String:image];
 NSString *bundlePath=NSBundle.mainBundle.bundlePath;
 return path.length&&bundlePath.length&&[path hasPrefix:bundlePath];
}

static BOOL GSControllerTreeContainsPhotosCode(UIViewController *controller,NSMutableSet *seen){
 if(!controller||[seen containsObject:controller])return NO;[seen addObject:controller];
 if(GSClassLoadedFromPhotosBundle(controller.class))return YES;
 for(UIViewController *child in controller.childViewControllers)
  if(GSControllerTreeContainsPhotosCode(child,seen))return YES;
 UIViewController *presented=controller.presentedViewController;
 return presented&&!presented.isBeingDismissed&&GSControllerTreeContainsPhotosCode(presented,seen);
}

static BOOL GSWindowBelongsToPhotosUI(UIWindow *window){
 if(!window.rootViewController)return NO;
 return GSControllerTreeContainsPhotosCode(window.rootViewController,[NSMutableSet set]);
}

static BOOL GSWindowActuallyCoversNativeTabs(UIWindow *candidate,UIWindow *hostWindow,UIWindow *overlayWindow){
 if(!candidate||candidate==hostWindow||candidate==overlayWindow||candidate.hidden||candidate.alpha<=0.01||!candidate.rootViewController)return NO;
 if(candidate.windowLevel<hostWindow.windowLevel||candidate.windowLevel>hostWindow.windowLevel+10.0)return NO;
 if(candidate.windowLevel==hostWindow.windowLevel&&!candidate.isKeyWindow)return NO;
 if(!GSWindowBelongsToPhotosUI(candidate))return NO;
 UITabBarController *tabs=[overlayWindow.rootViewController isKindOfClass:UITabBarController.class]?(UITabBarController *)overlayWindow.rootViewController:nil;
 UITabBar *tabBar=tabs.tabBar;
 if(!tabBar||tabBar.hidden||tabBar.alpha<=0.01||!tabBar.window)return NO;
 CGRect tabRect=[tabBar convertRect:tabBar.bounds toView:overlayWindow];
 if(CGRectIsNull(tabRect)||CGRectIsEmpty(tabRect))return NO;
 CGFloat y=CGRectGetMidY(tabRect);
 CGFloat xs[]={CGRectGetMinX(tabRect)+CGRectGetWidth(tabRect)*0.15,CGRectGetMidX(tabRect),CGRectGetMinX(tabRect)+CGRectGetWidth(tabRect)*0.85};
 for(NSUInteger i=0;i<3;i++){
  CGPoint screenPoint=[overlayWindow convertPoint:CGPointMake(xs[i],y) toWindow:nil];
  CGPoint candidatePoint=[candidate convertPoint:screenPoint fromWindow:nil];
  if(!CGRectContainsPoint(candidate.bounds,candidatePoint))continue;
  UIView *hit=[candidate hitTest:candidatePoint withEvent:nil];
  if(hit&&hit.window==candidate)return YES;
 }
 return NO;
}

static BOOL GSSceneHasOccludingPhotosWindow(UIWindowScene *scene,UIWindow *hostWindow,UIWindow *overlayWindow){
 for(UIWindow *window in scene.windows)if(GSWindowActuallyCoversNativeTabs(window,hostWindow,overlayWindow))return YES;
 return NO;
}

static BOOL GSSceneShouldMaskNativeTabs(UIWindowScene *scene,UIWindow *overlayWindow){
 UIViewController *tabs=nil;UIWindow *hostWindow=GSPhotosHostWindow(scene,&tabs);
 if(!hostWindow||!tabs)return YES;
 if(!GSVisibilityStateArmed(tabs)&&GSOverlayNativeTabsReady(overlayWindow)){
  GSSetVisibilityStateArmed(tabs,YES);GSSetExplicitHidden(tabs,NO);
 }
 if(GSVisibilityStateArmed(tabs)&&GSExplicitlyHidden(tabs))return YES;
 if(!GSPhotosSourceBarVisible(tabs,hostWindow))return YES;
 if(GSControllerHasPresentedOverlay(hostWindow.rootViewController,hostWindow))return YES;
 if(GSSceneHasOccludingPhotosWindow(scene,hostWindow,overlayWindow))return YES;
 return NO;
}

static void GSOverlayRootSetHidden(UIView *view,SEL selector,BOOL hidden){
 UIWindow *window=view.window;
 if(hidden&&GSIsPhotosGlassOverlayWindow(window)&&window.windowScene&&!GSSceneShouldMaskNativeTabs(window.windowScene,window))hidden=NO;
 ((void(*)(id,SEL,BOOL))GSOriginalOverlayRootSetHidden)(view,selector,hidden);
}

static void GSInstallOverlayRootHiddenGuard(UITabBarController *tabs){
 if(!tabs.isViewLoaded||GSHookedOverlayRootClass)return;
 Class cls=tabs.view.class;SEL selector=@selector(setHidden:);Method method=class_getInstanceMethod(cls,selector);if(!method)return;
 IMP current=method_getImplementation(method);
 IMP replaced=class_replaceMethod(cls,selector,(IMP)GSOverlayRootSetHidden,method_getTypeEncoding(method));
 GSOriginalOverlayRootSetHidden=replaced?:current;GSHookedOverlayRootClass=cls;
}

static void GSApplySceneMask(UIWindowScene *scene){
 UIWindow *overlayWindow=GSGlassOverlayWindow(scene);if(!overlayWindow)return;
 UITabBarController *tabs=[overlayWindow.rootViewController isKindOfClass:UITabBarController.class]?(UITabBarController *)overlayWindow.rootViewController:nil;
 if(tabs)GSInstallOverlayRootHiddenGuard(tabs);
 BOOL masked=GSSceneShouldMaskNativeTabs(scene,overlayWindow);
 overlayWindow.alpha=masked?0.0:1.0;
 if(tabs){
  tabs.view.hidden=masked;
  if(!masked){[tabs.view setNeedsLayout];[tabs.view layoutIfNeeded];}
 }
}

static void GSRefreshAllScenes(void){
 if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{GSRefreshAllScenes();});return;}
 for(UIScene *scene in UIApplication.sharedApplication.connectedScenes)if([scene isKindOfClass:UIWindowScene.class])GSApplySceneMask((UIWindowScene *)scene);
}

static void GSScheduleVisibilityRefreshes(void){
 GSRefreshAllScenes();
 for(NSNumber *delay in @[@0.05,@0.20,@0.50])dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay.doubleValue*NSEC_PER_SEC)),dispatch_get_main_queue(),^{GSRefreshAllScenes();});
}

static void GSMaskSceneNowForController(id controller){
 UIViewController *viewController=[controller isKindOfClass:UIViewController.class]?controller:nil;
 UIWindowScene *scene=viewController.viewIfLoaded.window.windowScene;if(!scene)return;
 for(UIWindow *window in scene.windows)if(GSIsPhotosGlassOverlayWindow(window))window.alpha=0.0;
}

static void GSSetTabBarHiddenAnimated(id controller,SEL selector,BOOL hidden,BOOL animated){
 if(GSVisibilityStateArmed(controller)){
  GSSetExplicitHidden(controller,hidden);if(hidden)GSMaskSceneNowForController(controller);
 }
 ((void(*)(id,SEL,BOOL,BOOL))GSOriginalSetTabBarHiddenAnimated)(controller,selector,hidden,animated);
 GSScheduleVisibilityRefreshes();
}

static void GSSetTabBarIsHidden(id controller,SEL selector,BOOL hidden){
 if(GSVisibilityStateArmed(controller)){
  GSSetExplicitHidden(controller,hidden);if(hidden)GSMaskSceneNowForController(controller);
 }
 ((void(*)(id,SEL,BOOL))GSOriginalSetTabBarIsHidden)(controller,selector,hidden);
 GSScheduleVisibilityRefreshes();
}

static void GSOverlaySetContentSuppressed(id window,SEL selector,BOOL suppressed){
 BOOL effective=suppressed;
 UIWindowScene *scene=[window isKindOfClass:UIWindow.class]?((UIWindow *)window).windowScene:nil;
 if(scene)effective=GSSceneShouldMaskNativeTabs(scene,(UIWindow *)window);
 ((void(*)(id,SEL,BOOL))GSOriginalOverlaySetContentSuppressed)(window,selector,effective);
 if(scene)dispatch_async(dispatch_get_main_queue(),^{GSApplySceneMask(scene);});
}

static IMP GSHookOwnOrInheritedMethod(Class cls,SEL selector,IMP replacement){
 Method method=class_getInstanceMethod(cls,selector);if(!method)return NULL;
 IMP current=method_getImplementation(method);
 IMP replaced=class_replaceMethod(cls,selector,replacement,method_getTypeEncoding(method));
 return replaced?:current;
}

static void GSInstallVisibilityGuard(void){
 if(GSVisibilityGuardInstalled)return;
 Class cls=NSClassFromString(@"PHSTabBarController");if(!cls)return;
 SEL animatedSelector=NSSelectorFromString(@"setTabBarHidden:animated:");Method animatedMethod=class_getInstanceMethod(cls,animatedSelector);
 if(animatedMethod&&method_getNumberOfArguments(animatedMethod)==4)GSOriginalSetTabBarHiddenAnimated=GSHookOwnOrInheritedMethod(cls,animatedSelector,(IMP)GSSetTabBarHiddenAnimated);
 SEL propertySelector=NSSelectorFromString(@"setTabBarIsHidden:");Method propertyMethod=class_getInstanceMethod(cls,propertySelector);
 if(propertyMethod&&method_getNumberOfArguments(propertyMethod)==3)GSOriginalSetTabBarIsHidden=GSHookOwnOrInheritedMethod(cls,propertySelector,(IMP)GSSetTabBarIsHidden);
 Class overlayClass=NSClassFromString(@"GSPhotosGlassOverlayWindow");SEL suppressedSelector=NSSelectorFromString(@"setContentSuppressed:");Method suppressedMethod=class_getInstanceMethod(overlayClass,suppressedSelector);
 if(suppressedMethod&&method_getNumberOfArguments(suppressedMethod)==3)GSOriginalOverlaySetContentSuppressed=GSHookOwnOrInheritedMethod(overlayClass,suppressedSelector,(IMP)GSOverlaySetContentSuppressed);
 GSVisibilityGuardInstalled=YES;GSScheduleVisibilityRefreshes();
}

__attribute__((constructor)) static void GSLoadPhotosGlassVisibilityGuard(void){
 @autoreleasepool{
  if(![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.google.Photos"]&&![[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleExecutable"]isEqual:@"GooglePhotos"])return;
  NSNotificationCenter *center=NSNotificationCenter.defaultCenter;
  for(NSNotificationName name in @[UIWindowDidBecomeKeyNotification,UIWindowDidResignKeyNotification,UIWindowDidBecomeVisibleNotification,UIWindowDidBecomeHiddenNotification,UIApplicationDidBecomeActiveNotification])
   [center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){(void)note;GSScheduleVisibilityRefreshes();}];
  dispatch_async(dispatch_get_main_queue(),^{GSInstallVisibilityGuard();});
 }
}
