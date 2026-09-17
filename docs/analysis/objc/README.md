# Objective-C metadata 全件索引

| Image | Class entries | Instance method entries | 全件データ |
| --- | ---: | ---: | --- |
| GooglePhotos | 12,643 | 98,308 | [main-methods.json.gz](main-methods.json.gz) |
| GooglePhotos_GeneratedFramework | 13,540 | 66,708 | [framework-methods.json.gz](framework-methods.json.gz) |
| 合計（image ごとの件数の和） | 26,183 | 165,016 | [hash / 件数 manifest](manifest.json) |

`className → [[selector, typeEncoding, staticIMP], ...]` という JSON を gzip 圧縮しています。第三者 SDK のクラスも含み、Google Photos 独自のクラス数ではありません。二つの image 間で同じ名前があっても別 entry として数えます。メソッドなしのクラスも保持しています。

## 検索

Python 3 標準ライブラリのみで検索できます。リポジトリのルートから:

```sh
python3 scripts/query-objc-index.py --class-name GMUAssetUploadRequest
python3 scripts/query-objc-index.py --selector backupLocalAssets:
python3 scripts/query-objc-index.py --class-name Scotty --limit 0
python3 scripts/query-objc-index.py --image main --classes-only --limit 0
```

`--limit 0` は全件出力です。既定は 50 行。表示件数と一致件数を末尾に出すため、表示上限を全件数と取り違えません。読み取り時に圧縮データの SHA-256 を manifest と照合します。任意の新規依存や IPA は検索に不要です。

## 抽出範囲と限界

- `__objc_classlist` の class と class_ro の instance-method list を抽出しました。
- 本体と内蔵 generated framework の **2 image のみ**が対象です。拡張 executable や OS framework の解析ではありません。
- metaclass の class method、category の追加 method、protocol、全 ivar/property、Swift-only 関数、C/C++ 関数、全 call graph は含みません。
- selector の存在は、その操作が実行時に通る・hook できる・機能が動く証明ではありません。
- IMP は ASLR slide 適用前の static VM address。image を必ず一緒に扱います。実機に直接使う固定アドレスではありません。
- 再署名・加工・別 IPA で一致するとは限りません。入力バイナリの SHA-256 は manifest を参照してください。

## 再抽出

提供 IPA から対象 executable を取り出し、次のように解析します。実行はせず、ファイルを読み取ります。

```sh
python3 scripts/extract-objc-metadata.py /path/to/GooglePhotos /tmp/main-methods.json
python3 scripts/extract-objc-metadata.py /path/to/GooglePhotos_GeneratedFramework /tmp/framework-methods.json
```

この parser は提供ファイルで確認した thin arm64 Mach-O、relative method list と pointer 表現を扱うためのものです。汎用 decompiler ではありません。解析エラー時は部分的な索引を成功扱いせず停止します。保存済み索引を更新する場合は元バイナリ・出力 hash と件数を再確認してください。

バイナリ、逆アセンブル全文、文字列 dump、通信データ、credential はこの索引に同梱していません。
