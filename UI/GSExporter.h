#import <Foundation/Foundation.h>
#import <Photos/Photos.h>
// These methods run on a worker queue. UI callbacks remain on the main queue.
NSArray<NSURL *> *GSExportAsset(PHAsset *asset, NSURL *directory, NSError **error);
NSString *GSImportFiles(NSArray<NSURL *> *files, NSString *account, NSString *quality, NSDate *date, NSError **error);
