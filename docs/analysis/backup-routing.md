# Google Photos の手動・自動バックアップ連携（jailed / jailbreak）

## 実機診断と変更理由

追加診断では GMUAssetUploadRequest.start → GMUUploadRequest.startFetcher →
GMUUploadMediaRequest.uploadFetcherDidCompleteWithData:error: → native completion
が観測されました。旧フックは PHSBackupActionBehaviorImpl / PHSActionsGridModel
の backupLocalAssets: だけで、別の手動操作と自動バックアップを捕まえていません。

jailed / rootless / rootful ともアプリ起動時に GMUAssetUploadRequest.start と
GMULivePhotoSingleUploadRequest.start を捕まえます。動画などのバックグラウンド
要求（GMUBackgroundAssetUploadRequest.start）と、もう一方の
Live Photo 変種（GMULivePhotoUploadRequest.start）も同じ PHAsset 原本の転送と
純正の fingerprint 再照合で扱います。該当 class が存在しない版では従来の 2 要求
のみが有効になり、起動時の ABI 照合で可否を決めます。各要求の asset は、両 IPA の
ivar メタデータで PHAsset と確認済みです。credentials は
GMUUploadRequestCredentials → PHSBaseWithAccountID.accountID を通して、現在の
PHSAccountManagerImpl.viewingAccount.accountID と比較します。

## 処理

1. Google Photos の手動・自動スケジューラーが PHAsset のアップロード要求を作成。
2. 連携が有効なら、送信先と現在のアカウントを照合し、PhotoKit の原本を GoToHP
   の永続キューへ取り込む。元の start はここでは実行しない。
3. Go のジョブが実際に completed となり、mediaKey が存在するまで待機。
4. 元の start を再開し、Google の既存 fingerprint 確認でサーバーの実データを
   照合する。ネイティブの成功結果・PhotosMCMediaItem は捏造しない。
5. native の startFetcher / startCNDEUpload / Scotty、または background の
   beginUploadMediaRequestWithFingerprint: へ進んだ場合は失敗として
   止める。GoToHP の失敗を純正アップロードへ自動フォールバックしない。

background の照合成功は finishUpload、早期エラーは 7.20.2 の
handleErrorWithCode:／7.92.0 の handleError: で終了するため、各経路で再照合状態を
解除します。blueprintDidComplete:mediaItem:error: は両版とも NSError 型です。

fingerprintDidComplete:error: の逆アセンブルでは
`enqueueRequestWithCredentials:fingerprint:completion:`、
`uploadRequest:didDiscoverFingerprintExists:mediaKey:`、
`existenceCheckDidFailWithFingerprint:` が確認でき、最後の経路が実データ送信へ
つながります。再照合失敗時には純正側にバックアップエラーが残り得ます。
Go 側の成功と純正側の再照合成功は診断で別々に数えます。既存 fingerprint の成功分岐では success=YES、resultantMediaItem=nil、error=nil が渡されます（framework 内 0x1a218a4 / 0x1a219ac）。mediaKey は別の didDiscoverFingerprintExists callback で通知されるため、nil の media item を再照合失敗とは扱いません。

## 使い方

- GoToHP の「画質」を「オリジナル画質」にする。
- 「手動・自動バックアップを GoToHP へ送る」を有効にする。
- 有効化後の純正バックアップ操作では GoToHP 画面・確認ダイアログを開かず、保存済みの送信先と画質で処理する。
- 自動バックアップには Google Photos 本体のバックアップもオンにする。
- この変更は有効化後に開始した要求が対象。既に送信中の純正要求を取り消す
  ものではないので、切替後にアプリを起動し直して検証する。
- jailed / LiveContainer ではアプリが停止・終了すると独立 daemon としては
  動作しない。Google Photos を前面で開くと永続キューを再開する。
- rootful/rootless も同じ共通要求置換を使用する。原本がキューへ渡るまでアプリを開く。その後の送信は daemon が担当し、認証が利用できる間はホスト終了後も続行する。

## オリジナル画質

