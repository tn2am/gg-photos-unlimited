# Implementation notes

## Upstream pin and call graph

Pinned commit: `0637c745dc590d74766b24eac80d689d2248e766` in [xob0t/gotohp](https://github.com/xob0t/gotohp/tree/0637c745dc590d74766b24eac80d689d2248e766).

Ordinary file: `GunshotUpload → ClassifyUploadWork → uploadWorkItem → uploadSingleFile → CalculateSHA1 → FindRemoteMediaByHash → GetUploadToken → UploadFileWithProgress → ParseScottyFinalizeToken → CommitUpload → commitSerialized → doCommitRequest`.

Live Photo: `ClassifyUploadWork` uses Apple image content identifier / QuickTime identifier and still-image-time metadata. One work item carries photo + video. `uploadLivePhotoWithCallback` uploads components, builds the linked create request, and commits one asset. Pairing failures are explicit; two arbitrary same-stem files are not silently treated as a Live Photo.

Authentication: `AddGoogleAccountWithProxy → exchangeEmbeddedSetupToken → validateGooglePhotosCredential → upsertCredential`. Raw credential import validates required fields and Google authentication before upsert. Imported credentials are URL query strings containing Android ID, account email, token, client signature, scope, language, and optional token-binding material. Account summaries exclude those secrets.

The projection excludes Wails files and desktop config migration tests; replaces configmanager with an iOS JSON store; reuses upstream Preferences definitions/setters only for upstream test compatibility. Two upstream persistence assertions are translated from YAML to JSON. Android ADB/executable discovery and modernc SQLite are absent. Native queue persistence does not need SQLite.

Small explicit adaptations, checked against the pinned source:

1. Initialize a nil TLSClientConfig before upstream dereferences it; never disable certificate validation, including proxy paths.
2. Set a six-hour per-request ceiling for requests lacking upstream context.
3. Fail closed on an ordinary remote duplicate-check error.
4. Facade supplies the job cancellation context to all API transport requests and accepts exactly one classified work item. For two inputs that item must be a Live Photo.

The submodule is immutable during builds. Script string anchors intentionally fail when upstream moves relevant code. Go build tests detect API drift. A projection build does not automatically prove the new upstream still implements the intended API policy.

## Transport and storage boundary

Jailbreak clients use direct Mach lookup and, when needed, a restricted libSandy profile plus authenticated XPC discovery. `Shared/GSXPC.h` supplies C ABI declarations (not an implementation) for SDKs without XPC headers, with explicit object ownership. The macOS discovery fixtures exercise these declarations against libxpc.

Only Photos and Google Photos with the expected signing identifiers and executable locations are accepted, using the kernel Mach audit trailer. The signing identifier is derived from an audit-token-bound SecTask; the supplementary path check uses the token PID. PID recycling cannot substitute the signing identity. IPC fails closed if Security SPI is unavailable.

Messages are simple Mach messages (no port/OOL descriptors), with a fixed maximum buffer and validated length. JSON has no filesystem path operation and cannot provide its own role. Only the audit-verified Google Photos process can mutate accounts and options over IPC for the in-app settings page. The internal settings role remains for the jailed adapter; the daemon never grants that role to a client. Approved Photos clients can begin/append/seal media jobs. Daemon-only conditions updates never arrive via a client-supplied role.

Each import reserves daemon-created random ID and explicit filename/size pairs; offset-checked 32 KiB chunks populate private files. Content hashes are accumulated while chunks arrive, so sealing a large video does not reread the file under the queue lock. Seal verifies sizes and fsyncs files before publishing a pending job. Queue state is fsynced and atomically replaced before scheduling. A write failure stops scheduling until restart; corrupt state fails initialization rather than silently resetting history. Received tokens are not persisted in queue state.

The queue snapshots account and quality. Upload execution uses independent API clients for concurrency. Phase transitions are durable; per-byte progress is in-memory to avoid flash churn. On restart an incomplete import is cancelled, active upload returns to pending, and an uncertain commit becomes a failed job requiring manual review/retry. Network retries restart at byte zero. Remote hash checks reduce duplicate risk but cannot implement an exactly-once transaction with Google.

Staging is private to the mobile daemon. No `/var/jb` hardcoding in user data. The package-stage script expands Theos's package prefix only for executables, LaunchDaemons and the libSandy profile. Rootless and rootful must not be installed simultaneously.

## Native account authorization

On application launch, both builds wait for the signed-in identity and automatically obtain a `photos.native` bearer from the existing SSO authorizer. No GoToHP screen is needed. Foreground activation rechecks authentication, with in-flight coalescing and bounded retries. Jailed calls that provider directly; jailbreak forwards the bearer through the existing audit-authorized Mach service using `account_native` for connection and `native_bearer` for renewal. Only Google Photos may submit or clear a native bearer. The daemon validates a new binding at the Photos endpoint before persisting email/native ID. Access tokens live only in memory and are never part of account summaries, state or diagnostics.

The host serializes reconnect and renewal, refreshes every 60 seconds while scheduled, and refreshes on foreground activation. The daemon enforces a five-minute local retention cap; this is not Google's expiry guarantee. New work waits without spending retries when a native binding lacks a bearer, including after daemon restart. An interrupted commit still requires review. Closing or suspending the app prevents indefinite SSO refresh; reopening it replenishes authorization. Queue account bindings are preserved, and a bearer for another identity is never used.

Settings live inside Google Photos. The jailbreak package no longer builds/registers the Preferences bundle, depends on PreferenceLoader, or authorizes the Settings process to reach the daemon.

## IPA inspection

Provided input: `com.google.photos-7.92.0-eeveedecrypter.ipa`.

Read-only inspection of the main app Info.plist:

| Field | Value |
| --- | --- |
| CFBundleIdentifier | com.google.photos |
| CFBundleExecutable | GooglePhotos |
| CFBundleShortVersionString | 7.92.0 |
| MinimumOSVersion | 18.0 |
| NSPhotoLibraryUsageDescription | Present |

The initial integration used UIKit and public PhotoKit/PHPicker. Subsequent work added version/ABI-checked private manual-backup hooks and passive uploader diagnostics. The [application analysis index](analysis/index.md) links the complete extracted instance-method metadata, selected static call-path findings and unverified areas. No IPA executable or raw disassembly is distributed. Actual appearance and runtime compatibility still require device checks.

Jailed builds replace the Mach client/daemon with an in-process adapter; see [jailed.md](jailed.md). Shared API-detected native manual/automatic backup routing and the host completion monitor are documented in [native-routing.md](native-routing.md).
