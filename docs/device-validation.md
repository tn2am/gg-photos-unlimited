# Device validation gate

No jailbroken iPhone or Google test credential was available during implementation. This checklist records remaining runtime gates, not passed tests.

1. Install a package matching the jailbreak bootstrap; record iPhone model, iOS, injection framework, root scheme, and Google Photos version. The supplied 7.92.0 IPA requires iOS 18.0; it cannot validate iOS 15/16.
2. Run `/var/jb/usr/libexec/gotohpd --self-test` for rootless, `/usr/libexec/gotohpd --self-test` for rootful. Expect exit 0 (C → Go → C). Then check `launchctl print system/dev.tqmane.gunshot` and the in-app GoToHP connection status. Never launch a second real daemon manually.
3. Verify unauthorized processes cannot ping/import, account mutations from Photos fail, malformed/complex Mach messages are rejected, and missing identity SPI fails closed. Verify direct Mach lookup or the restricted libSandy profile plus authenticated XPC discovery on each jailbreak bootstrap. Test missing/restricted libSandy and unavailable/restarted daemon diagnostics.
4. Sign into a test account in unmodified Google Photos first; launch Google Photos after installing the tweak and verify native connection before opening any GoToHP screen, without token input. Confirm no iOS Settings entry remains after upgrading. Check no bearer appears in files, logs or diagnostics; metadata files stay 0600 / directory 0700. Test sign-out, account switching, foreground renewal and a daemon restart. Native pending jobs must wait for fresh authorization without consuming retries.
5. JPEG, PNG, HEIC, RAW, MP4, MOV, 4K, HDR: upload one original; inspect remote pixel size/codec, capture date/timezone, filename, EXIF/orientation/GPS. PhotoKit export does not reencode, but server preservation must still be checked.
6. Live Photo: HEIC+MOV and JPEG+MOV; confirm the remote library shows **one playable asset**. Validate identifier, still-image-time, capture date, rotation and location. This build exports original resources, not the edited representation. Mismatched pair must fail, not become two successful entries.
7. Queue 100+ mixed assets, a 2,000-item album and 60 HEIC/HEIF originals using **Uploads → Choose album**. Test full/limited permissions, an unreadable original, stop/reselect and the 100-item normal picker. Preparation may need iCloud download and an open app. Kill Google Photos after Queued; verify jailbreak daemon progress continues while authorized (jailed uploads resume on reopening). Restart gotohpd, respring SpringBoard, disable network, switch Wi-Fi to cellular, unplug charger, pause/cancel, retry failed jobs. Check commit interruption stays uncertain instead of claiming cancelled/completed. See [bulk import diagnostics](bulk-import.md).
8. Duplicate files: same account/policy should return existing queued/completed ID; alternate accounts/policies are separate. Simulate remote hash lookup failure and lost commit response.
9. Original / Saver / Quota: compare account storage before and after with a fresh test asset. A media key is not proof of zero quota usage. Do not mark unlimited behavior verified without server/account-side evidence.
10. Monitor RAM, CPU, thermal and storage under large video + 4 concurrent jobs. Audit token SPI, arm64 daemon on arm64e hardware, jailbreak TLS trust and respring behavior all require real-device evidence.

Current limits: no byte-offset remote resume; no GoToHP-managed Keychain store; no arbitrary device-profile editor; no automatic assertion of quota savings. Staging copies remain for failed jobs until cancel; cancel removes staging, never remote photos. Uninstall keeps private account/queue data for deliberate recovery/removal.

## Native backup handoff

Use the [backup-routing controls and diagnostics](native-routing.md). These checks apply separately to jailed, rootless and rootful:

- OFF preserves standard manual/automatic backup. ON hands single, multiple and automatic requests to GoToHP once without opening its settings.
- Both native handoff and direct GoToHP uploads refresh the native display after completion with settings closed. Check real data, quality and quota separately as above.
- Account mismatch, expired authorization, PhotoKit refusal, disk full or failed reconciliation must not resend media through the native payload path.
- Jailed requires foreground execution. After a jailbreak import reaches the daemon, closing the host must retain the queue; reopening must renew authorization and synchronize the display.
