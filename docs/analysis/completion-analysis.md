# Native upload 完了処理の解析

対象は提供 7.92.0 generated framework の下記関数です。Objective-C metadata から IMP を求め、arm64 instruction と selector stub の参照を追跡しました。これは限定した関数の静的解析で、全 call graph や実行ログではありません。

| 関数 | Static VM address | 追跡で確認した参照 |
| --- | --- | --- |
| GMUUploadRequest.commonUploadFetcherDidCompleteWithData:error: | 0x1995e4c | blueprint / proto / editMedia / uploadToken / queueForAccountId: |
| GMUUploadRequest.didCompleteWithSuccess:resultantMediaItem:error: | 0x1a4d1d8 | delegate 通知、requestDidComplete:withSuccess:、delegate / uploadData のクリア |
| GMUAssetUploadRequest.didCompleteWithSuccess:resultantMediaItem:error: | 0x1a2267c | hasMetadata、metadata、dedupInfo、localDedupKey、fingerprints、removeFingerprintForAsset:error: |
| GMUUploadMediaRequest.uploadFetcherDidCompleteWithData:error: | 0x1994830 | asset state、blueprint、editList、setOriginalBytesScottyUploadTokenData:、startCNDEUpload、allUploadsDidCompleteWithData:error: |

## 実装への意味

- native 完了は単なる bool の通知ではありません。delegate と request queue の両方に結果を渡す経路があります。
- asset request の完了経路は metadata と dedup 情報を参照します。gotohp の mediaKey string を `resultantMediaItem` 引数に置くだけでは互換 object になりません。
- transport 完了は native blueprint の後続処理につながります。Scotty の成功と Google Photos の media commit 完了を同一視できません。
- edited/original bytes を別に扱う参照もあるため、PhotoKit の original を一律アップロードするだけでは native 編集 upload と同等とは言えません。

現在の実装では Go の完了結果から native model を捏造せず、元の fingerprint / サーバー照合を再開し、純正の delegate に結果を処理させます。上記の静的解析だけでは native result の全 schema、各 branch の実行条件、全 upload 経路の網羅は確定できません。

## 次に必要な証拠

[診断手順](../native-routing.md)で native completion の resultClass、通過する binding、failure 有無を取得します。そのログだけで全互換性を証明できるわけではありませんが、型と経路を絞る根拠になります。認証情報やサーバー本文を添付する必要はありません。
