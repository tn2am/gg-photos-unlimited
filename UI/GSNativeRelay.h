#pragma once
#import <Foundation/Foundation.h>
// Jailbreak only. Connect on a worker; refresh on main. Never returns a token.
FOUNDATION_EXPORT BOOL GSConnectDaemonAccount(NSDictionary *account, NSError **error);
FOUNDATION_EXPORT void GSRefreshDaemonAccount(void);
FOUNDATION_EXPORT NSDictionary *GSNativeRelaySnapshot(void);
