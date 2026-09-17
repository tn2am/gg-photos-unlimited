# Google Photos 7.20.2 compatibility audit

The supplied **Google Photos 7.20.2**, build **7.20.738660793**, and **7.92.0** are IPA-audited reference versions. Adapters are now selected per feature from the actual classes, selectors and exact Objective-C signatures, without a version-number gate. Authentication, completion callbacks, storage UI and quality UI can independently use different API generations. Device validation is still required; binary audits and mocked contracts do not establish successful authentication or uploads against Google's servers.

## Input and OS requirements

The supplied IPA contains `GooglePhotos` and `Frameworks/ModuleFramework.framework/ModuleFramework`, both decrypted (`cryptid = 0`), thin arm64 images. Their `LC_BUILD_VERSION` declares **iOS 16.1**, SDK 17.5. Although the top-level Info.plist says `MinimumOSVersion = 10.0`, that does **not** make this binary usable on iOS 10–15. The tweak's own deployment target is separate from the host application's minimum OS.

The main image yielded 6,780 classes / 64,988 instance methods; ModuleFramework yielded 15,623 / 86,308. [The scoped contract manifest](objc/7.20.2-contracts.json) records SHA-256 hashes and the selectors, encodings, and static addresses relevant to this adapter. It is not a full decompilation. The IPA and executable bytes are not distributed in this repository.

## Audited differences

| Integration | 7.20.2 | 7.92.0 |
| --- | --- | --- |
| Native account | `PHSAccountManagerImpl.ssoService` → `SSOService.authorizationForIdentity:scopes:` | `photosSSOService` → `fetcherAuthorizerForAccountID:scopes:` |
| Authorization callback | `authorizeRequest:completionHandler:` (`v32@0:8@16@?24`) | Same ABI |
| Asset completion | `didCompleteWithSuccess:resultantMediaItem:errorCode:` (`v36@0:8B16@20q28`) | `…error:` with object argument (`v36@0:8B16@20@28`) |
| Live Photo completion | `didCompleteWithError:resultantMediaItem:` | Same ABI |
| Unlimited card | Model `storageState`, native UIKit cell title; **no model `title` getter** | Model `storageState` + `title`, including Swift/Bento reads |
| Unlimited localized resource | `OneGoogleStorageCardUnlimitedTitle`, ID **0x79** | Same key, ID **0x81** |
| Backup detail display | `modelForBackedupStatus` → inherited content-model factory | `getBackupStatusModelData` → `PHSOneUpInfoPanelBackupStatusData` |
| Native library refresh | `PHSUserItemsSynchronizer.fetchData` / `fetchDataSoft` | Same ABI |
| Settings/menu and manual action | Existing audited custom-section/action and `backupLocalAssets:` signatures | Same ABI |

### Authentication

`SSOService.authorizationForIdentity:scopes:` at ModuleFramework `0x14a804` uses the identity's user ID and sorted scopes for its authorization cache and constructs `SSOAuthorizationImpl` with `initWithSSOIdentity:scopes:logger:`. The adapter passes the currently viewed account's valid `_ssoIdentity` and `photos.native` scope. Native SSO retains ownership of refresh and Keychain access. Account matching before/after completion, the background-thread wait, timeout, and token redaction remain in place.

**Sign in before injecting.** First open Google Photos without the tweak and complete Google login; then install the tweak or update to the injected IPA while preserving the same app data and signing identity. Injection can cause Google to reject login. An app downgrade may also fail to read newer app data; this change does not provide a database migration or guarantee that a 7.92.0 session survives a downgrade.

### Backup handoff and completion

The same explicit action and native request families provide manual/automatic handoff. In both jailed and jailbreak modes the native request waits for the Go queue and then runs its original fingerprint/server lookup. Success is only observed from native reconciliation; the adapter does not manufacture a successful native media item or write native backup flags.

The legacy base completion at `0x10c3318` constructs `NSError` in `com.google.photos.upload.error.asset` via `0x10ca478` on failure, forwarding the integer error code. The BOOL success argument controls success independently of that integer. Hook blocks and calls therefore use **NSInteger**, not an Objective-C object, for this version. Live Photo keeps its separate object-error callback. Diagnostics also use the correct signature and report the actual host version.

