#pragma once
#import <Foundation/Foundation.h>

FOUNDATION_EXPORT void GSInstallPhotosGlass(void);
FOUNDATION_EXPORT BOOL GSPhotosGlassAvailable(void);
FOUNDATION_EXPORT BOOL GSPhotosGlassEnabled(void);
FOUNDATION_EXPORT void GSSetPhotosGlass(BOOL enabled);
FOUNDATION_EXPORT NSDictionary *GSPhotosGlassSnapshot(void);
