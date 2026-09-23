# code-signing

Zero Platform Lab が配布する Windows アプリケーションを、自前のコード署名証明書で
署名する仕組み。

## アプリを作っている人へ

**[docs/for-app-repos.md](docs/for-app-repos.md) を読んでください。**
アプリ側に書くのは 10 行ほどです。

```yaml
  sign:
    needs: build
    uses: zero-platform-lab/code-signing/.github/workflows/sign-windows.yml@master
    with:
      artifact-name: windows-build
      files: '*.exe'
    secrets: inherit
```

前提が 2 つあります。

- **リポジトリが Public であること。** 公開しない配布物に署名する意味はなく、
  GitHub Free プランでは Private で Organization Secrets が使えない
- **Organization Secret の対象に自分のリポジトリを加えてもらうこと。** 管理者に依頼する

## アプリを使う人へ

配布物の署名を確認する手順は
[public/RELEASE_NOTE_SNIPPET.md](public/RELEASE_NOTE_SNIPPET.md) にあります。
Release の本文にも同じものが載ります。

公開証明書は [public/signing.cer](public/signing.cer)。

```
発行者    CN=Zero Platform Lab, O=Zero Platform Lab
SHA-256   97:D3:70:0C:CE:4D:0C:06:8D:B0:0E:24:60:48:17:BC:A0:AD:C9:D2:F4:4E:36:07:76:58:41:55:E3:E2:3D:E0
SHA-1     0E:70:1D:C2:53:14:3D:4E:AA:3C:1F:98:09:4A:D0:EF:10:47:5A:66
有効期限  2031-09-23
```

これは**自己署名証明書**です。公開 CA によるものではないので、登録していない
環境では「不明な発行元」と表示されます。Microsoft SmartScreen の警告も、署名の
有無とは別の仕組みなので出ます。

## 管理する人へ

| 文書 | 内容 |
|---|---|
| [docs/setup-secrets.md](docs/setup-secrets.md) | Secrets の登録、Free プランの制約、鍵の扱い |
| [scripts/new-cert.sh](scripts/new-cert.sh) | 証明書の作成。**手元で実行する** |

秘密鍵はこのリポジトリに含まれません。GitHub の Organization Secrets にのみ
あり、**読み出せません**。失った場合は証明書を作り直します。タイムスタンプを
入れてあるので、過去に署名した配布物は証明書の期限後も検証できます。

## 仕組み

```
アプリ側リポジトリ
  build    成果物を作って upload-artifact
  sign     このリポジトリの sign-windows.yml を呼ぶ
             signtool で署名 (SHA-256 + RFC3161 タイムスタンプ)
             拇印の一致とタイムスタンプの有無を検証
  release  署名済みと signing.cer を Release へ
```

検証に `signtool verify /pa` は使いません。自己署名なので、証明書を信頼ストアに
入れていないランナーでは必ず落ちるためです。代わりに「署名の状態」「拇印の一致」
「タイムスタンプの有無」を見ています。
