# Jailed / sideload / LiveContainer

開発版。iOS 15+ / arm64 の `GooglePhotos` executable 向けに Go runtime を同梱した dylib です。解析対象の Google Photos 7.92.0 は iOS 18+。Sideloadly で起動・認証・アップロード・無制限ストレージ表示の利用者報告があります。LiveContainer を含む他の環境は実機確認が必要です。

> [!IMPORTANT]
> **最初から GunshotJailed を注入・有効化し、その状態でログインしてください。** 更新時はアプリや LiveContainer の guest を削除せず、同じ署名アカウント・Bundle ID・データコンテナを維持します。

[免責事項](../README.ja.md#免責事項--disclaimer)も確認してください。

## 配布物とビルド

```sh
bash scripts/package.sh jailed
python3 scripts/verify-package.py jailed
```

`packages/jailed/` に次を生成します。ビルド済み成果物の利用に Theos / Xcode / Go は不要です。

| ファイル | 用途 |
| --- | --- |
| `gotohp-tweak-jailed.deb` | Sideloadly などの IPA injector に渡す archive |
| `GunshotJailed.dylib` | 同じ deb の単体バイナリ。LiveContainer の tweak import 用 |
| `ThirdPartyNotices.txt` | gotohp、Go runtime、静的リンクした依存モジュールの notices |

Go uploader と依存 Go モジュールは静的リンク済みです。iOS 標準 framework 以外の実行時依存はありません。**rootless / rootful の deb や `Gunshot.dylib` は jailed 注入に使わず、deb と単体 dylib を二重に注入しないでください。**

## Sideloadly

Windows / macOS の [Sideloadly](https://sideloadly.io/)で、復号済み Google Photos IPA に `.deb` を注入します。ツールが dylib を展開するため、手動展開や拡張子の変更は不要です。

1. 復号済み Google Photos IPA をメインの IPA 欄に読み込みます。
2. **Advanced Options → Inject dylibs/frameworks** を有効にし、追加ボタン（＋ / Add）で `gotohp-tweak-jailed.deb` を選びます。表記はバージョンにより異なります。選択欄が `.dylib` のみなら、対応形式 / すべてのファイルへ切り替えます。
3. 注入一覧を確認し、接続 iPhone と **Apple Account・Bundle ID** を指定して **Start**。更新時は前回と同じ値を使い、アプリのデータを維持して上書きします。別の方法で導入する場合は export モードで IPA を保存し、導入先に必要な署名を行います。
4. 注入済みの **Google Photos を起動してログイン**します。GoToHP の設定はプロフィールメニューから開けます。

初回の信頼 / Developer Mode、Windows の iTunes / iCloud などの接続環境は [Sideloadly FAQ](https://sideloadly.io/faq) に従ってください。

jailed 版は起動時に、再署名で変わった識別子を Google Photos の SSO 内で `com.google.photos` に補正します。共有 Keychain に権限不足（`-34018`）がある場合は、純正のアプリ専用 Keychain 設定も使います。この補正に別途 Sideload Spoofer を入れる必要はありません。

7.20.2 / 7.92.0 の認証経路を解析し、互換 API の有無で適用します。LiveContainer では適用しません。Google 側の拒否が解消するかは実機検証が必要です。診断 JSON の `sideloadIdentity` に補正の適用状態を記録します（識別子・認証 URL・トークンは記録しません）。

### 他の注入ツール・手動注入

1. 復号済み IPA に対応 injector で jailed deb を注入します。手動なら `GunshotJailed.dylib` を app の Frameworks に配置し、メイン executable に `@rpath/GunshotJailed.dylib` の `LC_LOAD_DYLIB` を追加します。
2. dylib を含むアプリ全体を、利用可能な証明書・プロビジョニングで再署名してサイドロードします。ビルド時の ad-hoc 署名では通常の iOS にインストールできません。

注入先は **メインの `GooglePhotos` executable のみ**です。app extension や arm64e-only executable は対象外です。Bundle ID を変える場合も executable 名は維持してください。

署名済み IPA、証明書、Google Photos バイナリは配布しません。再署名で使えなくなる Google Photos 自体の機能は修復できません。

## LiveContainer

[公式の tweak 手順](https://livecontainer.github.io/docs/guides/tweaks)に沿って、単体 dylib を使います。

1. Google Photos IPA を取り込みます。初回起動・ログインの前に、次の手順で tweak を有効化します。既存の guest を更新する場合は、同じ guest / データコンテナを維持します。
2. **Tweaks** タブに Google Photos 用のフォルダを作り、`GunshotJailed.dylib` を **Import Tweak** します。全アプリ用の root Tweaks には配置しません。
3. Google Photos の app settings → **Tweak Folder** にそのフォルダを指定します。TweakLoader を有効にし、公式手順に従って必要なら **Sign** を実行します。
4. tweak を有効にした **Google Photos を起動してログイン**します。GoToHP の設定はプロフィールメニューから開けます。

IPA 内に事前注入する方式を使う場合も、ログイン済みの guest / データを維持し、外部 tweak と重複させないでください。単一 guest / container で検証してください。複数 Go runtime の同時ロード、multitask、実行中の data-container 切替は未検証です。ファイル選択に問題があれば[公式の app 設定](https://github.com/LiveContainer/LiveContainer#fix-file-picker--local-notification)を確認してください。

## アカウントとアップロード

7.92.0 では GoToHP の設定を開くと、ログイン中のアカウントを既存 SSO 経由で自動接続します。接続を更新するには**再接続**をタップします。トークンの手動入力は不要です。認証失敗時はエラーを表示し、別アカウントには送信しません。

**アップロード → 写真・動画を選択**から写真を選びます。ホストに `NSPhotoLibraryUsageDescription` が必要です（7.92.0 は確認済み）。認証の詳細は[認証経路・保存内容](analysis/native-account.md)、Google Photos のバックアップ連携は [backup-routing.md](analysis/backup-routing.md) を参照してください。

## 実行・保存の制約

uploader は Google Photos プロセス内で動作します。バックグラウンド通知で upload を中断し pending に戻し、前面復帰時や再起動後に GoToHP を開くと再開します。画面ロック・OS suspend・force kill 後の継続には対応しません。中断処理が間に合わなくても次回初期化で queue を復旧します。再送は先頭から行い、commit 中断は結果不明として停止します。認証・ディスク処理中は中断通知の処理が遅れる場合があります。

アカウントの binding と queue は host / guest の `Application Support/GoToHP` に保存します。native token は Google Photos の SSO が管理し、GoToHP では保存しません。以前に手動 import した credential は削除するまで JSON に残る場合があります。

JSON は 0600、ディレクトリは 0700 で、初回 unlock 後にアクセス可能、backup 対象外です。独自の Keychain store はなく、同じアプリ / LiveContainer のコードや管理者からは隔離されません。独立 daemon 用の外部 IPC は開きません。

## 実機検証

Sideloadly / LiveContainer ごとに、起動、設定、認証、JPEG / 動画 / Live Photo、複数選択、Wi-Fi / 充電条件、background 中断、foreground 復帰、force kill と再起動、期限切れ credential を確認してください。Native routing は [native-routing.md](native-routing.md) の項目で別途検証します。
