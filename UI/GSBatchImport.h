#pragma once
#import <Foundation/Foundation.h>

// Providers run on the import worker, one item at a time. nil means inaccessible.
typedef id (^GSBatchItemProvider)(NSUInteger index);
typedef void (^GSBatchProgress)(NSDictionary *snapshot);
FOUNDATION_EXPORT BOOL GSStartBatchImport(NSUInteger count, NSString *source, BOOL assets,
 GSBatchItemProvider provider, NSString *account, NSString *identity,
 GSBatchProgress progress, GSBatchProgress completion);
FOUNDATION_EXPORT void GSStopBatchImport(BOOL backgroundExpired);
FOUNDATION_EXPORT NSDictionary *GSBatchImportSnapshot(void);
// Resolve a bounded page of identifiers off main; never load itemProvider media.
FOUNDATION_EXPORT GSBatchItemProvider GSPhotoIdentifierProvider(NSArray *identifiers);

void GSAutoScanIfEnabled(void);
