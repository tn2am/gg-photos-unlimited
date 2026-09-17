#import "../Shared/GSLocalization.h"
#include <assert.h>
int main(void){@autoreleasepool{
 assert([GSLanguageForPreferences(@[@"ja-JP"])isEqual:@"ja"]);
 assert([GSLanguageForPreferences(@[@"en_GB",@"ja"])isEqual:@"en"]);
 assert([GSLanguageForPreferences(@[@"fr-FR",@"ja"])isEqual:@"ja"]);
 assert([GSLanguageForPreferences(@[@"fr"])isEqual:@"en"]);
 assert([GSLanguageForPreferences(@[])isEqual:@"en"]);
 GSSetLanguage(@"ja");assert([GSL(@"Quality")isEqual:@"画質"]);
 assert(([[NSString stringWithFormat:GSL(@"Upload history (%lu)"),3UL]isEqual:@"アップロード履歴（3件）"]));
 GSSetLanguage(@"en");assert([GSL(@"Quality")isEqual:@"Quality"]);
 assert(([[NSString stringWithFormat:GSL(@"Upload history (%lu)"),3UL]isEqual:@"Upload history (3)"]));
 assert([GSLocalizedStatus(@"認証確認済み · アップロード可能",@"ja")isEqual:@"Authenticated · Ready to upload"]);
 assert([GSL(@"unknown future key")isEqual:@"unknown future key"]);
 GSSetLanguage(@"invalid");assert([GSLanguageOverride()isEqual:@"system"]);
 GSSetLanguage(@"ja");GSSetLanguage(@"system");assert([GSLanguageOverride()isEqual:@"system"]);
 NSLog(@"PASS Japanese, English, regional and unsupported locales, override, reset, format strings and missing-key fallback");
 return 0;
}}