PhotoKit の photo / video / pairedVideo の原本リソースを使用します。
Go commit の field 7=3、初代 Pixel XL profile が original、field 7=1 が saver です。
通常 quota モードも field 7=3、Pixel 8 profile を使用します。
旧 CommitUpload スキーマでは field 7 を Quality と呼んでいますが、7.92.0 の
正式クライアント側の名称は storagePolicy です。field 10 の uploadQuality=1 は
OriginalBytes を意味します。1 を Storage Saver と解釈して変更してはいけません。
テストでは実際にシリアライズした protobuf を HTTP テストサーバーで読み取ります。

original は ForceUpload を指定します。旧経路は同じハッシュが既にサーバーに
あれば画質を確認せず終了していたため、以前の saver の結果を original の
成功として扱うおそれがありました。ローカルキュー内の重複防止は維持します。ただし旧版の original 完了記録は画質未検証のため、新しい original 要求を省略する根拠にはしません。新しい原本送信を実行したジョブには originalPolicy=1 を保存します。
Google 側が既存メディアの画質を更新するか、quota をどう計上するかは別の
実機検証事項です。圧縮済みファイルから失われた品質を復元する機能ではありません。

## 診断・検証

`backupRouting` に intercepted / queued / reconciling / nativeReconciled /
reconcileFailed / nativePayloadBlocked / accountMismatch / failed / unsupported
の件数を記録します。トークン・メール・asset ID・mediaKey は出力しません。

## 追加診断 4 と表示・同期の修正

利用者が Web の同一写真を確認し、オリジナル画質と報告しました。今回の症状は
送信 profile の違いではありません。[表示と同期の解析](original-quality-display.md)
に upstream 2 実装・enum・iOS の表示判定を記録しています。

旧 backupLocalAssets: フックは GoToHP 画面へ直接移譲して共通要求を迂回し、
診断 4 の events / backupRouting 件数が空になっていました。両方式で共通要求
フックが利用できる場合は純正 UI の要求作成を通し、その要求で GoToHP へ移譲します。
これにより純正の delegate と完了時の fingerprint 再照合が維持されます。

GoToHP 単独のアップロードを含め、永続化された完了 revision を前景で監視し、
現在のアカウントの既存 PHSUserItemsSynchronizer.fetchData に差分同期を要求します。
設定画面を閉じても動作します。アプリがまだ同期オブジェクトを公開していない場合は
次の純正 fetchData / fetchDataSoft まで保留します。要求の成功とサーバーからの反映は
同義ではなく、通信と Google の反映待ちは発生します。

## 画面なしの手動操作

旧互換経路（共通要求フックが使えない場合の手動 UI）も、
GoToHP 画面を生成する処理を廃止しました。PhotoKit の原本を書き出し、保存済みの
アカウント・画質で永続キューへ直接追加します。ファイル処理は専用の直列キューで
行い、画面を塞ぎません。通常の共通要求では純正の進捗・完了経路を維持します。

アカウント不一致、未対応/ロック済み写真、書出し失敗は純正送信に切り替えません。
取込前の失敗は GoToHP 設定画面の状態と診断 manualRouting.lastError に表示し、
取込後のアップロード結果は永続キューの履歴で確認します。診断の actions / queued /
failed は互換経路の累計で、個人情報や原本の内容を含みません。

連携を有効にする時の送信先確認と、ユーザーが自分で開く GoToHP 設定・アップロード
画面は維持します。毎回の純正バックアップ操作から画面を開く処理はありません。

ネイティブ fixture は UI を経由しない自動要求も同じ start で検証し、
アカウント不一致・二重 start・キャンセル・原本の画質指定・Go 完了後の再照合・
再照合時の native payload ブロックを確認します。実 Google サーバーでの完了、
HEIC / MOV / Live Photo のサーバー再照合と画質表示は端末での確認が必要です。

## 診断 7：7.20.2 jailbreak の欠落と修正

診断 7(1) は `appVersion=7.20.2`、IPC 接続成功、native authorization の
`refreshed` を示しています。一方、手動取込の件数は 0、純正の
`GMUAssetUploadRequest.start → startFetcher → uploadFetcherDidCompleteWithData:error:`
が観測され、共通要求の `backupRouting` と `photosIntegration` 自体がありません。
PR #8/#9 の処理が jailed のソース一覧と起動経路だけに入り、jailbreak には
組み込まれていなかったことと一致します。

rootless/rootful にも `GSBackupRequests` と `GSPhotosIntegration` を組み込み、
起動時の `GSStartBackupIntegration` を両方式で共有します。新しいバージョン
制限は設けず、7.20.2 の数値 errorCode と 7.92.0 の NSError completion を
クラス・selector・ABI で自動選択します。[両 IPA の監査](google-photos-7.20.2.md)。

