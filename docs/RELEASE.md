# リリース手順

すべて `make` から実行できます。署名の準備・後始末はスクリプトが行うので、
キーチェーンを手で触る必要はありません。

## 日常

```bash
make status        # ローカルと App Store Connect の現状
make preflight     # ビルド・テスト・型・契約・審査適合・秘密情報
make testflight    # 次のビルド番号でアーカイブ〜TestFlight 配信
```

`make testflight` は次のビルド番号を自動で決めます。App Store Connect 上の
最新番号と `project.yml` の値を比べ、大きいほうに 1 を足します。番号の重複で
アップロードが弾かれることはありません。

明示したいときは `ARGS` で渡します。

```bash
make testflight ARGS="--build 25"
make testflight ARGS="--dry-run"          # IPA を作るだけ。アップロードしない
make testflight ARGS="--skip-preflight"   # 検査を飛ばす
```

## 審査提出

```bash
make submit VERSION=1.0.2
```

アーカイブからアップロード、App Store バージョンの作成、提出前診断、審査提出
までを続けて行います。バージョンが未作成なら現行バージョンのメタデータを
引き継いで作成します。

提出前に `asc review doctor` を実行し、ブロッカーがあればそこで止まります。

## 事前に必要なもの

| ツール | 用途 | 導入 |
|---|---|---|
| xcodegen | `project.yml` から `.xcodeproj` を生成 | `brew install xcodegen` |
| asc | App Store Connect API | `brew install rorkai/tap/asc` |
| greenlight | 審査適合スキャン（任意） | `brew install revylai/tap/greenlight` |

`asc auth status` でプロファイル `protoductai` が有効なことを確認してください。

## 署名について

`scripts/lib.sh` の `prepare_signing` が毎回この3点を整えます。いずれも
`errSecInternalComponent` という同じエラーになるため、原因の切り分けに時間が
かかったものです。

1. **ロックされた他プロジェクトのキーチェーンを検索リストから外す**
   解錠できないキーチェーンが検索対象にあると、走査のたびにパスワード
   ダイアログが出て応答待ちで止まります。
2. **WWDR 中間証明書を署名キーチェーンに取り込む**
   ないと証明書チェーンを構築できず `unable to build chain to self-signed
   root` になります。
3. **署名キーチェーンを既定に設定する**
   `--keychain` を渡していても、既定が別だと codesign が解決に失敗します。

検索リストと既定キーチェーンは、途中で失敗した場合も含めて `trap` で元に
戻します。

署名前に `WIZMARK_KEYCHAIN_PASSWORD` を環境変数で設定してください。
既定のパスワードはありません。値をソースやドキュメントに記録しないでください。

### プロビジョニングプロファイル

アーカイブ前に、指定のプロファイルが現在の証明書を含むかを指紋で照合します。
プロファイルは古い証明書のまま生き続けるため、失効に気づかないまま
アーカイブ途中で失敗しがちです。含まれていなければその場で止まります。

現在使うのは `WizMark AppStore V2` と `WizMarkShare AppStore V2` です。

## preflight が見るもの

- **ビルド**（シミュレータ、Debug）
- **テスト**
- **Convex の型**（`tsc --noEmit`）
- **Convex の戻り値契約** — 後述
- **審査適合**（greenlight）
- **秘密情報**（API キーらしき文字列）

### Convex の戻り値契約

ConvexMobile の戻り値なし `mutation` は、レスポンスを `String?` として
デコードします。

```swift
public func mutation(_ name: String, with args: ...) async throws {
    let _: String? = try await mutation(name, with: args)
}
```

そのため `{ ok: true }` のようなオブジェクトを返す mutation は、**サーバ側で
成功していてもアプリ側のデコーダで失敗します**。ユーザーには「データの
フォーマットが正しくないため、読み込めませんでした」と出ます。

preflight は、Swift 側で結果を捨てている mutation を洗い出し、Convex 側が
`null` 以外を返していないか検査します。早期 return も対象です。

結果を読む mutation（`publish`、`join`）はこの制約を受けません。

## Web とバックエンド

```bash
make web-deploy      # ランディングページを Cloudflare Pages へ
make convex-deploy   # Convex 関数をデプロイ
```

`wizmark-web` は GitHub 連携ではなく手動デプロイです。push しても反映
されないので、このコマンドが必要です。

Convex は `convex/` 配下すべてを一括で反映します。**一部の関数が欠けた状態で
実行すると、デプロイ済みの関数が消えます。** 実行前に `ls convex/*.ts` で
`rateLimit.ts` と `revenuecat.ts` を含む全ファイルが揃っていることを
確認してください。
