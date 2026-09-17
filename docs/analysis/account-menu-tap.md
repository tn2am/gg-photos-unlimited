# GoToHP 設定のタップと表示経路

Google Photos 7.92.0 で「GoToHP の設定」の行は表示されるが、タップしても開かない実機報告への修正。

## 解析した経路

- `OGLAccountMenuUIEventHandler.performCustomActionType:indexPath:accountMenuViewController:` (`0x163fd7c`) は `session.coordinator` に `dismissAllAnimated:completion:` を要求する (`0x163fe2c`)。
- completion (`0x163fe74`) 内で `triggerCustomActionWithIndexPath:accountMenuViewController:` が呼ばれる (`0x163fea0`)。
- `OGLAccountMenuActionHandler` のそのメソッド (`0x12ed6b8`) は `session.accountMenuPresenter.accountMenuDependencies.customItemsDelegate` を取得し、アプリ側の `accountMenuViewController:performActionAtIndexPath:` に渡す (`0x12ed744`)。

従来の実装は、この delegate が渡す controller から直ちに present し、controller が UIViewController でなければ黙って終了していた。UIViewController でも、dismiss 後に window から外れた controller を使用すると設定画面を表示できない。実機でどの条件が成立したかまではログがないが、どちらの経路も今回修正する。

## 修正

1. 自作の `OGLAccountMenuCustomItem` に関連オブジェクトでマーカーを付ける。
2. native UI event handler の dismiss 前に、その session の data source から item を取得する。マーカーのある項目だけを GoToHP の表示処理へ渡す。
3. 既存項目・対応しない型・解決できない data source は元実装へ渡す。全画面の row 番号や表示文字列だけで識別しない。
4. delegate は fallback として保持する。controller が wrapper / nil でも、foreground の key window の表示中 controller を解決する。
5. UIKit は main queue で処理し、進行中の画面遷移の完了を待つ。既存の GoToHP 画面がある場合には重ねて開かない。

## UI

- 設定を接続状態、アカウント、アップロード設定、Google Photos 連携、キュー管理、診断、履歴に分けた。
- 日本語ラベル、SF Symbols、Dynamic Type、標準の grouped background を使用。
- 真偽値はスイッチ、画質・同時数・再試行回数は選択メニューにした。値をタップで循環させない。
- 履歴は日本語の状態と読みやすいデータサイズを表示し、未登録時は空の状態を表示する。
- 状態取得の polling とユーザー操作の busy を分離し、polling 中のタップを捨てない。設定変更前の古い応答が画面に反映されないよう世代を照合する。
- 認証待ちでも「完了」で閉じられる。

## 検証

`tests/account_menu.m` は UIKit の最小 shim と実際の hook 実装を使い、対応バージョンの判定、行数、元の項目の保持、dismiss 前の GoToHP タップ、delegate fallback、二重インストール、data source 未解決を検証する。実際の iPhone の表示・アニメーション・タップは実機確認が必要。

`tests/settings_ui.m` は実際の UIKit と GSPanel を iPhone シミュレーターで起動し、detached controller、既にモーダルがある root、連続タップ、nil の表示元、設定画面の描画を検証する。バックエンドはテスト用に固定し、Google 認証やアップロードは実行しない。ライト・ダーク・履歴画面の画像は CI の `settings-ui-smoke` artifact に保存する。
