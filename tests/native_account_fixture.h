#pragma once
#import <Foundation/Foundation.h>
#import "../UI/GSNativeAccount.h"
#include <assert.h>

// Both audited IPAs use an opaque GIPGaiaAccountID value in native requests
// and synchronizers; SSOIdentity.userID is a separate NSString. Keep this
// representation boundary while linking the real GSNativeAccount bridge.
@interface GIPGaiaAccountID : NSObject <NSCopying>
@property(nonatomic,copy,readonly) NSString *gaiaID;
- (instancetype)initWithGaiaID:(NSString *)gaiaID;
@end
@implementation GIPGaiaAccountID
- (instancetype)initWithGaiaID:(NSString *)gaiaID{if((self=[super init]))_gaiaID=[gaiaID copy];return self;}
- (id)identifier{return self.gaiaID;}
- (BOOL)isEqual:(id)other{return [other isKindOfClass:GIPGaiaAccountID.class]&&[self.gaiaID isEqual:[other gaiaID]];}
- (NSUInteger)hash{return self.gaiaID.hash;}
- (id)copyWithZone:(NSZone *)zone{return self;}
@end
@protocol SSOIdentity <NSObject> @end
@interface GSFixtureIdentity : NSObject <SSOIdentity>
@property(nonatomic) _Bool hasValidAuth;
@property(nonatomic,copy) NSString *userID;
@property(nonatomic,copy) NSString *userEmail;
@end
@implementation GSFixtureIdentity @end
@interface PHSAccount : NSObject {
@public id<SSOIdentity> _ssoIdentity;
}
@property(nonatomic,strong) GIPGaiaAccountID *accountID;
@end
@implementation PHSAccount @end
@interface PHSAccountManagerImpl : NSObject
@property(nonatomic,strong) PHSAccount *viewingAccount;
@end
@implementation PHSAccountManagerImpl @end

static PHSAccountManagerImpl *GSFixtureAccountManager;
static PHSAccount *GSFixtureMakeAccount(NSString *userID,NSString *email){
 GSFixtureIdentity *identity=[GSFixtureIdentity new];identity.userID=userID;identity.userEmail=email;identity.hasValidAuth=YES;
 PHSAccount *account=[PHSAccount new];account->_ssoIdentity=identity;
 account.accountID=[[GIPGaiaAccountID alloc]initWithGaiaID:userID];return account;
}
static void GSFixtureSelectAccount(PHSAccount *account){
 assert(NSThread.isMainThread);GSInstallNativeAccount();
 if(!GSFixtureAccountManager)GSFixtureAccountManager=[PHSAccountManagerImpl new];
 GSFixtureAccountManager.viewingAccount=account;
 assert([GSFixtureAccountManager viewingAccount]==account); // Real capture hook.
}