- 共通要求フックがある場合、手動 UI は純正スケジューラーを通し、GoToHP の
  設定画面を生成しません。自動スケジューラーも同じ start で移譲します。
- jailbreak の PhotoKit 取込は daemon の online / Wi-Fi / charging / paused を
  読み、前景で条件を満たしてから実行します。原本書出し後もアカウントを再照合します。
  条件の変更権限は daemon のままです。
- native request がバックグラウンド移行でキャンセルされても、取り込み済みの
  daemon ジョブは維持します。前景でのキャンセルは Go ジョブにも伝えます。
- 共通の `GSUploadMonitor` は前景で約 3 秒ごとに永続 completionRevision を
  監視します。単独の GoToHP アップロードも対象です。新しい完了を検知すると
  現在のアカウントの純正 fetchData を要求します（約 1 秒の集約待ち）。
- 設定画面を開かず起動直後から監視し、背景での完了も前景復帰で読み直します。
  オフライン・IPC 失敗・別アカウントの古い応答で revision を消費しません。
  revision 0 を完了と扱わず、同じ前景セッションの同じ revision は集約します。
- 診断は両方式で backupRouting / photosIntegration / completionMonitor を出力。
  uploadSummary.conditions は状態の bool 値だけで、アカウントや token は含みません。

純正の fingerprint 再照合と fetchData が実際のバックアップ表示を更新します。
GoToHP の completed だけで純正の成功フラグを書き換えません。ネットワークや
サーバー反映に時間がかかる場合があり、実端末での表示更新時間は別途確認が必要です。

## 診断 8：両版のキュー追加前失敗（ID 型の混同）

PR #18 の最初の修正版について、7.20.2 jailbreak / 7.92.0 jailed の両方で
純正の手動・自動バックアップが失敗する報告がありました。

| 診断 | 観測 |
| --- | --- |
| 7.20.2 / 診断 8 | intercepted=7、failed=6、accountMismatch=1、queued なし。daemon 接続・認証更新は成功 |
| 7.92.0 / 診断 2 (2) | intercepted=5、failed=5、queued なし。認証済み、前景・Wi-Fi・online=true |
| 両版の completionMonitor | reachable=true でも uploadSummary がなく、syncSignals=0 |
| 7.92.0 の embedded runtime | completionRevision=4 の summary が存在。キューの取得自体は成功 |

原因は、追加した途中のアカウント照合と完了監視で、SSO の文字列 userID を
`GSNativeAccountMatches` に渡したことです。この関数は純正の
`viewingAccount.accountID`（`GIPGaiaAccountID` オブジェクト）と比較するため、
同じアカウントでも文字列とは一致しません。取込前に失敗し、完了監視でも
通信に成功した応答をアカウント不一致として捨てていました。

両 IPA には `GIPGaiaAccountID` の `initWithGaiaID:`、`gaiaID`、`identifier`、
`isEqual:`、`copyWithZone:` があり、単なる NSString とは異なるオブジェクトです。
SSO の userID と native accountID は用途ごとに分けて照合します。

| 入力 | 使用する比較 |
| --- | --- |
| credentials.accountID / 同期オブジェクトの accountID | GSNativeAccountMatches：純正オブジェクト同士の isEqual: |
| summary.identifier / 保存した SSO userID | GSNativeIdentityMatches：有効なログイン中 SSO userID の文字列比較 |

修正では型の変換やアカウント判定の省略を行わず、比較する ID の種類を揃えます。
SSO のサインアウト・期限切れ・アカウント変更、純正要求のアカウント不一致は
引き続き停止します。監視の `identityMatched` は bool だけ、転送の
`authorizationChanged` は件数だけを追加し、ID や token を診断へ出しません。

従来の転送・監視テストは accountID と SSO userID を同じ文字列で代用し、
この回帰を見逃しました。現在は別型の native accountID オブジェクトを用い、
実際の `GSNativeAccount.m` をリンクして、手動／自動のキュー追加・再照合・
監視・アカウント切替を検証します。純正 API の差分は従来どおり機能ごとに検出し、
7.20.2 の整数 completion と新版の NSError completion を維持します。
