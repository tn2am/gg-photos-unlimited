#pragma once
#import <Foundation/Foundation.h>
FOUNDATION_EXPORT void GSInstallBackupRequests(void);
FOUNDATION_EXPORT BOOL GSBackupRequestsAvailable(void);
FOUNDATION_EXPORT NSDictionary *GSBackupRequestsSnapshot(void);
