#pragma once
#import <Foundation/Foundation.h>
// Main-thread lifecycle entry points, shared by jailed and jailbreak hosts.
FOUNDATION_EXPORT void GSStartAccountConnection(void);
FOUNDATION_EXPORT void GSResumeAccountConnection(void);
FOUNDATION_EXPORT NSDictionary *GSAccountConnectionSnapshot(void);
