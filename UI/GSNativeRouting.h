#pragma once
#import <UIKit/UIKit.h>
#import <Photos/Photos.h>
FOUNDATION_EXPORT BOOL GSIsGooglePhotos(void);
FOUNDATION_EXPORT void GSInstallNativeRouting(void);
FOUNDATION_EXPORT BOOL GSNativeRoutingAvailable(void);
FOUNDATION_EXPORT BOOL GSNativeRoutingEnabled(void);
FOUNDATION_EXPORT NSString *GSNativeRoutingAccount(void);
FOUNDATION_EXPORT void GSSetNativeRouting(BOOL enabled, NSString *account);
FOUNDATION_EXPORT NSDictionary *GSNativeRoutingSnapshot(void);
