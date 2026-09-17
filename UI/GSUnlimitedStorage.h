#import <Foundation/Foundation.h>

void GSInstallUnlimitedStorage(void);
BOOL GSUnlimitedStorageAvailable(void);
BOOL GSUnlimitedStorageEnabled(void);
void GSSetUnlimitedStorage(BOOL enabled);
NSDictionary *GSUnlimitedStorageSnapshot(void);
