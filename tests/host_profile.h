#pragma once
#ifdef GS_TEST_LEGACY
#define GSFixtureVersion (NSProcessInfo.processInfo.environment[@"GS_TEST_PHOTOS_VERSION"]?:@"7.20.2")
#else
#define GSFixtureVersion (NSProcessInfo.processInfo.environment[@"GS_TEST_PHOTOS_VERSION"]?:@"7.92.0")
#endif
