# Google Photos のログイン中アカウントとメニュー

対象: Google Photos 7.20.2 / 7.92.0を解析基準とするAPI自動検出。jailed / Sideloadly / LiveContainer、およびrootless / rootful。

## 実機で報告された事象

ユーザーの同一 iPhone では Safari と注入なしの Google Photos でログインでき、Sideloadly の `Inject dylibs/frameworks` を有効にすると Google の認証画面が「安全性を確認できなかった」と拒否した。注入なしでログインした後、tweak を追加すると起動できた。

この比較は注入に伴う変更が関係することを示すが、GoToHP の特定フックと Sideloadly が追加するコードのどちらが原因かは未確定。今回の変更は Google の安全性判定を回避するものではない。既存のログインを保持して更新し、ログイン済みアプリを削除しない。

## メニュー

`PHSMyAccountMenuDataSource` の以下の既存カスタム項目 API に、1 セクション・1 行の「GoToHP の設定」を追加する。

| Selector | Encoding |
|---|---|
| numberOfCustomSectionsForAccountMenuViewController: | Q24@0:8@16 |
| accountMenuViewController:numberOfCustomItemsInSectionAtIndex: | Q32@0:8@16Q24 |
| accountMenuViewController:customItemAtIndexPath: | @32@0:8@16@24 |
| accountMenuViewController:performActionAtIndexPath: | v32@0:8@16@24 |

`OGLAccountMenuCustomItem.initWithTitle:icon:itemType:` の type=1 は、既存カスタムアクションの生成箇所 `0x100c0ca10` で確認した。元の項目とクリックは元実装へ渡す。全 ABI を確認してからまとめてフックする。Google Photos の UIWindow 上のフローティングボタンは削除し、jailed では UIWindow のフック自体を廃止した。設定はアカウントメニューのレイアウトに参加し、下部ナビゲーションに重ならない。

カスタムセクションと共通の設定・ヘルプ行の順序は Google Photos が決定するため、スクリーンショットで希望された「ヘルプの直下」と完全に同じ順序になるかは実機確認が必要。座標で強制配置しない。

## 認証経路

1. `PHSAccountManagerImpl.viewingAccount` の戻り値を変えず、既存 manager を weak 参照する。
2. `PHSAccount._ssoIdentity` の型を検証し、`hasValidAuth`、`userID`、`userEmail` から現在のアカウントのメタデータを取得する。
3. Google Photosを起動してログイン情報が利用可能になると、jailed / jailbreakとも `account_native` でこのアカウントを自動接続する。GoToHP画面を開く必要はない。入力欄にトークンを貼り付ける必要はない。
4. Go core の `Api.BearerToken` は、native binding に対して C ABI provider を呼ぶ。
5. `photosSSOService.fetcherAuthorizerForAccountID:scopes:` から `photos.native` scope の既存 SSO authorizer を取得し、`authorizeRequest:completionHandler:` に Google Photos の HTTPS URL のリクエストを渡す。このリクエスト自体は送信しない。
6. native authorizer が更新した Authorization ヘッダーから bearer を受け取り、gotohp の API 呼び出しに使う。アカウント接続時は既存のリモート hash lookup により API が受け付けることを検証してから binding を保存する。

