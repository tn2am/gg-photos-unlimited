# Google Photos の標準バックアップ操作を GoToHP へ転送

jailed / rootless / rootful で、対応する純正の手動・自動バックアップ要求を
GoToHP に渡します。IPA の解析基準は **7.20.2 / 7.92.0** で、版番号を固定せず、
各機能が必要とする class / selector / 引数の型を実行時に照合します。
[処理と診断の詳細](analysis/backup-routing.md)。

1. Google Photos を起動し、ログイン中のアカウントへの自動接続を待ちます。
2. プロフィールメニュー → **GoToHP の設定**で画質を選び、
   **手動・自動バックアップを GoToHP へ送る**を有効化して送信先を確認します。
   この切替は既定 OFF です。
3. Google Photos の通常のバックアップボタンを使います。対応する操作は
   GoToHP の画面や毎回の確認を出さずにキューへ送ります。
4. 自動バックアップには Google Photos 本体のバックアップも ON にします。

元のスケジューラーと delegate を維持し、共通の `GMUAssetUploadRequest` /
`GMULivePhotoSingleUploadRequest` で PhotoKit 原本を転送します。動画などの
バックグラウンド要求（`GMUBackgroundAssetUploadRequest`）と、
もう一方の Live Photo 変種（`GMULivePhotoUploadRequest`）も同じく転送します。
該当 class が存在しない版では従来の 2 要求のみが有効になり、起動時の ABI 照合で
可否を決めます。各要求の `asset` は PHAsset 原本を指します。Go の実際の
完了後に純正の fingerprint 照合を再開し、成功を確認します。GoToHP 単独の
アップロードも前景の完了監視で検知し、純正のアカウント別 fetchData による
表示更新を要求します。設定を開いたままにする必要や、毎回の再起動はありません。
通信とサーバー反映に時間がかかる場合はあります。

アカウント不一致・書出し失敗・再照合失敗では純正のデータ送信に戻しません。
Google Photos の DB、バックアップフラグ、成功結果を直接作り替えません。
画質と送信先は GoToHP の設定を使用します。送信先を変更した場合は転送設定を
OFF/ON して再確認してください。新規要求から有効なので、導入・切替前にすでに
始まっていた純正送信は対象外です。

jailed / LiveContainer では Google Photos を前面で開いてください。jailbreak では
原本が daemon のキューに渡るまで開き、その後は認証が利用できる間 daemon が
続行します。Google Photos が終了すると純正の新しい自動要求は作られません。
認証の更新にはホストが必要です。[認証の制約](analysis/native-account.md)。

旧手動 `backupLocalAssets:` の互換処理はソースに残りますが、共通要求の ABI が
不適合なら設定から手動・自動連携を新たに有効化できません。
locked folder・編集専用・共有専用など、任意の全経路の置換は保証しません。
[実機検証項目](device-validation.md)。

## 対応範囲

| 経路 | 現在の扱い |
| --- | --- |
| GMUAssetUploadRequest.start | 手動・自動の PHAsset 原本を GoToHP の永続キューへ転送 |
| GMUBackgroundAssetUploadRequest.start | 動画などの要求を GoToHP へ転送。再照合の finishUpload／エラー終了で後始末 |
| GMULivePhotoSingleUploadRequest.start | 写真・pairedVideo を一組で転送し、純正のサーバー再照合で完了判定 |
| GMULivePhotoUploadRequest.start | もう一方の Live Photo 要求変種を同じく一組で転送 |
| 純正の完了 callback | 旧版の数値 errorCode / 新版の NSError を自動選択。成功結果を捏造しない |
| GMUUploadRequest.startFetcher / startCNDEUpload | 転送有効時・再照合中の native payload fallback を停止 |
| GMUBackgroundAssetUploadRequest.beginUploadMediaRequestWithFingerprint: | background URLSession／Scotty に進む前に native payload fallback を停止 |
| Swift Scotty / statelessUpload | 対応 ABI が存在する場合に payload fallback を停止。7.20.2 では該当 Swift class は未検出 |
| GoToHP の設定から直接送信 | 共通の完了監視が純正 fetchData に表示更新を要求 |
| locked folder / 編集専用 / 共有専用 / 既存 background URLSession | 全経路の移譲を検証できていない。通常の PHAsset バックアップと同等とは扱わない |

Go の completed / mediaKey だけでは、純正側のバックアップ成功を保証しません。

## 診断

GoToHP 設定の **Upload diagnostics** を有効にし、標準操作を試して
**Export diagnostics** を使います。`backupRouting` の intercepted / queued /
nativeReconciled、`photosIntegration` の syncRequested、`completionMonitor` の
syncSignals / uploadSummary を確認できます。

標準経路そのものを調べるときだけ転送を OFF にします。その場合は純正送信となり、
GoToHP の画質 policy は適用されません。診断はトークン・写真・account ID・mediaKey・
HTTP 本文を記録しません。CI は API fixture、Go queue、パッケージ構成を検証しますが、
Google サーバーの再照合や端末での表示時間を証明するものではありません。