7.20.2 has no audited 7.92.0 Swift `ScottyUploadServiceImpl` class. Its optional probes may be unmatched. The shared `GMUUploadRequest.startFetcher` and `GMUUploadMediaRequest.startCNDEUpload` payload guards remain active. Edited Live Photo data is handed to a native data-upload request in `startEditedBytesUploadWithData:isPhotoUpload:`; this audit does not establish complete locked-folder/edited-media coverage. See [coverage boundaries](../native-routing.md). Both builds install the common request hooks; jailbreak hands media to gotohpd through the existing authenticated import protocol. The shared completion monitor requests native library sync without a settings page. [Diagnostic 7 and the integration fix](backup-routing.md#診断-77202-jailbreak-の欠落と修正).

### Native unlimited display

`PHSMyAccountMenuDataSource.storageCardData` at main `0x10036adc4` assigns native state **2** for unlimited reason 1. `OGLStringResources.stringForID:` at ModuleFramework `0x12d10c` indexes the resource table at `0x6f285b0`; index **0x79** resolves to `OneGoogleStorageCardUnlimitedTitle`. The native UIKit cell already has the relevant layout/state path.

Both adapters now resolve `OGLBundle.oneGoogleResourceBundle` (class method `@16@0:8`; legacy address `0x12d18c`, modern reference address `0x17bedc4`) and load the key `OneGoogleStorageCardUnlimitedTitle` from the `OneGoogle` table, without calling `stringForID:`. This avoids using a stale numeric index on a later release. The legacy adapter requires the cell's exact ABI, changes the display getter, and supplies the native localized title. It never adds the absent model `title` getter. On/off remains available, default on. Missing resources retain the native display. Encoding suppresses display overrides so saved quota/state values stay native. This changes only the card, not the account's actual quota or upload policy.

### Original-quality label and refresh

At main `0x10082c084`, `modelForBackedupStatus` builds the title, quality subtitle, native icon, and action through `contentViewModelWithTitle:subtitle:subtitleContainsHTML:image:`. The adapter overrides this inherited factory **on the details subclass only**, scoped to that controller's backup-status call, with scope restored even on exceptions. It preserves the original factory, title, image, and native action setup.

Only `isBackedUp`, `hasOriginalBytes == Yes (1)`, non-partial backup, and storage policy Standard (1) permit the quality subtitle correction. Unknown/No/Maybe and partial backups retain the native label. The app's normal account-bound synchronizer performs refresh; neither quota counters nor the media database are edited.

## Validation

The macOS CI runs both 7.92.0 and 7.20.2 contracts. Legacy fixtures omit the new SSO factory, new asset-completion selector, new detail-model class, storage title getter, and Swift upload service. They exercise native account switching, silent manual/automatic routing, reconciliation failure without native payload fallback, integer completion preservation, quality evidence checks, account-bound refresh, settings actions, and native unlimited on/off/archive behavior. CI also builds rootless, rootful, and jailed packages and runs the existing UIKit settings smoke test.

Real-device checks still needed on 7.20.2: login-first installation, native account refresh, settings/menu tap, unlimited display on/off after reopening the menu, original JPEG/HEIC/video/Live Photo upload, manual and automatic handoff, completion refresh without relaunch, cancellation/network loss, and upgrade/downgrade behavior. Jailed uploads require the app to remain active; this is not a background-execution entitlement change.

## Automatic API detection

The host executable must be GooglePhotos. Version metadata only informs the `auditedHostVersion` diagnostic field; missing, unfamiliar, older and future version strings do not disable compatible APIs. A matching modern API is preferred; a matching legacy API can be used independently by each feature. Missing or incompatible signatures disable the affected path rather than guessing an argument type. Shared menu and routing hooks retain their own ABI checks.

CI runs both API shapes, mixed completion classes and malformed signatures, and reruns modern and legacy contracts under unrelated version metadata. These are simulated API contracts, not device verification of uninspected app releases. Private API behavior can still change without a signature change.

## Jailbreak daemon transport

Clients first try direct Mach lookup. For lookup errors 1100 / 1102, they request the restricted libSandy profile and retry; authenticated XPC discovery is the final fallback, with a five-second discovery timeout. Discovery uses `XPC_CONNECTION_MACH_SERVICE_PRIVILEGED` because gotohpd is a LaunchDaemon even though it runs as mobile. Diagnostics distinguish lookup, sandbox-profile and discovery failures without recording extension tokens.

The profile permits only Google Photos and Apple Photos and grants two exact services through two Mach extension classes (four grants total). The daemon still independently verifies the client's audit-token-bound signing identity. Its main thread services the Foundation/CFRunLoop; a serial worker handles Mach RPC. [Transport and authorization boundary](../architecture.md#transport-and-storage-boundary) / [device checks](../device-validation.md).
