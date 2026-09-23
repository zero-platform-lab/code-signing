# Windows アプリに署名する — アプリ開発者向け

Zero Platform Lab の証明書で、自分のアプリの Windows 配布物に署名する手順。

署名の中身は [code-signing](https://github.com/zero-platform-lab/code-signing) 側に
あるので、**アプリ側に書くのは呼び出しだけ**。10 行ほど。

## 前提

**リポジトリが Public であること。**

- 署名は「他人に配る配布物が改ざんされていないこと」を示す仕組み。
  公開しない配布物に署名する意味はない
- GitHub Free プランでは、Organization Secrets は Public リポジトリでしか使えない

Private のまま進めると、原因の分かりにくいエラーで止まる。

```
Secret SIGNING_PFX_BASE64 is required, but not provided while calling.
```

これは `secrets: inherit` の書き忘れに見えるが、実際は Secret が
呼び出し元からも見えていない。

## 1 回だけ、管理者に頼むこと

自分のリポジトリを Organization Secret の対象に加えてもらう。3 つある。

```
SIGNING_PFX_BASE64
SIGNING_PFX_PASSWORD
SIGNING_THUMBPRINT
```

管理者が行う作業。**既存の対象を消さないよう、1 件ずつ追加する。**

```bash
REPO_ID=$(gh api repos/zero-platform-lab/あなたのリポジトリ名 --jq .id)
for s in SIGNING_PFX_BASE64 SIGNING_PFX_PASSWORD SIGNING_THUMBPRINT; do
  gh api -X PUT "orgs/zero-platform-lab/actions/secrets/$s/repositories/$REPO_ID"
  echo "$s ok"
done
```

**`gh secret set --repos` は使わないこと。** あれは対象の一覧を丸ごと
置き換えるので、すでに署名を使っている他のリポジトリが外れる。
一覧を作り直したい場合にだけ使う。

確認:

```bash
for s in SIGNING_PFX_BASE64 SIGNING_PFX_PASSWORD SIGNING_THUMBPRINT; do
  printf '%s -> ' "$s"
  gh api "orgs/zero-platform-lab/actions/secrets/$s/repositories" \
    --jq '[.repositories[].name] | join(", ")'
done
```

Web からなら Organization → Settings → Secrets and variables → Actions で、
各 Secret の **Repository access** に追加する。

## 2. ワークフローを書く

`.github/workflows/release.yml` に置く。タグを打つと動く例。

```yaml
name: release

on:
  push:
    tags: ['v*']

permissions:
  contents: write        # Release の作成に要る

jobs:
  # ── ビルド。ここは自分のアプリに合わせて書き換える ──
  build:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - run: cargo build --release          # 例。dotnet publish でも msbuild でもよい
      - uses: actions/upload-artifact@v4
        with:
          name: windows-build
          path: target/release/*.exe
          if-no-files-found: error

  # ── 署名。中身は code-signing 側にある ──
  sign:
    needs: build
    uses: zero-platform-lab/code-signing/.github/workflows/sign-windows.yml@master
    with:
      artifact-name: windows-build     # 上で upload した名前
      files: '*.exe'                   # 署名対象。artifact の中の相対パス
    secrets: inherit                   # ★ これが無いと動かない

  # ── 署名済みだけを Release に出す ──
  release:
    needs: sign
    runs-on: ubuntu-latest
    steps:
      - uses: actions/download-artifact@v4
        with:
          name: signed
          path: dist

      # 利用者が検証するための公開証明書と手順を同梱する
      - uses: actions/checkout@v4
        with:
          repository: zero-platform-lab/code-signing
          path: cs
      - run: cp cs/public/signing.cer cs/public/THUMBPRINT.txt dist/

      - uses: softprops/action-gh-release@v2
        with:
          files: dist/*
          body_path: cs/public/RELEASE_NOTE_SNIPPET.md
```

**`secrets: inherit` を忘れないこと。** 一番多い失敗。

## 入力

| 名前 | 必須 | 既定 | 意味 |
|---|---|---|---|
| `artifact-name` | 必須 | | 署名前の成果物の名前 |
| `files` | 必須 | | 署名対象。空白区切りで複数可。成果物の中の相対パス |
| `signed-artifact-name` | | `signed` | 署名後に上げる名前 |
| `timestamp-url` | | DigiCert | RFC3161 タイムスタンプ局 |

`files` に該当が 1 件も無ければ**失敗する**。黙って素通りはしない。

対応形式は `EXE` `DLL` `MSI` `MSIX`。

## 3. 動作を確かめる

タグを打つ。

```bash
git tag v0.1.0 && git push origin v0.1.0
```

Actions のログに次が出れば成功。

```
署名する 1 件:
  D:\a\...\work\YourApp.exe
YourApp.exe: status=UnknownError thumbprint一致=True タイムスタンプ=あり
```

**`UnknownError` は正常。** 「署名は健全だが、Windows がこの発行元を信頼していない」
という意味で、自己署名なのでこうなる。`HashMismatch` や `NotSigned` が本当の失敗。

## つまずきやすいところ

| 症状 | 原因 |
|---|---|
| `Secret ... is required, but not provided` | `secrets: inherit` が無い。または Organization Secret の対象に入っていない。**リポジトリが Private でも起きる** |
| `workflow not found` | `uses:` のパスかタグが違う |
| `対象が見つからない: *.exe` | `artifact-name` と `files` が噛み合っていない。`files` は artifact の中の相対パス |
| 署名は通るが検証で落ちる | 証明書が更新されたのに Secret が古い。管理者に確認する |
| タイムスタンプが `なし` | タイムスタンプ局に到達できていない。`timestamp-url` を別の局に変える |

## 利用者に伝えること

Release には `signing.cer` と検証手順が同梱される。利用者は次を知っておく必要がある。

- 公開 CA の証明書ではないので、**そのままでは「不明な発行元」と表示される**
- 証明書を信頼ストアに登録すれば `Valid` になる（管理者権限が要る）
- **SmartScreen の警告は署名では消えない**。ダウンロード実績で判定される仕組み
- 署名はアプリの安全性を保証しない。改ざんされていないことと発行元の同一性を示すだけ

詳しくは [`public/RELEASE_NOTE_SNIPPET.md`](../public/RELEASE_NOTE_SNIPPET.md)。
Release の本文にそのまま使える。

## 証明書の情報

```
発行者    CN=Zero Platform Lab, O=Zero Platform Lab
SHA-256   97:D3:70:0C:CE:4D:0C:06:8D:B0:0E:24:60:48:17:BC:A0:AD:C9:D2:F4:4E:36:07:76:58:41:55:E3:E2:3D:E0
SHA-1     0E:70:1D:C2:53:14:3D:4E:AA:3C:1F:98:09:4A:D0:EF:10:47:5A:66
有効期限  2031-09-23
```
