# Organization Secrets の登録

証明書を作った直後と、更新したときに行う。

## 前提

`gh` に `admin:org` スコープが要る。無い場合は追加する。

```bash
gh auth refresh -h github.com -s admin:org
```

対話でブラウザが開く。Organization の管理者であること。

## 登録

`code-signing` を clone した場所で、`secrets/` が手元にある状態で実行する。

```bash
cd ~/code-signing

# 対象リポジトリ。署名を使うアプリを増やすたびにここへ足す
REPOS=code-signing

gh secret set SIGNING_PFX_BASE64 --org zero-platform-lab \
  --visibility selected --repos "$REPOS" < secrets/signing.pfx.b64

gh secret set SIGNING_PFX_PASSWORD --org zero-platform-lab \
  --visibility selected --repos "$REPOS" < secrets/signing.pfx.password

# 拇印は SHA-1 から区切りを除いた 40 文字。signtool と検証で使う
grep '^SHA-1' secrets/THUMBPRINT.txt | cut -d: -f2- | tr -d ': \n' |
  gh secret set SIGNING_THUMBPRINT --org zero-platform-lab \
    --visibility selected --repos "$REPOS"
```

**`cut -d: -f2-` を使うこと。** `sed 's/.*: *//'` は拇印に含まれるコロンまで
食ってしまい、末尾の 2 文字だけが残る。

## 確認

```bash
gh secret list --org zero-platform-lab
```

3 つが出れば登録できている。値は表示されない。

拇印だけは公開情報なので、中身を確かめてよい。

```bash
grep '^SHA-1' secrets/THUMBPRINT.txt | cut -d: -f2- | tr -d ': \n'; echo
# 40 文字の 16 進。現在: 0E701DC253143D4EAA3C1F98094AD0EF10475A66
```

## アプリを増やすとき

**`gh secret set --repos` を使わないこと。** 対象の一覧を丸ごと置き換えるため、
すでに署名を使っている他のリポジトリが外れる。1 件ずつ追加する。

```bash
REPO_ID=$(gh api repos/zero-platform-lab/<新しいリポジトリ> --jq .id)
for s in SIGNING_PFX_BASE64 SIGNING_PFX_PASSWORD SIGNING_THUMBPRINT; do
  gh api -X PUT "orgs/zero-platform-lab/actions/secrets/$s/repositories/$REPO_ID"
done
```

この作業に手元の `secrets/` は要らない。値を触らず、対象だけを足すため。

Web からなら Organization → Settings → Secrets and variables → Actions で、
各 Secret の Repository access に追加する。

## なぜ code-signing は Public なのか

**Free プランの制約が 2 つあり、どちらも Private だと詰む。**

| 制約 | 内容 |
|---|---|
| Organization Secrets | Private リポジトリでは使えない。**登録は通るのに値が空になる** |
| 再利用可能ワークフロー | 同一リポジトリか Public リポジトリのものしか呼べない |

2026-09-23 に Private で試したところ、`Secret ... is required, but not provided
while calling` で失敗した。エラーからは `secrets: inherit` の問題に見えるが、
実際は呼び出し元からも見えていなかった。

Public にすれば両方解消する。このリポジトリに秘密情報は無く、むしろ利用者が
署名と検証の方法を確認できる利点がある。秘密鍵は `secrets/` にあり、
`.gitignore` で除外してあるので上がらない。

**Private に戻すと、アプリ側から `uses:` で呼べなくなる。**

そもそも署名が要るのは他人に配る配布物、つまり Public リポジトリのものだけ。
公開しない配布物に署名する意味はない。

## 手元の後始末 — 方針: 控えを残さない

**2026-09-23 に決定。** 秘密鍵は GitHub Secrets にのみ置き、手元の
`secrets/` は登録後に削除する。別途の退避は取らない。

### 承知しておくこと

**GitHub Secrets は読み出せない。** 一度登録すると API からも画面からも
値を取り出せず、ワークフローの中で使えるだけ。したがって手元を消した時点で、
次のことができなくなる。

```
別のリポジトリや Organization へ登録し直す
手元で署名する
他の環境へ移す
```

鍵を失った場合は、`scripts/new-cert.sh` で**新しい証明書を作り直す**。
タイムスタンプを入れてあるので、過去に署名した配布物は証明書の期限後も
検証できる。作り直しの影響はこれから出すものに限られ、利用者には
新しい公開証明書の登録を案内する。

### 順序を守ること

**登録する前に消さない。**

```
1. gh auth refresh -h github.com -s admin:org
2. 上の手順で 3 つの Secret を登録する
3. gh secret list --org zero-platform-lab で 3 つ揃っていることを確認する
4. そのあとで rm -rf secrets/
```

`secrets/` は `.gitignore` で除外済みで、コミットされることはない。
