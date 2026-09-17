#pragma once
#import <Foundation/Foundation.h>
FOUNDATION_EXPORT void GSInstallUploadDiagnostics(void);
FOUNDATION_EXPORT BOOL GSUploadDiagnosticsAvailable(void);
FOUNDATION_EXPORT BOOL GSUploadDiagnosticsEnabled(void);
FOUNDATION_EXPORT void GSSetUploadDiagnostics(BOOL enabled);
FOUNDATION_EXPORT NSDictionary *GSUploadDiagnosticsSnapshot(void);
