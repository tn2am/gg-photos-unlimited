#import <Foundation/Foundation.h>
// Exposed to Swift through ClangImporter, as Google's ObjC card model is.
@interface GSStorageFixtureData : NSObject <NSSecureCoding>
@property(nonatomic) NSInteger storageState;
@property(nonatomic,copy) NSString *title,*subtitle;
@property(nonatomic) double usedStorage,totalStorage;
@property(nonatomic,copy) void(^cardActionCallback)(void);
@end
NSInteger GSReadStorageFromSwift(const void *object);
BOOL GSReadUnlimitedTitleFromSwift(const void *object);