`GSNativeAccountSummary().identifier` は SSO の userID 文字列で、純正の `accountID` オブジェクトとは別型です。非同期処理前後の SSO 確認には `GSNativeIdentityMatches`、要求と同期オブジェクトの accountID 確認には `GSNativeAccountMatches` を使用します。[両版の転送回帰と修正](backup-routing.md#診断-8両版のキュー追加前失敗id-型の混同)。

永続化するのは email と `gunshot_native_id` のみ。access token、refresh token、Cookie、Keychain の内容はファイルや診断ログに保存しない。Android master token への変換・ログインセッション全件抽出・認証 URL の書き換えは行わない。

トークン取得前後で現在の account ID とログイン状態を確認する。アカウント切り替え・サインアウト時には以前のキューを別のアカウントに送らず失敗させる。元のアカウントへ戻して GoToHP を開き、失敗したジョブを retry する。SSO はメインスレッドで呼び、Go の worker は最大 30 秒待つ。メインスレッドを待機させない。native token を得られなくても Android 認証へフォールバックしない。

## 制約と検証

- jailbreak版は下記の認証リレーを使用する。Google Photosを閉じた後の認証更新には制限がある。
- Google Photos の内部 ABI と iOS token の API 互換性に依存する。実機の接続・upload・quota の確認前に成功を保証しない。
- Go tests: アカウント識別子、都度の provider 呼び出し、provider 不在、エラーの秘匿、ヘッダー改行拒否、従来 credential との分離。
- macOS native fixture: 既存 manager の取得、メインスレッド待機拒否、SSO callback、異なるアカウント、サインアウト、取得途中のアカウント切替。
- 実機: メニュー表示・位置・既存項目、ログイン済みアカウントの自動接続、JPEG 1 枚、期限切れ後の更新、再起動、アカウント切替と retry を確認する。

## 接続表示と runtime 診断（2026-09-12）

`ネットワーク接続を待っています` は Google のログイン拒否ではなく、
キューの `online` が false の場合にも出ていた表示です。旧 jailed adapter は
`foreground && networkOnline` を一つの値にまとめていたため、アプリ状態の
待機とネットワーク待機を区別できませんでした。メール表示だけでは現在の
認証成功も証明できません（保存済みの送信先を表示する場合があります）。

設定画面ではアカウント設定済み／今回の認証確認済みと、アップロードの
待機理由を分離します。NWPath の通知は認証を実行する core queue とは別の
queue で受け取り、アプリ・scene の通知および設定のポーリング時に前面状態を
再取得します。Wi-Fi・充電・前面実行の制約を解除する変更ではありません。

jailed の診断 JSON には `runtime` が追加されます。

| キー | 意味 |
| --- | --- |
| `coreReady` | Go サービスの初期化完了 |
| `conditionsAccepted` | 最後の開始条件更新を Go が受理したか |
| `authorization` | `not_checked` / `checking` / `validated` / `failed`（今回のプロセス内の接続検証結果） |
| `foreground` | アプリまたは foreground scene の存在 |
| `path` | `unknown` / `satisfied` / `requires_connection` / `unsatisfied` |
| `networkOnline` | NWPath が satisfied か。Google エンドポイントの疎通保証ではない |
| `wifi`, `charging` | 実行条件のサンプル |

このスナップショットは認証中にも取得できます。トークン、メールアドレス、
アカウント ID、HTTP ヘッダー、Google のレスポンス本文は含めません。
旧診断ファイルの upload bindings が全て matched でも、認証や通信が成功した
証拠にはなりません。今回の添付診断は観測イベント 0 件であり、実機で待機した
原因を特定できる情報は含まれていませんでした。

シミュレーターテストは実際の EmbeddedService / UIKit / NWPath を使用し、
実際の Go c-archive に開始条件とキュー参照を渡し、アカウント操作だけを fixture に置換します。認証中の main callback
から診断取得できること、前面での online 伝達、認証確認表示、秘密情報を
含まない診断キーを検証します。実 Google アカウント認証・アップロード成功を
このテストの合格だけで保証するものではありません。

### 追記：認証済みなのにキューが開始しない原因

次の実機診断では `authorization=validated`、Wi-Fi / 前面 / path は正常で、
`networkOnline` が JSON の `1`、`charging` が `0` になっていました。
Objective-C の比較・論理式は `int` なので、`@(a && b)` は bool ではなく
数値を生成します。conditions の `online` / `charging` にこの数値が入り、
Go の bool フィールドへの JSON デコードが失敗していました。
旧実装は応答を無視し、Go の online は初期値 false のままでした。

修正では wire 上の bool を明示的な `@YES` / `@NO` で生成し、応答の成否を
`conditionsAccepted` に記録します。失敗時に「アップロード可能」とは表示しません。
前回のシミュレーター用 Go 代替処理は NSNumber の boolValue で 1/0 も許容し、
この不一致を見逃していました。今回は開始条件・キュー参照に本物の Go を使用します。
C ABI テストでも数値の拒否、JSON boolean の受理と online=true の反映を確認します。

## Jailbreakの認証リレー（診断6の接続成功後）

診断6では `lookup.direct=0`、`request.send=0`、`request.receive=0`、`stage=connected`。ユーザーもdaemon接続の成功を確認した。残っていたのは認証取得UIの `GS_JAILED` 制限と、daemonにSSO providerがないことだった。

- Google Photos起動時に、旧版/新版で利用可能なSSO APIからログイン中アカウントの認証を自動取得する。接続・更新操作でトークン入力を求めない。
- `account_native` で短期bearerをdaemonへ送り、Photosのhash lookupで検証してからemail/native IDを保存する。更新の `native_bearer` は既存bindingとIDが一致する場合のみ受理する。これらと消去操作は監査済みGoogle Photosプロセスだけに許可する。
- SSO取得はworkerから開始し、native APIとcallbackはmainで動かす。接続と更新を直列化し、IDの一致を取得前後で検証する。SSO取得失敗・サインアウトなどではリレーを消去し、別アカウントのbearerを流用しない。
- Google Photosの前面復帰と、実行中の60秒タイマーで更新する。daemon側はbearerをメモリ内に最大5分だけ保持する。5分は保持上限であり、Google側の有効期限を保証する値ではない。Googleによる期限切れ・拒否は別途起こり得る。
- アプリ終了後も保持中の認証で送信できるが、SSO更新を無期限に継続することはできない。保持期限切れやdaemon再起動後は新しいジョブを待機させ、再試行回数を消費しない。Google Photosを開くと更新し、待機中キューを再開する。commit結果不明の扱いは従来通り手動確認する。
- 診断の `nativeAuthentication` は `source` と `authorization` のみ。token、email、ID、HTTPヘッダーを含めない。
- iOSの「設定」への登録とPreferences bundleのビルド、PreferenceLoader依存を削除。設定はGoogle Photos内で行う。libSandyの許可対象とdaemonの監査判定からSettingsも外す。

検証対象: 本物のnative account adapterを使った新版/旧版SSO fixtureと認証リレー、接続拒否、取得中のアカウント変更、更新の重複抑止。Go側はローカルTLS endpointによる接続検証、権限境界、非保存、期限・再起動後の待機/再開を確認する。実Googleアカウントを使うiPhone上の認証・アップロードは実機確認が必要。

### 起動時の自動接続（jailed / jailbreak共通）

`GSAccountConnection` を両方の起動フックから開始する。SSO manager/identityがまだ利用できなければ2秒のmetadataポーリングで待つ。ログイン前には認証要求を送らず、identityが利用可能になるとworkerから `account_native` を実行する。成功後の通常ポーリングは認証RPCを送らない。失敗後は60秒間隔、前面復帰では再確認し、5秒以内の重複通知を抑止する。サインアウト・identity変更も検出し、古い取得結果を新しいアカウントの接続成功として扱わない。

GoToHP画面の `viewDidLoad` から自動接続を開始する処理は削除。「再接続」は明示的な再試行として残す。設定画面を開かないnative fixtureをjailed/jailbreak × 新旧APIで実行する。UIKit fixtureも設定を提示する前に自動接続が完了していることを確認する。診断の `accountConnection` は状態だけで、アカウントIDやトークンを含めない。
