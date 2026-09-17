#import <Foundation/Foundation.h>
@class UIWindow;
@interface UIViewController : NSObject @end
@interface UITableViewController : UIViewController @end
@interface UIActivity : NSObject @end
@interface UIImage : NSObject
+ (instancetype)systemImageNamed:(NSString *)name;
@end
@interface NSIndexPath (GSMenuFixture)
@property(nonatomic,readonly) NSInteger section;
@property(nonatomic,readonly) NSInteger row;
+ (instancetype)indexPathForRow:(NSInteger)row inSection:(NSInteger)section;
@end
