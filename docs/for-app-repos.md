# アプリ側リポジトリの設定

Zero Platform Lab のアプリで Windows 配布物に署名する手順。
署名の中身は `code-signing` 側にあるので、**アプリ側に書くのは呼び出しだけ**。

## 1 回だけやること — Secrets を使えるようにする

Organization Secrets は既定で全リポジトリには見えない。対象に加える。

```bash
gh secret set SIGNING_PFX_BASE64 --org zero-platform-lab \
  --visibility selected --repos code-signing,app-a,app-b < secrets/signing.pfx.b64
```

`--repos` に**そのリポジトリを追加**する。3 つの Secret すべてで行う。

```
SIGNING_PFX_BASE64
SIGNING_PFX_PASSWORD
SIGNING_THUMBPRINT
```

Web からなら Organization → Settings → Secrets and variables → Actions で、
各 Secret の **Repository access** に追加する。

`code-signing` が Private なので、そこの再利用可能ワークフローを他リポジトリから
呼ぶには、`code-signing` 側の Settings → Actions → General →
**Access** を「Accessible from repositories in the organization」にしておく。

## ワークフローを書く

`.github/workflows/release.yml` に置く例。

```yaml
name: release

on:
  push:
    tags: ['v*']

permissions:
  contents: write        # Release の作成に要る

jobs:
  # 1. 普通にビルドして、成果物を上げる
  build:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      # ここは各アプリのビルド手順に置き換える
      - run: cargo build --release
      - uses: actions/upload-artifact@v4
        with:
          name: windows-build
          path: target/release/*.exe
          if-no-files-found: error

  # 2. 署名する。中身は code-signing 側にある
  sign:
    needs: build
    uses: zero-platform-lab/code-signing/.github/workflows/sign-windows.yml@v1
    with:
      artifact-name: windows-build
      files: '*.exe'
    secrets: inherit

  # 3. 署名済みだけを Release に出す
  release:
    needs: sign
    runs-on: ubuntu-latest
    steps:
      - uses: actions/download-artifact@v4
        with:
          name: signed
          path: dist

      # 利用者が信頼ストアへ入れるための公開証明書を同梱する
      - uses: actions/checkout@v4
        with:
          repository: zero-platform-lab/code-signing
          path: cs
          sparse-checkout: |
            public
      - run: cp cs/public/signing.cer cs/public/THUMBPRINT.txt dist/

      - uses: softprops/action-gh-release@v2
        with:
          files: dist/*
          body_path: cs/public/RELEASE_NOTE_SNIPPET.md
```

**`secrets: inherit` を忘れないこと。** これが無いと Secrets が渡らず、
再利用可能ワークフローが起動時に失敗する。

## 入力

| 名前 | 必須 | 既定 | 意味 |
|---|---|---|---|
| `artifact-name` | 必須 | | 署名前の成果物の名前 |
| `files` | 必須 | | 署名対象のパターン。空白区切り。成果物の中の相対パス |
| `signed-artifact-name` | | `signed` | 署名後に上げる名前 |
| `timestamp-url` | | DigiCert | RFC3161 タイムスタンプ局 |

`files` に該当が 1 件も無ければ**失敗する**。黙って素通りはしない。

## 署名対象

`EXE` `DLL` `MSI` `MSIX` を想定している。`signtool` が扱える形式なら
`files` に足せば署名される。検証の走査対象はこの 4 拡張子。

## よくある失敗

| 症状 | 原因 |
|---|---|
| ワークフローが起動しない | `secrets: inherit` がない。または Organization Secret の対象に入っていない |
| `workflow not found` | `code-signing` の Actions Access が組織内に開放されていない |
| `対象が見つからない: *.exe` | `artifact-name` と `files` の組み合わせが合っていない。`path:` 直下からの相対 |
| 署名は通るが検証で落ちる | `SIGNING_THUMBPRINT` が古い。証明書を更新したのに Secret を直していない |

## 検証について知っておくこと

このワークフローは `signtool verify /pa` を使わない。**自己署名なので、
証明書を信頼ストアに入れていない GitHub のランナーでは必ず落ちるため。**

代わりに確認しているのは次の 3 点。

```
署名の状態が Valid か UnknownError であること
  UnknownError は「署名は健全だが発行元が未信頼」。自己署名では正常
  HashMismatch や NotSigned は本当の失敗
署名者の拇印が SIGNING_THUMBPRINT と一致すること
タイムスタンプが付いていること
```

「Windows が発行元を信頼しているか」ではなく、「**正しい鍵で署名され、
改ざんされていないか**」を確かめている。
